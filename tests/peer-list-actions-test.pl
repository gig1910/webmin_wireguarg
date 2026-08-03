#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use JSON::PP qw(encode_json);

sub slurp {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "$path: $!\n";
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

my $interface = slurp("$FindBin::Bin/../edit_interface.cgi");
die "peer actions column missing\n" if $interface !~ /interface_peer_actions/;
die "enabled peer color marker missing\n" if $interface !~ /label-success wg-peer-state-enabled/;
die "disabled peer color marker missing\n" if $interface !~ /label-default wg-peer-state-disabled/;
die "peer row toggle control missing\n" if $interface !~ /wg-peer-toggle/;
die "peer row toggle is not a non-submitting button\n" if $interface !~ /type=\"button\"[^>]+data-peer-toggle-button/;
die "peer row toggle does not send POST\n" if $interface !~ /method:\s*'POST'/;
die "peer row toggle does not use an explicit action URL\n" if $interface !~ /data-action-url/;
die "legacy toggle form still present\n" if $interface =~ /ui_form_start\('toggle_peer\.cgi'/;
die "deactivation confirmation missing\n" if $interface !~ /confirmPeerDisable/;
die "runtime refresh after toggle missing\n" if $interface !~ /poller\.tick/;
die "interface page root missing\n" if $interface !~ /data-wg-interface-page/;
die "peer toggle still uses a document-wide click listener\n" if $interface =~ /document\.addEventListener\('click'/;
die "peer toggle is not scoped to the current page root\n" if $interface !~ /root\.addEventListener\('click', onPeerToggleClick\)/;
die "previous SPA controller is not destroyed\n" if $interface !~ /__wgInterfacePageController\.destroy\(\)/;
die "peer toggle has no duplicate-request lock\n" if $interface !~ /dataset\.actionPending/;
die "page controller does not remove runtime listeners\n" if $interface !~ /removeEventListener\('wg-runtime', onRuntime\)/;

my $peer_page = slurp("$FindBin::Bin/../edit_peer.cgi");
die "peer detail toggle is not a non-submitting button\n" if $peer_page !~ /id=\"wg-peer-toggle-detail\"/;
die "peer detail toggle does not send POST\n" if $peer_page !~ /method:\s*'POST'/;
die "peer detail still contains legacy toggle form\n" if $peer_page =~ /ui_form_start\('toggle_peer\.cgi'/;

my $toggle = slurp("$FindBin::Bin/../toggle_peer.cgi");
die "peer toggle does not persist configuration\n" if $toggle !~ /atomic_write_config/;
die "peer toggle does not apply runtime configuration\n" if $toggle !~ /action_apply_interface/;
die "peer toggle does not use AJAX JSON response\n" if $toggle !~ /application\/json/;
die "peer toggle has no rollback on runtime failure\n" if $toggle !~ /original_contents/ || $toggle !~ /rollback/;

my ($block) = $interface =~ /print <<SCRIPT;\n(.*?)\nSCRIPT/s;
die "interface JavaScript block missing\n" if !defined $block;
my ($script) = $block =~ m{<script>\s*(.*?)\s*</script>}s;
die "interface JavaScript content missing\n" if !defined $script;
$script =~ s/\$js_[A-Za-z0-9_]+/"test"/g;

my $node = `command -v node 2>/dev/null`;
chomp($node);
if ($node) {
    my $path = "$FindBin::Bin/peer-list-actions-$$.js";
    open(my $fh, '>', $path) or die $!;
    print {$fh} $script;
    close($fh);
    system($node, '--check', $path) == 0 or die "peer list JavaScript syntax check failed\n";
    unlink($path);

    my $runtime_path = "$FindBin::Bin/peer-list-spa-$$.js";
    open(my $runtime, '>', $runtime_path) or die $!;
    print {$runtime} <<'JS_HEAD';
const vm = require('vm');
const pageScript = __PAGE_SCRIPT__;
let activeRoot = null;
let confirmCount = 0;
let fetchCount = 0;

function makeClassList() {
    return { toggle() {}, add() {}, remove() {} };
}

function makeRoot(name) {
    const listeners = new Map();
    return {
        name,
        isConnected: true,
        listeners,
        addEventListener(type, handler) { listeners.set(type, handler); },
        removeEventListener(type, handler) {
            if (listeners.get(type) === handler) listeners.delete(type);
        },
        contains(node) { return !!node && node.root === this; },
        querySelector() { return null; },
        querySelectorAll() { return []; }
    };
}

const documentListeners = new Map();
global.window = global;
global.CSS = { escape(value) { return String(value); } };
global.MutationObserver = class {
    constructor(handler) { this.handler = handler; }
    observe() {}
    disconnect() {}
};
global.document = {
    currentScript: null,
    documentElement: {},
    addEventListener(type, handler) {
        if (!documentListeners.has(type)) documentListeners.set(type, new Set());
        documentListeners.get(type).add(handler);
    },
    removeEventListener(type, handler) {
        if (documentListeners.has(type)) documentListeners.get(type).delete(handler);
    }
};
global.confirm = function() { confirmCount++; return true; };
global.fetch = async function() {
    fetchCount++;
    return {
        ok: true,
        status: 200,
        headers: { get() { return 'application/json; charset=utf-8'; } },
        async text() { return '{"ok":true,"disabled":true,"digest":"next","message":"done"}'; }
    };
};
window.__wgRuntimePollers = {};

function loadPage(root) {
    activeRoot = root;
    document.currentScript = { closest() { return activeRoot; } };
    vm.runInThisContext(pageScript);
}

(async function() {
    const first = makeRoot('first');
    loadPage(first);
    if (typeof first.listeners.get('click') !== 'function') throw new Error('first page click handler missing');

    const second = makeRoot('second');
    loadPage(second);
    if (first.listeners.has('click')) throw new Error('old SPA click handler was not removed');
    if (typeof second.listeners.get('click') !== 'function') throw new Error('second page click handler missing');
    for (const type of ['wg-runtime', 'wg-runtime-error', 'wg-runtime-warning']) {
        if (!documentListeners.has(type) || documentListeners.get(type).size !== 1) {
            throw new Error(type + ' listener leaked across SPA reload');
        }
    }

    const wrapper = {
        root: second,
        dataset: {
            peerId: 'peer-id', peerIndex: '0', peerDisabled: '0',
            configDigest: 'digest', publicKey: 'public', actionUrl: '/wireguard/toggle_peer.cgi'
        },
        classList: makeClassList(),
        querySelector() { return null; }
    };
    const button = {
        root: second,
        dataset: {},
        textContent: 'Disable peer',
        disabled: false,
        classList: makeClassList(),
        closest(selector) { return selector === '.wg-peer-toggle' ? wrapper : null; }
    };
    const event = {
        target: { closest(selector) { return selector === '[data-peer-toggle-button]' ? button : null; } },
        preventDefault() {},
        stopPropagation() {}
    };

    await second.listeners.get('click')(event);
    if (confirmCount !== 1) throw new Error('one click produced ' + confirmCount + ' confirmations');
    if (fetchCount !== 1) throw new Error('one click produced ' + fetchCount + ' requests');
    console.log('SPA peer toggle listener test passed');
})().catch(function(error) {
    console.error(error && error.stack ? error.stack : error);
    process.exit(1);
});
JS_HEAD
    close($runtime);
    my $runtime_source;
    {
        open(my $rfh, '<', $runtime_path) or die $!;
        local $/; $runtime_source = <$rfh>; close($rfh);
    }
    $runtime_source =~ s/__PAGE_SCRIPT__/encode_json($script)/e;
    open(my $wfh, '>', $runtime_path) or die $!;
    print {$wfh} $runtime_source;
    close($wfh);
    system($node, $runtime_path) == 0 or die "peer list SPA listener test failed\n";
    unlink($runtime_path);
}

print "peer list state and action tests passed\n";
