#!/usr/local/bin/perl
require './wireguard-lib.pl';
require './lib/network-icons-ui-lib.pl';
ReadParse();
assert_view_access();
assert_manage_access();

my $notice='';
# Authentic Theme navigation can arrive as a POST without an edit action.
# Rendering the directory is read-only, regardless of the navigation method.
# An explicit action, however, always requires POST + a valid CSRF token.
my $action=$in{'action'} || '';
if (length($action)) {
    assert_post_and_csrf();
    request_rate_limit('network_icons',12,60);
    error($text{'network_icons_invalid'}) if $action !~ /^(?:set_icon|delete_icon|clear_cache)$/;
    my $payload={
        action=>$action,
        cidr=>$in{'cidr'} || '',
        icon=>$in{'icon'} || '?',
        label=>$in{'label'} || '',
        confirm=>$in{'confirm'} || '',
    };
    # Webmin ReadParse can yield UTF-8 octets. Convert only byte values, once,
    # before JSON::PP encodes the request for the Python SQLite backend.
    for my $field (qw(icon label)) {
        my $value = $payload->{$field};
        next if !defined($value) || utf8::is_utf8($value) || $value !~ /[\x80-\xFF]/;
        $payload->{$field} = eval { Encode::decode('UTF-8', $value, Encode::FB_CROAK()) };
        error($text{'network_icons_invalid'}) if $@;
    }
    my ($result,$err)=analytics_backend('network_manage',$payload);
    error($err || $text{'network_icons_invalid'}) if !$result;
    $notice=$text{'network_icons_saved'};
}
my ($report,$err)=analytics_backend('network_manage',{action=>'list'});
error($err) unless $report;
ui_print_header(undef,$text{'network_icons_title'},'',undef,1,1);
print wg_build_banner();
my $network_page_id='wg-net-'.substr(sha256_hex(time().rand()),0,16);
print '<div data-wg-network-page="'.html_escape($network_page_id).'">';
print '<div class="alert alert-success">'.html_escape($notice).'</div>' if $notice;
print '<p>'.html_escape($text{'network_icons_help'}).'</p>';
# Shared network/GeoIP controls live here, independently of any peer.
my $geo=wg_geoip_update_status();
my $deps=optional_dependency_quick_status('geoip');
my $geo_message=$geo->{'database_mtime'}
    ? text('geoip_update_age',strftime('%Y-%m-%d %H:%M',localtime($geo->{'database_mtime'})),
        0+($geo->{'database_age_days'}||0))
    : ($geo->{'legacy_database_available'} ? $text{'geoip_legacy_ready'} : $text{'geoip_update_missing_db'});
$geo_message .= ' — '.$text{'geoip_update_stale'} if $geo->{'stale'};
print '<section class="panel panel-default"><div class="panel-heading"><b>'.
    html_escape($text{'geoip_update_title'}).'</b></div><div class="panel-body"><p>'.
    html_escape($geo_message).'</p>';
if (!$deps->{'command_available'}) {
    print '<p>'.html_escape($text{'geoip_dependency_missing'}).'</p>';
    if ($access{'install_dependencies'} && $deps->{'package_manager_available'}) {
        print '<p>'.direct_link_button('install_dependency.cgi',$text{'geoip_install_button'},
            {dependency=>'geoip'}).'</p>';
    }
}
if ($access{'manage'} && $geo->{'configured'} && $geo->{'command_available'} &&
    $geo->{'timer_available'} && (!$geo->{'timer_enabled'} || !$geo->{'timer_active'})) {
    print ui_form_start('geoip_timer.cgi','post');
    print csrf_hidden();
    print '<button type="submit" class="btn btn-default">'.
        html_escape($text{'geoip_update_enable'}).'</button>';
    print ui_form_end();
}
print '</div></section>';

