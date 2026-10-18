#!/usr/local/bin/perl
require './wireguard-lib.pl';
require './lib/peer-activity-ui-lib.pl';
require './lib/peer-diagnostic-ui-lib.pl';
ReadParse();
assert_view_access();
my $csrf = csrf_token();

my $name = $in{'name'};
error($text{'error_invalid_name'}) if (!valid_interface_name($name));
my ($cfg, $read_error) = parse_wireguard_config(conf_path($name));
error(text('error_read', conf_path($name), $read_error)) if (!$cfg);

my $new = !defined($in{'peer'}) || $in{'peer'} eq '';
my $peer = $new ? undef : get_peer_by_index($cfg, $in{'peer'});
error($text{'error_peer'}) if (!$new && !$peer);

my $public_key = $peer ? (get_section_value($peer, 'PublicKey') || '') : '';
my $title = $new ? $text{'peer_add_title'} : text('peer_title', peer_display_name($peer, $in{'peer'}));

ui_print_header(undef, $title, '', undef, 1, 1);
print wg_build_banner();
print wg_ui_transport_script();
print wg_ui_foundation();
print '<div class="wg-ui">';
my $peer_tabs_id='wg-peer-tabs-'.substr(sha256_hex(join('|',time(),rand())),0,12);
if ($peer) {
    print '<div id="'.html_escape($peer_tabs_id).'" class="wg-peer-detail-tabs">';
    print '<ul class="nav nav-tabs" role="tablist">'.
        '<li class="active"><a href="#'.html_escape($peer_tabs_id).'-settings" data-wg-peer-tab="settings" role="tab" aria-selected="true" aria-controls="'.html_escape($peer_tabs_id).'-settings">'.
        html_escape($text{'peer_tab_settings'}).'</a></li>'.
        '<li><a href="#'.html_escape($peer_tabs_id).'-usage" data-wg-peer-tab="usage" role="tab" aria-selected="false" aria-controls="'.html_escape($peer_tabs_id).'-usage">'.
        html_escape($text{'peer_tab_usage'}).'</a></li>'.
        '<li><a href="#'.html_escape($peer_tabs_id).'-activity" data-wg-peer-tab="activity" role="tab" aria-selected="false" aria-controls="'.html_escape($peer_tabs_id).'-activity">'.
        html_escape($text{'peer_tab_activity'}).'</a></li></ul>';
    print '<div id="'.html_escape($peer_tabs_id).'-settings" data-wg-peer-pane="settings" role="tabpanel">';
}
print '<div id="wg-peer-runtime-error" class="alert alert-warning" style="display:none"></div>' if ($peer);

