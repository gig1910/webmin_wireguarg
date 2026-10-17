=head1 index-page-ui-lib.pl

Webmin dashboard: collector control and live interface state.
Keeps page rendering and authorization in index.cgi.

=cut

sub wg_index_collector_script
{
    my ($js_collector_id, $js_collector_healthy, $js_collector_stale, $js_collector_stopped, $js_collector_failed, $js_collector_starting, $js_collector_stopping, $js_collector_unavailable, $js_collector_last_update, $js_collector_storage, $js_collector_service_state, $js_collector_confirm_stop, $js_collector_confirm_restart, $js_collector_running_action, $js_collector_compacting, $js_collector_restart_required, $js_collector_last_compaction, $js_collector_config_pending, $js_collector_config_unverified, $js_collector_config_different) = @_;
    my $render = <<'COLLECTOR_JS_HEAD';
<script>
(function() {
COLLECTOR_JS_HEAD
$render .= "const rootId=$js_collector_id;\n";
$render .= "const healthyText=$js_collector_healthy, staleText=$js_collector_stale, stoppedText=$js_collector_stopped, failedText=$js_collector_failed;\n";
$render .= "const startingText=$js_collector_starting, stoppingText=$js_collector_stopping, unavailableText=$js_collector_unavailable;\n";
$render .= "const lastUpdateText=$js_collector_last_update, storageText=$js_collector_storage, serviceStateText=$js_collector_service_state;\n";
$render .= "const confirmStop=$js_collector_confirm_stop, confirmRestart=$js_collector_confirm_restart, runningActionText=$js_collector_running_action;\n";
$render .= "const compactingText=$js_collector_compacting, restartRequiredText=$js_collector_restart_required, lastCompactionText=$js_collector_last_compaction;\n";
$render .= "const configPendingText=$js_collector_config_pending, configUnverifiedText=$js_collector_config_unverified, configDifferentText=$js_collector_config_different;\n";

    $render .= <<'COLLECTOR_JS';
    const root = document.getElementById(rootId);
    if (!root || root.dataset.initialized === '1') return;
    const previous=window.__wgCollectorController;
    if(previous&&typeof previous.destroy==='function')previous.destroy();
    root.dataset.initialized = '1';
    const status = root.querySelector('[data-role="status"]');
    const details = root.querySelector('[data-role="details"]');
    const warning = root.querySelector('[data-role="warning"]');
    const actions = root.querySelector('[data-role="actions"]');
    const consoleWrap = root.querySelector('[data-role="console-wrap"]');
    const consoleOutput = root.querySelector('[data-role="console"]');
    let busy = false, disposed = false;
    function fmtBytes(value) {
        let n = Number(value || 0), units = ['B','KiB','MiB','GiB']; let i = 0;
        while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
        return (i ? n.toFixed(1) : String(Math.round(n))) + ' ' + units[i];
    }
    function setButtonVisibility(service) {
        if (!actions) return;
        const active = service && service.state === 'active';
        actions.querySelectorAll('button[data-action]').forEach(function(button) {
            const action = button.dataset.action;
            button.style.display = action === 'start' ? (active ? 'none' : '') : (active ? '' : 'none');
            button.disabled = busy;
        });
    }
    function render(data) {
        const h = data && data.health ? data.health : {};
        const service = data && data.service ? data.service : {};
        const state = service.state || 'unknown';
        let message = unavailableText, css = 'text-warning';
        if (state === 'active') {
            if (h.config_pending) { message = configPendingText; css = 'text-warning'; }
            else if (h.state === 'compacting') { message = compactingText; css = 'text-warning'; }
            else if (!h.available || h.stale || h.ok === false) { message = staleText; css = 'text-warning'; }
            else { message = healthyText; css = 'text-success'; }
        }
        else if (state === 'activating') { message = startingText; css = 'text-warning'; }
        else if (state === 'deactivating') { message = stoppingText; css = 'text-warning'; }
        else if (state === 'failed') { message = failedText; css = 'text-danger'; }
        else if (state === 'inactive') { message = stoppedText; css = 'text-muted'; }
        status.textContent = message;
        status.className = css;
        const when = h.timestamp ? new Date(h.timestamp * 1000).toLocaleString() : '—';
        const stateLabel = state + (service.substate ? '/' + service.substate : '');
        let detailText = serviceStateText + ': ' + stateLabel + '; ' + lastUpdateText + ': ' + when + '; ' + storageText + ': ' + fmtBytes(h.history_storage_bytes || h.storage_bytes || 0) + ' / ' + fmtBytes(h.max_total_bytes || 0);
        if (h.last_compaction && h.last_compaction.timestamp) {
            detailText += '; ' + lastCompactionText + ': ' + fmtBytes(h.last_compaction.bytes_before || 0) + ' → ' + fmtBytes(h.last_compaction.bytes_after || 0);
        }
        details.textContent = detailText;
        if (warning) {
            const mismatched = Array.isArray(h.config_mismatch_keys) ? h.config_mismatch_keys : [];
            const needsRestart = h.config_state === 'restart_required' && h.restart_required;
            const unverified = h.config_state === 'unverified';
            warning.textContent = needsRestart
                ? restartRequiredText + (mismatched.length ? ' ' + configDifferentText + ': ' + mismatched.join(', ') : '')
                : (unverified ? configUnverifiedText : '');
            warning.style.display = (needsRestart || unverified) ? 'block' : 'none';
        }
        setButtonVisibility(service);
    }
    async function request(method, action) {
        const options = { method: method, credentials: 'same-origin', cache: 'no-store', headers: {'Accept':'application/json','X-Requested-With':'XMLHttpRequest'} };
        if (method === 'POST') {
            options.headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
            options.body = new URLSearchParams({_wg_csrf: root.dataset.csrf, action: action}).toString();
        }
        const data = await window.WireGuardTransport.requestJson(root.dataset.url, options);
        if(disposed)return data;
        if (method === 'POST' && consoleOutput) consoleOutput.textContent = data.output || '';
        render(data);
        if (!data.ok) throw new Error(data.error || 'Команда не достигла ожидаемого состояния. Подробности показаны в консоли.');
        return data;
    }
    const onAction=async function(event) {
        if(disposed)return;
        const button = event.target.closest('button[data-action]'); if (!button || !root.contains(button) || busy) return;
        const action = button.dataset.action;
        if (action === 'stop' && !confirm(confirmStop)) return;
        if (action === 'restart' && !confirm(confirmRestart)) return;
        busy = true;
        setButtonVisibility({state: action === 'stop' ? 'active' : 'inactive'});
        if (consoleWrap) consoleWrap.style.display = 'block';
        if (consoleOutput) consoleOutput.textContent = runningActionText + '\n';
        try { await request('POST', action); }
        catch (error) { status.textContent = error.message; status.className = 'text-danger'; }
        finally {
            busy = false;
            if(!disposed){
                try { await request('GET'); } catch (e) {}
                setTimeout(function(){
                    if(root.isConnected&&!disposed&&!busy)request('GET').catch(function(){});
                },1200);
            }
        }
    };
    root.addEventListener('click',onAction);
    function destroy(){
        if(disposed)return;
        disposed=true;
        clearInterval(refreshTimer);
        root.removeEventListener('click',onAction);
        window.removeEventListener('pagehide',destroy);
        if(window.__wgCollectorController&&window.__wgCollectorController.root===root)
            delete window.__wgCollectorController;
    }
    request('GET').catch(function(error) {
        if(!disposed){status.textContent=error.message;status.className='text-danger';}
    });
    const refreshTimer=setInterval(function(){
        if(!root.isConnected||disposed){destroy();return;}
        if(!busy&&!document.hidden)request('GET').catch(function(){});
    },10000);
    window.__wgCollectorController={root:root,destroy:destroy};
    window.addEventListener('pagehide',destroy,{once:true});
})();
</script>
COLLECTOR_JS
    return $render;
}

