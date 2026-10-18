#!/usr/local/bin/perl
require './wireguard-lib.pl';
require './lib/interface-page-ui-lib.pl';
ReadParse();
assert_view_access();
my $csrf = csrf_token();

my $name = $in{'name'};
error($text{'error_invalid_name'}) if (!valid_interface_name($name));
my $path = conf_path($name);
error(text('error_interface', $name)) if (!-r $path);
my ($cfg, $parse_error) = parse_wireguard_config($path);
error(text('error_read', $path, $parse_error)) if (!$cfg);
my $ifc = $cfg->{'interface'} || { 'values' => {}, 'meta' => {} };

ui_print_header(undef, text('interface_title', $name), '', undef, 1, 1);
print wg_build_banner();
my $page_instance = substr(sha256_hex(join('|', $$, time(), rand(), $name)), 0, 16);
print wg_ui_foundation();
print '<div class="wg-ui" data-wg-interface-page="'.html_escape($page_instance).'">';
print '<div id="wg-interface-runtime-error" class="alert alert-warning" style="display:none"></div>';
print '<div id="wg-peer-action-result" class="alert" style="display:none"></div>';

my $static_public = $ifc->{'public_key_comment'} || '';
my $public_display = length($static_public) ? html_escape($static_public) : html_escape($text{'runtime_loading'});
my $private_state = length($ifc->{'private_key'} || '') ? $text{'key_saved'} : $text{'key_missing'};
my $client_allowed_display = get_meta_value($ifc, 'clientallowedips') || '';
if (!length($client_allowed_display)) {
    my @automatic_networks = interface_address_networks($ifc);
    $client_allowed_display = @automatic_networks
        ? text('interface_client_allowed_auto', join(', ', @automatic_networks))
        : $text{'interface_client_allowed_none'};
}

print ui_table_start($text{'interface_settings'}, 'width=100%', 4, ['width=25%', 'width=25%', 'width=25%', 'width=25%']);
print ui_table_row($text{'interface_file'}, '<tt>'.html_escape($path).'</tt>');
print ui_table_row($text{'interface_state'}, '<span class="wg-ui-status" id="wg-interface-state">'.html_escape($text{'runtime_loading'}).'</span>');
print ui_table_row($text{'interface_addresses'}, wg_ui_ip_value(join(', ', get_section_values($ifc, 'Address')) || '-',kind=>'cidr'));
print ui_table_row($text{'interface_listen_port'}, '<span id="wg-interface-port">'.html_escape(get_section_value($ifc, 'ListenPort') || '-').'</span>');
print ui_table_row($text{'interface_public_key'},
    '<span class="wg-ui-copy"><tt id="wg-interface-public-key">'.$public_display.'</tt>'.
    wg_ui_icon_action(icon=>'copy',label=>$text{'ui_copy_public'},
        attrs=>{'data-wg-copy-target'=>'wg-interface-public-key'}).'</span>');
print ui_table_row($text{'interface_private_key'}, html_escape($private_state));
print ui_table_row($text{'interface_client_endpoint'},
    '<span class="wg-ui-copy"><span class="wg-ui-mono" id="wg-interface-client-endpoint">'.
    html_escape(get_meta_value($ifc,'clientendpoint')||'-').'</span>'.
    wg_ui_icon_action(icon=>'copy',label=>$text{'ui_copy_endpoint'},
       attrs=>{'data-wg-copy-target'=>'wg-interface-client-endpoint'}).'</span>');
print ui_table_row($text{'interface_client_allowed'}, wg_ui_ip_value($client_allowed_display,kind=>'cidr'));
print ui_table_end();