my %ranges;
for my $item (@{$report->{'cache'}||[]}) {
    next if !defined($item->{'cidr'});
    $ranges{$item->{'cidr'}}={%$item};
}
for my $item (@{$report->{'icons'}||[]}) {
    next if !defined($item->{'cidr'});
    $ranges{$item->{'cidr'}} ||= {cidr=>$item->{'cidr'}};
    $ranges{$item->{'cidr'}}->{'manual'}=$item;
}
print '<h3>'.html_escape($text{'network_icons_manual'}).'</h3>';
print '<p>'.html_escape($text{'network_icons_cache_help'}).'</p>';
print '<div id="wg-network-editor">';
print ui_form_start(module_script_url('network_icons.cgi'),'post');
print csrf_hidden();
print ui_hidden('action','set_icon');
print '<div class="wg-network-form">'.
    '<label>'.html_escape($text{'network_icons_prefix'}).' <input name="cidr" required placeholder="203.0.113.0/24" maxlength="64"></label> '.
    '<label>'.html_escape($text{'network_icons_symbol'}).' <input name="icon" value="?" maxlength="8" size="5"></label> '.
    '<label>'.html_escape($text{'network_icons_label'}).' <input name="label" maxlength="100" size="30"></label> '.
    '<button type="submit" class="btn btn-primary">'.html_escape($text{'network_icons_save'}).'</button></div>';
print ui_form_end();
print '</div>';
print '<table class="table table-striped table-hover"><thead><tr><th>'.
    html_escape($text{'network_icons_prefix'}).'</th><th>'.html_escape($text{'network_icons_symbol'}).
    '</th><th>'.html_escape($text{'network_icons_label'}).'</th><th>'.
    html_escape($text{'network_icons_owner'}).'</th><th>'.
    html_escape($text{'network_icons_country'}).'</th><th>'.
    html_escape($text{'network_icons_geoip_samples'}).'</th><th>'.
    html_escape($text{'interface_peer_actions'}).'</th></tr></thead><tbody>';
for my $cidr (sort keys %ranges) {
    my $item=$ranges{$cidr};
    my $manual=$item->{'manual'};
    my $icon=$manual ? ($manual->{'icon'}||'?') : '?';
    my $label=$manual ? ($manual->{'label'}||'') : '';
    my $country=$item->{'country'} || '';
    my $owner=$item->{'owner'} || '';
    my $geoip_codes=join(',', @{$item->{'geoip_countries'}||[]});
    print '<tr><td><button type="button" class="wg-network-edit-link" data-wg-edit-range="1"'.
        ' data-cidr="'.html_escape($cidr).'"'.
        ' data-icon="'.html_escape($icon).'"'.
        ' data-label="'.html_escape($label).'">'.html_escape($cidr).'</button></td>'.
        '<td>'.html_escape($icon).'</td><td>'.html_escape($label).'</td>'.
        '<td>'.html_escape($owner).'</td>'.
        '<td><span data-wg-country="'.html_escape($country).'">'.html_escape($country).'</span></td>'.
        '<td><span data-wg-geoip-codes="'.html_escape($geoip_codes).'" title="'.html_escape($text{'network_icons_geoip_help'}).'">'.html_escape($geoip_codes).'</span></td><td>';
    if ($manual) {
        print ui_form_start(module_script_url('network_icons.cgi'),'post');
        print csrf_hidden();
        print ui_hidden('action','delete_icon');
        print ui_hidden('cidr',$cidr);
        print '<button type="submit" class="btn btn-default">'.
            html_escape($text{'network_icons_delete'}).'</button>';
        print ui_form_end();
    }
    print '</td></tr>';
}
print '</tbody></table>';
print ui_form_start(module_script_url('network_icons.cgi'),'post');
print csrf_hidden();
print ui_hidden('action','clear_cache');
print '<label>'.html_escape($text{'network_icons_confirm'}).' <input name="confirm" maxlength="5" autocomplete="off"></label> ';
print '<button type="submit" class="btn btn-danger">'.html_escape($text{'network_icons_clear'}).'</button>';
print ui_form_end();
print wg_network_icons_page_script(json_encode_utf8($network_page_id));
print '</div>';
ui_print_footer('index.cgi',$text{'index_title'});
