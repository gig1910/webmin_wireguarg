#!/usr/local/bin/perl
require './wireguard-lib.pl';
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
print '<div id="wg-peer-runtime-error" class="alert alert-warning" style="display:none"></div>' if ($peer);

if ($peer) {
    my $handshake = $peer->{'disabled'} ? $text{'peer_disabled'} : $text{'runtime_loading'};
    print '<div class="wg-peer-live">'.
        '<b>'.$text{'peer_state'}.':</b> '.html_escape($peer->{'disabled'} ? $text{'peer_disabled'} : $text{'peer_enabled'}).
        ' &nbsp; <b>'.$text{'peer_handshake'}.':</b> <span data-peer-hs>'.html_escape($handshake).'</span>'.
        ' &nbsp; <b>'.$text{'peer_endpoint'}.':</b> <span data-peer-endpoint>'.
        html_escape(get_section_value($peer, 'Endpoint') || '-').'</span>'.
        ' &nbsp; <b>'.$text{'runtime_updated'}.':</b> <span data-wg-runtime-time>'.$text{'runtime_loading'}.'</span></div>';
    print graph_html($name, $public_key, text('graph_peer_title', peer_display_name($peer, $in{'peer'})));
}

if ($access{'manage'}) {
    sub textarea_field {
        my ($field_name, $value, $rows) = @_;
        return '<textarea name="'.html_escape($field_name).'" rows="'.$rows.'" style="width:100%">'.
            html_escape($value || '').'</textarea>';
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
        ui_textbox('clientaddress', $client_address, 48).'<br><small>'.$client_address_help.'</small>'
    );
    print ui_table_row(
        $text{'peer_allowed_ips'},
        textarea_field('allowed_ips', $routes, 3).'<br><small>'.$text{'peer_allowed_ips_help'}.'</small>'
    );
    print ui_table_row($text{'peer_endpoint'}, ui_textbox('endpoint', $peer ? (get_section_value($peer, 'Endpoint') || '') : '', 52));
    print ui_table_row($text{'peer_keepalive'}, ui_textbox('keepalive', $peer ? (get_section_value($peer, 'PersistentKeepalive') || '') : '', 10));
    print ui_table_row($text{'peer_client_endpoint'}, ui_textbox('clientendpoint', $peer ? (get_meta_value($peer, 'clientendpoint') || '') : '', 52));
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
        ui_textbox('clientallowedips', $client_allowed_override, 60).'<br><small>'.$client_allowed_help.'</small>'
    );
    print ui_table_row($text{'peer_client_mtu'}, ui_textbox('clientmtu', $peer ? (get_meta_value($peer, 'clientmtu') || '') : '', 10));
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
                    $export_html .= '<br>'.ui_link_button(
                        'install_dependency.cgi?dependency=qrencode&name='.urlize($name).'&peer='.urlize($in{'peer'}),
                        $text{'qr_install_button'}
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

    print '<button class="btn btn-success" name="save" value="1">'.$text{'save_only'}.'</button></form>';

    if ($peer) {
        my $toggle_url = module_script_url('toggle_peer.cgi');
        my $toggle_label = $peer->{'disabled'} ? $text{'peer_enable'} : $text{'peer_disable'};
        my $toggle_class = $peer->{'disabled'} ? 'btn-success' : 'btn-warning';
        print '<div class="wg-peer-actions">'.
            '<div id="wg-peer-toggle-result" class="alert" style="display:none"></div>'.
            '<button type="button" id="wg-peer-toggle-detail" class="btn '.$toggle_class.'"'.
            ' data-action-url="'.html_escape($toggle_url).'"'.
            ' data-peer-index="'.html_escape($in{'peer'}).'"'.
            ' data-peer-disabled="'.($peer->{'disabled'} ? '1' : '0').'"'.
            ' data-config-digest="'.html_escape($cfg->{'digest'}).'"'.
            ' data-public-key="'.html_escape($public_key).'">'.html_escape($toggle_label).'</button>'.
            '</div><hr><div class="wg-danger-zone"><b>'.$text{'danger_zone'}.'</b><br>'.
            ui_link_button(
                'delete_peer.cgi?name='.urlize($name).'&peer='.urlize($in{'peer'}).'&public_key='.urlize($public_key),
                $text{'peer_delete'}
            ).'</div>';

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
        const originalText = button.textContent;
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
            button.textContent = originalText;
            button.disabled = false;
        }
    });
})();
</script>
TOGGLE_SCRIPT
    }
}

