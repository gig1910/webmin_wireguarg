#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();

ui_print_header(undef, $text{'index_title'}, '', undef, 1, 1);
my ($items, $list_error) = list_configured_interfaces();
if ($list_error) {
    print ui_alert_box(html_escape($list_error), 'danger');
    print ui_config_link('index_config');
    ui_print_footer('/', $text{'index_title'});
    exit;
}

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
                mini_action_form($name, 'start', $text{'interface_start'}, 'success', '').
            '</span>'.
            '<span data-wg-action-stop="'.html_escape($name).'" style="display:none">'.
                mini_action_form($name, 'stop', $text{'interface_stop'}, 'danger', $text{'confirm_stop'}).
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
        ['width=18%', 'width=18%', 'width=25%', 'width=10%', 'width=10%', 'width=19%'],
        $text{'index_interfaces'}
    );
    print ui_columns_row($_) for @rows;
    print ui_columns_end();
}
else {
    print ui_alert_box($text{'index_none'}, 'info');
}
print '</div>';

if ($access{'manage'}) {
    print '<p>'.ui_link_button('interface_form.cgi', $text{'index_add'}).'</p>';
}
print '<p>'.ui_link_button('journal.cgi', $text{'index_logs'}).'</p>' if ($access{'logs'});


my $collector_url = module_script_url('collector_status.cgi');
my $collector_csrf = csrf_token();
my $collector_id = 'wg-collector-'.substr(sha256_hex(time().rand().$$), 0, 12);
print '<div id="'.html_escape($collector_id).'" class="panel panel-default" data-url="'.html_escape($collector_url).'" data-csrf="'.html_escape($collector_csrf).'">'.
    '<div class="panel-heading"><b>'.html_escape($text{'collector_title'}).'</b></div>'.
    '<div class="panel-body">'.
    '<div data-role="status">'.html_escape($text{'collector_loading'}).'</div>'.
    '<div data-role="warning" class="alert alert-warning" style="display:none;margin-top:8px;margin-bottom:8px"></div>'.
    '<div data-role="details" style="margin-top:6px"></div>';
if ($access{'manage'}) {
    print '<div data-role="actions" style="margin-top:8px">'.
        '<button type="button" class="btn btn-success" data-action="start">'.html_escape($text{'collector_start'}).'</button> '.
        '<button type="button" class="btn btn-warning" data-action="restart">'.html_escape($text{'collector_restart'}).'</button> '.
        '<button type="button" class="btn btn-danger" data-action="stop">'.html_escape($text{'collector_stop'}).'</button>'.
        '</div>'.
        '<div data-role="console-wrap" style="display:none;margin-top:10px">'.
        '<b>'.html_escape($text{'collector_console'}).'</b>'.
        '<pre data-role="console" style="margin-top:6px;max-height:360px;overflow:auto;white-space:pre-wrap"></pre>'.
        '</div>';
}
print '</div></div>';
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
my $js_collector_last_compaction = json_encode_utf8($text{'collector_last_compaction'});
print <<'COLLECTOR_JS_HEAD';
<script>
(function() {
COLLECTOR_JS_HEAD
print "const rootId=$js_collector_id;\n";
print "const healthyText=$js_collector_healthy, staleText=$js_collector_stale, stoppedText=$js_collector_stopped, failedText=$js_collector_failed;\n";
print "const startingText=$js_collector_starting, stoppingText=$js_collector_stopping, unavailableText=$js_collector_unavailable;\n";
print "const lastUpdateText=$js_collector_last_update, storageText=$js_collector_storage, serviceStateText=$js_collector_service_state;\n";
print "const confirmStop=$js_collector_confirm_stop, confirmRestart=$js_collector_confirm_restart, runningActionText=$js_collector_running_action;\n";
print "const compactingText=$js_collector_compacting, restartRequiredText=$js_collector_restart_required, lastCompactionText=$js_collector_last_compaction;\n";
print <<'COLLECTOR_JS';
    const root = document.getElementById(rootId);
    if (!root || root.dataset.initialized === '1') return;
    root.dataset.initialized = '1';
    const status = root.querySelector('[data-role="status"]');
    const details = root.querySelector('[data-role="details"]');
    const warning = root.querySelector('[data-role="warning"]');
    const actions = root.querySelector('[data-role="actions"]');
    const consoleWrap = root.querySelector('[data-role="console-wrap"]');
    const consoleOutput = root.querySelector('[data-role="console"]');
    let busy = false;
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
            if (h.state === 'compacting') { message = compactingText; css = 'text-warning'; }
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
        if (warning) { warning.textContent = h.restart_required ? restartRequiredText : ''; warning.style.display = h.restart_required ? 'block' : 'none'; }
        setButtonVisibility(service);
    }
    async function request(method, action) {
        const options = { method: method, credentials: 'same-origin', cache: 'no-store', headers: {'Accept':'application/json','X-Requested-With':'XMLHttpRequest'} };
        if (method === 'POST') {
            options.headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
            options.body = new URLSearchParams({_wg_csrf: root.dataset.csrf, action: action}).toString();
        }
        const response = await fetch(root.dataset.url, options);
        const body = await response.text();
        let data; try { data = JSON.parse(body); } catch (e) { throw new Error(body.replace(/\s+/g,' ').slice(0,240)); }
        if (method === 'POST' && consoleOutput) consoleOutput.textContent = data.output || '';
        render(data);
        if (!data.ok) throw new Error(data.error || 'Команда не достигла ожидаемого состояния. Подробности показаны в консоли.');
        return data;
    }
    root.addEventListener('click', async function(event) {
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
        finally { busy = false; try { await request('GET'); } catch (e) {} setTimeout(function(){ if(root.isConnected && !busy) request('GET').catch(function(){}); }, 1200); }
    });
    request('GET').catch(function(error) { status.textContent = error.message; status.className = 'text-danger'; });
    const refreshTimer=setInterval(function(){ if(!root.isConnected){clearInterval(refreshTimer);return;} if(!busy && !document.hidden)request('GET').catch(function(){}); },10000);
})();
</script>
COLLECTOR_JS

