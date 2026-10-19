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
print '<input type="hidden" name="country_override" value="">';
print '<div class="wg-ui-form-row">'.
    '<label>'.html_escape($text{'network_icons_prefix'}).' <input name="cidr" required placeholder="203.0.113.0/24" maxlength="64"></label> '.
    '<label>'.html_escape($text{'network_icons_symbol'}).' <input name="icon" value="?" maxlength="8" size="5"></label> '.
    '<label>'.html_escape($text{'network_icons_label'}).' <input name="label" maxlength="100" size="30"></label> '.
    '<label>'.html_escape($text{'network_icons_city'}).' <input name="city" maxlength="100" size="22" autocomplete="off"></label> '.
    '<label>'.html_escape($text{'network_icons_city_code'}).' <input name="city_code" maxlength="5" size="8" placeholder="RUMOW" title="'.html_escape($text{'network_icons_city_help'}).'"></label> '.
    '</div>';
print '<div class="wg-network-editor-actions">'.
    wg_ui_button(type=>'submit',icon=>'save',tone=>'success',label=>$text{'network_icons_save'}).
    wg_ui_button(type=>'button',icon=>'search',tone=>'info',label=>$text{'unlocode_search_button'},attrs=>{'data-wg-city-search-button'=>'1'}).
    wg_ui_button(type=>'button',icon=>'close',tone=>'danger',label=>$text{'network_city_clear'},attrs=>{'data-wg-city-clear'=>'1'}).
    '</div>';
