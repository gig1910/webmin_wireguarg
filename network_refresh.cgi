#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_manage_access();
assert_post_and_csrf();
request_rate_limit('network_refresh',8,60);

my $ip=$in{'ip'} || '';
my $mode=$in{'mode'} || '';
error($text{'network_icons_invalid'}) if
    $ip !~ /^[0-9A-Fa-f:.]{3,45}$/ || $mode !~ /^(?:whois|geoip|city)$/;

# Authorize ONLY addresses already observed and stored in the exact-IP cache.
# Never accept an arbitrary externally supplied target for a WHOIS query.
my ($known,$known_err)=analytics_backend('network_manage',
    {action=>'check_observed_ip',ip=>$ip});
error($known_err || $text{'network_icons_invalid'})
    if !$known || !$known->{'known'};

my $result;
my $err;
if ($mode eq 'whois') {
    my $response=peer_ip_whois($ip);
    error($response->{'detail'} || $text{'network_icons_invalid'})
        unless $response->{'ok'};
    ($result,$err)=analytics_backend('network_manage',{
        action=>'refresh_whois',ip=>$ip,
        whois_fields=>$response->{'fields'}||[]
    });
}
else {
    my $country='';
    my $city='';
    if ($mode eq 'geoip') {
        my $response=peer_ip_geoip($ip);
        error($response->{'detail'} || $text{'network_icons_invalid'})
            unless $response->{'ok'};
        $country=$response->{'country_code'}||'';
        $city=$response->{'city'}||'';
    }
    else {
        # Read the original observation, not a manual CIDR override.
        my ($observed,$observed_error)=analytics_backend('network_manage',{
            action=>'get_observed_ip',ip=>$ip
        });
        error($observed_error || $text{'network_icons_invalid'}) unless $observed;
        $country=$observed->{'country'}||'';
        $city=$observed->{'city'}||'';
    }
    ($result,$err)=analytics_backend('network_manage',{
        action=>'refresh_geoip',ip=>$ip,country=>$country,city=>$city
    });
}
error($err || $text{'network_icons_invalid'}) unless $result;
ui_print_header(undef,$text{'network_refresh_title'},'',undef,1,1);
print wg_build_banner();
print wg_ui_foundation();
print '<div class="wg-ui"><div class="alert alert-success">'.
    html_escape($text{'network_refresh_done'}).' '.html_escape($ip).'</div>';
print wg_ui_button(href=>'network_icons.cgi',icon=>'external',
    action=>'navigate',label=>$text{'unlocode_return'});
print '</div>';
ui_print_footer();
