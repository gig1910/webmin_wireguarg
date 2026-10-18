use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Path qw(make_path);
my $subprocess_lib = abs_path(dirname(__FILE__)).'/lib/subprocess-lib.pl';
require $subprocess_lib;

sub _wg_first_executable
{
    foreach my $path (@_) {
        return $path if (defined($path) && length($path) && -x $path);
    }
    return undef;
}

sub _wg_install_log
{
    my ($path, $message) = @_;
    return if (!defined($path) || !length($path));
    if (open(my $fh, '>>', $path)) {
        my @t = localtime();
        printf {$fh} "%04d-%02d-%02d %02d:%02d:%02d %s\n",
            $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0], $message;
        close($fh);
        chmod(0600, $path);
    }
}

sub _wg_slurp
{
    my ($path) = @_;
    return undef if (!defined($path) || !-r $path);
    open(my $fh, '<', $path) || return undef;
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

sub _wg_atomic_write
{
    my ($path, $content, $mode) = @_;
    my $dir = dirname($path);
    my $tmp = "$path.tmp.$$";
    open(my $fh, '>', $tmp) || return (0, "$!");
    print {$fh} $content or do { my $e="$!"; close($fh); unlink($tmp); return (0,$e); };
    close($fh) or do { my $e="$!"; unlink($tmp); return (0,$e); };
    chmod($mode || 0644, $tmp);
    rename($tmp, $path) || do { my $e="$!"; unlink($tmp); return (0,$e); };
    return (1, undef);
}

sub _wg_managed_unit
{
    my ($content) = @_;
    return 0 if (!defined($content));
    return 1 if ($content =~ /^# Managed by Webmin WireGuard module\b/m);
    # Compatibility with module releases before the marker was introduced.
    return 1 if ($content =~ /^Description=Webmin WireGuard traffic and runtime collector$/m &&
                 $content =~ /stats-collector\.pl/);
    return 0;
}

sub _wg_unit_content
{
    my ($perl, $module_dir, $state_dir) = @_;
    return "# Managed by Webmin WireGuard module; use systemd drop-ins for local overrides.\n".
        "[Unit]\n".
        "Description=Webmin WireGuard traffic and runtime collector\n".
        "After=network.target\n".
        "StartLimitIntervalSec=60\n".
        "StartLimitBurst=5\n\n".
        "[Service]\n".
        "Type=simple\n".
        "ExecStart=$perl $module_dir/stats-collector.pl\n".
        "Restart=on-failure\n".
        "RestartSec=5\n".
        "TimeoutStartSec=15\n".
        "TimeoutStopSec=5\n".
        "KillSignal=SIGTERM\n".
        "SendSIGKILL=true\n".
        "KillMode=control-group\n".
        "OOMPolicy=stop\n".
        "UMask=0077\n".
        "NoNewPrivileges=true\n".
        "PrivateTmp=true\n".
        "ProtectSystem=strict\n".
        "ProtectHome=true\n".
        "ProtectKernelTunables=true\n".
        "ProtectKernelModules=true\n".
        "ProtectControlGroups=true\n".
        "RestrictSUIDSGID=true\n".
        "LockPersonality=true\n".
        "RestrictRealtime=true\n".
        "MemoryMax=96M\n".
        "MemorySwapMax=32M\n".
        "CPUQuota=10%\n".
        "TasksMax=32\n".
        "LimitNOFILE=64\n".
        "Nice=10\n".
        "IOSchedulingClass=idle\n".
        "ReadWritePaths=$state_dir -/var/lib/node_exporter/textfile_collector -/var/lib/prometheus/node-exporter\n\n".
        "[Install]\n".
        "WantedBy=multi-user.target\n";
}

sub _wg_unlocode_units
{
    my ($python,$module_dir,$db,$state_dir)=@_;
    my $service="# Managed by Webmin WireGuard module; UN/LOCODE is optional.\n".
        "[Unit]\nDescription=Refresh Webmin WireGuard UN/LOCODE catalog\n".
        "After=network-online.target\nWants=network-online.target\n\n".
        "[Service]\nType=oneshot\n".
        "ExecStart=$python $module_dir/unlocode-update.py $db $state_dir\n".
        "TimeoutStartSec=180\nUMask=0077\nNoNewPrivileges=true\n".
        "PrivateTmp=true\nProtectSystem=strict\nProtectHome=true\n".
        "ReadWritePaths=$state_dir\n\n";
    my $timer="# Managed by Webmin WireGuard module; UN/LOCODE is optional.\n".
        "[Unit]\nDescription=Periodic Webmin WireGuard UN/LOCODE refresh\n\n".
        "[Timer]\nOnCalendar=monthly\nRandomizedDelaySec=12h\n".
        "Persistent=true\nUnit=webmin-wireguard-unlocode.service\n\n".
        "[Install]\nWantedBy=timers.target\n";
    return ($service,$timer);
}

sub _wg_install_unlocode_timer
{
    my ($module_dir,$state_dir,$stats_dir,$unit_dir,$systemctl,$log)=@_;
    return if $ENV{'WEBMIN_WIREGUARD_SKIP_UNLOCODE'};
    my $python=_wg_first_executable('/usr/bin/python3','/bin/python3');
    return _wg_install_log($log,'UN/LOCODE: python3 unavailable, optional update skipped')
        if !$python;
    my ($service,$timer)=_wg_unlocode_units(
        $python,$module_dir,"$stats_dir/analytics.sqlite3",$state_dir);
    my %wanted=(
        'webmin-wireguard-unlocode.service'=>$service,
        'webmin-wireguard-unlocode.timer'=>$timer
    );
    my $changed=0;
    for my $name (sort keys %wanted) {
        my $file="$unit_dir/$name";
        my $old=_wg_slurp($file);
        if (defined($old) && $old !~ /^# Managed by Webmin WireGuard module;/) {
            _wg_install_log($log,"UN/LOCODE: unmanaged unit $file left unchanged");
            return;
        }
        next if defined($old) && $old eq $wanted{$name};
        my ($ok,$error)=_wg_atomic_write($file,$wanted{$name},0644);
        if (!$ok) {
            _wg_install_log($log,"UN/LOCODE: cannot install $file: $error");
            return;
        }
        $changed=1;
    }
    return if !$systemctl;
    system($systemctl,'daemon-reload') if $changed;
    my $enable=system($systemctl,'enable','--now','webmin-wireguard-unlocode.timer');
    # Do not delay the installer for network downloads or CSV imports.
    my $status_file="$state_dir/unlocode-status.json";
    my $recent=0;
    if (-f $status_file) {
        my $mtime=(stat($status_file))[9] || 0;
        $recent=$mtime && time()-$mtime<30*86400 ? 1 : 0;
    }
    my $start=$recent ? 0 :
        system($systemctl,'start','--no-block','webmin-wireguard-unlocode.service');
    _wg_install_log($log,"UN/LOCODE: timer enable=$enable, initial queue=$start, fresh=$recent");
}

sub module_install
{
    my $module_dir = $ENV{'WEBMIN_WIREGUARD_MODULE_DIR'} || abs_path(dirname(__FILE__));
    my $state_dir = $ENV{'WEBMIN_WIREGUARD_STATE_DIR'} || '/var/webmin/wireguard';
    my $stats_dir = "$state_dir/stats";
    my $diagnostic_dir = "$state_dir/diagnostics";
    my $unit = $ENV{'WEBMIN_WIREGUARD_UNIT_PATH'} || '/etc/systemd/system/webmin-wireguard-stats.service';
    my $systemctl = $ENV{'WEBMIN_WIREGUARD_SYSTEMCTL'} || _wg_first_executable('/usr/bin/systemctl', '/bin/systemctl');
    my $perl = $ENV{'WEBMIN_WIREGUARD_PERL'} || _wg_first_executable('/usr/bin/perl', $^X) || $^X;
    my $log = "$state_dir/collector-install.log";

    # Module settings under /etc/webmin/wireguard and existing metrics/history
    # are intentionally not recreated or cleared during upgrades.
    eval {
        make_path($state_dir, { mode => 0700 }) if (!-d $state_dir);
        make_path($stats_dir, { mode => 0700 }) if (!-d $stats_dir);
        make_path($diagnostic_dir, { mode => 0700 }) if (!-d $diagnostic_dir);
        chmod(0700, $state_dir, $stats_dir, $diagnostic_dir);
    };
    if ($@ || !-d $stats_dir) {
        _wg_install_log($log, "cannot create state directories: ".($@ || $!));
        return;
    }

    my $unit_dir = dirname($unit);
    eval { make_path($unit_dir) if (!-d $unit_dir); };
    my $wanted = _wg_unit_content($perl, $module_dir, $state_dir);
    my $current = _wg_slurp($unit);
    my $unit_changed = 0;

    if (defined($current) && !_wg_managed_unit($current)) {
        # Never overwrite a same-named service that was not created by this
        # module.  This is safer than silently taking over an administrator's
        # unrelated or custom service.
        _wg_install_log($log, "existing unit $unit is not module-managed; leaving it unchanged");
    }
    elsif (!defined($current) || $current ne $wanted) {
        if (defined($current)) {
            my $backup_dir = "$state_dir/unit-backups";
            eval { make_path($backup_dir, { mode => 0700 }) if (!-d $backup_dir); };
            if (-d $backup_dir) {
                my $stamp = time();
                my $backup = "$backup_dir/webmin-wireguard-stats.service.$stamp.$$";
                _wg_atomic_write($backup, $current, 0600);
                if (opendir(my $bdh, $backup_dir)) {
                    my @backups = sort {
                        (stat($b))[9] <=> (stat($a))[9]
                    } map { "$backup_dir/$_" }
                      grep { /^webmin-wireguard-stats\.service\.\d+\.\d+$/ && -f "$backup_dir/$_" }
                      readdir($bdh);
                    closedir($bdh);
                    if (@backups > 5) {
                        unlink($_) for @backups[5 .. $#backups];
                    }
                }
            }
        }
        my ($ok, $write_error) = _wg_atomic_write($unit, $wanted, 0644);
        if (!$ok) {
            _wg_install_log($log, "cannot write managed systemd unit $unit: $write_error");
            return;
        }
        $unit_changed = 1;
    }

    # Independent optional location catalog. Queue download asynchronously;
    # unreachable UNECE must never block initial installation or upgrades.
    eval {
        _wg_install_unlocode_timer($module_dir,$state_dir,$stats_dir,
            $unit_dir,$systemctl,$log);
    };
    _wg_install_log($log,"UN/LOCODE optional setup: $@") if $@;

    # Create the first snapshot immediately without deleting existing history.
    if (!$ENV{'WEBMIN_WIREGUARD_SKIP_ONESHOT'}) {
        local $ENV{'WEBMIN_WIREGUARD_ONCE'} = 1;
        local $ENV{'WEBMIN_WIREGUARD_CONFIG'} = $ENV{'WEBMIN_WIREGUARD_CONFIG'} || '/etc/webmin/wireguard/config';
        local $ENV{'WEBMIN_WIREGUARD_STATE_DIR'} = $state_dir;
        # A first-run compaction must not hold the Webmin installer forever.
        # The long-running service will retry collecting after installation.
        my $one_shot_timeout = int($ENV{'WEBMIN_WIREGUARD_ONESHOT_TIMEOUT'} || 120);
        $one_shot_timeout = 1 if $one_shot_timeout < 1;
        $one_shot_timeout = 120 if $one_shot_timeout > 120;
        my ($ok, $out, $err, $rc) = wg_capture_subprocess(
            [$perl, "$module_dir/stats-collector.pl"], '',
            timeout => $one_shot_timeout,
            max_stdout => 65_536, max_stderr => 65_536,
        );
        _wg_install_log($log, "one-shot collector exit=".
            ($rc == -1 ? -1 : ($rc >> 8)).
            " ok=".($ok ? 1 : 0)." error=".substr($err || '', 0, 512));
    }

    if (!$systemctl) {
        _wg_install_log($log, 'systemctl not found; collector unit was prepared but not started');
        return;
    }

    if (defined($current) && !_wg_managed_unit($current)) {
        _wg_install_log($log, 'collector service control skipped because the existing unit is not module-managed');
        return;
    }

    my $reload = $unit_changed ? system($systemctl, 'daemon-reload') : 0;
    my $enable = system($systemctl, 'enable', 'webmin-wireguard-stats.service');
    my $start = $unit_changed
        ? system($systemctl, 'restart', 'webmin-wireguard-stats.service')
        : system($systemctl, 'start', 'webmin-wireguard-stats.service');
    _wg_install_log($log, "unit_changed=$unit_changed, daemon-reload exit=".
        ($reload == -1 ? -1 : ($reload >> 8)).", enable exit=".
        ($enable == -1 ? -1 : ($enable >> 8)).", service action exit=".
        ($start == -1 ? -1 : ($start >> 8)));
}

1;
