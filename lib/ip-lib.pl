=head1 ip-lib.pl

Internal module.

=cut

sub valid_interface_name
{
    my ($name) = @_;
    return defined($name) && $name =~ /^[A-Za-z0-9_=+.-]{1,15}$/;
}

sub valid_host
{
    my ($host) = @_;
    return 0 if (!defined($host) || !length($host) || length($host) > 253 || $host =~ /^-/);
    return ($host =~ /^[A-Za-z0-9_.:%-]+$/ || $host =~ /^\[[0-9A-Fa-f:%]+\]$/);
}

sub valid_cidr
{
    my ($value) = @_;
    return 0 if (!defined($value));
    $value = _trim($value);
    return 0 if ($value !~ /^(.+)\/(\d+)$/);
    my ($address, $prefix) = ($1, int($2));
    if (defined(inet_pton(AF_INET, $address))) {
        return $prefix >= 0 && $prefix <= 32;
    }
    if (defined(inet_pton(AF_INET6, $address))) {
        return $prefix >= 0 && $prefix <= 128;
    }
    return 0;
}

sub validate_cidr_list
{
    my ($values) = @_;
    foreach my $value (@$values) {
        return (0, $value) if (!valid_cidr($value));
    }
    return (1, undef);
}

sub cidr_network
{
    my ($value) = @_;
    return undef if (!valid_cidr($value));
    $value = _trim($value);
    my ($address, $prefix) = $value =~ /^(.+)\/(\d+)$/;
    $prefix = int($prefix);

    my ($family, $packed);
    $packed = inet_pton(AF_INET, $address);
    if (defined($packed)) {
        $family = AF_INET;
    }
    else {
        $packed = inet_pton(AF_INET6, $address);
        return undef if (!defined($packed));
        $family = AF_INET6;
    }

    my @bytes = unpack('C*', $packed);
    my $full_bytes = int($prefix / 8);
    my $remaining_bits = $prefix % 8;
    for (my $i = 0; $i < @bytes; $i++) {
        next if ($i < $full_bytes);
        if ($i == $full_bytes && $remaining_bits) {
            my $mask = (0xff << (8 - $remaining_bits)) & 0xff;
            $bytes[$i] &= $mask;
        }
        else {
            $bytes[$i] = 0;
        }
    }

    my $network = inet_ntop($family, pack('C*', @bytes));
    return defined($network) ? $network.'/'.$prefix : undef;
}

sub interface_address_networks
{
    my ($ifc) = @_;
    return () if (!$ifc);
    my (@networks, %seen);
    foreach my $value (get_section_values($ifc, 'Address')) {
        foreach my $address (_split_list($value)) {
            my $network = cidr_network($address);
            next if (!defined($network) || $seen{$network}++);
            push(@networks, $network);
        }
    }
    return @networks;
}

sub _cidr_details
{
    my ($value) = @_;
    return undef if (!valid_cidr($value));
    $value = _trim($value);
    my ($address, $prefix) = $value =~ /^(.+)\/(\d+)$/;
    $prefix = int($prefix);

    my ($family, $bits, $packed);
    $packed = inet_pton(AF_INET, $address);
    if (defined($packed)) {
        $family = AF_INET;
        $bits = 32;
    }
    else {
        $packed = inet_pton(AF_INET6, $address);
        return undef if (!defined($packed));
        $family = AF_INET6;
        $bits = 128;
    }

    my @network = unpack('C*', $packed);
    my $full_bytes = int($prefix / 8);
    my $remaining_bits = $prefix % 8;
    for (my $i = 0; $i < @network; $i++) {
        next if ($i < $full_bytes);
        if ($i == $full_bytes && $remaining_bits) {
            my $mask = (0xff << (8 - $remaining_bits)) & 0xff;
            $network[$i] &= $mask;
        }
        else {
            $network[$i] = 0;
        }
    }

    my @last = @network;
    for (my $i = 0; $i < @last; $i++) {
        next if ($i < $full_bytes);
        if ($i == $full_bytes && $remaining_bits) {
            my $host_mask = (1 << (8 - $remaining_bits)) - 1;
            $last[$i] |= $host_mask;
        }
        else {
            $last[$i] = 0xff;
        }
    }

    return {
        value => $value,
        family => $family,
        bits => $bits,
        prefix => $prefix,
        address_packed => $packed,
        network_packed => pack('C*', @network),
        last_packed => pack('C*', @last),
    };
}

