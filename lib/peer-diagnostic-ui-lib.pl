# Standalone diagnostic panel controller; CGI is responsible only for ACL,
# scoped markup and validated JSON-encoded arguments.
sub wg_peer_diagnostic_script
{
    my ($js_diag_dom_id, $js_name, $js_peer, $js_starting,
        $js_stopping, $js_diagnostic_url, $js_status_url, $js_stop_url,
        $csrf) = @_;
    return <<SCRIPT;
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
        stopButton.style.display = show ? 'inline-flex' : 'none';
        const wrap=typeof stopButton.closest==='function'
            ? stopButton.closest('[data-wg-diag-stop]') : null;
        if(wrap)wrap.style.display=show?'inline-flex':'none';
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
        return window.WireGuardTransport.readJson(response,{requireOk:true});
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

1;
