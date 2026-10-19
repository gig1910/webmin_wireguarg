#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_manage_access();
assert_post_and_csrf();
request_rate_limit('geoip_timer',3,600);

my ($ok,$message)=wg_geoip_enable_vendor_timer();
if (($in{'_wg_ajax'}||'') eq '1') {
    json_response({ok=>$ok ? JSON::PP::true() : JSON::PP::false(),
        error=>$ok ? '' : ($message||'GeoIP timer failure')});
    exit;
}
ui_print_header(undef,$text{'geoip_update_title'},'',undef,1,1);
print wg_build_banner();
print wg_ui_foundation();
print '<div class="wg-ui">';
print '<div class="'.($ok?'alert alert-success':'alert alert-warning').'">'.
    html_escape($ok ? $text{'geoip_update_enabled'} : $message).'</div>';
my $name=$in{'name'} || '';
my $index=$in{'peer'} || '';
if (valid_interface_name($name) && $index =~ /^\d{1,6}$/) {
    print '<p>'.direct_link_button('edit_peer.cgi',$text{'geoip_update_back'},
        {name=>$name,peer=>$index}).'</p>';
}
print '<p>'.direct_link_button('index.cgi',$text{'back'},{}).'</p>';
print '</div>';
ui_print_footer();