if ($peer) {
    my $handshake = $peer->{'disabled'} ? $text{'peer_disabled'} : $text{'runtime_loading'};
    print '<div class="wg-peer-live">'.
        '<b>'.$text{'peer_state'}.':</b> '.html_escape($peer->{'disabled'} ? $text{'peer_disabled'} : $text{'peer_enabled'}).
        ' &nbsp; <b>'.$text{'peer_handshake'}.':</b> <span data-peer-hs>'.html_escape($handshake).'</span>'.
        ' &nbsp; <b>'.$text{'peer_endpoint'}.':</b> <span data-peer-endpoint>'.
        html_escape(get_section_value($peer, 'Endpoint') || '-').'</span>'.
        ' &nbsp; <b>'.$text{'runtime_updated'}.':</b> <span data-wg-runtime-time>'.$text{'runtime_loading'}.'</span></div>';
    # Global network assignments are edited from the network directory,
    # while this peer retains its own on-demand WHOIS/GeoIP investigation.
    # On-demand IP investigation; no automatic WHOIS/network side effects.
    my $ip_dom_id='wg-peer-ip-'.time().'-'.int(rand(1000000000));
    my $ip_dom_json=json_encode_utf8($ip_dom_id);
    my $ip_name_json=json_encode_utf8($name);
    my $ip_index_json=json_encode_utf8("$in{'peer'}");
    my $ip_csrf_json=json_encode_utf8($csrf);
    my $ip_labels_json=json_encode_utf8({
        busy=>$text{'peer_ip_busy'}, whois=>$text{'peer_ip_whois'},
        cityNote=>$text{'ui_ip_city_note'},
        geoip=>$text{'peer_ip_geoip'}, raw=>$text{'peer_ip_raw'},
        handshake=>$text{'peer_ip_handshake_time'},
        unavailable=>$text{'peer_ip_unavailable'}
    });
    my $ip_url_json=json_encode_utf8(module_script_url('peer_ip_info.cgi'));
    # Local-only health check: no remote IP requests just to view the peer.
    my $geo_status=wg_geoip_update_status();
    my $geo_dependencies=optional_dependency_quick_status('geoip');
    my $geo_message=$text{'geoip_update_missing_db'};
    if ($geo_status->{'database_mtime'}) {
        my $date=strftime('%Y-%m-%d %H:%M',localtime($geo_status->{'database_mtime'}));
        $geo_message=text('geoip_update_age',
            $date,0+($geo_status->{'database_age_days'} || 0));
        $geo_message .= ' — '.$text{'geoip_update_stale'}
            if $geo_status->{'stale'};
    }
    if ($geo_status->{'legacy_database_available'} && !$geo_status->{'database_mtime'}) {
        $geo_message=$text{'geoip_legacy_ready'};
    }
    if (!$geo_dependencies->{'command_available'}) {
        $geo_message .= ' — '.$text{'geoip_dependency_missing'};
    }
    if (!$geo_status->{'command_available'}) {
        $geo_message .= ' — '.$text{'geoip_update_missing_tool'};
    }
    elsif (!$geo_status->{'configured'}) {
        $geo_message .= ' — '.$text{'geoip_update_missing_credentials'};
    }
    elsif (!$geo_status->{'timer_available'}) {
        $geo_message .= ' — '.$text{'geoip_update_missing_timer'};
    }
    elsif ($geo_status->{'timer_enabled'} && $geo_status->{'timer_active'}) {
        $geo_message .= ' — '.$text{'geoip_update_scheduled'};
    }
    else {
        $geo_message .= ' — '.$text{'geoip_update_disabled'};
    }
    print '<section id="'.html_escape($ip_dom_id).'" class="panel panel-default">'.
        '<div class="panel-heading"><strong>'.html_escape($text{'peer_ip_title'}).'</strong></div>'.
        '<div class="panel-body"><p class="help-block">'.html_escape($text{'peer_ip_help'}).'</p>'.
        '<p class="'.($geo_status->{'stale'} ? 'alert alert-warning':'help-block').'">'.
        '<strong>'.html_escape($text{'geoip_update_title'}).':</strong> '.
        html_escape($geo_message).'</p>'.
        wg_ui_button(type=>'button',icon=>'globe',tone=>'info',
            label=>$text{'peer_ip_lookup'},attrs=>{'data-role'=>'lookup'}).
        '<div data-role="output" aria-live="polite"></div>';
    if (!$geo_dependencies->{'command_available'} &&
        $access{'install_dependencies'} && $geo_dependencies->{'package_manager_available'}) {
        print '<p>'.direct_link_button(
            'install_dependency.cgi', $text{'geoip_install_button'},
            { dependency => 'geoip', name => $name, peer => $in{'peer'} }
        ).'</p>';
    }
    if (!$geo_dependencies->{'command_available'} &&
        !$geo_dependencies->{'package_manager_available'}) {
        print '<p class="help-block">'.html_escape($text{'dependency_package_manager_missing'}).'</p>';
    }
    if ($access{'manage'} && $geo_status->{'configured'} &&
        $geo_status->{'command_available'} && $geo_status->{'timer_available'} &&
        (!$geo_status->{'timer_enabled'} || !$geo_status->{'timer_active'})) {
        print ui_form_start('geoip_timer.cgi','post');
        print csrf_hidden();
        print ui_hidden('name',$name);
        print ui_hidden('peer',$in{'peer'});
        print '<button type="submit" class="btn btn-default">'.
            html_escape($text{'geoip_update_enable'}).'</button>';
        print ui_form_end();
    }
    print '</div></section>';
    print <<IP_LOOKUP_SCRIPT;
<script>
(function(){
  'use strict';
  const root=document.getElementById($ip_dom_json);
  if(!root)return;
  const button=root.querySelector('[data-role="lookup"]');
  const output=root.querySelector('[data-role="output"]');
  const detailsLabels=$ip_labels_json;
  const info={name:$ip_name_json,peer:$ip_index_json,csrf:$ip_csrf_json,url:$ip_url_json};
  function node(tag,text,parent,className){
    const el=document.createElement(tag);
    if(className)el.className=className;
    if(text!==undefined&&text!==null)el.textContent=String(text);
    (parent||output).append(el);
    return el;
  }
  function renderSection(label,result){
    const section=node('section',null,output,'wg-peer-ip-section');
    node('h4',label,section);
    if(!result||!result.ok){
      node('p',(result&&result.detail)||detailsLabels.unavailable,section,'help-block');
      return;
    }
    const table=node('table',null,section,'table table-striped');
    const body=node('tbody',null,table);
    for(const entry of result.fields||[]){
      const tr=node('tr',null,body);
      node('th',entry.label||'',tr);
      const value=String(entry.value||''),prefix=value.trim().slice(0,2).toUpperCase();
      const countryField=/country/i.test(String(entry.label||''));
      const code=countryField&&/^[A-Z]{2}\$/.test(prefix)&&
        (value.trim().length===2||value.trim().charAt(2)===',')?prefix:'';
      const flag=window.WireGuardUI.flag(code||(countryField?result.country_code:''));
      node('td',(flag?flag+' ':'')+value,tr);
    }
    if(label===detailsLabels.geoip && detailsLabels.cityNote &&
      !(result.fields||[]).some(field=>field.label==='City'))
      node('p',detailsLabels.cityNote,section,'help-block');
    if(result.source)node('small',result.source,section,'help-block');
    if(result.raw){
      const expandable=node('details',null,section);
      node('summary',detailsLabels.raw,expandable);
      node('pre',result.raw,expandable);
    }
  }
  button.addEventListener('click',async ()=>{
    button.disabled=true;
    output.replaceChildren();
    node('p',detailsLabels.busy,output,'help-block');
    try{
      const params=new URLSearchParams({
        name:info.name,peer:info.peer,_wg_csrf:info.csrf
      });
      const response=await fetch(info.url,{method:'POST',
        credentials:'same-origin',cache:'no-store',
        headers:{'Accept':'application/json',
                 'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},
        body:params.toString()});
      if(!(response.headers.get('content-type')||'').toLowerCase().includes('application/json'))
        throw new Error('HTTP '+response.status);
      const data=await response.json();
      if(!data.ok)throw new Error(data.error||'HTTP '+response.status);
      if(!root.isConnected)return;
      output.replaceChildren();
      if(!data.available){
        node('p',data.detail||detailsLabels.unavailable,output,'alert alert-info');
        return;
      }
      node('h4',data.ip,output);
      node('p',detailsLabels.handshake+': '+
        new Date(Number(data.handshake)*1000).toLocaleString(),output,'help-block');
      renderSection(detailsLabels.whois,data.whois);
      renderSection(detailsLabels.geoip,data.geoip);
    }catch(error){
      if(root.isConnected){
        output.replaceChildren();
        node('p',error.message||String(error),output,'alert alert-warning');
      }
    }finally{
      if(root.isConnected)button.disabled=false;
    }
  });
})();
</script>
IP_LOOKUP_SCRIPT
}

if ($access{'manage'}) {
    sub textarea_field {
        my ($field_name, $value, $rows) = @_;
        return '<textarea name="'.html_escape($field_name).'" rows="'.$rows.'"'.
            ($field_name eq 'allowed_ips' ? ' data-wg-validate="cidr-list"'.
                ' data-wg-invalid-message="'.html_escape($text{'ui_form_invalid'}).'"' : '').
            ' style="width:100%">'.html_escape($value || '').'</textarea>';
    }

    my ($client_address, $routes_ref, $auto_address_network);
    if ($peer) {
        ($client_address, $routes_ref) = peer_client_address_and_routes($peer);
    }
    else {
        ($client_address, $auto_address_network) = first_free_peer_address($cfg);
        $client_address ||= '';
        $routes_ref = [];
    }
    my $routes = join("\n", @$routes_ref);

    print ui_form_start('save_peer.cgi', 'post'); print csrf_hidden();
    print ui_hidden('name', $name);
    print ui_hidden('config_digest', $cfg->{'digest'});
    if (!$new) {
        print ui_hidden('peer', $in{'peer'});
        print ui_hidden('old_public_key', $public_key);
    }

    print ui_table_start($new ? $text{'peer_add_title'} : $text{'peer_edit_title'}, 'width=100%', 2);
    print ui_table_row($text{'peer_name'}, ui_textbox('peer_name', $peer ? ($peer->{'meta'}->{'name'} || '') : '', 40));
    my $client_address_help = $text{'peer_client_address_help'};
    if ($new) {
        if (length($client_address)) {
            $client_address_help .= '<br>'.html_escape(
                text('peer_client_address_auto', $client_address, $auto_address_network || '-')
            );
        }
        else {
            $client_address_help .= '<br><span class="text-warning">'.
                html_escape($text{'peer_client_address_no_free'}).'</span>';
        }
    }
    print ui_table_row(
        $text{'peer_client_address'},
        wg_ui_validated_input('clientaddress',$client_address,48,'cidr-list',
             $text{'ui_form_invalid'}).'<br><small>'.$client_address_help.'</small>'
    );
    print ui_table_row(
        $text{'peer_allowed_ips'},
        textarea_field('allowed_ips', $routes, 3).'<br><small>'.$text{'peer_allowed_ips_help'}.'</small>'
    );
    print ui_table_row($text{'peer_endpoint'}, wg_ui_validated_input('endpoint',$peer ?
             (get_section_value($peer,'Endpoint')||'') : '',52,'endpoint',
             $text{'ui_form_endpoint'}));
    print ui_table_row($text{'peer_keepalive'}, wg_ui_number_input('keepalive',$peer ?
             (get_section_value($peer,'PersistentKeepalive')||'') : '',0,65535));
    print ui_table_row($text{'peer_client_endpoint'}, wg_ui_validated_input('clientendpoint',$peer ?
             (get_meta_value($peer,'clientendpoint')||'') : '',52,'endpoint',
             $text{'ui_form_endpoint'}));
    print ui_table_row($text{'peer_client_dns'}, ui_textbox('clientdns', $peer ? (get_meta_value($peer, 'clientdns') || '') : '', 52));
    my $client_allowed_override = $peer ? (get_meta_value($peer, 'clientallowedips') || '') : '';
    my ($resolved_client_allowed, $client_allowed_source) = resolve_client_allowed_ips($cfg, $peer);
    my $client_allowed_help = $text{'peer_client_allowed_help'};
    if (!length($client_allowed_override)) {
        if ($client_allowed_source eq 'interface') {
            $client_allowed_help .= '<br>'.html_escape(text('peer_client_allowed_inherited', $resolved_client_allowed));
        }
        elsif ($client_allowed_source eq 'auto') {
            $client_allowed_help .= '<br>'.html_escape(text('peer_client_allowed_auto', $resolved_client_allowed));
        }
        else {
            $client_allowed_help .= '<br>'.html_escape($text{'peer_client_allowed_omitted'});
        }
    }
    print ui_table_row(
        $text{'peer_client_allowed'},
        wg_ui_validated_input('clientallowedips',$client_allowed_override,60,'cidr-list',
             $text{'ui_form_invalid'}).'<br><small>'.$client_allowed_help.'</small>'
    );
    print ui_table_row($text{'peer_client_mtu'}, wg_ui_number_input('clientmtu',$peer ?
             (get_meta_value($peer,'clientmtu')||'') : '',1,65535));
    print ui_table_row($text{'peer_disabled_field'}, ui_yesno_radio('disabled', $peer && $peer->{'disabled'} ? 1 : 0));
    print ui_table_end();

    print ui_table_start($text{'key_settings'}, 'width=100%', 2);
    print ui_table_row(
        $text{'peer_private_key'},
        html_escape($peer && length($peer->{'private_key'} || '') ? $text{'key_saved'} : $text{'key_missing'})
    );
    print ui_table_row(
        $text{'peer_private_key_new'},
        '<input type="password" name="private_key" id="wg-private-key" size="48" autocomplete="new-password">'.
        '<br><small>'.$text{'key_blank_keep'}.'</small>'
    );
    print ui_table_row($text{'peer_generate_key'}, ui_checkbox('generate_key', 1, $text{'peer_generate_key_help'}, 0));
    print ui_table_row(
        $text{'peer_public_key'},
        ui_textbox('public_key', $public_key, 52).'<br><small>'.$text{'key_public_ignored'}.'</small>'
    );
    # Render PSK controls explicitly; do not intercept ui_table_row by $0.
    print preshared_key_form_rows_for_state(
        $peer && length(get_section_value($peer, 'PresharedKey') || '') ? 1 : 0
    );

    if ($peer && $access{'export_clients'}) {
        my $issues = client_config_static_issues($cfg, $peer);
        my $export_html = '';
        if (!@$issues) {
            $export_html .= direct_link_button(
                'client_config.cgi', $text{'peer_show_config'},
                { name => $name, peer => $in{'peer'} }
            ).' ';
            $export_html .= direct_link_button(
                'download_client.cgi', $text{'peer_download'},
                { name => $name, peer => $in{'peer'} }, download => 1
            ).' ';
            my ($export_allowed, $export_allowed_source) = resolve_client_allowed_ips($cfg, $peer);
            if ($export_allowed_source eq 'auto') {
                $export_html .= '<br><small>'.html_escape(text('peer_client_allowed_auto', $export_allowed)).'</small>';
            }
            elsif ($export_allowed_source eq 'none') {
                $export_html .= '<br><div class="alert alert-warning">'.html_escape($text{'qr_warn_no_allowed'}).'</div>';
            }
            my $qr_status = optional_dependency_quick_status('qrencode');
            if ($qr_status->{'command_available'}) {
                $export_html .= direct_link_button(
                    'peer_qr.cgi', $text{'peer_qr'},
                    { name => $name, peer => $in{'peer'} }
                );
                if ($qr_status->{'package_version'}) {
                    $export_html .= '<br><small>'.html_escape(
                        text('qr_package_ready', $qr_status->{'package_version'})
                    ).'</small>';
                }
            }
            elsif ($qr_status->{'package_installed'}) {
                $export_html .= '<br><div class="alert alert-warning">'.html_escape(
                    text('qr_package_path_missing', $qr_status->{'package_version'}, $qr_status->{'command'})
                ).' '.ui_link_button('config.cgi', $text{'dependency_open_settings'}).'</div>';
            }
            else {
                $export_html .= '<br><div class="alert alert-info">'.html_escape(
                    text('qr_command_missing', $qr_status->{'command'})
                );
                if ($access{'install_dependencies'} && $qr_status->{'package_manager_available'}) {
                    $export_html .= '<br>'.direct_link_button(
                        'install_dependency.cgi', $text{'qr_install_button'},
                        { dependency => 'qrencode', name => $name, peer => $in{'peer'} }
                    );
                }
                elsif (!$qr_status->{'package_manager_available'}) {
                    $export_html .= '<br><small>'.html_escape($text{'dependency_package_manager_missing'}).'</small>';
                }
                $export_html .= '</div>';
            }
        }
        else {
            $export_html .= '<div class="alert alert-info"><b>'.$text{'peer_export_unavailable'}.'</b><ul>';
            $export_html .= '<li>'.html_escape($_).'</li>' for @$issues;
            $export_html .= '</ul>';
            if (!length($peer->{'private_key'} || '')) {
                $export_html .= '<button type="button" class="btn" id="wg-focus-private">'.
                    html_escape($text{'peer_set_private'}).'</button>';
            }
            $export_html .= '</div>';
        }
        print ui_table_row($text{'peer_client_export'}, $export_html);
    }
    elsif ($new) {
        print ui_table_row($text{'peer_client_export'}, '<small>'.$text{'peer_export_after_save'}.'</small>');
    }
    print ui_table_end();

    print '<div class="wg-ui-button-row"><div class="wg-ui-action-group">'.
        wg_ui_button(type=>'submit',icon=>'save',tone=>'success',
            label=>$text{'save_only'},attrs=>{name=>'save',value=>1});
    if ($peer) {
        my $toggle_label=$peer->{'disabled'} ? $text{'peer_enable'} : $text{'peer_disable'};
        my $toggle_icon=$peer->{'disabled'} ? 'play' : 'stop';
        my $toggle_tone=$peer->{'disabled'} ? 'success' : 'warning';
        print wg_ui_button(type=>'button',icon=>$toggle_icon,
            label=>$toggle_label,tone=>$toggle_tone,
            attrs=>{
                id=>'wg-peer-toggle-detail',
                'data-action-url'=>module_script_url('toggle_peer.cgi'),
                'data-peer-index'=>"$in{'peer'}",
                'data-peer-disabled'=>$peer->{'disabled'} ? 1 : 0,
                'data-config-digest'=>$cfg->{'digest'},
                'data-public-key'=>$public_key,
            });
    }
    print '</div></div></form>';
    if ($peer) {
        print '<div id="wg-peer-toggle-result" class="alert" style="display:none"></div>';
        my $delete_url='delete_peer.cgi?name='.urlize($name).'&peer='.
            urlize($in{'peer'}).'&public_key='.urlize($public_key);
        print wg_ui_danger_zone(
            '<a href="'.html_escape($delete_url).'" class="btn btn-danger"'.
            ' data-wg-confirm="'.html_escape($text{'peer_delete'}.' — '.peer_display_name($peer,$in{'peer'})).'">'.
            html_escape($text{'peer_delete'}).'</a>');

        my $toggle_name_js = json_encode_utf8($name);
        my $toggle_busy_js = json_encode_utf8($text{'peer_toggle_busy'});
        my $toggle_confirm_js = json_encode_utf8($text{'confirm_peer_disable'});
        print <<TOGGLE_SCRIPT;
<script>
(function() {
    const button = document.getElementById('wg-peer-toggle-detail');
    const result = document.getElementById('wg-peer-toggle-result');
    if (!button) return;
    const interfaceName = $toggle_name_js;
    const busyText = $toggle_busy_js;
    const confirmDisable = $toggle_confirm_js;

    async function decodeJsonResponse(response) {
        const body = await response.text();
        const contentType = (response.headers.get('content-type') || '').toLowerCase();
        if (!contentType.includes('application/json')) {
            const sample = body.replace(/\\s+/g, ' ').trim().slice(0, 240);
            throw new Error('HTTP ' + response.status + ': сервер вернул не JSON' + (sample ? ': ' + sample : ''));
        }
        try { return JSON.parse(body); }
        catch (error) {
            const sample = body.replace(/\\s+/g, ' ').trim().slice(0, 240);
            throw new Error('Некорректный JSON-ответ' + (sample ? ': ' + sample : ''));
        }
    }

    button.addEventListener('click', async function(event) {
        event.preventDefault();
        const currentlyDisabled = button.dataset.peerDisabled === '1';
        if (!currentlyDisabled && !window.confirm(confirmDisable)) return;
        const originalHtml = button.innerHTML;
        button.disabled = true;
        button.textContent = busyText;
        if (result) result.style.display = 'none';
        const payload = new URLSearchParams({ _wg_csrf: '$csrf',
            name: interfaceName,
            peer: button.dataset.peerIndex || '',
            config_digest: button.dataset.configDigest || '',
            old_public_key: button.dataset.publicKey || '',
            ajax: '1'
        });
        try {
            const response = await fetch(button.dataset.actionUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
                    'Accept': 'application/json'
                },
                body: payload.toString(),
                credentials: 'same-origin',
                cache: 'no-store'
            });
            const data = await decodeJsonResponse(response);
            if (!response.ok || !data.ok) throw new Error(data.error || ('HTTP ' + response.status));
            if (result) {
                result.className = 'alert alert-success';
                result.textContent = data.message || '';
                result.style.display = 'block';
            }
            window.location.reload();
        }
        catch (error) {
            if (result) {
                result.className = 'alert alert-danger';
                result.textContent = error.message || String(error);
                result.style.display = 'block';
            }
            button.innerHTML = originalHtml;
            button.disabled = false;
        }
    });
})();
</script>
TOGGLE_SCRIPT
    }
}

