#!/usr/bin/env perl

use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
use Irssi::TextUI;

use JSON;

use Mojolicious::Lite;
use Mojo::Server::Daemon;

use File::Basename 'dirname';
use File::Spec;

use Data::UUID::LibUUID;
use MIME::Base64 qw(encode_base64);
use MIME::Lite;

$VERSION = '0.0.1';
%IRSSI = (
  authors => 'Timothy J Fontaine',
  contact => 'tjfontaine@gmail.com',
  name    => 'irssi_proxy_websocket',
  license => 'MIT/X11',
  description => 'Proxy module that listens on a WebSocket',
);

Irssi::theme_register([
 'irssi_proxy_websocket',
 '{line_start}{hilight ' . $IRSSI{'name'} . ':} $0'
]);

$ENV{MOJO_REUSE} = 1;

# Mojo likes to spew, this makes irssi mostly unsuable
app->log->level('fatal');
app->static->root(File::Spec->catdir(dirname(__FILE__), 'client'));

Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_host', 'localhost');
Irssi::settings_add_int('irssi_proxy_websocket', 'ipw_port', 3000);
Irssi::settings_add_bool('irssi_proxy_websocket', 'ipw_ssl', 0);
Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_cert', '');
Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_key', '');
Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_pkcs12', '');

sub setup_changed {
  my ($host, $port, $ssl, $cert, $key, $pkcs);
  $host = Irssi::settings_get_str('ipw_host');
  $port = Irssi::settings_get_int('ipw_port');
  $ssl  = Irssi::settings_get_bool('ipw_ssl');
  $cert = Irssi::settings_get_str('ipw_cert');
  $key  = Irssi::settings_get_str('ipw_key');
  $pkcs = Irssi::settings_get_str('ipw_pkcs12');

  if(length($cert) && !-e $cert) {
    logmsg("Certificate file doesn't exist: $cert");
  }
  if(length($key) && !-e $key) {
    logmsg("Key file doesn't exist: $key");
  }
  if(length($pkcs) && !-e $pkcs) {
    logmsg("PKCS12 file doesn't exist: $pkcs");
  }
};

my $listen_url;

my $host = Irssi::settings_get_str('ipw_host');
my $port = Irssi::settings_get_int('ipw_port');
my $cert = Irssi::settings_get_str('ipw_cert');
my $key  = Irssi::settings_get_str('ipw_key');

if(!Irssi::settings_get_bool('ipw_ssl') && -e $cert && -e $key) {
  $listen_url = sprintf("https://%s:%d:%s:%s", $host, $port, $cert, $key);
} else {
  $listen_url = sprintf("http://%s:%d", $host, $port);
}

my $daemon = Mojo::Server::Daemon->new(
  app => app,
  listen => [$listen_url],
);

#TODO XXX FIXME mojo creates a random port for some ioloop operations
# this is bound to make people angry who don't understand why
$daemon->prepare_ioloop;

sub ws_loop {
  $daemon->ioloop->one_tick;
}

#TODO XXX FIXME we may be able to up this to 1000 or higher if abuse
# mojo ->{handle} into the input_add system
my $loop_id = Irssi::timeout_add(100, \&ws_loop, 0);

my $json = JSON->new->allow_nonref;
$json->allow_blessed(1);

my %clients = ();

sub logmsg {
  my $msg = shift;
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'irssi_proxy_websocket', $msg);
}

websocket '/' => sub {
  my $client = shift;
  logmsg("Client Connected From: " . $client->tx->remote_address);
  $clients{$client} = {
    client => $client,
    activewindow => 0,
    color => 0,
  };
  $client->on_message(\&parse_msg);
  $client->on_finish(sub {
    logmsg("Client From: " . $client->tx->remote_address . " Closed");
    delete $clients{$client};
  });
};

get '/' => sub {
  my $client = shift;
  $client->render_static('index.html');
};

get '/mobileconfig' => sub {
  my $client = shift;
  unless(-e Irssi::settings_get_str('ipw_pkcs12')) {
    return $client->render_text("/SET ipw_pkcs12 /path/to/certificate/in/pkcs12/ipw.p12");
  }
  $client->render_static('mobileconfig.html');
};

post '/mobileconfig' => sub {
  my $client = shift;

  unless(-e Irssi::settings_get_str('ipw_pkcs12')) {
    $client->redirect_to('/');
  }

  open PKCS12, Irssi::settings_get_str('ipw_pkcs12');
  local($/);
  my $base64 = encode_base64(<PKCS12>);
  close PKCS12;

  my $mcxml = <<"__EOI__";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadCertificateFileName</key>
      <string>ipw.p12</string>
      <key>PayloadContent</key>
      <data>%s</data>
      <key>PayloadDescription</key>
      <string>Provides device authentication (certificate or identity).</string>
      <key>PayloadDisplayName</key>
      <string>ipw.p12</string>
      <key>PayloadIdentifier</key>
      <string>com.atxconsulting.irssi_proxy_websocket.credential</string>
      <key>PayloadOrganization</key>
      <string>Ataraxia Consulting</string>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>%s</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDescription</key>
  <string>Certificate for Irssi Proxy Websocket</string>
  <key>PayloadDisplayName</key>
  <string>Irssi Proxy Websocket</string>
  <key>PayloadIdentifier</key>
  <string>com.atxconsulting.irssi_proxy_websocket</string>
  <key>PayloadOrganization</key>
  <string>Ataraxia Consulting</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>%s</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
__EOI__

  my $msg = MIME::Lite->new(
    From    => $client->param('from'),
    To      => $client->param('to'),
    Subject => 'Irssi Proxy Websocket Mobileconfig',
    Type    => 'multipart/mixed',
  );
  
  $msg->attach(
    Type     => 'TEXT',
    Data     => "This is the mobile config for ios devices, you must open on such a device",
  );

  $msg->attach(
    Type        => 'text/xml',
    Data        => sprintf($mcxml, $base64, new_uuid_string(), new_uuid_string()),
    Filename    => 'ipw.mobileconfig',
    Encoding    => 'base64',
    Disposition => 'attachment',
  );

  $msg->send;
  $client->redirect_to('/');
};

