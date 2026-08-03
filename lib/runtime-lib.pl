=head1 runtime-lib.pl

Internal module.

=cut

sub get_active_interfaces
{
    my $wg = command_path('wg_cmd', '/usr/bin/wg');
    return ({}, text('error_command', $wg)) if (!has_command($wg));
    my ($ok, $out) = run_command([ $wg, 'show', 'interfaces' ], 1, 15, 4000);
    return ({}, $out) if (!$ok);
    my %active = map { $_ => 1 } grep { valid_interface_name($_) } split(/\s+/, _trim($out));
    return (\%active, undef);
}

sub get_interface_dump
{
    my ($name) = @_;
    return (undef, $text{'error_invalid_name'}) if (!valid_interface_name($name));
    my $wg = command_path('wg_cmd', '/usr/bin/wg');
    return (undef, text('error_command', $wg)) if (!has_command($wg));
    my ($ok, $out) = run_command([ $wg, 'show', $name, 'dump' ], 1, 15, 100000);
    return (undef, $out) if (!$ok);
    my $dump = { 'interface' => {}, 'peers' => {}, 'peer_list' => [] };
    my @lines = grep { length($_) } split(/\r?\n/, $out);
    return ($dump, undef) if (!@lines);
    my @if = split(/\t/, shift(@lines), -1);
    if (@if >= 4) {
        $dump->{'interface'} = { 'public_key' => $if[1], 'listen_port' => $if[2], 'fwmark' => $if[3] };
    }
    foreach my $line (@lines) {
        my @p = split(/\t/, $line, -1);
        next if (@p < 8);
        my $peer = {
            'public_key' => $p[0], 'endpoint' => $p[2], 'allowed_ips' => $p[3],
            'latest_handshake' => int($p[4] || 0), 'rx_bytes' => int($p[5] || 0),
            'tx_bytes' => int($p[6] || 0), 'persistent_keepalive' => int($p[7] || 0),
        };
        $dump->{'peers'}->{$peer->{'public_key'}} = $peer;
        push(@{$dump->{'peer_list'}}, $peer);
    }
    return ($dump, undef);
}

sub get_all_runtime_dump
{
    my $wg = command_path('wg_cmd', '/usr/bin/wg');
    return ({}, text('error_command', $wg)) if (!has_command($wg));

    my $timeout = int($config{'runtime_timeout'} || 5);
    $timeout = 1 if ($timeout < 1);
    $timeout = 60 if ($timeout > 60);
    my ($ok, $out) = run_command([ $wg, 'show', 'all', 'dump' ], 1, $timeout, 1000000);
    return ({}, $out) if (!$ok);

    my %interfaces;
    foreach my $line (grep { length($_) } split(/\r?\n/, $out)) {
        my @f = split(/\t/, $line, -1);
        if (@f == 5) {
            my $name = $f[0];
            next if (!valid_interface_name($name));
            $interfaces{$name} = {
                'name' => $name,
                'interface' => {
                    'public_key' => $f[2] || '',
                    'listen_port' => $f[3] || '',
                    'fwmark' => $f[4] || '',
                },
                'peers' => {},
                'peer_list' => [],
                'rx_bytes' => 0,
                'tx_bytes' => 0,
            };
            next;
        }
        next if (@f < 9);
        my $name = $f[0];
        next if (!$interfaces{$name});
        my $peer = {
            'public_key' => $f[1] || '',
            'endpoint' => $f[3] || '',
            'allowed_ips' => $f[4] || '',
            'latest_handshake' => int($f[5] || 0),
            'rx_bytes' => int($f[6] || 0),
            'tx_bytes' => int($f[7] || 0),
            'persistent_keepalive' => int($f[8] || 0),
        };
        $interfaces{$name}->{'peers'}->{$peer->{'public_key'}} = $peer;
        push(@{$interfaces{$name}->{'peer_list'}}, $peer);
        $interfaces{$name}->{'rx_bytes'} += $peer->{'rx_bytes'};
        $interfaces{$name}->{'tx_bytes'} += $peer->{'tx_bytes'};
    }
    return (\%interfaces, undef);
}