if ($peer && $access{'logs'}) {
    print wg_ui_button(icon=>'log',
        label=>$text{'interface_logs'},
        href=>'journal.cgi?name='.urlize($name));
}

if ($peer && $access{'diagnostics'}) {
    my $target = first_client_address($peer) || '';
    $target = (_split_list($target))[0] || '';
    $target =~ s{/\d+$}{};

    # Authentic Theme can keep old module DOM fragments in the document.
    # A request-specific root prevents duplicate IDs from binding the new page
    # controls to an older, hidden peer page.
    my $diag_dom_id = 'wg-diag-'.time().'-'.$$.'-'.int(rand(1000000));
    my $js_diag_dom_id = json_encode_utf8($diag_dom_id);
    my $js_name = json_encode_utf8($name);
    my $js_peer = json_encode_utf8("$in{'peer'}");
    my $js_starting = json_encode_utf8($text{'diagnostics_starting'});
    my $js_stopping = json_encode_utf8($text{'diagnostics_stopping'} || 'Stopping command...');
    my $js_diagnostic_url = json_encode_utf8(module_script_url('diagnostic.cgi'));
    my $js_status_url = json_encode_utf8(module_script_url('diagnostic_status.cgi'));
    my $js_stop_url = json_encode_utf8(module_script_url('diagnostic_stop.cgi'));

    print '<details class="wg-ui-tools" data-wg-tool-panel>'.
        '<summary>'.wg_ui_icon('chevron').' '.html_escape($text{'diagnostics_title'}).'</summary>'.
        '<div id="'.html_escape($diag_dom_id).'" class="wg-diagnostic-root wg-ui-tools-body">'.

        '<div class="wg-diag-grid">'.
        '<label>'.$text{'diagnostics_target'}.'<input data-role="target" value="'.html_escape($target).'" class="form-control"></label>'.
        '<label>'.$text{'diagnostics_ping_count'}.'<input data-role="count" type="number" min="1" max="1000" value="3" class="form-control"></label>'.
        '<label>'.$text{'diagnostics_port'}.'<input data-role="port" type="number" min="1" max="65535" class="form-control"></label>'.
        '<label><input data-role="infinite" type="checkbox"> '.$text{'diagnostics_infinite'}.'</label>'.
        '</div><p>'.
        wg_ui_button(type=>'button',icon=>'network',label=>$text{'diagnostics_ping'},
            attrs=>{'data-diag'=>'ping'}).
        wg_ui_button(type=>'button',icon=>'chart',label=>$text{'diagnostics_trace'},
            attrs=>{'data-diag'=>'trace'}).
        wg_ui_button(type=>'button',icon=>'shield',label=>$text{'diagnostics_port_test'},
            attrs=>{'data-diag'=>'port_test'}).
        '<span data-wg-diag-stop style="display:none">'.
        wg_ui_button(type=>'button',icon=>'stop',tone=>'warning',
            label=>$text{'diagnostics_stop'},attrs=>{'data-role'=>'stop'}).
        '</span>'.
        '</p><pre data-role="output" style="display:none;min-height:130px;max-height:420px;overflow:auto;white-space:pre-wrap"></pre>'.
        '</div></details>';

    print wg_peer_diagnostic_script(
        $js_diag_dom_id, $js_name, $js_peer, $js_starting,
        $js_stopping, $js_diagnostic_url, $js_status_url, $js_stop_url,
        $csrf);
}


