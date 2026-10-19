#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();

sub fail_ip_info {
    my ($message) = @_;
    json_response({ok=>JSON::PP::false(),error=>"$message"});
    exit;
}

eval { assert_post_and_csrf(); request_rate_limit('peer_ip_info',6,60); 1 }
    or fail_ip_info($@ || $text{'action_post'});

my $name=$in{'name'} || '';
fail_ip_info($text{'error_invalid_name'}) if !valid_interface_name($name);
my $peer_index=$in{'peer'};
fail_ip_info($text{'error_peer'}) if !defined($peer_index) || $peer_index !~ /^\d{1,6}$/;
my ($cfg,$err)=parse_wireguard_config(conf_path($name));
fail_ip_info($err || $text{'error_peer'}) if !$cfg;
my $peer=get_peer_by_index($cfg,$peer_index);
fail_ip_info($text{'error_peer'}) if !$peer;
my $public=get_section_value($peer,'PublicKey') || '';
fail_ip_info($text{'error_peer'}) if $public !~ /^[A-Za-z0-9+\/]{43}=$/;

# A name, tunnel IP or peer index is NEVER the persistent identity.
# Validate current configuration first, then look up only by public-key hash.
my $hash=sha256_hex($public);
fail_ip_info($text{'peer_ip_no_history'}) if !-f analytics_db_path();
my %ip_request=(peer_id=>$hash);
if (defined($in{'ip'}) || defined($in{'at'})) {
    my $requested=$in{'ip'} || '';
    my $when=$in{'at'} || '';
    fail_ip_info($text{'peer_ip_no_history'})
        unless $requested =~ /^[A-Fa-f0-9:.]{3,45}$/ &&
               $when =~ /^[0-9]{1,12}$/ && $when > 0;
    $ip_request{'event_ip'}=$requested;
    $ip_request{'event_at'}=0+$when;
}
my ($record,$backend_error)=analytics_backend('peer_ip',\%ip_request);
fail_ip_info($backend_error || $text{'peer_ip_no_history'}) if !$record;
if (!$record->{'available'}) {
    json_response({ok=>JSON::PP::true(),available=>JSON::PP::false(),
                   detail=>$text{'peer_ip_no_handshake'}});
    exit;
}
my $ip=$record->{'ip'} || '';
# Only globally routable, canonical numeric IPs may leave the server.
fail_ip_info($text{'peer_ip_no_handshake'}) if $ip !~ /^[0-9a-f:.]{3,45}$/i;
if (!$record->{'public'}) {
    json_response({ok=>JSON::PP::true(),available=>JSON::PP::false(),
                   detail=>$text{'peer_ip_private'}.' ('.$ip.')'});
    exit;
}
my $whois=peer_ip_whois($ip);
my $geoip=peer_ip_geoip($ip);
# Cache is populated ONLY by a manual user-triggered lookup, not by polling.
# Best-effort storage must never mask WHOIS/GeoIP results.
my ($cached,$cache_error)=analytics_backend('network_record', {
    ip=>$ip, whois_fields=>$whois->{'fields'} || [],
    geoip_country_code=>$geoip->{'country_code'} || '',
    geoip_city=>$geoip->{'city'} || '',
    geoip_city_code=>$geoip->{'city_code'} || ''
});
my ($lookup,$lookup_error)=analytics_backend('network_lookup',{ips=>[$ip]});
my $city_match=$lookup && $lookup->{'results'} ?
    ($lookup->{'results'}{$ip} || {}) : {};
my $result={
    ok=>JSON::PP::true(),
    available=>JSON::PP::true(),
    ip=>$ip, handshake=>0+($record->{'handshake'} || 0),
    whois=>$whois, geoip=>$geoip,
    network_cached=>$cached ? JSON::PP::true() : JSON::PP::false(),
    city_match=>{city=>$city_match->{'city'}||'',
        city_code=>$city_match->{'city_code'}||'',
        source=>$city_match->{'city_source'}||''},
    network_cache_error=>$cached ? '' : ($cache_error||'Cache unavailable'),
};
json_response($result);
