#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

open(my $fh, '<', "$FindBin::Bin/../postinstall.pl") or die $!;
local $/; my $unit_source = <$fh>; close($fh);
for my $setting (qw(
    NoNewPrivileges PrivateTmp ProtectSystem ProtectHome
    ProtectKernelTunables ProtectKernelModules ProtectControlGroups
    RestrictSUIDSGID MemoryMax MemorySwapMax CPUQuota TasksMax Nice
    IOSchedulingClass ReadWritePaths TimeoutStartSec TimeoutStopSec
    KillSignal SendSIGKILL KillMode StartLimitIntervalSec StartLimitBurst
    OOMPolicy LimitNOFILE
)) {
    die "systemd hardening missing $setting\n" if $unit_source !~ /\Q$setting\E=/;
}
die "collector stop timeout is not bounded to five seconds\n"
    if $unit_source !~ /TimeoutStopSec=5/;

open($fh, '<', "$FindBin::Bin/../stats-collector.pl") or die $!;
local $/; my $collector = <$fh>; close($fh);
for my $feature (qw(config_fingerprint history_storage_bytes last_compaction health.json .collector.lock interruptible_pause terminate_child)) {
    die "collector bound/health feature missing $feature\n" if index($collector, $feature) < 0;
}

open($fh, '<', "$FindBin::Bin/../lib/collector-config-lib.pl") or die $!;
local $/; my $shared = <$fh>; close($fh);
for my $feature (qw(stats_max_points stats_max_file_bytes stats_max_total_bytes collector_effective_settings collector_settings_fingerprint)) {
    die "shared collector normalization missing $feature\n" if index($shared, $feature) < 0;
}

print "collector hardening tests passed\n";