sub sendto_client {
  my ($client, $msg) = @_;
  $msg = $json->encode($msg);
  $client->send_message($msg);
}

sub sendto_all_clients {
  my $msg = shift;

  while (my ($client, $chash) = each %clients) {
    sendto_client($chash->{'client'}, $msg);
  }
}

sub parse_msg {
  my ($client, $message) = @_;
  $message =~ s/\r\n$//;

  my $command = $json->decode($message);
  if ($command->{'event'} eq 'sendcommand') {
    my $active_window = Irssi::window_find_refnum(int($command->{'window'}));
    if ($command->{'msg'} =~ /^\//) {
      $active_window->command($command->{'msg'});
    } else {
      my $name = $active_window->get_active_name();
      $active_window->command("MSG " . $name . " " . $command->{'msg'});
    }
  } elsif ($command->{'event'} eq 'listwindows') {
    listwindows($client, $command);
  } elsif ($command->{'event'} eq 'getscrollback') {
    getscrollback($client, $command);
  } elsif ($command->{'event'} eq 'activewindow') {
    activewindow($client, $command);
  } else {
    logmsg($command->{'event'});
  }
}

sub activewindow {
  my ($client, $event) = @_;
  my $window = Irssi::window_find_refnum(int($event->{'window'}));
  $window->set_active();
  $clients{$client}->{'activewindow'} = int($event->{'window'});
}

sub listwindows {
  my ($client, $event) = @_;
  
  my @windows = ();
  foreach my $window (Irssi::windows()) {
    my @items = ();
    my $entry = {
      'window' => "$window->{'refnum'}",
      'name' => $window->{'name'},
      'items' => \@items,
      'data_level' => $window->{data_level},
    };

    for my $item ($window->items) {
      push(@items, {
        name => $item->{name},
        type => $item->{type},
        active => $item->is_active,
      });
    }

    push(@windows, $entry);
  }

  sendto_client($client, {
    event => "windowlist",
    windows => \@windows
  });
};

sub getscrollback {
  my ($client, $event) = @_;
  my $window = Irssi::window_find_refnum(int($event->{'window'}));
  my $line = $window->view->{buffer}->{cur_line};
  my @lines = ();

  for (my $i = 0; $i < $event->{'count'} && defined($line); $line = $line->prev) {
    my $l = $line->get_text($event->{'color'});
    push(@lines, $l);
    $i++;
  }

  @lines = reverse(@lines);

  sendto_client($client, {
    event => "scrollback",
    window => $event->{'window'},
    lines => \@lines,
  });
}

sub gui_print_text_finished {
  my ($window) = @_;
  my $ref = $window->{'refnum'}; 
  my $color_line = $window->view->{buffer}->{cur_line}->get_text(1);
  my $plain_line = $window->view->{buffer}->{cur_line}->get_text(0);

  while (my ($client, $chash) = each %clients) {
    if ($chash->{'activewindow'} == int($ref)) {
      my $line;

      if($chash->{'color'}) {
        $line = $color_line;
      } else {
        $line = $plain_line;
      }

      sendto_client($chash->{'client'}, {
        event => 'addline',
        window => $ref,
        line => $line,
      });
    }
  }
}

sub window_created {
  my $window = shift;

  sendto_all_clients({
    event => 'addwindow',
    window => "$window->{'refnum'}",
    name => $window->{name},
  });
}

sub window_destroyed {
  my $window = shift;

  sendto_all_clients({
    event => 'delwindow',
    window => "$window->{'refnum'}",
  });
}

sub window_activity {
  my ($window, $oldlevel) = @_;

  sendto_all_clients({
    event => 'activity',
    window => "$window->{'refnum'}",
    level => $window->{data_level},
    oldlevel => $oldlevel,
  });
}

Irssi::signal_add("gui print text finished", "gui_print_text_finished");

# TODO XXX FIXME we still need to handle renumbering
Irssi::signal_add("window created", "window_created");
Irssi::signal_add("window destroyed", "window_destroyed");
Irssi::signal_add("window activity", "window_activity");

Irssi::signal_add("setup changed", "setup_changed");

sub UNLOAD {
  Irssi::timeout_remove($loop_id);
  Irssi::signal_remove("gui print text finished", "gui_print_text_finished");
  Irssi::signal_remove("window created", "window_created");
  Irssi::signal_remove("window destroyed", "window_destroyed");
  Irssi::signal_remove("window activity", "window_activity");
}
