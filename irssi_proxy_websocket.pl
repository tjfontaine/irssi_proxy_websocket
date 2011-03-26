#!/usr/bin/env perl

use strict;
use vars qw($VERSION %IRSSI);

use IO::Socket::INET;
use Errno;

use Irssi;
use Irssi::TextUI;

use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;

use JSON;
use Data::Dumper;

use HTML::Entities;

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

my $socket = IO::Socket::INET->new(
    Blocking  => 0,
    LocalAddr => '0.0.0.0',
    LocalPort => 3000,
    Proto     => 'tcp',
    Type      => SOCK_STREAM,
    Listen    => 1,
    ReuseAddr => 1,
);
$socket->blocking(0);
$socket->listen;

Irssi::input_add($socket->fileno, Irssi::INPUT_READ, \&socket_datur, 0);

my %clients = ();

sub socket_datur ($) {
  my $client;
  if ($client = $socket->accept) {
    my $client_pipe;
    $clients{$client} = {
      hs => Protocol::WebSocket::Handshake::Server->new,
      frame => Protocol::WebSocket::Frame->new,
      cpipe => \$client_pipe,
      client => $client,
      connected => 0,
      activewindow => 0,
    };
    $client_pipe = Irssi::input_add($client->fileno, Irssi::INPUT_READ, \&client_datur, $client);
  }
}

sub logmsg {
  my $msg = shift;
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'irssi_proxy_websocket', $msg);
}

sub sendto_client {
  my ($client, $msg) = @_;
  my $chash = $clients{$client};

  if ($chash->{'connected'}) {
    $msg = $json->encode($msg);

    my $frame = Protocol::WebSocket::Frame->new($msg);
    my $buffer = $frame->to_string;
    while(length($buffer) > 0) {
      my $rs = $client->syswrite($buffer);
      $buffer = substr($buffer, $rs);
    }
  }
}

sub sendto_all_clients {
  my $msg = shift;

  while (my ($client, $chash) = each %clients) {
    sendto_client($chash->{'client'}, $msg);
  }
}

sub close_client {
  my ($client, $msg) = @_;
  my $cpipe = $clients{$client}->{'cpipe'};
  Irssi::input_remove($$cpipe);
  logmsg($msg);
  delete $clients{$client};
  #$client->shutdown;
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
  my $view = $window->view();
  my @lines = ();

  for (my $line = $view->get_lines(); defined($line); $line = $line->next) {
    push(@lines, encode_entities($line->get_text(0)));
  }

  @lines = @lines[-100..-1];

  sendto_client($client, {
    event => "scrollback",
    window => $event->{'window'},
    lines => \@lines,
  });
}

sub client_datur {
  my $client = shift;
  my $chash = $clients{$client};

  my $hs = $chash->{'hs'};
  my $frame = $chash->{'frame'};

  my $rs = $client->sysread(my $chunk, 512);
  
  if ($rs == 0 || (!defined $rs && !$!{EAGAIN})) {
    close_client($client, "Connection Closed");
    return;
  }

  if (!$hs->is_done) {
    unless (defined $hs->parse($chunk)) {
      close_client($client, "Handshake Fail: " . $hs->error);
      return;
    }
    if ($hs->is_done) {
      $client->syswrite($hs->to_string);
      client_connected($client);
    }
    return;
  }

  $frame->append($chunk);
  while (defined(my $message = $frame->next)) {
    parse_msg($client, $message);
  }
}

sub client_connected {
  my $client = shift;
  my $chash = $clients{$client};

  logmsg('Client Connected!');
  $chash->{'connected'} = 1;
}

my $whash = {};

sub gui_print_text {
  #"gui print text", WINDOW_REC, int fg, int bg, int flags, char *text, TEXT_DEST_REC
  my ($window, $fg, $bg, $flags, $text, $tdest) = @_;
  my $ref = $window->{'refnum'};
  unless (defined($whash->{$ref})) {
    $whash->{$ref} = ''; 
  }
  $whash->{$ref} .= encode_entities($text);
}

sub gui_print_text_finished {
  my ($window) = @_;
  my $ref = $window->{'refnum'}; 

  while (my ($client, $chash) = each %clients) {
    if ($chash->{'activewindow'} == int($ref)) {
      sendto_client($chash->{'client'}, {
        event => 'addline',
        window => $ref,
        line => $whash->{$ref},
      });
    }
  }
  $whash->{$ref} = '';
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

Irssi::signal_add("gui print text", "gui_print_text");
Irssi::signal_add("gui print text finished", "gui_print_text_finished");

Irssi::signal_add("window created", "window_created");
Irssi::signal_add("window destroyed", "window_destroyed");
Irssi::signal_add("window activity", "window_activity");
