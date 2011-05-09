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

Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_host', 'localhost');
Irssi::settings_add_int('irssi_proxy_websocket', 'ipw_port', 3000);
Irssi::settings_add_bool('irssi_proxy_websocket', 'ipw_ssl', 0);
Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_cert', '');
Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_key', '');
Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_password', '');

my $daemon;
my $loop_id;

sub mojoify {
  $ENV{MOJO_REUSE} = 1;

  # Mojo likes to spew, this makes irssi mostly unsuable
  app->log->level('fatal');

  # TODO XXX FIXME this should be a setting
  app->static->root(File::Spec->catdir(dirname(__FILE__), 'client'));
  my $listen_url;

  my $host = Irssi::settings_get_str('ipw_host');
  my $port = Irssi::settings_get_int('ipw_port');
  my $cert = Irssi::settings_get_str('ipw_cert');
  my $key  = Irssi::settings_get_str('ipw_key');

  if(Irssi::settings_get_bool('ipw_ssl') && -e $cert && -e $key) {
    $listen_url = sprintf("https://%s:%d:%s:%s", $host, $port, $cert, $key);
  } else {
    $listen_url = sprintf("http://%s:%d", $host, $port);
  }

  $daemon = Mojo::Server::Daemon->new(app => app);
  $daemon->listen([$listen_url]);

  # TODO XXX FIXME mojo creates a random port for some ioloop operations
  # this is bound to make people angry who don't understand why
  $daemon->prepare_ioloop;

  #TODO XXX FIXME we may be able to up this to 1000 or higher if abuse
  # mojo ->{handle} into the input_add system
  $loop_id = Irssi::timeout_add(100, \&ws_loop, 0);
}

mojoify();

sub setup_changed {
  my ($cert, $key);
  $cert = Irssi::settings_get_str('ipw_cert');
  $key  = Irssi::settings_get_str('ipw_key');

  if(length($cert) && !-e $cert) {
    logmsg("Certificate file doesn't exist: $cert");
  }
  if(length($key) && !-e $key) {
    logmsg("Key file doesn't exist: $key");
  }

  # TODO XXX FIXME
  # we should probably check that it was us that changed
  mojoify();
};

sub ws_loop {
  if($daemon) {
    $daemon->ioloop->one_tick;
  }
}

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
    color => 0,
    authenticated => 0,
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

sub sendto_client {
  my ($client, $msg) = @_;
  if($clients{$client}->{'authenticated'}) {
    $client->send_message($json->encode($msg));
  }
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
  } elsif ($command->{'event'} eq 'authenticate') {
    authenticate($client, $command);
  } elsif ($command->{'event'} eq 'configure') {
    configure($client, $command);
  } elsif ($command->{'event'} eq 'activeitem') {
    activeitem($client, $command);
  } elsif ($command->{'event'} eq 'listitems') {
    listitems($client, $command);
  } else {
    logmsg($command->{'event'});
  }
}

sub activewindow {
  my ($client, $event) = @_;
  my $window = Irssi::window_find_refnum(int($event->{'window'}));
  $window->set_active();
}

sub activeitem {
  my ($client, $event) = @_;
  my $window = Irssi::window_find_refnum(int($event->{'window'}));
  for my $item ($window->items) {
    if ($item->{name} eq $event->{'name'}) {
      $item->set_active();
      return;
    }
  }
}

sub get_items {
  my $window = shift;
  my @items = ();
  for my $item ($window->items) {
    push(@items, {
      name => $item->{name},
      type => $item->{type},
      active => $item->is_active,
    });
  }
  return @items;
}

sub listitems {
  my ($client, $event) = @_;
  my $window = Irssi::window_find_refnum(int($event->{'window'}));
  my @items = get_items($window);
  sendto_client($client, {
    event => "itemlist",
    items => \@items,
    window => $event->{'window'},
  });
}

sub listwindows {
  my ($client, $event) = @_;
  
  my $active_window = Irssi::active_win()->{'refnum'};

  my @windows = ();
  foreach my $window (Irssi::windows()) {
    my @items = get_items($window);
    my $entry = {
      window => "$window->{'refnum'}",
      name => $window->{name},
      items => \@items,
      data_level => $window->{data_level},
      active => $active_window == $window->{refnum} ? 1 : 0,
    };
    
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

my $wants_hilight_message = {};

sub gui_print_text_finished {
  my ($window) = @_;
  my $ref = $window->{'refnum'}; 
  my $color_line = $window->view->{buffer}->{cur_line}->get_text(1);
  my $plain_line = $window->view->{buffer}->{cur_line}->get_text(0);

  while (my ($client, $chash) = each %clients) {
    my $line = $plain_line;

    if($chash->{'color'}) {
      $line = $color_line;
    }
  
    if ($wants_hilight_message->{$ref}) {
      sendto_client($chash->{'client'}, {
        event => 'hilight',
        window => $ref,
        line => $line,
      });
    }

    sendto_client($chash->{'client'}, {
      event => 'addline',
      window => $ref,
      line => $line,
    });
  }

  if ($wants_hilight_message->{$ref}) {
    delete $wants_hilight_message->{$ref};
  }
}

sub authenticate {
  my ($client, $event) = @_;
  my $chash = $clients{$client};

  if ($event->{'password'} eq Irssi::settings_get_str('ipw_password')) {
    $chash->{'authenticated'} = 1;
    sendto_client($chash->{'client'}, {
      event => 'authenticated',
    });
  }
}

sub configure {
  my ($client, $event) = @_;
  my $chash = $clients{$client};

  for my $key (keys %{$event}) {
    if($key ne 'event') {
      $chash->{$key} = $event->{$key};
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

  while (my ($client, $chash) = each %clients) {
    sendto_client($chash->{'client'}, {
      event => 'activity',
      window => "$window->{'refnum'}",
      level => $window->{data_level},
      oldlevel => $oldlevel,
    });
  }
}

sub window_hilight {
  my $window = shift;
  $wants_hilight_message->{$window->{'refnum'}} = 1;
}

sub window_refnum_changed {
  my ($window, $oldnum) = @_;

  sendto_all_clients({
    event => 'renumber',
    old => $oldnum,
    cur => $window->{'refnum'},
  });
}

sub window_item_list {
  my ($window, $item) = @_;
  my @items = get_items($window);
  sendto_all_clients({
    event => 'itemlist',
    items => \@items,
    window => $window->{'refnum'},
  })
}

Irssi::signal_add("gui print text finished", "gui_print_text_finished");

Irssi::signal_add("window created", "window_created");
Irssi::signal_add("window destroyed", "window_destroyed");
Irssi::signal_add("window activity", "window_activity");
Irssi::signal_add_first("window hilight", "window_hilight");
Irssi::signal_add("window refnum changed", "window_refnum_changed");
Irssi::signal_add("window item new", "window_item_list");
Irssi::signal_add("window item remove", "window_item_list");
Irssi::signal_add("window item name changed", "window_item_list");

Irssi::signal_add("setup changed", "setup_changed");

sub UNLOAD {
  Irssi::timeout_remove($loop_id);
  Irssi::signal_remove("gui print text finished", "gui_print_text_finished");
  Irssi::signal_remove("window created", "window_created");
  Irssi::signal_remove("window destroyed", "window_destroyed");
  Irssi::signal_remove("window activity", "window_activity");
}
