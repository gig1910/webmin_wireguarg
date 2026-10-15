#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
eval {
    assert_view_access();
    my $peer = $in{'peer_id'} || '';
    die $text{'analytics_error_peer'} if ($peer && $peer !~ /^[a-f0-9]{64}$/);
    my $interface = $in{'interface'} || '';
    die $text{'analytics_error_interface'}
        if ($interface && !valid_interface_name($interface));
    my $from = $in{'from'} || '';
    my $to = $in{'to'} || '';
    die $text{'analytics_error_time'}
        if ($from !~ /^\d{1,12}$/ || $to !~ /^\d{1,12}$/);
    my ($result, $err) = analytics_backend('query', {
        'peer_id' => $peer, 'interface' => $interface,
        'from' => 0 + $from, 'to' => 0 + $to,
    });
    die $err if (!$result);
    # Immediate, read-only resolution of renamed/configured peers; the
    # collector persists these labels in SQLite for later deletion/disable.
    my ($items) = list_configured_interfaces();
    if ($items && ref($result->{'peers'}) eq 'ARRAY') {
        my %current;
        my %links;
        for my $item (@$items) {
            my $parsed = $item->{'config'} || {};
            my $index = 0;
            for my $entry (@{$parsed->{'peers'} || []}) {
                my $public = get_section_value($entry, 'PublicKey') || '';
                if ($public =~ /^[A-Za-z0-9+\/]{43}=$/) {
                    my $id = sha256_hex($public);
                    my $name = get_meta_value($entry, 'name') || '';
                    $current{$id} = $name if length($name);
                    $links{$id} = module_script_url('edit_peer.cgi',
                        name => $item->{'name'}, peer => $index);
                }
                $index++;
            }
        }
        for my $record (@{$result->{'peers'}}) {
            $record->{'name'} = $current{$record->{'id'}}
                if exists $current{$record->{'id'}};
            $record->{'peer_url'} = $links{$record->{'id'}}
                if exists $links{$record->{'id'}};
        }
    }
    json_response($result);
    1;
} or do {
    my $error = $@ || $text{'analytics_error_time'};
    $error =~ s/\s+$//;
    json_response({ ok => JSON::PP::false(), error => "$error" });
};
