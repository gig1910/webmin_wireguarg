#!/usr/local/bin/perl
require './wireguard-lib.pl';
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
my $page_instance = substr(sha256_hex(join('|', $$, time(), rand(), $name)), 0, 16);
print '<div data-wg-interface-page="'.html_escape($page_instance).'">';
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
    my $name_link = '<a href="edit_peer.cgi?name='.urlize($name).'&peer='.$i.'"><b>'.html_escape(peer_display_name($peer, $i)).'</b></a>';
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
        '<span data-wg-endpoint="'.$id.'">'.html_escape($endpoint).'</span>',
        '<span data-wg-handshake="'.$id.'">'.html_escape($handshake).'</span>',
        '<span data-wg-rx="'.$id.'">—</span>',
        '<span data-wg-tx="'.$id.'">—</span>',
        $actions,
    ];
}

if (@rows) {
    print '<div class="wg-runtime-time">'.$text{'runtime_updated'}.': <span data-wg-runtime-time>'.$text{'runtime_loading'}.'</span></div>';
    print ui_columns_start(
        [$text{'interface_peer_name'}, $text{'interface_peer_state'}, $text{'interface_peer_allowed'}, $text{'interface_peer_endpoint'}, $text{'interface_peer_handshake'}, $text{'interface_peer_rx'}, $text{'interface_peer_tx'}, $text{'interface_peer_actions'}],
        100, 0, undef, $text{'interface_peers'}
    );
    print ui_columns_row($_) for @rows;
    print ui_columns_end();
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
my $runtime_error_prefix = $text{'index_runtime_error'};
$runtime_error_prefix =~ s/\$1//g;
my $js_runtime_error_prefix = json_encode_utf8($runtime_error_prefix);
print <<SCRIPT;
<style>
.wg-peer-toggle { margin: 0; display: inline-block; }
.wg-peer-state-disabled { opacity: .75; }
.wg-peer-action-pending { opacity: .65; }
</style>
<script>
(function() {
    const scriptElement = document.currentScript;
    const root = scriptElement && scriptElement.closest('[data-wg-interface-page]');
    if (!root) return;

    if (window.__wgInterfacePageController &&
        typeof window.__wgInterfacePageController.destroy === 'function') {
        window.__wgInterfacePageController.destroy();
    }

    const interfaceName = $js_name;
    const activeText = $js_active;
    const inactiveText = $js_inactive;
    const notRunningText = $js_not_running;
    const peerEnabledText = $js_peer_enabled;
    const peerDisabledText = $js_peer_disabled;
    const peerEnableText = $js_peer_enable;
    const peerDisableText = $js_peer_disable;
    const peerBusyText = $js_peer_busy;
    const confirmPeerDisable = $js_confirm_disable;
    const runtimeLoadingText = $js_runtime_loading;
    const runtimeErrorPrefix = $js_runtime_error_prefix;
    const requestControllers = new Set();
    let destroyed = false;

    function findById(id) {
        return root.querySelector('#' + CSS.escape(id));
    }

    function formatBytes(value) {
        value = Number(value) || 0;
        const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
        let index = 0;
        while (value >= 1024 && index < units.length - 1) { value /= 1024; index++; }
        const number = index === 0 ? value.toFixed(0) : value >= 100 ? value.toFixed(0) : value >= 10 ? value.toFixed(1) : value.toFixed(2);
        return number + ' ' + units[index];
    }

    function setActions(active) {
        const loading = findById('wg-actions-loading');
        const activeActions = findById('wg-actions-active');
        const inactiveActions = findById('wg-actions-inactive');
        if (loading) loading.style.display = 'none';
        if (activeActions) activeActions.style.display = active ? 'inline' : 'none';
        if (inactiveActions) inactiveActions.style.display = active ? 'none' : 'inline';
    }

    function isPeerDisabled(id) {
        const state = root.querySelector('[data-wg-peer-state="' + CSS.escape(id) + '"]');
        return !!state && state.dataset.disabled === '1';
    }

    function updatePeerState(id, disabled) {
        const state = root.querySelector('[data-wg-peer-state="' + CSS.escape(id) + '"]');
        if (state) {
            state.dataset.disabled = disabled ? '1' : '0';
            state.textContent = disabled ? peerDisabledText : peerEnabledText;
            state.classList.toggle('label-success', !disabled);
            state.classList.toggle('wg-peer-state-enabled', !disabled);
            state.classList.toggle('label-default', disabled);
            state.classList.toggle('wg-peer-state-disabled', disabled);
        }
        const wrapper = root.querySelector('.wg-peer-toggle[data-peer-id="' + CSS.escape(id) + '"]');
        if (wrapper) {
            wrapper.dataset.peerDisabled = disabled ? '1' : '0';
            const button = wrapper.querySelector('[data-peer-toggle-button]');
            if (button) {
                button.textContent = disabled ? peerEnableText : peerDisableText;
                button.classList.toggle('btn-success', disabled);
                button.classList.toggle('btn-warning', !disabled);
            }
        }
        const handshake = root.querySelector('[data-wg-handshake="' + CSS.escape(id) + '"]');
        const rx = root.querySelector('[data-wg-rx="' + CSS.escape(id) + '"]');
        const tx = root.querySelector('[data-wg-tx="' + CSS.escape(id) + '"]');
        if (handshake) handshake.textContent = disabled ? peerDisabledText : runtimeLoadingText;
        if (disabled) {
            if (rx) rx.textContent = '—';
            if (tx) tx.textContent = '—';
        }
    }

    function showPeerResult(message, kind) {
        const box = findById('wg-peer-action-result');
        if (!box) return;
        box.className = 'alert alert-' + (kind || 'success');
        box.textContent = message || '';
        box.style.display = message ? 'block' : 'none';
    }

    async function decodeJsonResponse(response) {
        const body = await response.text();
        const contentType = (response.headers.get('content-type') || '').toLowerCase();
        if (!contentType.includes('application/json')) {
            const sample = body.replace(/\s+/g, ' ').trim().slice(0, 240);
            throw new Error('HTTP ' + response.status + ': сервер вернул не JSON' + (sample ? ': ' + sample : ''));
        }
        try {
            return JSON.parse(body);
        }
        catch (error) {
            const sample = body.replace(/\s+/g, ' ').trim().slice(0, 240);
            throw new Error('Некорректный JSON-ответ' + (sample ? ': ' + sample : ''));
        }
    }

    async function onPeerToggleClick(event) {
        const button = event.target.closest('[data-peer-toggle-button]');
        if (!button || !root.contains(button)) return;
        event.preventDefault();
        event.stopPropagation();

        const wrapper = button.closest('.wg-peer-toggle');
        if (!wrapper || wrapper.dataset.actionPending === '1') return;
        const peerId = wrapper.dataset.peerId;
        const currentlyDisabled = wrapper.dataset.peerDisabled === '1';
        if (!currentlyDisabled && !window.confirm(confirmPeerDisable)) return;

        wrapper.dataset.actionPending = '1';
        const originalText = button.textContent;
        button.disabled = true;
        button.textContent = peerBusyText;
        wrapper.classList.add('wg-peer-action-pending');
        showPeerResult('', 'success');

        const payload = new URLSearchParams({ _wg_csrf: '$csrf',
            name: interfaceName,
            peer: wrapper.dataset.peerIndex || '',
            config_digest: wrapper.dataset.configDigest || '',
            old_public_key: wrapper.dataset.publicKey || '',
            ajax: '1'
        });
        const requestController = new AbortController();
        requestControllers.add(requestController);

        try {
            const response = await fetch(wrapper.dataset.actionUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
                    'Accept': 'application/json'
                },
                body: payload.toString(),
                credentials: 'same-origin',
                cache: 'no-store',
                signal: requestController.signal
            });
            const data = await decodeJsonResponse(response);
            if (!response.ok || !data.ok) throw new Error(data.error || ('HTTP ' + response.status));
            if (destroyed) return;
            const disabled = !!data.disabled;
            updatePeerState(peerId, disabled);
            root.querySelectorAll('.wg-peer-toggle').forEach(function(item) {
                if (data.digest) item.dataset.configDigest = data.digest;
            });
            root.querySelectorAll('input[name="config_digest"]').forEach(function(input) {
                input.value = data.digest || input.value;
            });
            showPeerResult(data.message || (disabled ? peerDisabledText : peerEnabledText), 'success');
            Object.values(window.__wgRuntimePollers || {}).forEach(function(poller) {
                if (poller && typeof poller.tick === 'function') poller.tick();
            });
        }
        catch (error) {
            if (!destroyed && error.name !== 'AbortError') {
                showPeerResult(error.message || String(error), 'danger');
                button.textContent = originalText;
            }
        }
        finally {
            requestControllers.delete(requestController);
            if (!destroyed && root.contains(wrapper)) {
                delete wrapper.dataset.actionPending;
                wrapper.classList.remove('wg-peer-action-pending');
                button.disabled = false;
            }
        }
    }

    function onRuntime(event) {
        const data = event.detail || {};
        const iface = data.interfaces && data.interfaces[interfaceName] ? data.interfaces[interfaceName] : { active: false, peers: [] };
        const active = !!iface.active;
        const state = findById('wg-interface-state');
        if (state) { state.textContent = active ? activeText : inactiveText; state.style.fontWeight = active ? 'bold' : 'normal'; }
        const port = findById('wg-interface-port');
        if (port && iface.listen_port) port.textContent = iface.listen_port;
        const publicKey = findById('wg-interface-public-key');
        if (publicKey && iface.public_key) publicKey.textContent = iface.public_key;
        setActions(active);

        const peers = new Map((iface.peers || []).map(function(peer) { return [peer.id, peer]; }));
        root.querySelectorAll('[data-wg-handshake]').forEach(function(element) {
            const id = element.dataset.wgHandshake;
            if (isPeerDisabled(id)) {
                element.textContent = peerDisabledText;
                return;
            }
            const peer = peers.get(id);
            element.textContent = peer ? (peer.handshake_text || '-') : (active ? '-' : notRunningText);
        });
        root.querySelectorAll('[data-wg-rx]').forEach(function(element) {
            const id = element.dataset.wgRx;
            if (isPeerDisabled(id)) { element.textContent = '—'; return; }
            const peer = peers.get(id);
            element.textContent = peer ? formatBytes(peer.rx) : '—';
        });
        root.querySelectorAll('[data-wg-tx]').forEach(function(element) {
            const id = element.dataset.wgTx;
            if (isPeerDisabled(id)) { element.textContent = '—'; return; }
            const peer = peers.get(id);
            element.textContent = peer ? formatBytes(peer.tx) : '—';
        });
        peers.forEach(function(peer, id) {
            if (isPeerDisabled(id)) return;
            const endpoint = root.querySelector('[data-wg-endpoint="' + CSS.escape(id) + '"]');
            if (endpoint && peer.endpoint) endpoint.textContent = peer.endpoint;
        });
        root.querySelectorAll('[data-wg-runtime-time]').forEach(function(element) {
            element.textContent = new Date((data.timestamp || Date.now() / 1000) * 1000).toLocaleString();
        });
        const error = findById('wg-interface-runtime-error');
        if (error) error.style.display = 'none';
    }

    function onRuntimeError(event) {
        const error = findById('wg-interface-runtime-error');
        if (!error) return;
        error.textContent = runtimeErrorPrefix + (event.detail && event.detail.error ? event.detail.error : '');
        error.style.display = 'block';
    }

    function onRuntimeWarning(event) {
        const error = findById('wg-runtime-error') || findById('wg-interface-runtime-error');
        if (!error) return;
        error.textContent = event.detail && event.detail.warning ? event.detail.warning : '';
        error.style.display = error.textContent ? 'block' : 'none';
    }

    const detachObserver = new MutationObserver(function() {
        if (!root.isConnected) destroy();
    });

    function destroy() {
        if (destroyed) return;
        destroyed = true;
        root.removeEventListener('click', onPeerToggleClick);
        document.removeEventListener('wg-runtime', onRuntime);
        document.removeEventListener('wg-runtime-error', onRuntimeError);
        document.removeEventListener('wg-runtime-warning', onRuntimeWarning);
        requestControllers.forEach(function(controller) { controller.abort(); });
        requestControllers.clear();
        detachObserver.disconnect();
        if (window.__wgInterfacePageController && window.__wgInterfacePageController.root === root) {
            delete window.__wgInterfacePageController;
        }
    }

    root.addEventListener('click', onPeerToggleClick);
    document.addEventListener('wg-runtime', onRuntime);
    document.addEventListener('wg-runtime-error', onRuntimeError);
    document.addEventListener('wg-runtime-warning', onRuntimeWarning);
    detachObserver.observe(document.documentElement, { childList: true, subtree: true });
    window.__wgInterfacePageController = { root: root, destroy: destroy };
})();
</script>
SCRIPT

print runtime_poll_html($name);
print '</div>';
ui_print_footer('index.cgi', $text{'index_title'});
