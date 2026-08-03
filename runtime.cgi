#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();

eval {
    assert_view_access();
    my $requested = $in{'name'} || '';
    die $text{'error_invalid_name'}."\n" if (length($requested) && !valid_interface_name($requested));

    my $interval = int($config{'stats_refresh_interval'} || 5);
    $interval = 2 if ($interval < 2);
    my $stale_after = $interval * 3;
    $stale_after = 15 if ($stale_after < 15);

    # Normally this reads the snapshot produced by the background collector.
    # On a fresh installation, or if the service failed, perform a throttled
    # asynchronous fallback refresh so status pages remain usable.
    my ($snapshot, $snapshot_error, $fallback_refreshed) = refresh_runtime_snapshot($stale_after);
    die $snapshot_error."\n" if (!$snapshot);
    my $snapshot_timestamp = 0 + ($snapshot->{'timestamp'} || 0);
    my $age = time() - $snapshot_timestamp;
    $age = 0 if ($age < 0);

    my %interfaces;
    foreach my $name (sort keys %{$snapshot->{'interfaces'} || {}}) {
        next if (length($requested) && $name ne $requested);
        my $dump = $snapshot->{'interfaces'}->{$name} || {};
        my @peers;
        foreach my $peer (@{$dump->{'peer_list'} || []}) {
            my (undef, $handshake_text) = handshake_state($peer->{'latest_handshake'} || 0);
            push(@peers, {
                'id' => substr(sha256_hex($peer->{'public_key'} || ''), 0, 16),
                'public_key' => $peer->{'public_key'} || '',
                'endpoint' => $peer->{'endpoint'} || '',
                'allowed_ips' => $peer->{'allowed_ips'} || '',
                'handshake' => 0 + ($peer->{'latest_handshake'} || 0),
                'handshake_text' => $handshake_text,
                'rx' => 0 + ($peer->{'rx_bytes'} || 0),
                'tx' => 0 + ($peer->{'tx_bytes'} || 0),
                'persistent_keepalive' => 0 + ($peer->{'persistent_keepalive'} || 0),
            });
        }
        $interfaces{$name} = {
            'name' => $name,
            'active' => JSON::PP::true(),
            'public_key' => $dump->{'interface'}->{'public_key'} || '',
            'listen_port' => $dump->{'interface'}->{'listen_port'} || '',
            'fwmark' => $dump->{'interface'}->{'fwmark'} || '',
            'peer_count' => 0 + scalar(@peers),
            'rx' => 0 + ($dump->{'rx_bytes'} || 0),
            'tx' => 0 + ($dump->{'tx_bytes'} || 0),
            'peers' => \@peers,
        };
    }

    my $response = {
        'ok' => JSON::PP::true(),
        'timestamp' => $snapshot_timestamp || time(),
        'cache_age' => 0 + $age,
        'stale' => $age > $stale_after ? JSON::PP::true() : JSON::PP::false(),
        'interfaces' => \%interfaces,
    };
    $response->{'warning'} = text('runtime_cache_stale', human_duration($age)) if ($age > $stale_after);
    $response->{'fallback_refreshed'} = JSON::PP::true() if ($fallback_refreshed);
    json_response($response);
    1;
} or do {
    my $error = $@ || 'error';
    $error =~ s/\s+$//;
    json_response({ 'ok' => JSON::PP::false(), 'error' => "$error" }, '503 Service Unavailable');
};
