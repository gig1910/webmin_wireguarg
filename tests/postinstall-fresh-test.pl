#!/usr/bin/env perl
use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec;

my $tmp = tempdir(CLEANUP => 1);
my $module = "$tmp/module";
my $state = "$tmp/state";
my $unit = "$tmp/systemd/webmin-wireguard-stats.service";
my $systemctl = "$tmp/systemctl";
my $systemctl_log = "$tmp/systemctl.log";
make_path($module);

open(my $collector, '>', "$module/stats-collector.pl") or die $!;
print {$collector} <<'COLLECTOR';
#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
my $state = $ENV{'WEBMIN_WIREGUARD_STATE_DIR'} or die "missing state dir";
make_path("$state/stats") if (!-d "$state/stats");
open(my $fh, '>', "$state/stats/runtime.json") or die $!;
print {$fh} '{"timestamp":1,"interfaces":{}}';
close($fh);
COLLECTOR
close($collector);
chmod(0755, "$module/stats-collector.pl");

open(my $ctl, '>', $systemctl) or die $!;
print {$ctl} <<'SYSTEMCTL';
#!/bin/sh
set -eu
test -d "$WEBMIN_WIREGUARD_STATE_DIR"
test -d "$WEBMIN_WIREGUARD_STATE_DIR/stats"
printf '%s\n' "$*" >> "$WEBMIN_WIREGUARD_SYSTEMCTL_LOG"
exit 0
SYSTEMCTL
close($ctl);
chmod(0755, $systemctl);

local $ENV{'WEBMIN_WIREGUARD_MODULE_DIR'} = $module;
local $ENV{'WEBMIN_WIREGUARD_STATE_DIR'} = $state;
local $ENV{'WEBMIN_WIREGUARD_UNIT_PATH'} = $unit;
local $ENV{'WEBMIN_WIREGUARD_SYSTEMCTL'} = $systemctl;
local $ENV{'WEBMIN_WIREGUARD_SYSTEMCTL_LOG'} = $systemctl_log;
local $ENV{'WEBMIN_WIREGUARD_PERL'} = $^X;

require './postinstall.pl';
module_install();

die "state directory not created\n" if (!-d $state);
die "stats directory not created\n" if (!-d "$state/stats");
die "diagnostics directory not created\n" if (!-d "$state/diagnostics");
die "one-shot snapshot not created\n" if (!-s "$state/stats/runtime.json");
die "unit not created\n" if (!-s $unit);

open(my $ufh, '<', $unit) or die $!;
local $/;
my $unit_text = <$ufh>;
close($ufh);
die "unit missing writable state path\n" if ($unit_text !~ /^ReadWritePaths=\Q$state\E$/m);
die "unit missing collector path\n" if ($unit_text !~ /\Q$module\/stats-collector.pl\E/);

open(my $lfh, '<', $systemctl_log) or die $!;
my $calls = <$lfh>;
close($lfh);
die "systemctl daemon-reload not called\n" if ($calls !~ /daemon-reload/);
die "systemctl enable not called\n" if ($calls !~ /enable webmin-wireguard-stats\.service/);
die "systemctl restart not called for a newly written unit\n" if ($calls !~ /restart webmin-wireguard-stats\.service/);

# Existing module-managed units are updated atomically while state/history are preserved.
open(my $hist, '>', "$state/stats/keep.history") or die $!;
print {$hist} "keep\n";
close($hist);
open(my $managed, '>', $unit) or die $!;
print {$managed} "[Unit]\nDescription=Webmin WireGuard traffic and runtime collector\n[Service]\nExecStart=/old/stats-collector.pl\n";
close($managed);
open(my $dropin, '>', "$tmp/dropin-preserved") or die $!;
print {$dropin} "preserved\n";
close($dropin);
module_install();
die "history was removed during upgrade\n" if (!-s "$state/stats/keep.history");
die "managed unit backup was not created\n" if (!glob("$state/unit-backups/webmin-wireguard-stats.service.*"));

# An unrelated same-name unit must never be overwritten or controlled.
open(my $foreign, '>', $unit) or die $!;
print {$foreign} "[Unit]\nDescription=Foreign service\n[Service]\nExecStart=/bin/true\n";
close($foreign);
unlink($systemctl_log);
module_install();
open(my $check_foreign, '<', $unit) or die $!;
local $/; my $foreign_text = <$check_foreign>; close($check_foreign);
die "foreign unit was overwritten\n" if ($foreign_text !~ /Description=Foreign service/);
if (-e $systemctl_log) {
    open(my $foreign_log, '<', $systemctl_log) or die $!;
    my $foreign_calls = do { local $/; <$foreign_log> };
    close($foreign_log);
    die "foreign unit was controlled\n" if ($foreign_calls =~ /(?:enable|start|restart).*webmin-wireguard-stats/);
}

print "fresh-install and upgrade-preservation collector setup tests passed\n";