sub human_duration
{
    my ($seconds) = @_;
    $seconds = int($seconds || 0);
    return $seconds.'s' if ($seconds < 60);
    return int($seconds / 60).'m' if ($seconds < 3600);
    return int($seconds / 3600).'h '.int(($seconds % 3600) / 60).'m' if ($seconds < 86400);
    return int($seconds / 86400).'d '.int(($seconds % 86400) / 3600).'h';
}

sub handshake_state
{
    my ($epoch) = @_;
    return ('never', $text{'status_never'}) if (!$epoch);
    my $age = time() - $epoch;
    $age = 0 if ($age < 0);
    my $recent = int($config{'recent_handshake_seconds'} || 180);
    return ($age <= $recent ? 'recent' : 'stale', text('status_ago', human_duration($age)));
}

sub interface_summary
{
    my ($item, $active, $runtime) = @_;
    my $section = $item->{'config'} ? $item->{'config'}->{'interface'} : undef;
    my @addresses = get_section_values($section, 'Address');
    my $listen_port = get_section_value($section, 'ListenPort');
    $listen_port = $runtime->{'interface'}->{'listen_port'} if ($active && $runtime && $runtime->{'interface'}->{'listen_port'});
    my $enabled = 0;
    my $disabled = 0;
    foreach my $p (@{$item->{'config'}->{'peers'} || []}) { $p->{'disabled'} ? $disabled++ : $enabled++; }
    return { 'addresses' => join(', ', @addresses), 'listen_port' => $listen_port || '', 'peer_count' => $enabled, 'disabled_count' => $disabled };
}

sub action_start_interface
{
    my ($name) = @_;
    my $path = conf_path($name);
    return (0, text('action_missing', $name)) if (!-r $path);
    my ($cfg) = parse_wireguard_config($path);
    return (0, $text{'error_interface_private_missing'}) if (!$cfg || !length($cfg->{'interface'}->{'private_key'} || ''));
    my $wgq = command_path('wg_quick_cmd', '/usr/bin/wg-quick');
    require_command($wgq);
    return run_command([ $wgq, 'up', $path ], 0, 90, 50000);
}

sub action_stop_interface
{
    my ($name) = @_;
    my $path = conf_path($name);
    return (0, text('action_missing', $name)) if (!-r $path);
    my $wgq = command_path('wg_quick_cmd', '/usr/bin/wg-quick');
    require_command($wgq);

    my ($cfg) = parse_wireguard_config($path);
    my $save_config = $cfg && lc(get_section_value($cfg->{'interface'}, 'SaveConfig') || '') eq 'true';
    if (!$save_config) {
        return run_command([ $wgq, 'down', $path ], 0, 90, 50000);
    }

    # wg-quick SaveConfig=true rewrites the file on shutdown and would remove
    # Webmin metadata, peer names and stored client private keys. Keep the file
    # as the source of truth: allow wg-quick to shut down, then restore exactly
    # the original contents while holding the module lock.
    lock_file($path);
    my $original = read_file_contents($path);
    if (!defined($original)) {
        unlock_file($path);
        return (0, 'Cannot read configuration before shutdown', 1, 'read configuration');
    }
    my $backup = backup_config($path);
    if (!$backup) {
        unlock_file($path);
        return (0, $text{'error_backup'}, 1, 'backup configuration');
    }
    my @result = run_command([ $wgq, 'down', $path ], 0, 90, 50000);
    my ($restore_ok, $restore_error) = _write_exact_unlocked($path, $original);
    unlock_file($path);
    if (!$restore_ok) {
        return (0, ($result[1] || '')."\n".text('error_restore', $restore_error), 1, $result[3]);
    }
    return @result;
}