if ($peer) {
    print '</div>'; # End settings
    print '<div id="'.html_escape($peer_tabs_id).'-usage" data-wg-peer-pane="usage" role="tabpanel" hidden>';
    print graph_html($name, $public_key,
        text('graph_peer_title',peer_display_name($peer,$in{'peer'})));
    print '<p>'.direct_link_button('analytics.cgi',$text{'analytics_peer_link'},
        {peer_id=>sha256_hex($public_key)}).'</p>';
    print '</div>';
    print '<div id="'.html_escape($peer_tabs_id).'-activity" data-wg-peer-pane="activity" role="tabpanel" hidden>';
    print '<div class="wg-peer-activity-toolbar"><label>'.
        html_escape($text{'analytics_period'}).' <select data-wg-peer-activity-period class="form-control">'.
        '<option value="21600">'.html_escape($text{'analytics_6h'}).'</option>'.
        '<option value="86400" selected>'.html_escape($text{'analytics_24h'}).'</option>'.
        '<option value="604800">'.html_escape($text{'analytics_7d'}).'</option>'.
        '<option value="2592000">'.html_escape($text{'analytics_month'}).'</option>'.
        '<option value="31536000">'.html_escape($text{'analytics_year'}).'</option>'.
        '</select></label> '.
        wg_ui_icon_action(icon=>'refresh',tone=>'info',
        label=>$text{'journal_refresh'},attrs=>{'data-wg-peer-activity-refresh'=>'1'}).
        '</div>';
    print '<p class="help-block">'.html_escape($text{'analytics_warning'}).'</p>';
    print '<div data-wg-peer-activity-status class="help-block" role="status"></div>';
    print '<div class="table-responsive" data-wg-peer-activity-sort>'.
        '<table class="table table-striped table-hover"><thead><tr>'.
        '<th>'.html_escape($text{'analytics_event_time'}).'</th>'.
        '<th>'.html_escape($text{'analytics_event_type'}).'</th>'.
        '<th>'.html_escape($text{'analytics_event_endpoint'}).'</th>'.
        '<th>'.html_escape($text{'analytics_event_previous'}).'</th>'.
        '</tr></thead><tbody data-wg-peer-activity-rows></tbody></table></div>';
    print '</div></div>'; # end activity and three-tab root
    my $js_tabs_id=json_encode_utf8($peer_tabs_id);
    my $js_analytics_url=json_encode_utf8(module_script_url('analytics_data.cgi'));
    my $js_peer_id=json_encode_utf8(sha256_hex($public_key));
    my $js_activity_labels=json_encode_utf8({
        loading=>$text{'analytics_loading'},
        empty=>$text{'analytics_empty'},
        limited=>$text{'analytics_events_limited'},
        events=>{ map { $_ => $text{'analytics_event_'.$_} }
          qw(endpoint_ip_observed endpoint_ip_changed) },
    });
    print wg_table_sort_script();
    print wg_peer_activity_tabs_script(
        $js_tabs_id, $js_analytics_url, $js_peer_id, $js_activity_labels);
}

