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
# One explicit request: independently query both sources; city is resolved
# from that exact IP in the SQLite backend. Do not copy CIDR overrides.
my $whois=peer_ip_whois($ip);
my $geoip=peer_ip_geoip($ip);
my $commit=($in{'commit'}||'') eq '1';
my ($stored,$err);
if ($commit && $whois->{'ok'} && $geoip->{'ok'}) {
    ($stored,$err)=analytics_backend('network_record',{
        ip=>$ip,whois_fields=>$whois->{'fields'}||[],
        geoip_country_code=>$geoip->{'country_code'}||'',
        geoip_city=>$geoip->{'city'}||''
    });
}
elsif ($commit && $whois->{'ok'}) {
    ($stored,$err)=analytics_backend('network_manage',{
        action=>'refresh_whois',ip=>$ip,
        whois_fields=>$whois->{'fields'}||[]
    });
}
elsif ($commit && $geoip->{'ok'}) {
    ($stored,$err)=analytics_backend('network_manage',{
        action=>'refresh_geoip',ip=>$ip,
        country=>$geoip->{'country_code'}||'',city=>$geoip->{'city'}||''
    });
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