sub action_apply_interface
{
    my ($name) = @_;
    my $path = conf_path($name);
    return (0, text('action_missing', $name)) if (!-r $path);
    my $wg = command_path('wg_cmd', '/usr/bin/wg');
    my $wgq = command_path('wg_quick_cmd', '/usr/bin/wg-quick');
    require_command($wg); require_command($wgq);
    my ($ok, $stripped, $status, $cmd) = run_command([ $wgq, 'strip', $path ], 1, 30, 100000);
    return (0, $stripped, $status, $cmd) if (!$ok);
    my $tmp = File::Spec->catfile(dirname($path), '.'.basename($path).'.strip.'.$$.'.tmp');
    sysopen(my $fh, $tmp, O_WRONLY|O_CREAT|O_EXCL, 0600) || return (0, "$!", 1, 'create temporary strip file');
    print {$fh} $stripped; close($fh); chmod(0600, $tmp);
    my @result = run_command([ $wg, 'syncconf', $name, $tmp ], 0, 30, 50000);
    unlink($tmp);
    return @result;
}

sub action_restart_interface
{
    my ($name) = @_;
    my ($down_ok, $down_out, $down_status, $down_cmd) = action_stop_interface($name);
    return (0, $down_out, $down_status, $down_cmd) if (!$down_ok);
    my ($up_ok, $up_out, $up_status, $up_cmd) = action_start_interface($name);
    return ($up_ok, $down_out.$up_out, $up_status, $down_cmd.' ; '.$up_cmd);
}

sub peer_client_address_and_routes
{
    my ($peer) = @_;
    return ('', []) if (!$peer);

    my @all;
    foreach my $value (get_section_values($peer, 'AllowedIPs')) {
        push(@all, _split_list($value));
    }

    my @addresses = _split_list(get_meta_value($peer, 'clientaddress') || '');
    my @routes;
    if (@addresses) {
        my %address = map { $_ => 1 } @addresses;
        @routes = grep { !$address{$_} } @all;
    }
    elsif (@all) {
        push(@addresses, shift(@all));
        @routes = @all;
    }

    return (join(', ', @addresses), \@routes);
}

sub first_client_address
{
    my ($peer) = @_;
    my ($address) = peer_client_address_and_routes($peer);
    return length($address || '') ? $address : undef;
}

sub interface_public_key
{
    my ($ifc, $runtime) = @_;
    return $runtime->{'interface'}->{'public_key'} if ($runtime && length($runtime->{'interface'}->{'public_key'} || ''));

    # The module recalculates and stores this comment whenever a private key is
    # saved. Reusing it avoids spawning `wg pubkey` on every config/QR request.
    my $stored_public = $ifc->{'public_key_comment'} || '';
    return $stored_public if (length($stored_public));

    my $private = $ifc->{'private_key'} || '';
    if (length($private)) {
        my ($pub) = derive_public_key($private);
        return $pub if ($pub);
    }
    return '';
}

sub _endpoint_has_explicit_port
{
    my ($endpoint) = @_;
    $endpoint = _trim($endpoint);
    return 0 if (!length($endpoint));
    return 1 if ($endpoint =~ /^\[[^\]]+\]:\d+$/);       # [IPv6]:port
    return 1 if ($endpoint =~ /^[^:\[\]]+:\d+$/);       # host/IPv4:port
    return 0;
}

sub resolve_client_endpoint
{
    my ($cfg, $peer, $runtime) = @_;
    my $ifc = $cfg ? $cfg->{'interface'} : undef;
    my $endpoint = get_meta_value($peer, 'clientendpoint') ||
                   get_meta_value($ifc, 'clientendpoint') || '';
    $endpoint = _trim($endpoint);
    return ('', 'missing') if (!length($endpoint));
    return ($endpoint, 'explicit') if (_endpoint_has_explicit_port($endpoint));

    my $port = '';
    if ($runtime && $runtime->{'interface'}) {
        $port = $runtime->{'interface'}->{'listen_port'} || '';
    }
    $port ||= get_section_value($ifc, 'ListenPort') || '';
    $port = _trim($port);
    return ($endpoint, 'missing_port') if ($port !~ /^\d+$/ || $port < 1 || $port > 65535);

    if ($endpoint =~ /^\[([^\]]+)\]$/) {
        return ('['.$1.']:'.$port, 'appended');
    }
    if ($endpoint =~ /:/) {
        # A colon without an explicit port is a bare IPv6 address.
        return ('['.$endpoint.']:'.$port, 'appended');
    }
    return ($endpoint.':'.$port, 'appended');
}

