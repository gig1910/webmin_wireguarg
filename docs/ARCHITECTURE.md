# Architecture

Version 1.0.0 replaces the former 1,800-line shared library with a compatibility facade and responsibility-oriented internal modules.

- `wireguard-lib.pl` — Webmin bootstrap and compatibility loader.
- `lib/security-lib.pl` — ACL checks, CSRF integrity, same-origin validation and request throttling.
- `lib/ip-lib.pl` — CIDR parsing, overlap detection, free-address allocation and client route resolution.
- `lib/command-lib.pl` — command paths, bounded command execution, firewall preflight and optional dependency handling.
- `lib/firewall-ufw-lib.pl` and `wg-firewall-hook.pl` — standalone, tagged UFW rules managed by wg-quick lifecycle hooks (not tied to the Webmin CGI process).
- `lib/config-lib.pl` — loss-aware configuration parser, key handling, backups and atomic writes.
- `lib/runtime-lib.pl` — runtime dump parsing and start/stop/apply/restart operations.
- `lib/api-ui-lib.pl` — JSON transport, Webmin URLs, formatting and action forms.
- `lib/metrics-lib.pl` — runtime cache, history reads and traffic graph/poller rendering.
- `lib/collector-config-lib.pl` — dependency-free normalization and fingerprinting shared by Webmin CGI code and the standalone collector.
- `stats-collector.pl` — bounded, singleton background metrics collector.
- `diagnostic-worker.pl` — isolated asynchronous diagnostic job worker.
- `lib/subprocess-lib.pl` — bounded nonblocking subprocess executor used by CGI and collector.
- `dependency-worker.pl` — detached and serialized apt installer with session-bound status in its CGI.
- `network_store.py` — separate WHOIS prefix, exact-IP GeoIP and manual network-icon domain; shares the existing SQLite file with analytics without changing the peer identity model.
- `analytics-store.py` — SQLite analytics entry point and shared connection owner; delegates network directory operations to `network_store.py`.

The split deliberately keeps functions in the Webmin module package. Existing CGI files therefore remain compatible while code ownership and tests are separated by concern. A later migration to namespaced Perl packages can be done without changing the CGI contract.


## Persistence and trust boundaries

- `/etc/wireguard/*.conf` is the authoritative configuration.
- `/etc/webmin/wireguard/config` contains module settings.
- `/var/webmin/wireguard` contains bounded runtime state, history, backups,
  CSRF tokens, rate-limit state and diagnostic jobs.
- Webmin ACL checks occur in every CGI endpoint.
- External commands are invoked through fixed/configured executable paths with
  argument arrays and timeouts.

## Network identity versus geographic observations

A WHOIS CIDR describes registry ownership and may cover IP addresses in different
countries. Local GeoIP country observations are therefore cached by **exact
canonical IP** in `geoip_cache`, not propagated to a WHOIS prefix. The manual
`network_icons` table overrides visual labels/icons only. The network lookup
API exposes `country_source`, `whois_country`, and `geoip_country`, with local
GeoIP taking priority for the individual observed address and WHOIS as fallback.
No external WHOIS request is triggered by opening the peer table.

The network directory currently shares `analytics.sqlite3` for compatibility.
The code boundary has been separated first; moving files or databases requires
a separately tested migration and must not silently erase existing entries.
