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

my $source = slurp("$FindBin::Bin/../edit_interface.cgi");
die "interface CGI must delegate to isolated page controller\n"
    unless $source =~ m{require './lib/interface-page-ui-lib.pl'} &&
           $source =~ /wg_interface_page_script\(/;
$source .= "\n".slurp("$FindBin::Bin/../lib/interface-page-ui-lib.pl");
die "page-instance selector missing\n"
    if $source !~ /document\.querySelector\('\[data-wg-interface-page=/;
die "interface controller still depends only on document.currentScript\n"
    if $source !~ /const root = \(typeof document\.querySelector/;
die "manual runtime refresh button missing\n"
    if $source !~ /data-wg-runtime-refresh/;
die "manual runtime refresh does not use forced poller refresh\n"
    if $source !~ /poller\.refresh\(\)/;

my ($block) = $source =~ /(?:print|return) <<SCRIPT;\n(.*?)\nSCRIPT/s;
die "interface JavaScript block missing\n" if !defined $block;
# Render the actual interpolating Perl heredoc. Syntax checks against the
# raw source miss Perl's treatment of '$/' at the end of JS regexes.
my %symbols;
$symbols{$_}=1 for ($block =~ /\$(js_[A-Za-z0-9_]+)/g);
{
    no strict 'refs';
    for my $symbol (keys %symbols) {
        ${"main::$symbol"} = '"test"';
    }
    ${'main::csrf'} = 'csrf-test';
}
my $rendered=eval "no strict 'vars'; sub { return <<WG_RENDER;\n$block\nWG_RENDER\n}";
die "Cannot interpolate interface page JavaScript: $@\n" if !$rendered || $@;
my $html=$rendered->();
my ($script) = $html =~ m{<script>\s*(.*?)\s*</script>}s;
die "rendered interface JavaScript content missing\n" if !defined $script;

my $node = `command -v node 2>/dev/null`;
chomp($node);
if ($node) {
    my $path = "$FindBin::Bin/interface-controller-root-$$.js";
    open(my $fh, '>', $path) or die $!;
    print {$fh} <<'JS_HEAD';
const vm = require('vm');
const pageScript = __PAGE_SCRIPT__;
let refreshCount = 0;
const rootListeners = new Map();
const documentListeners = new Map();
const refreshStatus = { textContent: '' };
const pollerRoot = {};

const root = {
    isConnected: true,
    addEventListener(type, handler) { rootListeners.set(type, handler); },
    removeEventListener(type, handler) {
        if (rootListeners.get(type) === handler) rootListeners.delete(type);
    },
    contains(node) { return node === refreshButton || node === pollerRoot || node === this; },
    querySelector(selector) {
        if (selector === '[data-wg-runtime-refresh-status]') return refreshStatus;
        return null;
    },
    querySelectorAll() { return []; }
};

const refreshButton = {
    dataset: {},
    disabled: false,
    textContent: 'Refresh',
    closest(selector) { return selector === '[data-wg-runtime-refresh]' ? this : null; }
};

global.window = global;
global.CSS = { escape(value) { return String(value); } };
global.MutationObserver = class {
    observe() {}
    disconnect() {}
};
global.document = {
    currentScript: null,
    documentElement: {},
    querySelector(selector) {
        return selector.startsWith('[data-wg-interface-page=') ? root : null;
    },
    addEventListener(type, handler) {
        if (!documentListeners.has(type)) documentListeners.set(type, new Set());
        documentListeners.get(type).add(handler);
    },
    removeEventListener(type, handler) {
        if (documentListeners.has(type)) documentListeners.get(type).delete(handler);
    }
};
global.confirm = function() { return true; };
global.AbortController = class {
    constructor() { this.signal = {}; }
    abort() {}
};
global.CustomEvent = class {
    constructor(type, options) { this.type = type; this.detail = options && options.detail; }
};
window.__wgRuntimePollers = {
    test: {
        root: pollerRoot,
        async refresh() { refreshCount++; return true; }
    }
};

vm.runInThisContext(pageScript);
if (typeof rootListeners.get('click') !== 'function') {
    throw new Error('page controller was not attached when document.currentScript was null');
}
for (const type of ['wg-runtime', 'wg-runtime-error', 'wg-runtime-warning']) {
    if (!documentListeners.has(type) || documentListeners.get(type).size !== 1) {
        throw new Error(type + ' listener missing');
    }
}

(async function() {
    const event = {
        target: refreshButton,
        preventDefault() {},
        stopPropagation() {}
    };
    await rootListeners.get('click')(event);
    if (refreshCount !== 1) throw new Error('manual refresh called poller ' + refreshCount + ' times');
    if (refreshButton.disabled) throw new Error('manual refresh button remained disabled');
    console.log('interface controller root and manual refresh test passed');
})().catch(function(error) {
    console.error(error && error.stack ? error.stack : error);
    process.exit(1);
});
JS_HEAD
    close($fh);

    my $runtime_source = slurp($path);
    $runtime_source =~ s/__PAGE_SCRIPT__/encode_json($script)/e;
    open(my $wfh, '>', $path) or die $!;
    print {$wfh} $runtime_source;
    close($wfh);
    system($node, $path) == 0 or die "interface controller root test failed\n";
    unlink($path);
}

print "interface controller root and manual refresh checks passed\n";
