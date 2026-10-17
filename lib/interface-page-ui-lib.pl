# WireGuard interface peer table, controls, icons and runtime controller.
# All dynamic input is encoded as JSON by the CGI before interpolation.
# Scope, listener disposal and polling semantics must remain unchanged.
sub wg_interface_page_script
{
    my ($js_page_instance, $js_name, $js_network_icons_url, $js_active, $js_inactive, $js_not_running, $js_peer_enabled, $js_peer_disabled, $js_peer_enable, $js_peer_disable, $js_peer_busy, $js_confirm_disable, $js_runtime_loading, $js_runtime_updated, $js_refresh, $js_runtime_error_prefix, $csrf) = @_;
    return <<SCRIPT;
<style>
.wg-peer-toggle { margin: 0; display: inline-block; }
.wg-peer-state-disabled { opacity: .75; }
.wg-peer-action-pending { opacity: .65; }
.wg-runtime-toolbar { margin: 10px 0; display: flex; align-items: center; gap: 10px; }
.wg-endpoint-with-icon { display:inline-flex; align-items:center; gap:5px; }
.wg-network-icon { display:inline-flex; flex:0 0 18px; width:18px;height:18px;
 align-items:center;justify-content:center;box-sizing:border-box;border:1.6px solid white;
 border-radius:50%;color:white;background:rgba(35,40,46,.55);font-weight:bold;font-size:12px;
 line-height:1;vertical-align:middle;white-space:nowrap;overflow:hidden; }
.wg-network-icon[data-custom="1"] { font-size:11px; }
.wg-geoip-country { font-size:11px; font-weight:600; letter-spacing:.04em; opacity:.9; }
.wg-geoip-country[hidden] { display:none!important; }
</style>
<script>
(function() {
    const pageInstance = $js_page_instance;
    const scriptElement = document.currentScript;
    const root = (typeof document.querySelector === 'function'
        ? document.querySelector('[data-wg-interface-page="' + pageInstance + '"]')
        : null) || (scriptElement && typeof scriptElement.closest === 'function'
            ? scriptElement.closest('[data-wg-interface-page]')
            : null);
    if (!root) return;

    if (window.__wgInterfacePageController &&
        typeof window.__wgInterfacePageController.destroy === 'function') {
        window.__wgInterfacePageController.destroy();
    }

    const interfaceName = $js_name;
    const networkIconsUrl = $js_network_icons_url;
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
    const runtimeUpdatedText = $js_runtime_updated;
    const refreshText = $js_refresh;
    const runtimeErrorPrefix = $js_runtime_error_prefix;
    const requestControllers = new Set();
    const tableSort = window.WireGuardTableSort && window.WireGuardTableSort.attach(
        root.querySelector('[data-wg-peer-sort-table]'),
        ['name','state','ip','endpoint','handshake','bytes','bytes','actions']);
    let destroyed = false;
    let knownNetworkIcons = {}, networkSignature = '', networkRequest = null;
    let networkLastCheck = 0;
    function endpointIp(value) {
        value=String(value||'').trim();
        if(value.startsWith('[')) {
            const end=value.indexOf(']');
            return end>1?value.slice(1,end).toLowerCase():'';
        }
        const m=value.match(/^(\\d{1,3}(?:\\.\\d{1,3}){3}):\\d{1,5}\$/);
        if(m)return m[1];
        if(/^[0-9a-f:]+\$/i.test(value)&&value.includes(':'))return value.toLowerCase();
        if(/^\\d{1,3}(?:\\.\\d{1,3}){3}\$/.test(value))return value;
        return '';
    }
    function showNetworkIcons() {
        root.querySelectorAll('[data-wg-net-icon]').forEach(function(icon){
            const endpoint=root.querySelector('[data-wg-endpoint="'+CSS.escape(icon.dataset.wgNetIcon)+'"]');
            const address=endpoint?endpointIp(endpoint.textContent):'';
            const info=address&&knownNetworkIcons[address];
            icon.textContent=info&&info.icon?info.icon:'?';
            icon.dataset.custom=info&&info.icon&&info.icon!=='?'?'1':'0';
            icon.title=info ? [info.cidr,info.label,info.country].filter(Boolean).join(' — ') : '';
            const country=root.querySelector('[data-wg-geoip-country="'+CSS.escape(icon.dataset.wgNetIcon)+'"]');
            if(country){
                const code=info&&typeof info.country==='string'&&/^[A-Za-z]{2}\$/.test(info.country.trim())
                    ?info.country.trim().toUpperCase():'';
                country.textContent=code;
                country.hidden=!code;
                country.title=code ? ((info.country_source==='geoip'?'GeoIP':'WHOIS')+': '+code) : '';
            }
        });
    }
    async function updateNetworkIcons() {
        const ips=Array.from(new Set(Array.from(root.querySelectorAll('[data-wg-endpoint]')).
          map(e=>endpointIp(e.textContent)).filter(Boolean))).slice(0,128);
        const signature=ips.slice().sort().join(',');
        showNetworkIcons();
        if(!signature || (signature===networkSignature && Date.now()-networkLastCheck<60000))return;
        if(networkRequest)networkRequest.abort();
        networkRequest=new AbortController();
        networkSignature=signature;networkLastCheck=Date.now();
        const url=new URL(networkIconsUrl,window.location.href);
        url.searchParams.set('ips',ips.join(','));
        try {
            const response=await fetch(url.toString(),{
                credentials:'same-origin',cache:'no-store',signal:networkRequest.signal,
                headers:{'Accept':'application/json'}
            });
            if(!(response.headers.get('content-type')||'').includes('application/json'))return;
            const result=await response.json();
            if(!destroyed&&result.ok&&result.results){
                knownNetworkIcons=result.results;
                showNetworkIcons();
            }
        }catch(e){ /* Read-only cache is optional. Never block runtime. */ }
    }

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

    function pagePoller() {
        const pollers = Object.values(window.__wgRuntimePollers || {});
        for (const poller of pollers) {
            if (poller && poller.root && root.contains(poller.root)) return poller;
        }
        return null;
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
            if (rx) { rx.textContent = '—'; rx.dataset.sortBytes = ''; }
            if (tx) { tx.textContent = '—'; tx.dataset.sortBytes = ''; }
            if (handshake) handshake.dataset.sortEpoch = '0';
        }
        if (tableSort) tableSort.apply();
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

    async function forceRuntimeRefresh(button) {
        if (!button || button.dataset.refreshPending === '1') return;
        button.dataset.refreshPending = '1';
        button.disabled = true;
        button.textContent = runtimeLoadingText;
        const status = root.querySelector('[data-wg-runtime-refresh-status]');
        if (status) status.textContent = runtimeLoadingText;
        showPeerResult('', 'success');

        try {
            let poller = pagePoller();
            if (!poller) {
                await new Promise(function(resolve) { setTimeout(resolve, 0); });
                poller = pagePoller();
            }
            if (!poller || typeof poller.refresh !== 'function') {
                throw new Error(runtimeErrorPrefix);
            }
            const ok = await poller.refresh();
            if (!ok) throw new Error(runtimeErrorPrefix);
            if (status) status.textContent = runtimeUpdatedText + ': ' + new Date().toLocaleString();
        }
        catch (error) {
            if (!destroyed) showPeerResult(error.message || String(error), 'danger');
            if (status) status.textContent = '';
        }
        finally {
            if (!destroyed && root.contains(button)) {
                delete button.dataset.refreshPending;
                button.disabled = false;
                button.textContent = refreshText;
            }
        }
    }

    async function onPeerToggleClick(event) {
        const refreshButton = event.target.closest('[data-wg-runtime-refresh]');
        if (refreshButton && root.contains(refreshButton)) {
            event.preventDefault();
            event.stopPropagation();
            await forceRuntimeRefresh(refreshButton);
            return;
        }

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
            const poller = pagePoller();
            if (poller && typeof poller.refresh === 'function') {
                await poller.refresh();
            }
            else if (poller && typeof poller.tick === 'function') {
                await poller.tick();
            }
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
        root.querySelectorAll('[data-wg-endpoint]').forEach(function(element) {
            const id = element.dataset.wgEndpoint;
            if (isPeerDisabled(id)) { element.textContent = '—'; return; }
            const peer = peers.get(id);
            element.textContent = peer ? (peer.endpoint || '(none)') : (active ? '—' : notRunningText);
        });
        updateNetworkIcons();
        root.querySelectorAll('[data-wg-handshake]').forEach(function(element) {
            const id = element.dataset.wgHandshake;
            if (isPeerDisabled(id)) {
                element.textContent = peerDisabledText;
                return;
            }
            const peer = peers.get(id);
            element.textContent = peer ? (peer.handshake_text || '-') : (active ? '-' : notRunningText);
            element.dataset.sortEpoch = peer ? String(peer.handshake || 0) : '0';
        });
        root.querySelectorAll('[data-wg-rx]').forEach(function(element) {
            const id = element.dataset.wgRx;
            if (isPeerDisabled(id)) { element.textContent = '—'; return; }
            const peer = peers.get(id);
            element.textContent = peer ? formatBytes(peer.rx) : '—';
            element.dataset.sortBytes = peer ? String(peer.rx || 0) : '';
        });
        root.querySelectorAll('[data-wg-tx]').forEach(function(element) {
            const id = element.dataset.wgTx;
            if (isPeerDisabled(id)) { element.textContent = '—'; return; }
            const peer = peers.get(id);
            element.textContent = peer ? formatBytes(peer.tx) : '—';
            element.dataset.sortBytes = peer ? String(peer.tx || 0) : '';
        });
        root.querySelectorAll('[data-wg-runtime-time]').forEach(function(element) {
            element.textContent = new Date((data.timestamp || Date.now() / 1000) * 1000).toLocaleString();
        });
        if (tableSort) tableSort.apply();
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
        if(networkRequest)networkRequest.abort();
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
}

1;