sub _packed_prefix_equal
{
    my ($left, $right, $prefix) = @_;
    my @left = unpack('C*', $left);
    my @right = unpack('C*', $right);
    return 0 if (@left != @right);
    my $full_bytes = int($prefix / 8);
    my $remaining_bits = $prefix % 8;
    for (my $i = 0; $i < $full_bytes; $i++) {
        return 0 if ($left[$i] != $right[$i]);
    }
    if ($remaining_bits) {
        my $mask = (0xff << (8 - $remaining_bits)) & 0xff;
        return 0 if (($left[$full_bytes] & $mask) != ($right[$full_bytes] & $mask));
    }
    return 1;
}

sub cidrs_overlap
{
    my ($left, $right) = @_;
    my $a = ref($left) ? $left : _cidr_details($left);
    my $b = ref($right) ? $right : _cidr_details($right);
    return 0 if (!$a || !$b || $a->{'family'} != $b->{'family'});
    my $prefix = $a->{'prefix'} < $b->{'prefix'} ? $a->{'prefix'} : $b->{'prefix'};
    return _packed_prefix_equal($a->{'network_packed'}, $b->{'network_packed'}, $prefix);
}

sub _packed_compare
{
    my ($left, $right) = @_;
    my @left = unpack('C*', $left);
    my @right = unpack('C*', $right);
    return @left <=> @right if (@left != @right);
    for (my $i = 0; $i < @left; $i++) {
        return -1 if ($left[$i] < $right[$i]);
        return 1 if ($left[$i] > $right[$i]);
    }
    return 0;
}

sub _packed_increment
{
    my ($packed) = @_;
    my @bytes = unpack('C*', $packed);
    for (my $i = $#bytes; $i >= 0; $i--) {
        if ($bytes[$i] < 255) {
            $bytes[$i]++;
            return pack('C*', @bytes);
        }
        $bytes[$i] = 0;
    }
    return undef;
}

sub _packed_decrement
{
    my ($packed) = @_;
    my @bytes = unpack('C*', $packed);
    for (my $i = $#bytes; $i >= 0; $i--) {
        if ($bytes[$i] > 0) {
            $bytes[$i]--;
            return pack('C*', @bytes);
        }
        $bytes[$i] = 255;
    }
    return undef;
}

sub _packed_in_cidr
{
    my ($packed, $family, $cidr) = @_;
    return 0 if (!$cidr || $family != $cidr->{'family'});
    return _packed_prefix_equal($packed, $cidr->{'network_packed'}, $cidr->{'prefix'});
}

sub peer_allowed_ip_conflict
{
    my ($cfg, $candidate_values, $skip_index) = @_;
    return undef if (!$cfg || !$candidate_values);
    my @candidate = grep { defined($_) } map { _cidr_details($_) } @$candidate_values;

    for (my $i = 0; $i < @{$cfg->{'peers'} || []}; $i++) {
        next if (defined($skip_index) && "$i" eq "$skip_index");
        my $peer = $cfg->{'peers'}->[$i];
        my @existing_values;
        foreach my $value (get_section_values($peer, 'AllowedIPs')) {
            push(@existing_values, _split_list($value));
        }
        foreach my $existing_value (@existing_values) {
            my $existing = _cidr_details($existing_value);
            next if (!$existing);
            foreach my $candidate (@candidate) {
                if (cidrs_overlap($candidate, $existing)) {
                    return {
                        candidate => $candidate->{'value'},
                        existing => $existing->{'value'},
                        peer_index => $i,
                        peer_name => peer_display_name($peer, $i),
                        disabled => $peer->{'disabled'} ? 1 : 0,
                    };
                }
            }
        }
    }
    return undef;
}