my $interface_toolbar_left= '';
my $interface_toolbar_right= '';
if ($access{'manage'}) {
    $interface_toolbar_left=wg_ui_button(
        href=>'interface_form.cgi?name='.urlize($name),
        icon=>'edit',label=>$text{'interface_edit'},action=>'edit').
        wg_ui_button(href=>'edit_peer.cgi?name='.urlize($name),
        icon=>'plus',label=>$text{'interface_add_peer'},action=>'add');
    $interface_toolbar_left.='<span class="wg-actions">'.
        '<span id="wg-actions-loading">'.html_escape($text{'runtime_loading'}).'</span>'.
        '<span id="wg-actions-active" style="display:none">'.
            mini_action_form($name,'restart',$text{'interface_restart'},'warning',$text{'confirm_restart'},'refresh',0).
            mini_action_form($name,'stop',$text{'interface_stop'},'warning',$text{'confirm_stop'},'stop',0).
        '</span>'.
        '<span id="wg-actions-inactive" style="display:none">'.
            mini_action_form($name,'start',$text{'interface_start'},'success','','play',0).
        '</span></span>';
}
$interface_toolbar_right=wg_ui_icon_action(
    icon=>'refresh',label=>$text{'ui_refresh_runtime'},tone=>'neutral',
    attrs=>{'data-wg-runtime-refresh'=>'1'}).
    '<span data-wg-runtime-refresh-status></span> '.
    wg_ui_button(href=>'analytics.cgi?interface='.urlize($name),
    icon=>'chart',label=>$text{'analytics_interface_link'}).
    ($access{'logs'}?wg_ui_button(
        href=>'journal.cgi?name='.urlize($name),
        icon=>'log',label=>$text{'interface_logs'}):'').
    ($access{'manage'}?wg_ui_button(
        href=>'network_icons.cgi',icon=>'network',
        label=>$text{'network_icons_title'}):'');
print wg_ui_action_bar($interface_toolbar_left,$interface_toolbar_right);
print graph_html($name, '', text('graph_interface_title', $name));

my $toggle_peer_url = module_script_url('toggle_peer.cgi');
my @rows;
for (my $i = 0; $i < @{$cfg->{'peers'}}; $i++) {
    my $peer = $cfg->{'peers'}->[$i];
    my $disabled = $peer->{'disabled'} ? 1 : 0;
    my $public_key = get_section_value($peer, 'PublicKey') || '';
    my $endpoint = get_section_value($peer, 'Endpoint') || '-';
    my $allowed = join(', ', get_section_values($peer, 'AllowedIPs')) || '-';
    my $short_allowed = shorten_text($allowed, 55);
    my $id = substr(sha256_hex($public_key), 0, 16);
    my $peer_url='edit_peer.cgi?name='.urlize($name).'&peer='.$i;
    my $name_link='<a href="'.html_escape($peer_url).'"><b>'.
        html_escape(peer_display_name($peer, $i)).'</b></a>';
    # Persistent analytics identity is the fingerprint, never the display name.
    my $history_action=length($public_key)
        ? wg_ui_icon_action(icon=>'history',
            label=>$text{'analytics_peer_link'}||$text{'analytics_peer_short'}||'История',
            tone=>'info',
            href=>'analytics.cgi?peer_id='.urlize(sha256_hex($public_key)))
        : '—';
    my $handshake = $disabled ? $text{'peer_disabled'} : $text{'runtime_loading'};
    my $state_class = $disabled
        ? 'label-default wg-ui-status wg-ui-status--muted wg-peer-state-disabled'
        : 'label-success wg-ui-status wg-ui-status--success wg-peer-state-enabled';
    my $state_html = '<span class="label '.$state_class.'" data-wg-peer-state="'.$id.'" data-disabled="'.($disabled ? '1' : '0').'">'.
        html_escape($disabled ? $text{'peer_disabled'} : $text{'peer_enabled'}).'</span>';

    my $ip_action=wg_ui_icon_action(
        icon=>'globe',label=>$text{'peer_ip_lookup'}||'WHOIS / GeoIP',tone=>'info',
        attrs=>{'data-wg-ip-inspect'=>"$i"});
    my $edit_action=wg_ui_icon_action(
        icon=>'edit',label=>$text{'peer_edit_title'}||'Редактировать',tone=>'info',
        href=>$peer_url);
    my $actions='<span class="wg-ui-table-actions">'.$ip_action.$edit_action;
    if ($access{'manage'}) {
        my $button_class = $disabled ? 'wg-ui-tone-success' : 'wg-ui-tone-warning';
        my $button_text = $disabled ? $text{'peer_enable'} : $text{'peer_disable'};
        $actions .= '<div class="wg-peer-toggle"'.
            ' data-peer-id="'.$id.'"'.
            ' data-peer-index="'.$i.'"'.
            ' data-peer-disabled="'.($disabled ? '1' : '0').'"'.
            ' data-config-digest="'.html_escape($cfg->{'digest'}).'"'.
            ' data-public-key="'.html_escape($public_key).'"'.
            ' data-action-url="'.html_escape($toggle_peer_url).'">'.
            '<button type="button" class="btn btn-link wg-ui-icon-btn '.$button_class.'" data-peer-toggle-button'.
            ' title="'.html_escape($button_text).'" aria-label="'.html_escape($button_text).'">'.
            '<span data-wg-toggle-play'.($disabled?'':' hidden').'>'.wg_ui_icon('play').'</span>'.
            '<span data-wg-toggle-stop'.($disabled?' hidden':'').'>'.wg_ui_icon('stop').'</span>'.
            '</button></div>';
    }
    $actions.='</span>';

    push @rows, [
        $name_link,
        $state_html,
        wg_ui_ip_value($allowed,kind=>'cidr'),
        '<span class="wg-network-icon" data-wg-net-icon="'.$id.'"'.
         ($endpoint eq '-'?' hidden':'').' title="'.html_escape($text{'network_icons_unknown'}).'">?</span>',
        '<span class="wg-geoip-country" data-wg-geoip-country="'.$id.'" hidden></span>',
        '<span class="wg-ui-mono" data-wg-endpoint="'.$id.'">'.html_escape($endpoint).'</span>',
        '<span data-wg-handshake="'.$id.'">'.html_escape($handshake).'</span>',
        '<span data-wg-rx="'.$id.'">—</span>',
        '<span data-wg-tx="'.$id.'">—</span>',
        $history_action,
        $actions,
    ];
}

