use strict;
use warnings;
use File::Basename qw(dirname);

sub _wg_uninstall_first_executable
{
    foreach my $path (@_) {
        return $path if (defined($path) && length($path) && -x $path);
    }
    return undef;
}

sub _wg_uninstall_slurp
{
    my ($path) = @_;
    return undef if (!defined($path) || !-r $path);
    open(my $fh, '<', $path) || return undef;
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

sub _wg_uninstall_managed_unit
{
    my ($content) = @_;
    return 0 if (!defined($content));
    return 1 if ($content =~ /^# Managed by Webmin WireGuard module\b/m);
    return 1 if ($content =~ /^Description=Webmin WireGuard traffic and runtime collector$/m &&
                 $content =~ /stats-collector\.pl/);
    return 0;
}

sub _wg_uninstall_log
{
    my ($state_dir, $message) = @_;
    return if (!defined($state_dir) || !-d $state_dir);
    my $path = "$state_dir/collector-install.log";
    if (open(my $fh, '>>', $path)) {
        my @t = localtime();
        printf {$fh} "%04d-%02d-%02d %02d:%02d:%02d %s\n",
            $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0], $message;
        close($fh);
        chmod(0600, $path);
    }
}

sub module_uninstall
{
    my $unit = $ENV{'WEBMIN_WIREGUARD_UNIT_PATH'} ||
        '/etc/systemd/system/webmin-wireguard-stats.service';
    my $state_dir = $ENV{'WEBMIN_WIREGUARD_STATE_DIR'} || '/var/webmin/wireguard';
    my $systemctl = $ENV{'WEBMIN_WIREGUARD_SYSTEMCTL'} ||
        _wg_uninstall_first_executable('/usr/bin/systemctl', '/bin/systemctl');
    my $content = _wg_uninstall_slurp($unit);

    # Never take ownership of or remove a same-named administrator service.
    if (defined($content) && !_wg_uninstall_managed_unit($content)) {
        _wg_uninstall_log($state_dir,
            "uninstall left foreign unit $unit unchanged");
        return;
    }

    if (defined($content)) {
        system($systemctl, 'disable', '--now', 'webmin-wireguard-stats.service')
            if (defined($systemctl) && -x $systemctl);
        if (!unlink($unit)) {
            _wg_uninstall_log($state_dir, "cannot remove managed unit $unit: $!");
            return;
        }
        system($systemctl, 'daemon-reload')
            if (defined($systemctl) && -x $systemctl);
    }

    # Module configuration, WireGuard configuration, metrics history, backups,
    # diagnostics and systemd drop-ins are deliberately preserved.  Removing
    # operational data must remain an explicit administrator action.
    _wg_uninstall_log($state_dir,
        'module uninstalled; configuration and state directories preserved');
}

1;
