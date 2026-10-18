#!/usr/local/bin/perl
require './wireguard-lib.pl';
require './lib/index-page-ui-lib.pl';
ReadParse();
assert_view_access();

ui_print_header(undef, $text{'index_title'}, '', undef, 1, 1);
print wg_build_banner();
my ($items, $list_error) = list_configured_interfaces();
if ($list_error) {
    print ui_alert_box(html_escape($list_error), 'danger');
    print ui_config_link('index_config');
    ui_print_footer('/', $text{'index_title'});
    exit;
}

my $index_page_id='wg-index-'.substr(sha256_hex(time().rand()),0,16);
print wg_ui_foundation();
print '<div class="wg-ui" data-wg-index-page="'.html_escape($index_page_id).'">';
print '<ul class="nav nav-tabs" style="margin-bottom:15px"><li class="active"><a href="index.cgi">'.html_escape($text{'analytics_interfaces_tab'}).'</a></li><li><a href="analytics.cgi">'.html_escape($text{'analytics_title'}).'</a></li></ul>';
print '<div id="wg-runtime-error" class="alert alert-warning" style="display:none"></div>';
print '<div class="wg-runtime-time">'.$text{'runtime_updated'}.': <span id="wg-index-runtime-time">'.$text{'runtime_loading'}.'</span></div>';

my @rows;
foreach my $item (@$items) {
    my $name = $item->{'name'};
    my $summary = interface_summary($item, 0, undef);
    my $status = '<span data-wg-state="'.html_escape($name).'">'.html_escape($text{'runtime_loading'}).'</span>';
    $status .= '<br>'.html_escape($item->{'error'}) if ($item->{'error'});
    my $peers = $summary->{'peer_count'};
    $peers .= ' <small>('.text('index_disabled_count', $summary->{'disabled_count'}).')</small>' if ($summary->{'disabled_count'});
    my $actions = '';
    if ($access{'manage'}) {
        $actions = '<span data-wg-actions-loading="'.html_escape($name).'">'.html_escape($text{'runtime_loading'}).'</span>'.
            '<span data-wg-action-start="'.html_escape($name).'" style="display:none">'.
                mini_action_form($name, 'start', $text{'interface_start'}, 'success', '', 'play').
            '</span>'.
            '<span data-wg-action-stop="'.html_escape($name).'" style="display:none">'.
                mini_action_form($name, 'stop', $text{'interface_stop'}, 'danger', $text{'confirm_stop'}, 'stop').
            '</span>';
    }
    push @rows, [
        '<a data-wg-interface-name="'.html_escape($name).'" href="edit_interface.cgi?name='.urlize($name).'"><b>'.html_escape($name).'</b></a>',
        $status,
        html_escape($summary->{'addresses'} || '-'),
        '<span data-wg-port="'.html_escape($name).'">'.html_escape($summary->{'listen_port'} || '-').'</span>',
        $peers,
        $actions,
    ];
}

print '<div id="wg-interface-table">';
if (@rows) {
    print ui_columns_start(
        [$text{'index_name'}, $text{'index_status'}, $text{'index_addresses'}, $text{'index_port'}, $text{'index_peers'}, $text{'index_actions'}],
        100, 0,
        ['width=19%', 'width=18%', 'width=29%', 'width=12%', 'width=12%', 'width=10%'],
        $text{'index_interfaces'}
    );
    print ui_columns_row($_) for @rows;
    print ui_columns_end();
}
else {
    print ui_alert_box($text{'index_none'}, 'info');
}
print '</div>';

my $index_left=$access{'manage'}
    ? wg_ui_button(href=>'interface_form.cgi',icon=>'plus',
        label=>$text{'index_add'},tone=>'success') : '';
my $index_right=($access{'logs'} ? wg_ui_button(
    href=>'journal.cgi',icon=>'log',label=>$text{'index_logs'}) : '').
    ($access{'manage'} ? wg_ui_icon_action(
    href=>'network_icons.cgi',icon=>'globe',
    label=>$text{'network_icons_title'},tone=>'info') : '');
print wg_ui_action_bar($index_left,$index_right);


my $collector_url = module_script_url('collector_status.cgi');
my $collector_csrf = csrf_token();
my $collector_id = 'wg-collector-'.substr(sha256_hex(time().rand().$$), 0, 12);
print '<div id="'.html_escape($collector_id).'" class="wg-ui-collector"'.
    ' data-url="'.html_escape($collector_url).'" data-csrf="'.html_escape($collector_csrf).'">'.
    '<details class="wg-ui-panel wg-ui-tools" data-wg-tool-panel>'.
    '<summary>'.wg_ui_icon('chevron').' '.html_escape($text{'collector_title'}).
    ' — <span data-role="status">'.html_escape($text{'collector_loading'}).'</span></summary>'.
    '<div class="wg-ui-tools-body">'.
    '<div data-role="warning" class="alert alert-warning" style="display:none"></div>'.
    '<div data-role="details" class="help-block"></div>';