if (@rows) {
    print '<div class="wg-runtime-time">'.$text{'runtime_updated'}.': <span data-wg-runtime-time>'.$text{'runtime_loading'}.'</span></div>';
    print '<div class="wg-ui-compact-table" data-wg-peer-sort-table="1">';
    print ui_columns_start(
        [$text{'interface_peer_name'}, $text{'interface_peer_state'}, $text{'interface_peer_allowed'}, '', '', $text{'interface_peer_endpoint'}, $text{'interface_peer_handshake'}, $text{'interface_peer_rx'}, $text{'interface_peer_tx'}, $text{'analytics_peer_short'}, $text{'interface_peer_actions'}],
        100, 0, undef, $text{'interface_peers'}
    );
    print ui_columns_row($_) for @rows;
    print ui_columns_end();
    print '</div>';
}
else {
    print ui_alert_box($text{'interface_no_peers'}, 'info');
}

if ($access{'manage'}) {
    my $url='delete_interface.cgi?name='.urlize($name);
    print wg_ui_danger_zone(
        wg_ui_button(href=>$url,icon=>'trash',tone=>'danger',
            label=>$text{'interface_delete'},
            attrs=>{'data-wg-confirm'=>$text{'interface_delete'}.' '.$name}));
}

my $js_page_instance = json_encode_utf8($page_instance);
my $js_name = json_encode_utf8($name);
my $js_active = json_encode_utf8($text{'status_active'});
my $js_inactive = json_encode_utf8($text{'status_inactive'});
my $js_not_running = json_encode_utf8($text{'status_not_running'});
my $js_peer_enabled = json_encode_utf8($text{'peer_enabled'});
my $js_peer_disabled = json_encode_utf8($text{'peer_disabled'});
my $js_peer_enable = json_encode_utf8($text{'peer_enable'});
my $js_peer_disable = json_encode_utf8($text{'peer_disable'});
my $js_peer_busy = json_encode_utf8($text{'peer_toggle_busy'});
my $js_confirm_disable = json_encode_utf8($text{'confirm_peer_disable'});
my $js_runtime_loading = json_encode_utf8($text{'runtime_loading'});
my $js_runtime_updated = json_encode_utf8($text{'runtime_updated'});
my $js_refresh = json_encode_utf8($text{'journal_refresh'});
my $runtime_error_prefix = $text{'index_runtime_error'};
$runtime_error_prefix =~ s/\$1//g;
my $js_runtime_error_prefix = json_encode_utf8($runtime_error_prefix);
my $js_network_icons_url = json_encode_utf8(module_script_url('network_icon_data.cgi'));
print wg_table_sort_script();
print wg_ui_transport_script();
print wg_ui_peer_inspector($name,$csrf,$page_instance);
print wg_interface_page_script(
    $js_page_instance, $js_name, $js_network_icons_url, $js_active, $js_inactive, $js_not_running, $js_peer_enabled, $js_peer_disabled, $js_peer_enable, $js_peer_disable, $js_peer_busy, $js_confirm_disable, $js_runtime_loading, $js_runtime_updated, $js_refresh, $js_runtime_error_prefix, $csrf);

print runtime_poll_html($name);
print '</div>';
ui_print_footer('index.cgi', $text{'index_title'});
