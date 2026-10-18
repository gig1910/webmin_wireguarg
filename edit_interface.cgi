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
print ui_table_row($text{'interface_state'}, '<span id="wg-interface-state">'.html_escape($text{'runtime_loading'}).'</span>');
print ui_table_row($text{'interface_addresses'}, html_escape(join(', ', get_section_values($ifc, 'Address')) || '-'));
print ui_table_row($text{'interface_listen_port'}, '<span id="wg-interface-port">'.html_escape(get_section_value($ifc, 'ListenPort') || '-').'</span>');
print ui_table_row($text{'interface_public_key'}, '<tt id="wg-interface-public-key">'.$public_display.'</tt>');
print ui_table_row($text{'interface_private_key'}, html_escape($private_state));
print ui_table_row($text{'interface_client_endpoint'}, html_escape(get_meta_value($ifc, 'clientendpoint') || '-'));
print ui_table_row($text{'interface_client_allowed'}, html_escape($client_allowed_display));
print ui_table_end();

print '<p>'.direct_link_button('analytics.cgi', $text{'analytics_interface_link'}, { interface => $name }).'</p>';
print '<p>'.direct_link_button('network_icons.cgi',$text{'network_icons_title'},{}).'</p>' if $access{'manage'};
print graph_html($name, '', text('graph_interface_title', $name));
print '<div class="wg-runtime-toolbar">'.
    '<button type="button" class="btn btn-default" data-wg-runtime-refresh>'.html_escape($text{'journal_refresh'}).'</button> '.
    '<span data-wg-runtime-refresh-status></span>'.
    '</div>';

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
    my $name_link = '<a href="edit_peer.cgi?name='.urlize($name).'&peer='.$i.'"><b>'.html_escape(peer_display_name($peer, $i)).'</b></a>';
    # Analytics is addressed solely by public-key fingerprint. Neither a
    # peer's name nor its AllowedIPs participates in historical identity.
    if (length($public_key)) {
        $name_link .= ' <small>&middot; <a href="analytics.cgi?peer_id='.
            urlize(sha256_hex($public_key)).'" data-wg-module-navigation="1">'.
            html_escape($text{'analytics_peer_short'}).'</a></small>';
    }
    my $handshake = $disabled ? $text{'peer_disabled'} : $text{'runtime_loading'};
    my $state_class = $disabled ? 'label-default wg-peer-state-disabled' : 'label-success wg-peer-state-enabled';
    my $state_html = '<span class="label '.$state_class.'" data-wg-peer-state="'.$id.'" data-disabled="'.($disabled ? '1' : '0').'">'.
        html_escape($disabled ? $text{'peer_disabled'} : $text{'peer_enabled'}).'</span>';

    my $actions = '—';
    if ($access{'manage'}) {
        my $button_class = $disabled ? 'btn-success' : 'btn-warning';
        my $button_text = $disabled ? $text{'peer_enable'} : $text{'peer_disable'};
        $actions = '<div class="wg-peer-toggle"'.
            ' data-peer-id="'.$id.'"'.
            ' data-peer-index="'.$i.'"'.
            ' data-peer-disabled="'.($disabled ? '1' : '0').'"'.
            ' data-config-digest="'.html_escape($cfg->{'digest'}).'"'.
            ' data-public-key="'.html_escape($public_key).'"'.
            ' data-action-url="'.html_escape($toggle_peer_url).'">'.
            '<button type="button" class="btn btn-xs '.$button_class.'" data-peer-toggle-button>'.html_escape($button_text).'</button>'.
            '</div>';
    }

    push @rows, [
        $name_link,
        $state_html,
        '<span title="'.html_escape($allowed).'">'.html_escape($short_allowed).'</span>',
        '<span class="wg-endpoint-with-icon"><span class="wg-network-icon" data-wg-net-icon="'.$id.'" title="'.html_escape($text{'network_icons_unknown'}).'">?</span> <span class="wg-geoip-country" data-wg-geoip-country="'.$id.'" hidden></span> '.
        '<span data-wg-endpoint="'.$id.'">'.html_escape($endpoint).'</span></span>',
        '<span data-wg-handshake="'.$id.'">'.html_escape($handshake).'</span>',
        '<span data-wg-rx="'.$id.'">—</span>',
        '<span data-wg-tx="'.$id.'">—</span>',
        $actions,
    ];
}

if (@rows) {
    print '<div class="wg-runtime-time">'.$text{'runtime_updated'}.': <span data-wg-runtime-time>'.$text{'runtime_loading'}.'</span></div>';
    print '<div data-wg-peer-sort-table="1">';
    print ui_columns_start(
        [$text{'interface_peer_name'}, $text{'interface_peer_state'}, $text{'interface_peer_allowed'}, $text{'interface_peer_endpoint'}, $text{'interface_peer_handshake'}, $text{'interface_peer_rx'}, $text{'interface_peer_tx'}, $text{'interface_peer_actions'}],
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

    print '<p>'.ui_link_button('interface_form.cgi?name='.urlize($name), $text{'interface_edit'}).' '.
        ui_link_button('edit_peer.cgi?name='.urlize($name), $text{'interface_add_peer'}).'</p>';
    print '<div class="wg-actions">'.
        '<span id="wg-actions-loading">'.html_escape($text{'runtime_loading'}).'</span>'.
        '<span id="wg-actions-active" style="display:none">'.
            mini_action_form($name, 'restart', $text{'interface_restart'}, 'warning', $text{'confirm_restart'}).
            mini_action_form($name, 'stop', $text{'interface_stop'}, 'danger', $text{'confirm_stop'}).
        '</span>'.
        '<span id="wg-actions-inactive" style="display:none">'.
            mini_action_form($name, 'start', $text{'interface_start'}, 'success', '').
        '</span>'.
        '</div><hr><div class="wg-danger-zone"><b>'.$text{'danger_zone'}.'</b><br>'.
        ui_link_button('delete_interface.cgi?name='.urlize($name), $text{'interface_delete'}).'</div>';
}
print '<p>'.ui_link_button('journal.cgi?name='.urlize($name), $text{'interface_logs'}).'</p>' if ($access{'logs'});

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
print wg_interface_page_script(
    $js_page_instance, $js_name, $js_network_icons_url, $js_active, $js_inactive, $js_not_running, $js_peer_enabled, $js_peer_disabled, $js_peer_enable, $js_peer_disable, $js_peer_busy, $js_confirm_disable, $js_runtime_loading, $js_runtime_updated, $js_refresh, $js_runtime_error_prefix, $csrf);

print runtime_poll_html($name);
print '</div>';
ui_print_footer('index.cgi', $text{'index_title'});