if ($peer && $access{'logs'}) {
    print '<p>'.ui_link_button('journal.cgi?name='.urlize($name), $text{'interface_logs'}).'</p>';
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

    print '<div id="'.html_escape($diag_dom_id).'" class="panel panel-default wg-diagnostic-root">'.
        '<div class="panel-heading"><b>'.$text{'diagnostics_title'}.'</b></div>'.
        '<div class="panel-body"><div class="wg-diag-grid">'.
        '<label>'.$text{'diagnostics_target'}.'<input data-role="target" value="'.html_escape($target).'" class="form-control"></label>'.
        '<label>'.$text{'diagnostics_ping_count'}.'<input data-role="count" type="number" min="1" max="1000" value="3" class="form-control"></label>'.
        '<label>'.$text{'diagnostics_port'}.'<input data-role="port" type="number" min="1" max="65535" class="form-control"></label>'.
        '<label><input data-role="infinite" type="checkbox"> '.$text{'diagnostics_infinite'}.'</label>'.
        '</div><p>'.
        '<button type="button" class="btn" data-diag="ping">'.$text{'diagnostics_ping'}.'</button> '.
        '<button type="button" class="btn" data-diag="trace">'.$text{'diagnostics_trace'}.'</button> '.
        '<button type="button" class="btn" data-diag="port_test">'.$text{'diagnostics_port_test'}.'</button> '.
        '<button type="button" class="btn btn-danger" data-role="stop" style="display:none">'.$text{'diagnostics_stop'}.'</button>'.
        '</p><pre data-role="output" style="display:none;min-height:130px;max-height:420px;overflow:auto;white-space:pre-wrap"></pre>'.
        '</div></div>';

    print <<SCRIPT;
<script>
(function() {
    const root = document.getElementById($js_diag_dom_id);
    if (!root || root.dataset.wgDiagnosticInitialized === '1') return;
    root.dataset.wgDiagnosticInitialized = '1';

    const output = root.querySelector('[data-role="output"]');
    const stopButton = root.querySelector('[data-role="stop"]');
    const infiniteCheckbox = root.querySelector('[data-role="infinite"]');
    const targetInput = root.querySelector('[data-role="target"]');
    const countInput = root.querySelector('[data-role="count"]');
    const portInput = root.querySelector('[data-role="port"]');
    const actionButtons = Array.from(root.querySelectorAll('button[data-diag]'));
    const startUrl = $js_diagnostic_url;
    let statusUrl = $js_status_url;
    let stopUrl = $js_stop_url;
    let activeJob = null;
    let activeIsInfinite = false;
    let activeOffset = 0;
    let activeDecoder = null;
    let pollTimer = null;
    let stopping = false;
    const stopLabel = stopButton ? stopButton.textContent : '';

    if (!output || !stopButton || !infiniteCheckbox || !targetInput || !countInput || !portInput) {
        return;
    }

    function showStop(show) {
        stopButton.style.display = show ? 'inline-block' : 'none';
        stopButton.disabled = !show || stopping;
    }

    function setBusy(busy) {
        actionButtons.forEach(function(button) { button.disabled = busy; });
        infiniteCheckbox.disabled = busy;
        if (!busy) showStop(false);
    }

    function append(text) {
        if (!text) return;
        output.textContent += text;
        output.scrollTop = output.scrollHeight;
    }

    async function jsonResponse(response) {
        const body = await response.text();
        const contentType = (response.headers.get('content-type') || '').toLowerCase();
        if (!contentType.includes('application/json')) {
            throw new Error('HTTP ' + response.status + ': ' + body.replace(/\\s+/g, ' ').trim().slice(0, 240));
        }
        let data;
        try { data = JSON.parse(body); }
        catch (error) { throw new Error('Некорректный JSON: ' + body.replace(/\\s+/g, ' ').trim().slice(0, 240)); }
        if (!data.ok) throw new Error(data.error || ('HTTP ' + response.status));
        return data;
    }

    function endpoint(base, values) {
        const url = new URL(base, window.location.href);
        Object.keys(values).forEach(function(key) { url.searchParams.set(key, values[key]); });
        return url.toString();
    }

    function decodeChunk(encoded, finalChunk) {
        if (!encoded) return '';
        const binary = atob(encoded);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        if (activeDecoder) return activeDecoder.decode(bytes, { stream: !finalChunk });

        // Fallback for a browser without TextDecoder. Diagnostic output is
        // primarily ASCII; non-ASCII text is decoded best-effort.
        let escaped = '';
        for (let i = 0; i < bytes.length; i++) {
            escaped += '%' + bytes[i].toString(16).padStart(2, '0');
        }
        try { return decodeURIComponent(escaped); }
        catch (error) { return binary; }
    }

    function finish() {
        if (pollTimer) clearTimeout(pollTimer);
        pollTimer = null;
        activeJob = null;
        activeIsInfinite = false;
        activeOffset = 0;
        activeDecoder = null;
        stopping = false;
        if (stopButton) stopButton.textContent = stopLabel;
        setBusy(false);
    }

    async function poll() {
        if (!activeJob) return;
        if (!root.isConnected) {
            stopSilently();
            finish();
            return;
        }
        try {
            const response = await fetch(endpoint(statusUrl, { job: activeJob, offset: String(activeOffset) }), {
                cache: 'no-store',
                credentials: 'same-origin',
                headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
            });
            const data = await jsonResponse(response);
            const finalChunk = !!data.done && !data.more;
            append(decodeChunk(data.chunk_b64 || '', finalChunk));
            activeOffset = Number(data.offset) || activeOffset;
            if (finalChunk) {
                if (activeDecoder) append(activeDecoder.decode());
                finish();
                return;
            }
            pollTimer = setTimeout(poll, data.more ? 0 : 500);
        }
        catch (error) {
            append('\\n' + (error.message || String(error)) + '\\n');
            finish();
        }
    }

    async function run(operation) {
        if (activeJob) return;

        // Change the UI before any API or optional browser operation. This also
        // makes client-side failures visible instead of looking like a dead button.
        output.style.display = 'block';
        output.textContent = $js_starting + '\\n';
        activeIsInfinite = operation === 'ping' && infiniteCheckbox.checked;
        activeOffset = 0;
        activeDecoder = typeof TextDecoder === 'function' ? new TextDecoder('utf-8') : null;
        stopping = false;
        setBusy(true);
        showStop(false);

        const data = new URLSearchParams({ _wg_csrf: '$csrf',
            name: $js_name,
            peer: $js_peer,
            target: targetInput.value,
            port: portInput.value,
            ping_count: countInput.value,
            infinite: activeIsInfinite ? '1' : '0',
            operation: operation
        });

        try {
            const response = await fetch(startUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'Accept': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest'
                },
                body: data.toString(),
                credentials: 'same-origin',
                cache: 'no-store'
            });
            const result = await jsonResponse(response);
            activeJob = result.job_id;
            statusUrl = result.status_url || statusUrl;
            stopUrl = result.stop_url || stopUrl;
            showStop(activeIsInfinite);
            poll();
        }
        catch (error) {
            append('\\n' + (error.message || String(error)) + '\\n');
            finish();
        }
    }

    async function stop() {
        if (!activeJob || !activeIsInfinite || stopping) return;
        stopping = true;
        stopButton.textContent = $js_stopping;
        showStop(true);
        append('\\n' + $js_stopping + '\\n');
        try {
            const response = await fetch(stopUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'Accept': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest'
                },
                body: new URLSearchParams({ _wg_csrf: '$csrf', job: activeJob }).toString(),
                credentials: 'same-origin',
                cache: 'no-store'
            });
            await jsonResponse(response);
        }
        catch (error) {
            append('\\n' + (error.message || String(error)) + '\\n');
            stopping = false;
            stopButton.textContent = stopLabel;
            showStop(true);
        }
    }

    function stopSilently() {
        if (!activeJob || !activeIsInfinite) return;
        const body = new Blob(
            [new URLSearchParams({ _wg_csrf: '$csrf', job: activeJob }).toString()],
            { type: 'application/x-www-form-urlencoded' }
        );
        if (navigator.sendBeacon) navigator.sendBeacon(stopUrl, body);
    }

    // Delegate every diagnostic action from the stable panel root. Authentic
    // Theme may replace styled button nodes after this script runs; a listener
    // attached directly to the original Stop button would then be lost.
    root.addEventListener('click', function(event) {
        const stopControl = event.target.closest('button[data-role="stop"]');
        if (stopControl && root.contains(stopControl)) {
            event.preventDefault();
            stop();
            return;
        }
        const button = event.target.closest('button[data-diag]');
        if (!button || !root.contains(button)) return;
        event.preventDefault();
        run(button.dataset.diag);
    });
    window.addEventListener('pagehide', stopSilently, { once: true });
})();
</script>
SCRIPT
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

ui_print_footer(
    'edit_interface.cgi?name='.urlize($name),
    text('interface_title', $name)
);
