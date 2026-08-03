#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use Digest::SHA ();
require "$FindBin::Bin/../lib/collector-config-lib.pl";

my $defaults = collector_effective_settings({});
die "bad default interval\n" unless $defaults->{'stats_refresh_interval'} == 5;
die "bad default retention\n" unless $defaults->{'stats_history_retention'} == 86400;
die "bad effective file cap\n" unless $defaults->{'stats_effective_file_bytes'} == 8388608;

my $tight = collector_effective_settings({
    stats_max_file_bytes => 8388608,
    stats_max_total_bytes => 262144,
    stats_history_retention => 300,
});
die "aggregate cap must constrain a single history file\n"
    unless $tight->{'stats_effective_file_bytes'} == 262144;
my $f1 = collector_settings_fingerprint($defaults);
my $f2 = collector_settings_fingerprint($tight);
die "collector fingerprint did not change\n" if $f1 eq $f2;
die "collector fingerprint is malformed\n" unless $f1 =~ /^[0-9a-f]{64}$/;

open(my $fh, '<', "$FindBin::Bin/../collector_status.cgi") or die $!;
local $/; my $status = <$fh>; close($fh);
die "running-settings mismatch detection missing\n"
    if $status !~ /restart_required/ || $status !~ /collector_settings_fingerprint/;
my ($desired_block) = $status =~ /(my \$desired.*?my \$ok)/s;
die "cannot locate collector desired-state check\n" if !defined($desired_block);
die "failed stop state is incorrectly accepted as a clean stop\n" if $desired_block =~ /eq 'failed'/;

open($fh, '<', "$FindBin::Bin/../index.cgi") or die $!;
local $/; my $index = <$fh>; close($fh);
die "collector restart warning UI missing\n"
    if $index !~ /collector_restart_required/ || $index !~ /data-role="warning"/;

for my $file (qw(config.info config.info.ru)) {
    open($fh, '<', "$FindBin::Bin/../$file") or die $!;
    local $/; my $info = <$fh>; close($fh);
    for my $key (qw(stats_refresh_interval stats_history_enabled stats_history_retention runtime_timeout stats_max_points stats_max_file_bytes stats_max_total_bytes stats_health_interval)) {
        my ($line) = $info =~ /^\Q$key\E=(.*)$/m;
        die "$file does not mark $key as restart-sensitive\n"
            if !defined($line) || $line !~ /restart|перезапуск/i;
    }
}

print "collector settings and restart-warning tests passed\n";
