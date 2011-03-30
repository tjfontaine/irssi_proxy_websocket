#!/usr/bin/env perl

use strict;
use vars qw($VERSION %IRSSI);

use IO::Socket::SSL;
use IO::Socket::INET;
use Errno;

use Irssi;
use Irssi::TextUI;

use JSON;
use Data::Dumper;

use Mojolicious::Lite;
use Mojo::Server::Daemon;

use File::Basename 'dirname';
use File::Spec;

# Mojo likes to spew, this makes irssi mostly unsuable
app->log->level('fatal');
app->static->root(File::Spec->catdir(dirname(__FILE__), 'client'));

Irssi::settings_add_str('irssi_proxy_websocket', 'ipw_listenurl', 'http://localhost:3000');

my $daemon = Mojo::Server::Daemon->new(
  app => app,
  listen => [Irssi::settings_get_str('ipw_listenurl')]
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
  #TODO XXX FIXME isn't there some on_close mechanism we should pay attention to?
};

get '/' => sub {
  my $client = shift;
  return $client->redirect_to('index.html');
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

sub UNLOAD {
  # TODO XXX FIXME boy wouldn't it be great if we could reload this without quitting?
  # The source indicates some checks for REUSE maybe we're just not setting this up
  # properly, but unloading should at least make the script stop listening
  Irssi::timeout_remove($loop_id);
  Irssi::signal_remove("gui print text finished", "gui_print_text_finished");
  Irssi::signal_remove("window created", "window_created");
  Irssi::signal_remove("window destroyed", "window_destroyed");
  Irssi::signal_remove("window activity", "window_activity");

  $daemon = undef;
}
