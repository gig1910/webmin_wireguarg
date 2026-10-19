#!/usr/local/bin/perl
require './wireguard-lib.pl';
require './lib/network-icons-ui-lib.pl';
require './lib/network-icons-action-lib.pl';
ReadParse();
assert_view_access();
assert_manage_access();

my $notice=wg_network_icons_dispatch();
my ($report,$err)=analytics_backend('network_manage',{action=>'list'});
error($err) unless $report;
ui_print_header(undef,$text{'network_icons_title'},'',undef,1,1);
print wg_build_banner();
my $network_page_id='wg-net-'.substr(sha256_hex(time().rand()),0,16);
print wg_ui_foundation();
print '<div class="wg-ui" data-wg-network-page="'.html_escape($network_page_id).'">';
print '<div class="alert alert-success">'.html_escape($notice).'</div>' if $notice;
print '<p>'.html_escape($text{'network_icons_help'}).'</p>';
print '<p class="help-block">'.html_escape(
    sprintf($text{'unlocode_status'},0+($report->{'unlocode_count'}||0))).' '.
    '<a href="https://unlocode.unece.org/publications/" target="_blank" rel="noopener noreferrer">'.
    html_escape($text{'unlocode_official'}).'</a></p>';

# UNECE refresh is asynchronous and distinct from geoipupdate.
print '<div class="wg-ui-form-row">';
print ui_form_start(module_script_url('unlocode_update.cgi'),'post');
print csrf_hidden();
print wg_ui_button(type=>'submit',icon=>'refresh-cw',action=>'restart',
    label=>$text{'unlocode_update_button'});
print ui_form_end();
print '</div>';
my $unlocode_state=File::Spec->catfile(_state_dir(),'unlocode-status.json');
if (-f $unlocode_state && -r $unlocode_state) {
    my $raw=read_file_contents($unlocode_state) || '';
    my $state=eval { JSON::PP::decode_json($raw) };
    if ($state && ref($state) eq 'HASH' && $state->{'updated_at'} =~ /^\d{9,12}$/) {
        print '<p class="help-block">'.html_escape(
            sprintf($text{'unlocode_last_updated'},
                 strftime('%Y-%m-%d %H:%M',localtime($state->{'updated_at'})))).'</p>';
    }
}

my $unlocode_error=File::Spec->catfile(_state_dir(),'unlocode-last-error.txt');
if (-f $unlocode_error && -r $unlocode_error && -s $unlocode_error < 2048) {
    my $message=read_file_contents($unlocode_error) || '';
    $message =~ s/[\r\n]+/ /g;
    print '<div class="alert alert-warning">'.
        html_escape($text{'unlocode_update_warning'}).' '.
        html_escape($message).'</div>';
}

# Shared network/GeoIP controls live here, independently of any peer.
my $geo=wg_geoip_update_status();
my $deps=optional_dependency_quick_status('geoip');
my $geo_message=$geo->{'database_mtime'}
    ? sprintf($text{'geoip_update_age'},strftime('%Y-%m-%d %H:%M',localtime($geo->{'database_mtime'})),
        0+($geo->{'database_age_days'}||0))
    : ($geo->{'legacy_database_available'} ? $text{'geoip_legacy_ready'} : $text{'geoip_update_missing_db'});
$geo_message .= ' — '.$text{'geoip_update_stale'} if $geo->{'stale'};
my @databases=wg_geoip_database_paths();
if (@databases) {
    my $type=$databases[0] =~ /GeoLite2-City\.mmdb$/ ?
        $text{'ui_dependency_city'} : $text{'ui_dependency_country_only'};
    $geo_message.=' — '.$type;
}
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
    print wg_ui_button(type=>'submit',icon=>'play',tone=>'success',
        label=>$text{'geoip_update_enable'});
    print ui_form_end();
}
print '<p>'.wg_ui_button(href=>'geoip_city_setup.cgi',icon=>'download',action=>'navigate',
    label=>$text{'geoip_city_title'}).'</p>' if $access{'manage'};
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
print '<div class="wg-ui-form-row">'.
    '<label>'.html_escape($text{'network_icons_prefix'}).' <input name="cidr" required placeholder="203.0.113.0/24" maxlength="64"></label> '.
    '<label>'.html_escape($text{'network_icons_symbol'}).' <input name="icon" value="?" maxlength="8" size="5"></label> '.
    '<label>'.html_escape($text{'network_icons_label'}).' <input name="label" maxlength="100" size="30"></label> '.
    '<label>'.html_escape($text{'network_icons_city'}).' <input name="city" maxlength="100" size="22"></label> '.
    '<label>'.html_escape($text{'network_icons_city_code'}).' <input name="city_code" maxlength="5" size="8" placeholder="RUMOW" title="'.html_escape($text{'network_icons_city_help'}).'"></label> '.
    wg_ui_button(type=>'submit',icon=>'save',tone=>'success',
        label=>$text{'network_icons_save'}).'</div>';
