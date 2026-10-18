#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
our $WIREGUARD_WEBMIN_VERSION;
$config{'stats_enabled'} = 1;
$config{'stats_refresh_interval'} = 5;
$config{'stats_live_window'} = 900;
$text{'graph_title'} = 'Traffic';
$text{'runtime_updated'} = 'Updated';
$text{'graph_tx_total'} = 'Sent';
$text{'graph_rx_total'} = 'Received';
$text{'status_not_running'} = 'Not running';
$text{'runtime_loading'} = 'Loading';
require "$FindBin::Bin/../wireguard-lib.pl";

sub main::html_escape { my ($v)=@_; $v='' if !defined $v; $v =~ s/&/&amp;/g; $v =~ s/</&lt;/g; $v =~ s/>/&gt;/g; $v =~ s/"/&quot;/g; return $v; }
sub main::urlize { my ($v)=@_; $v='' if !defined $v; $v =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X',ord($1))/eg; return $v; }

my $peer_html = graph_html('wg0', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', 'Peer traffic');
die "peer period selector missing\n" if $peer_html !~ /data-wg-period/;
die "peer custom date inputs missing\n" if $peer_html !~ /data-wg-from/ || $peer_html !~ /data-wg-to/;
die "peer range URL missing\n" if $peer_html !~ /url.searchParams.set\('from'/;
my $expected_version = $WIREGUARD_WEBMIN_VERSION;
my $html = graph_html('wg0', '', 'Traffic').runtime_poll_html('wg0').$peer_html;
die "runtime URL is not module-absolute/versioned\n" if $html !~ m{/wireguard/runtime\.cgi\?_wg_api=\Q$expected_version\E&amp;name=wg0};
die "history URL is not module-absolute/versioned\n" if $html !~ m{/wireguard/history\.cgi\?_wg_api=\Q$expected_version\E&amp;name=wg0};
die "runtime poller has no detached-page cleanup\n" if $html !~ /root\.isConnected/ || $html !~ /state\.cleanup/;
die "runtime poller does not stop on non-JSON response\n" if $html !~ /if\(error\.nonJson\)cleanup\(\)/;
die "runtime poller does not validate Content-Type\n" if $html !~ /content-type/;
my @scripts = ($html =~ m{<script>(.*?)</script>}sg);
die "no async scripts generated\n" if !@scripts;
my $node = `command -v node 2>/dev/null`; chomp $node;
if ($node) {
    my $index = 0;
    for my $script (@scripts) {
        my $path = "$FindBin::Bin/async-script-$$-".($index++).".js";
        open(my $fh, '>', $path) or die $!;
        print {$fh} $script;
        close($fh);
        system($node, '--check', $path) == 0 or die "JavaScript syntax check failed\n";
        unlink($path);
    }
}
print "asynchronous JavaScript tests passed\n";
