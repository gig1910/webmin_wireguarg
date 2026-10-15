#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
require "$FindBin::Bin/../wireguard-lib.pl";

my $history = [
    { timestamp=>100, rx=>100, tx=>200 },
    { timestamp=>105, rx=>150, tx=>280 },
    { timestamp=>110, rx=>190, tx=>300 },
    { timestamp=>140, rx=>2, tx=>310 },
    { timestamp=>145, rx=>20, tx=>3 },
    { timestamp=>150, rx=>30, tx=>50 },
];
my $summary = peer_usage_summary($history, 100, 150, 5);
die "received total incorrect: $summary->{rx}\n" unless $summary->{rx} == 118;
die "sent total incorrect: $summary->{tx}\n" unless $summary->{tx} == 167;
die "reset count incorrect\n" unless $summary->{resets} == 2;
die "gap not detected\n" unless $summary->{gaps} == 1;
die "observed timestamps incorrect\n" unless $summary->{first} == 100 && $summary->{last} == 150;
my $short = peer_usage_summary($history, 105, 110, 5);
die "short window incorrectly includes outside counters\n"
    unless $short->{rx} == 40 && $short->{tx} == 20 && $short->{intervals} == 1;
my $empty = peer_usage_summary([], 100, 150, 5);
die "empty history still reports measured traffic\n" if $empty->{intervals};
my $one = peer_usage_summary([$history->[0]], 100, 150, 5);
die "single observation incorrectly counts traffic\n" if $one->{intervals};

my $tmp = tempdir(CLEANUP=>1);
$config{'stats_dir'} = $tmp;
my $path = stats_history_path('wg0','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
open(my $fh, '>', $path) or die $!;
for my $row (@$history) {
    print {$fh} JSON::PP::encode_json($row)."\n";
}
close($fh);
my $selected = read_stats_history('wg0','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', 105, 100, 145);
die "bounded history was not in chronological order\n"
    unless @$selected == 4 && $selected->[0]->{timestamp} == 105 &&
        $selected->[-1]->{timestamp} == 145;
die "reader did not enforce upper timestamp\n"
    if grep { $_->{timestamp} > 145 } @$selected;
my $none = read_stats_history('wg0','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', 111, 100, 139);
die "reader leaked results outside empty range\n" if @$none;

my $html = graph_html('wg0','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=','Peer traffic');
die "peer graph missing range control\n" if $html !~ /data-wg-period/;
die "peer graph incorrectly uses unfiltered live graph\n" if $html =~ /class="wg-traffic-canvas"/;
print "peer consumption range and counter reset tests passed\n";