print ui_form_end();
print '</div>';
print '<table class="table table-striped table-hover"><thead><tr><th>'.
    html_escape($text{'network_icons_prefix'}).'</th><th>'.html_escape($text{'network_icons_symbol'}).
    '</th><th>'.html_escape($text{'network_icons_label'}).'</th><th>'.
    html_escape($text{'network_icons_owner'}).'</th><th>'.
    html_escape($text{'network_icons_country'}).'</th><th>'.html_escape($text{'network_icons_city'}).'</th><th>'.
    html_escape($text{'network_icons_geoip_samples'}).'</th><th>'.
    html_escape($text{'interface_peer_actions'}).'</th></tr></thead><tbody>';
for my $cidr (sort keys %ranges) {
    my $item=$ranges{$cidr};
    my $manual=$item->{'manual'};
    my $icon=$manual ? ($manual->{'icon'}||'?') : '?';
    my $label=$manual ? ($manual->{'label'}||'') : '';
    my $country=$item->{'country'} || '';
    my $owner=$item->{'owner'} || '';
    my $city=$manual && $manual->{'city'} ? $manual->{'city'} : '';
    my $city_code=$manual && $manual->{'city_code'} ? $manual->{'city_code'} : ''; 
    my @city_observations=@{$item->{'geoip_cities'}||[]};
    my $cities=join(', ',map {
        /^[A-Z]{2}([A-Z0-9]{3})$/ ? $1 :
        /^[A-Za-z][A-Za-z .'-]{1,79}$/ ? $_ : ()
    } @city_observations);
    my $city_hint=join(', ',@city_observations);
    my $geoip_codes=join(',', @{$item->{'geoip_countries'}||[]});
    print '<tr><td><span class="wg-ui-mono">'.html_escape($cidr).'</span></td>'.
        '<td>'.html_escape($icon).'</td><td>'.html_escape($label).'</td>'.
        '<td>'.html_escape($owner).'</td>'.
        '<td><span data-wg-country="'.html_escape($country).'">'.html_escape($country).'</span></td>'.
        '<td title="'.html_escape($city||$city_hint).'">'.html_escape(($city_code=~/^[A-Z]{2}([A-Z0-9]{3})$/ ? $1 : '')||$cities||'—').'</td>'.
        '<td><span data-wg-geoip-codes="'.html_escape($geoip_codes).'" title="'.html_escape($text{'network_icons_geoip_help'}).'">'.html_escape($geoip_codes).'</span></td>'.
        '<td><span class="wg-ui-table-actions">'.
        wg_ui_icon_action(icon=>'edit',tone=>'info',
            label=>$text{'ui_network_edit'},
            attrs=>{
                'data-wg-edit-range'=>'1',
                'data-cidr'=>$cidr,'data-icon'=>$icon,
                'data-label'=>$label,'data-city'=>$city,'data-city-code'=>$city_code,
            });
    if ($manual) {
        print ui_form_start(module_script_url('network_icons.cgi'),'post');
        print csrf_hidden();
        print ui_hidden('action','delete_icon');
        print ui_hidden('cidr',$cidr);
        print wg_ui_icon_action(icon=>'trash',tone=>'danger',type=>'submit',
            label=>$text{'network_icons_delete'},
            attrs=>{'data-wg-confirm'=>$text{'network_icons_delete'}.' — '.$cidr});
        print ui_form_end();
    }
    if ($item->{'observed_ips'} && @{$item->{'observed_ips'}}) {
        my @observed=@{$item->{'observed_ips'}};
        print '<details class="wg-network-refresh"><summary>'.
            html_escape(sprintf($text{'network_refresh_count'},scalar(@observed))).
            '</summary>';
        for my $ip (@observed) {
            next if $ip !~ /^[0-9A-Fa-f:.]{3,45}$/;
            print '<div class="wg-network-refresh-row"><span class="wg-ui-mono">'.
                html_escape($ip).'</span>';
            for my $entry (
                ['whois','network_refresh_whois','refresh-cw'],
                ['geoip','network_refresh_geoip','globe'],
                ['city','network_refresh_city','map-pin']
            ) {
                my ($mode,$label,$glyph)=@$entry;
                print ui_form_start(module_script_url('network_refresh.cgi'),'post');
                print csrf_hidden();
                print ui_hidden('ip',$ip);
                print ui_hidden('mode',$mode);
                print wg_ui_button(type=>'submit',icon=>$glyph,action=>'restart',
                    label=>$text{$label});
                print ui_form_end();
            }
            print '</div>';
        }
        print '</details>';
    }
    print '</span></td></tr>';
}
print '</tbody></table>';
print wg_ui_panel_start($text{'ui_network_maintenance'}).
    '<p class="help-block">'.html_escape($text{'network_icons_cache_help'}).'</p>';
print ui_form_start(module_script_url('network_icons.cgi'),'post');
print csrf_hidden();
print ui_hidden('action','clear_cache');
print '<input type="hidden" name="confirm" value="">';
print wg_ui_button(type=>'submit',icon=>'trash',tone=>'danger',
    label=>$text{'network_icons_clear'},attrs=>{
        'data-wg-confirm'=>$text{'network_icons_clear'},
        'data-wg-confirm-word'=>'CLEAR'});
print ui_form_end();
print wg_ui_panel_end();
print wg_network_icons_page_script(json_encode_utf8($network_page_id));
print '</div>';
ui_print_footer('index.cgi',$text{'index_title'});
