# Browser UI architecture

Webmin owns the page shell, authentication, access control and configuration
operations. JavaScript code is a presentation layer; **all privileged actions
must be re-authorized by the corresponding CGI endpoint**. Authentic Theme
may replace DOM fragments without a traditional full-page reload.

## Component boundaries

| Layer | Implementation | Responsibility |
|---|---|---|
| Page templates | `index.cgi`, `edit_interface.cgi`, `edit_peer.cgi`, `analytics.cgi` | Server-side HTML, localization, URLs and JSON-encoded initial state |
| Interface controller | `lib/interface-page-ui-lib.pl` | Peer runtime, actions, badges, SPA-safe event handlers and cleanup |
| Analytics controller | `lib/analytics-page-ui-lib.pl` | Historical SVG graph, filters, events and refresh |
| Peer activity controller | `lib/peer-activity-ui-lib.pl` | Tab navigation, activity polling and sortable rows |
| Peer diagnostics | `lib/peer-diagnostic-ui-lib.pl` | Asynchronous diagnostic progress, output and Stop |
| Runtime and chart controller | `lib/metrics-lib.pl` | Runtime polling and live interface traffic canvas |
| Peer history controller | `lib/peer-usage-ui-lib.pl` | Period selection and measured peer-usage canvas |
| Shared chart primitives | `lib/chart-ui-lib.pl` | Byte/rate labels, theme palette and chart axis limits |
| Shared table component | `lib/table-sort-ui-lib.pl` | Stable column sorting, IP parsing, and safe text-only row creation |
| Dashboard controller | `lib/index-page-ui-lib.pl` | Collector actions, runtime state and SPA listener disposal |
| Network directory controller | `lib/network-icons-ui-lib.pl` | CIDR editor, manual icons and WHOIS/GeoIP country badge presentation |
| Shared browser transport | `lib/ui-transport-lib.pl` | Same-origin JSON fetch defaults, Content-Type validation, parse errors and `nonJson` classification |

### Three chart data models

1. **Live interface traffic**: counters are sampled from runtime WireGuard
   state; deltas are converted to bytes per second, on a sliding time window.
2. **Peer consumption history**: short-interval counter observations and reset
   gaps are displayed with explicit periods and coverage notices.
3. **Long-term analytics**: SQLite 10-minute buckets, aggregated into display
   periods (bytes per interval, not bytes per second); SVG preserves missing
   segments and supports event filtering.

These are **not interchangeable input datasets**. Only common visual concerns
(formatting, theme colors, axis scaling) are reused. A single data adapter
would conflate counter resets, missing observations and bucket aggregation.

## Safe DOM construction and tables

The shared `WireGuardTableSort.appendTextRow(tbody, values)` builds actual
`<tr>` and `<td>` elements with `textContent`, never `innerHTML`.
Analytics events may then replace a cell with a validated, same-origin
navigation link. Sorting applies to the resulting DOM and handles absent
values without treating numeric zero as missing.

Other table-like pages still use Webmin's Perl table helpers for initial
server-side HTML; do not duplicate them in JavaScript merely for uniformity.

## Runtime and lifecycle invariants

- Scope all handlers to the current page root and detach them when an
  Authentic Theme navigation replaces the fragment.
- Cancel superseded fetches and ignore stale responses; avoid duplicate
  listeners on repeated page loads.
- Run side effects only on explicit requests. Opening a peer list must never
  trigger external WHOIS lookups.
- Use the module's CGI URLs and same-origin credentials, never construct
  privileged requests to arbitrary origins.
- Pass all values originating in configuration or translations through the
  existing JSON encoder before inserting them into JavaScript.
- **Perl interpolation happens before JavaScript parsing**: a source regex
  ending in `$/` can interpolate Perl's input-record separator. Tests must
  check the rendered script, not only `perl -c` and raw source strings.
- Keep downloaded peer keys and saved configuration out of browser logs.
  Server CGI remains the authorization boundary for exporting secrets.

## Regression gates

- `tests/chart-ui-test.pl`: shared units, color/scale helpers, multiple charts
- `tests/ui-transport-test.pl`: JSON transport, HTML/404 rejection and API error classification
- `tests/index-page-ui-test.pl`: dashboard's rendered JavaScript and shared module wiring
- `tests/index-lifecycle-test.pl`: dashboard listener disposal on repeat SPA navigation
- `tests/index-collector-lifecycle-test.pl`: collector timer and action listener cleanup
- `tests/table-sort-test.pl`: accessible sort, numeric IP comparison, safe DOM rows
- `tests/async-js-test.pl`, `tests/peer-usage-test.pl`: live polling and history
- `tests/interface-controller-root-test.pl`, `tests/peer-list-actions-test.pl`:
  SPA root ownership, cleanup and peer actions
- `tests/network-icons-ui-test.pl`: badges and peer activity tabs
- `tests/analytics-chart-test.pl`, `tests/analytics-ui-test.pl`:
  rendered analytics JavaScript, chart and events
- `tests/diagnostic-js-test.pl`: diagnostics and rendered JavaScript
- `scripts/smoke-release.sh`: verify built WBM actually includes and loads
  controllers, Python backend and checksum-verified assets

## Shared JSON transport and remaining deployment checks

`WireGuardTransport` is idempotently initialized per browser window. It
centralizes content-type checks, JSON decoding, small error excerpts, optional
`ok` checking, and same-origin request defaults. Runtime polling, diagnostic
progress, client graph refresh, and mutation requests **keep their own**
timeouts, cancellation, request ordering and lifecycle policies. For example,
the runtime poller still stops on `error.nonJson`, while diagnostic output
still decodes incremental chunks separately.

Dashboard and network-directory DOM are scoped by unique page-instance tokens,
preventing old Authentic Theme fragments from capturing new handlers. Dashboard
runtime event listeners and collector background-refresh timers/action handlers
are removed when navigation replaces the page. Both scenarios have behavioral
Node tests against consecutive page instances.

The source regression gate and packaged-WBM smoke test pass, but neither
replaces deployment verification with a real MiniServ/Authentic Theme process,
systemd services and apt/dpkg operations. Test in a separate Webmin instance
before production rollout. In particular, validate SPA navigation, multiple
charts/tables, delayed responses, ACL failures and optional dependency jobs.