sub wg_index_runtime_script
{
    my ($js_index_page_id,$js_active, $js_inactive, $js_orphan, $js_runtime_error_prefix) = @_;
    return <<SCRIPT;
<script>
(function() {
    const pageId=$js_index_page_id;
    const root=document.querySelector('[data-wg-index-page="'+pageId+'"]');
    if(!root)return;
    const prior=window.__wgIndexRuntimeController;
    if(prior && typeof prior.destroy==='function')prior.destroy();
    const activeText = $js_active;
    const inactiveText = $js_inactive;
    const orphanText = $js_orphan;
    const runtimeErrorPrefix = $js_runtime_error_prefix;
    const configured = new Set(Array.from(root.querySelectorAll('[data-wg-interface-name]')).map(function(e) { return e.dataset.wgInterfaceName; }));

    function setConfiguredState(name, active, iface) {
        const state = root.querySelector('[data-wg-state="' + CSS.escape(name) + '"]');
        if (state) {
            state.textContent = active ? activeText : inactiveText;
            state.style.fontWeight = active ? 'bold' : 'normal';
        }
        const port = root.querySelector('[data-wg-port="' + CSS.escape(name) + '"]');
        if (port && active && iface.listen_port) port.textContent = iface.listen_port;
        const loading = root.querySelector('[data-wg-actions-loading="' + CSS.escape(name) + '"]');
        const start = root.querySelector('[data-wg-action-start="' + CSS.escape(name) + '"]');
        const stop = root.querySelector('[data-wg-action-stop="' + CSS.escape(name) + '"]');
        if (loading) loading.style.display = 'none';
        if (start) start.style.display = active ? 'none' : 'inline';
        if (stop) stop.style.display = active ? 'inline' : 'none';
    }

    function addOrphan(name, iface) {
        if (root.querySelector('[data-wg-orphan="' + CSS.escape(name) + '"]')) return;
        const wrapper = root.querySelector('#wg-interface-table');
        const tbody = wrapper && wrapper.querySelector('tbody');
        if (!tbody) return;
        const tr = document.createElement('tr');
        tr.dataset.wgOrphan = name;
        [name, orphanText, '-', iface.listen_port || '-', String(iface.peer_count || 0), ''].forEach(function(value) {
            const td = document.createElement('td');
            td.textContent = value;
            tr.appendChild(td);
        });
        tbody.appendChild(tr);
    }

    function onRuntime(event) {
        const data = event.detail || {};
        const interfaces = data.interfaces || {};
        configured.forEach(function(name) { setConfiguredState(name, false, {}); });
        Object.keys(interfaces).forEach(function(name) {
            const iface = interfaces[name];
            if (configured.has(name)) setConfiguredState(name, !!iface.active, iface);
            else if (iface.active) addOrphan(name, iface);
        });
        const time = root.querySelector('#wg-index-runtime-time');
        if (time) time.textContent = new Date((data.timestamp || Date.now() / 1000) * 1000).toLocaleString();
        const error = root.querySelector('#wg-runtime-error');
        if (error) error.style.display = 'none';
    }

    function onRuntimeError(event) {
        const error = root.querySelector('#wg-runtime-error');
        if (!error) return;
        error.textContent = runtimeErrorPrefix + (event.detail && event.detail.error ? event.detail.error : '');
        error.style.display = 'block';
    }

    function onRuntimeWarning(event) {
        const error = root.querySelector('#wg-runtime-error') || root.querySelector('#wg-interface-runtime-error');
        if (!error) return;
        error.textContent = event.detail && event.detail.warning ? event.detail.warning : '';
        error.style.display = error.textContent ? 'block' : 'none';
    }
    function destroy(){
        document.removeEventListener('wg-runtime',onRuntime);
        document.removeEventListener('wg-runtime-error',onRuntimeError);
        document.removeEventListener('wg-runtime-warning',onRuntimeWarning);
        observer.disconnect();
        window.removeEventListener('pagehide',destroy);
        if(window.__wgIndexRuntimeController &&
           window.__wgIndexRuntimeController.root===root)
            delete window.__wgIndexRuntimeController;
    }
    const observer=new MutationObserver(function(){
        if(!root.isConnected)destroy();
    });
    document.addEventListener('wg-runtime',onRuntime);
    document.addEventListener('wg-runtime-error',onRuntimeError);
    document.addEventListener('wg-runtime-warning',onRuntimeWarning);
    observer.observe(document.documentElement,{childList:true,subtree:true});
    window.__wgIndexRuntimeController={root:root,destroy:destroy};
    window.addEventListener('pagehide',destroy,{once:true});
})();
</script>
SCRIPT
}

1;