print '<div data-wg-city-choices hidden role="listbox"></div>';
print ui_form_end();
print '</div>';
print '<table data-wg-network-table class="table table-striped table-hover"><thead><tr><th>'.
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
    my $observed_country=$item->{'country'} || '';
    my $country=$manual && $manual->{'country_override'} ? $manual->{'country_override'} : $observed_country;
    my $owner=$item->{'owner'} || '';
    my $city=$manual && $manual->{'city'} ? $manual->{'city'} : '';
    my $city_code=$manual && $manual->{'city_code'} ? $manual->{'city_code'} : ''; 
    my @city_observations=@{$item->{'geoip_cities'}||[]};
    # City has meaning only when it is a validated UN/LOCODE or an
    # actual city name. Reject corrupted legacy single-character values.
    my @display_cities=map {
        /^[A-Z]{2}([A-Z0-9]{3})$/ ? $1 :
        /^[A-Za-z][A-Za-z .'-]{2,79}$/ ? $_ : ()
    } @city_observations;
    my $cities=join(', ',@display_cities);
    my @observed_names=grep { defined($_) && length($_) } @{$item->{'geoip_city_names'}||[]};
    my $suggested_city=@observed_names==1 ? $observed_names[0] : '';
    my $suggested_code=@city_observations==1 && $city_observations[0]=~/^[A-Z]{2}[A-Z0-9]{3}$/ ? $city_observations[0] : '';
    my $city_hint=join(', ',grep {
        /^[A-Z]{2}[A-Z0-9]{3}$/ || /^[A-Za-z][A-Za-z .'-]{2,79}$/
    } @city_observations);
    my $geoip_codes=join(',', @{$item->{'geoip_countries'}||[]});
    print '<tr><td><span class="wg-ui-mono">'.html_escape($cidr).'</span></td>'.
        '<td>'.html_escape($icon).'</td><td>'.html_escape($label).'</td>'.
        '<td>'.html_escape($owner).'</td>'.
        '<td><span data-wg-country="'.html_escape($country).'">'.html_escape($country).'</span></td>'.
        '<td title="'.html_escape($city||$city_hint).'">'.html_escape($city||($city_code=~/^[A-Z]{2}([A-Z0-9]{3})$/ ? $1 : '')||$cities||'—').'</td>'.
        '<td><span data-wg-geoip-codes="'.html_escape($geoip_codes).'" title="'.html_escape($text{'network_icons_geoip_help'}).'">'.html_escape($geoip_codes).'</span></td>'.
        '<td><span class="wg-ui-table-actions">'.
        wg_ui_icon_action(icon=>'edit',tone=>'info',
            label=>$text{'ui_network_edit'},
            attrs=>{
                'data-wg-edit-range'=>'1',
                'data-cidr'=>$cidr,'data-icon'=>$icon,
                'data-label'=>$label,'data-city'=>$city,'data-city-code'=>$city_code,
                'data-observed-country'=>$observed_country,
                'data-manual-country'=>($manual ? ($manual->{'country_override'}||'') : ''),
                'data-suggested-city'=>($city ? '' : $suggested_city),
                'data-suggested-code'=>($city ? '' : $suggested_code),
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
        my @ips=grep { /^[0-9A-Fa-f:.]{3,45}$/ } @{$item->{'observed_ips'}};
        if (@ips) {
            print '<span class="wg-cache-lookup">';
            if (@ips > 1) {
                print '<select aria-label="'.html_escape($text{'network_refresh_select_ip'}).'">'.
                    join('',map { '<option value="'.html_escape($_).'">'.html_escape($_).'</option>' } @ips).
                    '</select>';
            }
            print wg_ui_icon_action(icon=>'globe',tone=>'info',
                label=>$text{'network_refresh_all'},
                attrs=>{'data-wg-cache-refresh'=> $ips[0]});
            print '</span>';
        }
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
print '<div class="wg-ui-modal" data-wg-cache-dialog hidden role="dialog" aria-modal="true">'.
    '<div class="wg-ui-modal-panel panel panel-default">'.
    '<div class="wg-ui-modal-header"><h3>'.html_escape($text{'network_refresh_title'}).'</h3>'.
    wg_ui_button(type=>'button',icon=>'close',label=>$text{'ui_close'},
        attrs=>{'data-wg-cache-close'=>'1'}).'</div>'.
    '<div class="wg-ui-modal-body" data-wg-cache-output role="status" aria-live="polite"></div>'.
    '<div class="wg-cache-confirm-actions" data-wg-cache-confirm hidden></div>'.
    '</div></div>';
print '<div class="wg-ui-modal" data-wg-locode-dialog hidden role="dialog" aria-modal="true">'.
    '<div class="wg-ui-modal-panel panel panel-default">'.
    '<div class="wg-ui-modal-header"><h3>Поиск UN/LOCODE</h3>'.
    wg_ui_button(type=>'button',icon=>'close',label=>$text{'ui_close'},
        attrs=>{'data-wg-locode-close'=>'1'}).'</div>'.
    '<div class="wg-locode-searchbar"><input type="search" data-wg-locode-query placeholder="Название или код города" aria-label="Поиск города">'.
    '<span data-wg-locode-count role="status"></span></div>'.
    '<label class="wg-locode-country-filter"><input type="checkbox" data-wg-locode-filter checked> Только ранее определённая страна: <strong data-wg-locode-country></strong></label>'.
    '<div data-wg-locode-results class="wg-locode-results"></div>'.
    '<div class="wg-locode-pagination"><button type="button" class="btn btn-default" data-wg-locode-prev>Назад</button>'.
    '<span data-wg-locode-page></span>'.
    '<button type="button" class="btn btn-default" data-wg-locode-next>Далее</button></div>'.
    '</div></div>';
print '<div hidden data-wg-city-save-url="'.html_escape(module_script_url('network_save.cgi')).'"></div>';
print '<div hidden data-wg-unlocode-search-url="'.html_escape(module_script_url('unlocode_search.cgi')).'"></div>';
print '<div hidden data-wg-cache-options data-wg-cache-url="'.
    html_escape(module_script_url('network_refresh.cgi')).'" data-wg-cache-token="'.
    html_escape(csrf_token()).'"></div>';
print wg_ui_transport_script();
print wg_network_icons_page_script(json_encode_utf8($network_page_id));
print '</div>';
ui_print_footer('index.cgi',$text{'index_title'});