if ($access{'manage'}) {
    print '<div data-role="actions" class="wg-ui-button-row">'.
        wg_ui_button(type=>'button',icon=>'play',tone=>'success',
            label=>$text{'collector_start'},attrs=>{'data-action'=>'start'}).
        wg_ui_button(type=>'button',icon=>'refresh',tone=>'warning',
            label=>$text{'collector_restart'},attrs=>{'data-action'=>'restart'}).
        wg_ui_button(type=>'button',icon=>'stop',tone=>'warning',
            label=>$text{'collector_stop'},attrs=>{'data-action'=>'stop'}).
        '</div>'.
        '<div data-role="console-wrap" style="display:none;margin-top:10px">'.
        '<b>'.html_escape($text{'collector_console'}).'</b>'.
        '<pre data-role="console" style="margin-top:6px;max-height:360px;overflow:auto;white-space:pre-wrap"></pre>'.
        '</div>';
}
print '</div></details></div>';
my $js_collector_id = json_encode_utf8($collector_id);
my $js_collector_healthy = json_encode_utf8($text{'collector_healthy'});
my $js_collector_stale = json_encode_utf8($text{'collector_stale'});
my $js_collector_stopped = json_encode_utf8($text{'collector_stopped'});
my $js_collector_failed = json_encode_utf8($text{'collector_failed'});
my $js_collector_starting = json_encode_utf8($text{'collector_starting'});
my $js_collector_stopping = json_encode_utf8($text{'collector_stopping'});
my $js_collector_unavailable = json_encode_utf8($text{'collector_unavailable'});
my $js_collector_last_update = json_encode_utf8($text{'collector_last_update'});
my $js_collector_storage = json_encode_utf8($text{'collector_storage'});
my $js_collector_service_state = json_encode_utf8($text{'collector_service_state'});
my $js_collector_confirm_stop = json_encode_utf8($text{'collector_confirm_stop'});
my $js_collector_confirm_restart = json_encode_utf8($text{'collector_confirm_restart'});
my $js_collector_running_action = json_encode_utf8($text{'collector_running_action'});
my $js_collector_compacting = json_encode_utf8($text{'collector_compacting'});
my $js_collector_restart_required = json_encode_utf8($text{'collector_restart_required'});
my $js_collector_config_pending = json_encode_utf8($text{'collector_config_pending'});
my $js_collector_config_unverified = json_encode_utf8($text{'collector_config_unverified'});
my $js_collector_config_different = json_encode_utf8($text{'collector_config_different'});
my $js_collector_last_compaction = json_encode_utf8($text{'collector_last_compaction'});
print wg_ui_transport_script();
print wg_index_collector_script(
    $js_collector_id, $js_collector_healthy, $js_collector_stale, $js_collector_stopped, $js_collector_failed, $js_collector_starting, $js_collector_stopping, $js_collector_unavailable, $js_collector_last_update, $js_collector_storage, $js_collector_service_state, $js_collector_confirm_stop, $js_collector_confirm_restart, $js_collector_running_action, $js_collector_compacting, $js_collector_restart_required, $js_collector_last_compaction, $js_collector_config_pending, $js_collector_config_unverified, $js_collector_config_different);

# Treat executable availability independently: a country-only database,
# WHOIS and QR generation are usable even when the full optional bundle is not.
my $qr_status=optional_dependency_quick_status('qrencode');
my $geo_status=wg_geoip_update_status();
my $mmdb=command_path('mmdblookup_cmd','/usr/bin/mmdblookup');
my $legacy=command_path('geoiplookup_cmd','/usr/bin/geoiplookup');
my $whois=command_path('whois_cmd','/usr/bin/whois');
my @geo_dbs=wg_geoip_database_paths();
my $has_geoip=(@geo_dbs && has_command($mmdb)) ||
    ($geo_status->{'legacy_database_available'} && has_command($legacy));
my $has_city=scalar(grep { /GeoLite2-City\\.mmdb$/ } @geo_dbs) > 0 && has_command($mmdb);
my $dep_markup='<div class="wg-ui-dependency-list">';
for my $item (
    [$text{'ui_dependency_qr'},$qr_status->{'command_available'},$qr_status->{'command'}],
    [$text{'ui_dependency_whois'},has_command($whois),$whois],
    [$text{'ui_dependency_geoip'},$has_geoip,
        $has_city?$text{'ui_dependency_city'}:
        ($has_geoip?$text{'ui_dependency_country_only'}:$text{'ui_dependency_missing_db'})],
    [$text{'ui_dependency_geoip_update'},$geo_status->{'command_available'} &&
        $geo_status->{'configured'} && $geo_status->{'timer_enabled'} &&
        $geo_status->{'timer_active'},
        $geo_status->{'command_available'} ? $text{'geoip_update_title'} :
            $text{'geoip_update_missing_tool'}],
) {
    my ($label,$available,$info)=@$item;
    $dep_markup.='<div class="wg-ui-dependency-item">'.
        '<strong>'.html_escape($label).'</strong> <span class="'.
        ($available?'text-success':'text-muted').'">'.
        html_escape($available?$text{'ui_dependency_available'}:$text{'ui_dependency_unavailable'}).
        '</span> <small>'.html_escape($info||'').'</small></div>';
}
if ($access{'install_dependencies'} && $qr_status->{'package_manager_available'}) {
    $dep_markup.=wg_ui_button(
        href=>'install_dependency.cgi?dependency=qrencode',
        icon=>'plus',label=>$text{'qr_install_button'});
    $dep_markup.=' '.wg_ui_button(
        href=>'install_dependency.cgi?dependency=geoip',
        icon=>'plus',label=>$text{'geoip_install_button'});
}
$dep_markup.='</div>';
print wg_ui_panel($text{'dependencies_title'},$dep_markup);

my $js_index_page_id=json_encode_utf8($index_page_id);
my $js_active = json_encode_utf8($text{'index_active'});
my $js_inactive = json_encode_utf8($text{'index_inactive'});
my $js_orphan = json_encode_utf8($text{'index_orphan'});
my $runtime_error_prefix = $text{'index_runtime_error'};
$runtime_error_prefix =~ s/\$1//g;
my $js_runtime_error_prefix = json_encode_utf8($runtime_error_prefix);
print wg_index_runtime_script($js_index_page_id, $js_active, $js_inactive, $js_orphan, $js_runtime_error_prefix);

print runtime_poll_html('');
print ui_config_link('index_config');
print '</div>';
ui_print_footer('/', $text{'index_title'});