my $qr_status = optional_dependency_quick_status('qrencode');
print '<div class="panel panel-default"><div class="panel-heading"><b>'.html_escape($text{'dependencies_title'}).'</b></div><div class="panel-body">';
if ($qr_status->{'command_available'}) {
    print '<span class="text-success">'.html_escape(text('dependency_command_available', $qr_status->{'command'})).'</span>';
}
else {
    print '<span>'.html_escape(text('dependency_qrencode_missing', $qr_status->{'command'})).'</span>';
    if ($access{'install_dependencies'} && $qr_status->{'package_manager_available'}) {
        print ' '.ui_link_button('install_dependency.cgi?dependency=qrencode', $text{'qr_install_button'});
    }
}
print '</div></div>';

my $js_active = json_encode_utf8($text{'index_active'});
my $js_inactive = json_encode_utf8($text{'index_inactive'});
my $js_orphan = json_encode_utf8($text{'index_orphan'});
my $runtime_error_prefix = $text{'index_runtime_error'};
$runtime_error_prefix =~ s/\$1//g;
my $js_runtime_error_prefix = json_encode_utf8($runtime_error_prefix);
print <<SCRIPT;
<script>
(function() {
    const activeText = $js_active;
    const inactiveText = $js_inactive;
    const orphanText = $js_orphan;
    const runtimeErrorPrefix = $js_runtime_error_prefix;
    const configured = new Set(Array.from(document.querySelectorAll('[data-wg-interface-name]')).map(function(e) { return e.dataset.wgInterfaceName; }));

    function setConfiguredState(name, active, iface) {
        const state = document.querySelector('[data-wg-state="' + CSS.escape(name) + '"]');
        if (state) {
            state.textContent = active ? activeText : inactiveText;
            state.style.fontWeight = active ? 'bold' : 'normal';
        }
        const port = document.querySelector('[data-wg-port="' + CSS.escape(name) + '"]');
        if (port && active && iface.listen_port) port.textContent = iface.listen_port;
        const loading = document.querySelector('[data-wg-actions-loading="' + CSS.escape(name) + '"]');
        const start = document.querySelector('[data-wg-action-start="' + CSS.escape(name) + '"]');
        const stop = document.querySelector('[data-wg-action-stop="' + CSS.escape(name) + '"]');
        if (loading) loading.style.display = 'none';
        if (start) start.style.display = active ? 'none' : 'inline';
        if (stop) stop.style.display = active ? 'inline' : 'none';
    }

    function addOrphan(name, iface) {
        if (document.querySelector('[data-wg-orphan="' + CSS.escape(name) + '"]')) return;
        const wrapper = document.getElementById('wg-interface-table');
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

    document.addEventListener('wg-runtime', function(event) {
        const data = event.detail || {};
        const interfaces = data.interfaces || {};
        configured.forEach(function(name) { setConfiguredState(name, false, {}); });
        Object.keys(interfaces).forEach(function(name) {
            const iface = interfaces[name];
            if (configured.has(name)) setConfiguredState(name, !!iface.active, iface);
            else if (iface.active) addOrphan(name, iface);
        });
        const time = document.getElementById('wg-index-runtime-time');
        if (time) time.textContent = new Date((data.timestamp || Date.now() / 1000) * 1000).toLocaleString();
        const error = document.getElementById('wg-runtime-error');
        if (error) error.style.display = 'none';
    });

    document.addEventListener('wg-runtime-error', function(event) {
        const error = document.getElementById('wg-runtime-error');
        if (!error) return;
        error.textContent = runtimeErrorPrefix + (event.detail && event.detail.error ? event.detail.error : '');
        error.style.display = 'block';
    });

    document.addEventListener('wg-runtime-warning', function(event) {
        const error = document.getElementById('wg-runtime-error') || document.getElementById('wg-interface-runtime-error');
        if (!error) return;
        error.textContent = event.detail && event.detail.warning ? event.detail.warning : '';
        error.style.display = error.textContent ? 'block' : 'none';
    });
})();
</script>
SCRIPT

print runtime_poll_html('');
print ui_config_link('index_config');
ui_print_footer('/', $text{'index_title'});
