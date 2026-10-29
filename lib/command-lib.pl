=head1 command-lib.pl

Internal module.

=cut

sub conf_dir { return $config{'conf_dir'} || '/etc/wireguard'; }
sub conf_path
{
    my ($name) = @_;
    error($text{'error_invalid_name'}) if (!valid_interface_name($name));
    return File::Spec->catfile(conf_dir(), $name.'.conf');
}

sub command_path
{
    my ($key, $fallback) = @_;
    return $config{$key} || $fallback;
}

sub shell_quote
{
    my ($value) = @_;
    $value = '' if (!defined($value));
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub run_command
{
    my ($argv, $safe, $timeout, $max_output) = @_;
    $timeout ||= int($config{'command_timeout'} || 15);
    $max_output ||= 20000;
    my $cmd = join(' ', map { shell_quote($_) } @$argv).' 2>&1';
    my $output = backquote_with_timeout($cmd, $timeout, $safe ? 1 : 0, $max_output);
    my $status = $?;
    return ($status == 0, $output, $status, $cmd);
}

sub run_command_stdin
{
    my ($argv, $stdin) = @_;
    my ($ok, $out, $err) = wg_capture_subprocess(
        $argv, $stdin,
        timeout => 30,
        max_stdout => 8_388_608,
        max_stderr => 65_536,
    );
    return ($ok, $out, $err);
}

sub require_command
{
    my ($path) = @_;
    error(text('error_command', $path)) if (!$path || !has_command($path));
}


# wg-quick invokes 'resolvconf' by name for [Interface] DNS entries.
# Match the inherited PATH of the wg-quick subprocess; resolvectl alone
# does not provide the required resolvconf command.
sub wg_quick_resolvconf_command
{
    foreach my $directory (split(/:/, $ENV{'PATH'} || '')) {
        next if (!length($directory));
        my $candidate = File::Spec->catfile($directory, 'resolvconf');
        return $candidate if (-f $candidate && -x $candidate);
    }
    return '';
}

sub wg_quick_dns_dependency_error
{
    my ($dns_entries) = @_;
    return '' if (!grep { length(_trim($_)) } @{$dns_entries || []});
    return '' if (length(wg_quick_resolvconf_command()));
    return $text{'error_dns_resolvconf_missing'} ||
        'wg-quick requires the resolvconf command when host DNS is configured.';
}

# The hook is invoked by systemd/wg-quick as well as by Webmin.
# Quote every argument; never interpolate a submitted port into shell code.
sub wg_firewall_hook_command
{
    my ($action, $port) = @_;
    my @args = ($^X, File::Spec->rel2abs('wg-firewall-hook.pl'), $action, '%i');
    push(@args, $port) if ($action eq 'up');
    return join(' ', map { shell_quote($_) } @args);
}

# UFW is optional: missing/inactive UFW must not prevent wg-quick from
# bringing up a tunnel. Unknown status is different: do not silently bypass
# an active firewall whose status command is failing.
sub wg_firewall_ufw_state
{
    my $ufw = '/usr/sbin/ufw';
    return 'missing' if (!-x $ufw);
    local $ENV{'LC_ALL'} = 'C';
    my ($ok, $output) = run_command([ $ufw, 'status' ], 1, 10, 4096);
    return 'unknown' if (!$ok);
    return 'active' if ($output =~ /^Status:\s+active\b/im);
    return 'inactive' if ($output =~ /^Status:\s+inactive\b/im);
    return 'unknown';
}

sub wg_firewall_status_warning
{
    my $state = wg_firewall_ufw_state();
    return '' if ($state eq 'active');
    return $text{'warning_firewall_ufw_missing'} if ($state eq 'missing');
    return $text{'warning_firewall_ufw_inactive'} if ($state eq 'inactive');
    return $text{'error_firewall_ufw_unknown'};
}

sub wg_firewall_preflight
{
    my ($port) = @_;
    return $text{'error_firewall_port_required'}
        if (!defined($port) || $port !~ /^[0-9]+$/ || $port < 1 || $port > 65535);
    return $text{'error_firewall_hook_missing'} if (!-r File::Spec->rel2abs('wg-firewall-hook.pl'));
    my $state = wg_firewall_ufw_state();
    return $text{'error_firewall_ufw_unknown'} if ($state eq 'unknown');
    return '';
}

sub optional_dependency_spec
{
    my ($id) = @_;
    return undef if (!defined($id));
    if ($id eq 'qrencode') {
        return {
            'id' => 'qrencode',
            'package' => 'qrencode',
            'packages' => ['qrencode'],
            'command_key' => 'qrencode_cmd',
            'command_fallback' => '/usr/bin/qrencode',
        };
    }
    if ($id eq 'geoip') {
        # Install an immediately usable offline country DB as well as the
        # optional GeoLite2 City updater and WHOIS client. The City MMDB
        # download still requires the administrator's MaxMind credentials.
        return {
            'id' => 'geoip',
            'package' => 'geoipupdate mmdb-bin geoip-bin geoip-database whois',
            'packages' => [qw(geoipupdate mmdb-bin geoip-bin geoip-database whois)],
            'commands' => [
                ['geoipupdate_cmd','/usr/bin/geoipupdate'],
                ['mmdblookup_cmd','/usr/bin/mmdblookup'],
                ['geoiplookup_cmd','/usr/bin/geoiplookup'],
                ['whois_cmd','/usr/bin/whois']
            ],
        };
    }
    return undef;
}

sub optional_dependency_quick_status
{
    my ($id) = @_;
    my $spec = optional_dependency_spec($id);
    return undef if (!$spec);

    my @commands = $spec->{'commands'}
        ? map { command_path($_->[0],$_->[1]) } @{$spec->{'commands'}}
        : (command_path($spec->{'command_key'}, $spec->{'command_fallback'}));
    my @missing = grep { !$_ || !has_command($_) } @commands;
    my $apt = command_path('apt_get_cmd', '/usr/bin/apt-get');
    return {
        %$spec,
        'command' => join(', ', @commands),
        'commands' => \@commands,
        'missing_commands' => \@missing,
        'command_available' => @missing ? 0 : 1,
        'package_manager_available' => (-e '/etc/debian_version' && has_command($apt)) ? 1 : 0,
        'apt_command' => $apt,
    };
}

sub optional_dependency_status
{
    my ($id) = @_;
    my $spec = optional_dependency_spec($id);
    return undef if (!$spec);

    my $status = optional_dependency_quick_status($id);
    my $dpkg = command_path('dpkg_query_cmd', '/usr/bin/dpkg-query');
    $status->{'package_installed'} = 0;
    $status->{'package_version'} = '';
    $status->{'dpkg_query_command'} = $dpkg;
    if (has_command($dpkg)) {
        my @versions;
        my $all_installed = 1;
        for my $package (@{$spec->{'packages'} || [$spec->{'package'}]}) {
            my ($ok, $out) = run_command([
                $dpkg, '-W', '-f=${Status}\t${Version}\n', $package
            ], 1, 10, 4096);
            if ($ok && $out =~ /^install\s+ok\s+installed\t([^\r\n]+)$/m) {
                push(@versions, @{$spec->{'packages'}} == 1 ? _trim($1) : $package.' '._trim($1));
            }
            else {
                $all_installed=0;
            }
        }
        $status->{'package_installed'} = $all_installed ? 1 : 0;
        $status->{'package_version'} = join(', ', @versions);
    }
    return $status;
}


1;