sub client_config_static_issues
{
    my ($cfg, $peer) = @_;
    my @issues;
    push(@issues, $text{'qr_no_private'}) if (!length($peer->{'private_key'} || ''));
    my $ifc = $cfg->{'interface'};
    if (!$ifc) {
        push(@issues, $text{'qr_no_interface'});
        return \@issues;
    }
    my $has_server_key = length($ifc->{'public_key_comment'} || '') || length($ifc->{'private_key'} || '');
    push(@issues, $text{'qr_no_server_public'}) if (!$has_server_key);
    push(@issues, $text{'qr_no_address'}) if (!length(first_client_address($peer) || ''));
    my ($endpoint, $endpoint_source) = resolve_client_endpoint($cfg, $peer, undef);
    push(@issues, $text{'qr_no_endpoint'}) if (!length($endpoint));
    push(@issues, $text{'qr_no_endpoint_port'}) if (length($endpoint) && $endpoint_source eq 'missing_port');
    return \@issues;
}

sub client_config_issues
{
    my ($cfg, $peer, $runtime) = @_;
    my @issues;
    push(@issues, $text{'qr_no_private'}) if (!length($peer->{'private_key'} || ''));
    my $ifc = $cfg->{'interface'};
    if (!$ifc) {
        push(@issues, $text{'qr_no_interface'});
        return \@issues;
    }
    my $server_pub = interface_public_key($ifc, $runtime);
    push(@issues, $text{'qr_no_server_public'}) if (!length($server_pub));
    push(@issues, $text{'qr_no_address'}) if (!length(first_client_address($peer) || ''));
    my ($endpoint, $endpoint_source) = resolve_client_endpoint($cfg, $peer, $runtime);
    push(@issues, $text{'qr_no_endpoint'}) if (!length($endpoint));
    push(@issues, $text{'qr_no_endpoint_port'}) if (length($endpoint) && $endpoint_source eq 'missing_port');
    return \@issues;
}

sub build_client_config
{
    my ($cfg, $peer, $runtime) = @_;
    my $issues = client_config_issues($cfg, $peer, $runtime);
    return (undef, $issues->[0]) if (@$issues);

    my $private = $peer->{'private_key'} || '';
    my $ifc = $cfg->{'interface'};
    my $server_pub = interface_public_key($ifc, $runtime);
    my $address = first_client_address($peer);
    my ($endpoint) = resolve_client_endpoint($cfg, $peer, $runtime);
    my ($allowed) = resolve_client_allowed_ips($cfg, $peer);
    my $dns = get_meta_value($peer, 'clientdns') || get_meta_value($ifc, 'clientdns') || '';
    my $mtu = get_meta_value($peer, 'clientmtu') || get_meta_value($ifc, 'clientmtu') || '';
    my $keepalive = get_section_value($peer, 'PersistentKeepalive') || '';
    my $psk = get_section_value($peer, 'PresharedKey') || '';
    my @lines = ('[Interface]', 'PrivateKey = '.$private, 'Address = '.$address);
    push(@lines, 'DNS = '.$dns) if (length($dns));
    push(@lines, 'MTU = '.$mtu) if (length($mtu));
    push(@lines, '', '[Peer]', 'PublicKey = '.$server_pub);
    push(@lines, 'PresharedKey = '.$psk) if (length($psk));
    push(@lines, 'Endpoint = '.$endpoint);
    push(@lines, 'AllowedIPs = '.$allowed) if (length($allowed));
    push(@lines, 'PersistentKeepalive = '.$keepalive) if (length($keepalive));
    return (join("\n", @lines)."\n", undef);
}


1;
