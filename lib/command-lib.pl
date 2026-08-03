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
    my ($writer, $reader);
    my $err = gensym();
    my $pid;
    eval {
        $pid = open3($writer, $reader, $err, @$argv);
        binmode($writer);
        print {$writer} $stdin;
        close($writer);
    };
    return (0, '', $@ || 'open3 failed') if ($@);
    my $out = do { local $/; <$reader> };
    my $eout = do { local $/; <$err> };
    close($reader);
    close($err);
    waitpid($pid, 0);
    return ($? == 0, defined($out) ? $out : '', defined($eout) ? $eout : '');
}

sub require_command
{
    my ($path) = @_;
    error(text('error_command', $path)) if (!$path || !has_command($path));
}


sub optional_dependency_spec
{
    my ($id) = @_;
    return undef if (!defined($id) || $id ne 'qrencode');
    return {
        'id' => 'qrencode',
        'package' => 'qrencode',
        'command_key' => 'qrencode_cmd',
        'command_fallback' => '/usr/bin/qrencode',
    };
}

sub optional_dependency_quick_status
{
    my ($id) = @_;
    my $spec = optional_dependency_spec($id);
    return undef if (!$spec);

    my $command = command_path($spec->{'command_key'}, $spec->{'command_fallback'});
    my $apt = command_path('apt_get_cmd', '/usr/bin/apt-get');
    return {
        %$spec,
        'command' => $command,
        'command_available' => ($command && has_command($command)) ? 1 : 0,
        'package_manager_available' => (-e '/etc/debian_version' && has_command($apt)) ? 1 : 0,
        'apt_command' => $apt,
    };
}

sub optional_dependency_status
{
    my ($id) = @_;
    my $spec = optional_dependency_spec($id);
    return undef if (!$spec);

    my $command = command_path($spec->{'command_key'}, $spec->{'command_fallback'});
    my $dpkg = command_path('dpkg_query_cmd', '/usr/bin/dpkg-query');
    my $apt = command_path('apt_get_cmd', '/usr/bin/apt-get');
    my $status = {
        %$spec,
        'command' => $command,
        'command_available' => ($command && has_command($command)) ? 1 : 0,
        'package_installed' => 0,
        'package_version' => '',
        'package_manager_available' => (-e '/etc/debian_version' && has_command($apt)) ? 1 : 0,
        'apt_command' => $apt,
        'dpkg_query_command' => $dpkg,
    };

    if (has_command($dpkg)) {
        my ($ok, $out) = run_command([
            $dpkg, '-W', '-f=${Status}\t${Version}\n', $spec->{'package'}
        ], 1, 10, 4096);
        if ($ok && $out =~ /^install\s+ok\s+installed\t([^\r\n]+)$/m) {
            $status->{'package_installed'} = 1;
            $status->{'package_version'} = _trim($1);
        }
    }
    return $status;
}


1;
