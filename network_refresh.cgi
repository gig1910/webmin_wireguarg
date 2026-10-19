#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_manage_access();
sub fail_refresh {
    my ($message)=@_;
    json_response({ok=>JSON::PP::false(),error=>"$message"});
    exit;
}
eval { assert_post_and_csrf(); request_rate_limit('network_refresh',8,60); 1 }
    or fail_refresh($@ || $text{'network_icons_invalid'});
my $ip=$in{'ip'}||'';
fail_refresh($text{'network_icons_invalid'})
    unless $ip =~ /^[0-9A-Fa-f:.]{3,45}$/;
my ($known,$known_err)=analytics_backend('network_manage',
    {action=>'check_observed_ip',ip=>$ip});
fail_refresh($known_err||$text{'network_icons_invalid'})
    unless $known && $known->{'known'};
my $commit=($in{'commit'}||'') eq '1';
my ($whois,$geoip,$stored,$err);
if ($commit) {
    # Commit the exact preview approved by the administrator; do not issue
    # a second WHOIS/GeoIP request that may block or return different data.
    my $raw=$in{'preview'}||'';
    fail_refresh('Invalid or oversized preview') if length($raw)>32768;
    my $preview=eval { JSON::PP::decode_json($raw) };
    fail_refresh('Invalid preview') unless ref($preview) eq 'HASH' &&
        ($preview->{'ip'}||'') eq $ip;
    $whois=$preview->{'whois'};
    $geoip=$preview->{'geoip'};
    fail_refresh('Invalid preview sources') unless
        ref($whois) eq 'HASH' && ref($geoip) eq 'HASH';
    my $fields=$whois->{'fields'};
    fail_refresh('Invalid WHOIS fields') unless
        ref($fields) eq 'ARRAY' && @$fields<=40 &&
        !grep { ref($_) ne 'HASH' ||
            length($_->{'label'}||'')>100 ||
            length($_->{'value'}||'')>2048 } @$fields;
    my $country=$geoip->{'country_code'}||'';
    my $city=$geoip->{'city'}||'';
    fail_refresh('Invalid GeoIP data') if
        length($country)>2 || $country !~ /^(?:[A-Z]{2})?$/ ||
        ref($city) || length($city)>100;
    if ($whois->{'ok'} && $geoip->{'ok'}) {
        ($stored,$err)=analytics_backend('network_record',{
            ip=>$ip,whois_fields=>$fields,
            geoip_country_code=>$country,geoip_city=>$city
        });
    }
    elsif ($whois->{'ok'}) {
        ($stored,$err)=analytics_backend('network_manage',{
            action=>'refresh_whois',ip=>$ip,whois_fields=>$fields
        });
    }
    elsif ($geoip->{'ok'}) {
        ($stored,$err)=analytics_backend('network_manage',{
            action=>'refresh_geoip',ip=>$ip,country=>$country,city=>$city
        });
    }
}
else {
    $whois=peer_ip_whois($ip);
    $geoip=peer_ip_geoip($ip);
}
my ($lookup,$lookup_error)=analytics_backend('network_lookup',{ips=>[$ip]});
my $info=$lookup && $lookup->{'results'} ? ($lookup->{'results'}{$ip}||{}) : {};
json_response({
    ok=>JSON::PP::true(),available=>JSON::PP::true(),
    ip=>$ip,whois=>$whois,geoip=>$geoip,
    committed=>$commit ? JSON::PP::true() : JSON::PP::false(),
    network_cached=>$stored ? JSON::PP::true() : JSON::PP::false(),
    network_cache_error=>$err||'',
    city_match=>{city=>$info->{'city'}||'',city_code=>$info->{'city_code'}||'',
                 source=>$info->{'city_source'}||''}
});
