#!/usr/bin/env perl

use strict;
use vars qw($VERSION %IRSSI);

use IO::Socket::INET;
use Errno;

use Irssi;

use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;

$VERSION = '0.0.1';
%IRSSI = (
  authors => 'Timothy J Fontaine',
  contact => 'tjfontaine@gmail.com',
  name    => 'irssi_proxy_websocket',
  license => 'MIT/X11',
  description => 'Proxy module that listens on a WebSocket',
);

my $socket = IO::Socket::INET->new(
    Blocking  => 0,
    LocalAddr => '0.0.0.0',
    LocalPort => 3000,
    Proto     => 'tcp',
    Type      => SOCK_STREAM,
    Listen    => 1,
    ReuseAddr => 1,
);

Irssi::theme_register(
[
 'irssi_proxy_websocket',
 '{line_start}{hilight ' . $IRSSI{'name'} . ':} $0'
]);

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
  my $frame = Protocol::WebSocket::Frame->new($msg);
  my $buffer = $frame->to_string;
  while(length($buffer) > 0) {
    my $rs = $client->syswrite($buffer);
    $buffer = substr($buffer, $rs);
  }
}

sub sendto_all_clients {
  my $msg = shift;

  while (my ($client, $chash) = each %clients) {
    sendto_client($chash->{'client'}, $msg . "\r\n");
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
  $message =~ s/\r\n//;
  my (@parts, $source);

  if ($message =~ /^:/) {
    @parts = split(/ /, $message, 2);
    $source = substr($parts[0], 2);
    $message = $parts[1];
  }

  @parts = split(/ /, $message, 2);

  my $command = $parts[0];
  my $plen = @parts;

  if ($plen == 1) {
    $message = undef;
  } else {
    $message = $parts[1];
  }

  my @params = ();

  while (defined ($message) && !($message =~ /^:/)) {
    @parts = split(/ /, $message, 2);
    push(@params, $parts[0]);
    $plen = @parts;

    if ($plen > 1) {
      $message = $parts[1];
    } else {
      $message = undef;
    }
  }

  if (defined ($message) && $message =~ /^:/) {
    push (@params, substr($message, 1));
  }
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
      logmsg('Client Connected!');
    }
    return;
  }

  $frame->append($chunk);
  while (defined(my $message = $frame->next)) {
    parse_msg($client, $message);
  }
}

sub server_incoming {
  my ($server, $line) = @_;
  sendto_all_clients($line);
}

Irssi::signal_add("server incoming", "server_incoming");
