#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Temp qw(tempdir);

my $tmp = tempdir(CLEANUP => 1);
my $state = "$tmp/state";
my $unit = "$tmp/webmin-wireguard-stats.service";
my $ctl = "$tmp/systemctl";
my $log = "$tmp/systemctl.log";
make_path($state);
open(my $cfh, '>', "$state/preserve.history") or die $!;
print {$cfh} "keep\n";
close($cfh);
open(my $sfh, '>', $ctl) or die $!;
print {$sfh} "#!/bin/sh\nprintf '%s\\n' \"\$*\" >> '$log'\nexit 0\n";
close($sfh);
chmod(0755, $ctl);

local $ENV{'WEBMIN_WIREGUARD_UNIT_PATH'} = $unit;
local $ENV{'WEBMIN_WIREGUARD_STATE_DIR'} = $state;
local $ENV{'WEBMIN_WIREGUARD_SYSTEMCTL'} = $ctl;
require './uninstall.pl';

open(my $ffh, '>', $unit) or die $!;
print {$ffh} "[Unit]\nDescription=Administrator service\n[Service]\nExecStart=/bin/sleep infinity\n";
close($ffh);
module_uninstall();
die "foreign unit removed\n" if !-f $unit;
die "systemctl touched foreign unit\n" if -e $log && -s $log;

open(my $mfh, '>', $unit) or die $!;
print {$mfh} "# Managed by Webmin WireGuard module; use systemd drop-ins for local overrides.\n[Unit]\nDescription=Webmin WireGuard traffic and runtime collector\n[Service]\nExecStart=/usr/bin/perl /usr/share/webmin/wireguard/stats-collector.pl\n";
close($mfh);
module_uninstall();
die "managed unit not removed\n" if -e $unit;
die "state data removed\n" if !-f "$state/preserve.history";
open(my $lfh, '<', $log) or die "systemctl log missing\n";
local $/; my $commands = <$lfh>; close($lfh);
die "disable command missing\n" if $commands !~ /disable --now webmin-wireguard-stats\.service/;
die "daemon-reload missing\n" if $commands !~ /daemon-reload/;
print "safe uninstall and state preservation tests passed\n";
