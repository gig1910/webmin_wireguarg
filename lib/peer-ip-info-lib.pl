=head1 peer-ip-info-lib.pl

On-demand WHOIS and local GeoIP lookup for the IP confirmed by a peer's
last handshake. The API caller must validate the peer identity and check
ipaddress.is_global before invoking this code. No automatic third-party
geolocation requests are performed.

=cut

sub peer_ip_whois_fields
{
    my ($raw) = @_;
    my %labels = (
        netrange => 'Network range', inetnum => 'Network range',
        inet6num => 'Network range', cidr => 'CIDR',
        netname => 'Network name', orgname => 'Organization',
        'org-name' => 'Organization', organization => 'Organization',
        owner => 'Organization', org => 'Organization',
        origin => 'Origin AS', originas => 'Origin AS',
        country => 'Country', 'abuse-mailbox' => 'Abuse contact',
        orgabuseemail => 'Abuse contact',
    );
    my %seen;
    my @result;
    for my $line (split(/\r?\n/, $raw || '')) {
        next if $line !~ /^\s*([A-Za-z][A-Za-z0-9_-]{1,40})\s*:\s*(.*?)\s*$/;
        my ($key, $value) = (lc($1), $2);
        next if !$labels{$key} || !length($value) || $value =~ /<[^>]+>/;
        my $label = $labels{$key};
        next if $seen{$label}++;
        push(@result, { label => $label, value => substr($value, 0, 256) });
        last if @result >= 12;
    }
    return \@result;
}

sub peer_ip_mmdb_value
{
    my ($path, $ip, @keys) = @_;
    return undef if !-r $path;
    my $tool = command_path('mmdblookup_cmd', '/usr/bin/mmdblookup');
    return undef if !has_command($tool);
    my ($ok, $out) = run_command(
        [$tool, '--file', $path, '--ip', $ip, @keys], 1, 5, 1024
    );
    return undef if !$ok || $out !~ /^\s*"([^"]{1,200})"\s+</;
    return $1;
}

sub peer_ip_geoip
{
    my ($ip) = @_;
    my $mmdb = command_path('mmdblookup_cmd', '/usr/bin/mmdblookup');
    if (has_command($mmdb)) {
        my @databases = wg_geoip_database_paths();
        my ($database) = @databases;
        if ($database) {
            my $country_code=peer_ip_mmdb_value($database, $ip, 'country', 'iso_code') || '';
            $country_code='' if $country_code !~ /^[A-Z]{2}$/;
            my @fields;
            for my $request (
                [ 'Country', 'country', 'names', 'en' ],
                [ 'Region', 'subdivisions', '0', 'names', 'en' ],
                [ 'City', 'city', 'names', 'en' ],
                [ 'Latitude', 'location', 'latitude' ],
                [ 'Longitude', 'location', 'longitude' ],
            ) {
                my ($label, @keys) = @$request;
                # Numeric GeoIP coordinates are returned as floating-point
                # scalars rather than strings; handled by local CLI fallback.
                next if $label eq 'Latitude' || $label eq 'Longitude';
                my $value = peer_ip_mmdb_value($database, $ip, @keys);
                push(@fields, {label=>$label, value=>$value}) if defined($value);
            }
            return { ok => @fields ? JSON::PP::true() : JSON::PP::false(),
                     source=>'GeoLite2 / MaxMind (local database)',
                     country_code=>$country_code,
                     fields=>\@fields, detail=>@fields ? '' : 'IP not found in GeoIP database' };
        }
    }
    my $legacy = command_path('geoiplookup_cmd', '/usr/bin/geoiplookup');
    if (has_command($legacy)) {
        my ($ok, $out) = run_command([$legacy, $ip], 1, 5, 3072);
        $out = substr($out || '',0,3072);
        my @fields;
        my $country_code='';
        for my $line (split(/\r?\n/,$out)) {
            next if $line !~ /^\s*GeoIP\s+(.+?)\s*:\s*(.*?)\s*$/;
            my ($label,$value)=($1,$2);
            next if $value =~ /not found|can't open|cannot open/i;
            $country_code=uc($1) if !$country_code && $value =~ /^([A-Z]{2}),/i;
            push(@fields, {label=>substr($label,0,90),value=>substr($value,0,350)});
            last if @fields>=6;
        }
        return { ok => @fields ? JSON::PP::true() : JSON::PP::false(),
                 source=>'GeoIP (local database)',country_code=>$country_code, fields=>\@fields,
                 detail=>@fields ? '' : ($out || 'No GeoIP data') };
    }
    return { ok=>JSON::PP::false(),source=>'Local GeoIP',
        fields=>[],detail=>'GeoIP tools/database not installed. Install geoip-bin + geoip-database, or mmdb-bin with GeoLite2 City/Country database.' };
}

sub peer_ip_whois
{
    my ($ip) = @_;
    my $tool=command_path('whois_cmd','/usr/bin/whois');
    if (!has_command($tool)) {
        return {ok=>JSON::PP::false(), fields=>[], raw=>'',
                detail=>'WHOIS command not installed (package: whois).'};
    }
    # The call is explicitly user-triggered; WHOIS contacts external registries.
    # The IP comes only from the SQLite handshake state, never from an HTTP field.
    my ($ok, $out) = run_command([$tool,$ip], 1, 8, 12000);
    $out = substr($out || '',0,12000);
    my $fields=peer_ip_whois_fields($out);
    return { ok=>$ok ? JSON::PP::true() : JSON::PP::false(),
             fields=>$fields,raw=>$out,
             detail=>$ok ? '' : 'WHOIS query failed or timed out' };
}

1;