sub first_free_peer_address
{
    my ($cfg) = @_;
    return (undef, undef) if (!$cfg || !$cfg->{'interface'});

    my @interface_addresses;
    foreach my $value (get_section_values($cfg->{'interface'}, 'Address')) {
        push(@interface_addresses, _split_list($value));
    }

    my @reserved = grep { defined($_) } map { _cidr_details($_) } @interface_addresses;
    my @used;
    foreach my $peer (@{$cfg->{'peers'} || []}) {
        foreach my $value (get_section_values($peer, 'AllowedIPs')) {
            push(@used, grep { defined($_) } map { _cidr_details($_) } _split_list($value));
        }
    }

    foreach my $interface_value (@interface_addresses) {
        my $network = _cidr_details($interface_value);
        next if (!$network || $network->{'prefix'} >= $network->{'bits'});

        my $candidate = $network->{'network_packed'};
        my $last = $network->{'last_packed'};
        if ($network->{'family'} == AF_INET && $network->{'prefix'} <= 30) {
            $candidate = _packed_increment($candidate);
            $last = _packed_decrement($last);
        }
        elsif ($network->{'family'} == AF_INET6 && $network->{'prefix'} <= 126) {
            # Avoid the all-zero interface identifier where the subnet is large
            # enough to do so. /127 remains valid point-to-point address space.
            $candidate = _packed_increment($candidate);
        }
        next if (!defined($candidate) || !defined($last) || _packed_compare($candidate, $last) > 0);

        while (_packed_compare($candidate, $last) <= 0) {
            my $blocked = 0;
            my $jump_to;

            foreach my $own (@reserved) {
                next if ($own->{'family'} != $network->{'family'});
                if ($candidate eq $own->{'address_packed'}) {
                    $blocked = 1;
                    $jump_to = $candidate;
                    last;
                }
            }

            if (!$blocked) {
                foreach my $range (@used) {
                    next if ($range->{'family'} != $network->{'family'});
                    if (_packed_in_cidr($candidate, $network->{'family'}, $range)) {
                        $blocked = 1;
                        if (!defined($jump_to) || _packed_compare($range->{'last_packed'}, $jump_to) > 0) {
                            $jump_to = $range->{'last_packed'};
                        }
                    }
                }
            }

            if (!$blocked) {
                my $address = inet_ntop($network->{'family'}, $candidate);
                my $host_prefix = $network->{'family'} == AF_INET ? 32 : 128;
                return ($address.'/'.$host_prefix, $network->{'value'});
            }

            $candidate = _packed_increment($jump_to || $candidate);
            last if (!defined($candidate));
        }
    }

    return (undef, undef);
}

sub resolve_client_allowed_ips
{
    my ($cfg, $peer) = @_;
    my $peer_value = get_meta_value($peer, 'clientallowedips') || '';
    return ($peer_value, 'peer') if (length(_trim($peer_value)));

    my $ifc = $cfg ? $cfg->{'interface'} : undef;
    my $interface_value = get_meta_value($ifc, 'clientallowedips') || '';
    return ($interface_value, 'interface') if (length(_trim($interface_value)));

    my @networks = interface_address_networks($ifc);
    return (join(', ', @networks), 'auto') if (@networks);
    return ('', 'none');
}

sub client_config_warnings
{
    my ($cfg, $peer) = @_;
    my ($allowed) = resolve_client_allowed_ips($cfg, $peer);
    return length($allowed) ? [] : [ $text{'qr_warn_no_allowed'} ];
}


1;