if ($peer) {
    my $runtime_name = json_encode_utf8($name);
    my $runtime_key = json_encode_utf8($public_key);
    my $runtime_not_running = json_encode_utf8($text{'status_not_running'});
    my $runtime_unknown = json_encode_utf8($text{'status_unknown'});
    my $runtime_error_prefix = $text{'index_runtime_error'};
    $runtime_error_prefix =~ s/\$1//g;
    my $runtime_error_js = json_encode_utf8($runtime_error_prefix);
    print <<RUNTIME_SCRIPT;
<script>
(function() {
    const interfaceName = $runtime_name;
    const publicKey = $runtime_key;
    const notRunningText = $runtime_not_running;
    const unknownText = $runtime_unknown;
    const runtimeErrorPrefix = $runtime_error_js;
    document.addEventListener('wg-runtime', function(event) {
        const data = event.detail || {};
        const iface = data.interfaces && data.interfaces[interfaceName];
        const peer = iface && iface.active ? (iface.peers || []).find(function(item) { return item.public_key === publicKey; }) : null;
        const handshake = document.querySelector('[data-peer-hs]');
        const endpoint = document.querySelector('[data-peer-endpoint]');
        if (handshake) handshake.textContent = !iface || !iface.active ? notRunningText : peer ? (peer.handshake_text || unknownText) : unknownText;
        if (endpoint && peer && peer.endpoint) endpoint.textContent = peer.endpoint;
        document.querySelectorAll('[data-wg-runtime-time]').forEach(function(element) {
            element.textContent = new Date((data.timestamp || Date.now() / 1000) * 1000).toLocaleString();
        });
        const error = document.getElementById('wg-peer-runtime-error');
        if (error) error.style.display = 'none';
    });
    document.addEventListener('wg-runtime-error', function(event) {
        const error = document.getElementById('wg-peer-runtime-error');
        if (!error) return;
        error.textContent = runtimeErrorPrefix + (event.detail && event.detail.error ? event.detail.error : '');
        error.style.display = 'block';
    });
    document.addEventListener('wg-runtime-warning', function(event) {
        const error = document.getElementById('wg-peer-runtime-error');
        if (!error) return;
        error.textContent = event.detail && event.detail.warning ? event.detail.warning : '';
        error.style.display = error.textContent ? 'block' : 'none';
    });
})();
</script>
RUNTIME_SCRIPT
    print runtime_poll_html($name);
}

print '<style>'.
    '.wg-diag-grid{display:grid;grid-template-columns:2fr 1fr 1fr;gap:12px;align-items:end}'.
    '.wg-peer-live{margin:8px 0 14px}'.
    '.wg-danger-zone{margin:12px 0}'.
    '@media(max-width:700px){.wg-diag-grid{grid-template-columns:1fr}}'.
    '</style>';

print '</div>'; # Shared UI root
ui_print_footer(
    'edit_interface.cgi?name='.urlize($name),
    text('interface_title', $name)
);
