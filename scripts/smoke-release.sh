#!/bin/sh
# Smoke-test the actual built WBM contents, not just source-tree tests.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
set -- "$ROOT"/dist/*.wbm.gz
[ "$#" -eq 1 ] && [ -f "$1" ] || {
    echo "Expected exactly one built WBM package in dist/" >&2
    exit 1
}
PACKAGE="$1"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

(cd "$ROOT/dist" && sha256sum -c SHA256SUMS && sha512sum -c SHA512SUMS) >/dev/null
tar -xzf "$PACKAGE" -C "$TMP"
[ -f "$TMP/wireguard/module.info" ] || {
    echo "Module metadata missing from WBM" >&2
    exit 1
}

(
    cd "$TMP/wireguard"
    PERL5LIB="$ROOT/tests/stub" perl -e '
        require "./wireguard-lib.pl";
        require "./lib/analytics-page-ui-lib.pl";
        require "./lib/peer-activity-ui-lib.pl";
        require "./lib/peer-diagnostic-ui-lib.pl";
        require "./lib/interface-page-ui-lib.pl";
        require "./lib/chart-ui-lib.pl";
        require "./lib/table-sort-ui-lib.pl";
        my $a=wg_analytics_controller_script(q{{}},q{""},q{""});
        my $p=wg_peer_activity_tabs_script(q{"peer-root"},q{"/wireguard/analytics_data.cgi"},
            q{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},q{{}});
        my $d=wg_peer_diagnostic_script(q{"diag-root"},q{"wg0"},q{"0"},q{"Starting"},
            q{"Stopping"},q{"/wireguard/diagnostic.cgi"},
            q{"/wireguard/diagnostic_status.cgi"},
            q{"/wireguard/diagnostic_stop.cgi"},q{fixture});
        die "Analytics JavaScript not rendered\n" if $a !~ /wg-analytics/;
        die "Peer activity JavaScript not rendered\n" if $p !~ /data-wg-peer-tab/;
        die "Diagnostic JavaScript not rendered\n" if $d !~ /diagnostic_status/;
        my $iface=wg_interface_page_script(
            q{"instance"},q{"wg0"},q{"/wireguard/network_icon_data.cgi"},
            (map { q{"test"} } 1..13),q{fixture});
        die "Interface runtime JavaScript not rendered\n"
            if $iface !~ /wg-runtime/ || $iface !~ /showNetworkIcons/;
        die "Chart helper not rendered\n"
            unless wg_chart_ui_script() =~ /WireGuardChart/;
        die "Table helper not rendered\n"
            unless wg_table_sort_script() =~ /WireGuardTableSort/;
        print "Packaged Perl UI controllers loaded\n";
    '
    export PYTHONDONTWRITEBYTECODE=1
    printf '{}\n' | python3 analytics-store.py health "$TMP/state/analytics.sqlite3" > "$TMP/health.json"
    python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["ok"] and data["peers"]==0 and data["buckets"]==0' < "$TMP/health.json"
    [ -f "$TMP/state/analytics.sqlite3" ] || {
        echo "Packaged Python analytics database could not initialize" >&2
        exit 1
    }
)

echo "WBM archive smoke test passed"
