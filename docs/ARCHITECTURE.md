# Architecture

Version 1.0.0 replaces the former 1,800-line shared library with a compatibility facade and responsibility-oriented internal modules.

- `wireguard-lib.pl` — Webmin bootstrap and compatibility loader.
- `lib/security-lib.pl` — ACL checks, CSRF integrity, same-origin validation and request throttling.
- `lib/ip-lib.pl` — CIDR parsing, overlap detection, free-address allocation and client route resolution.
- `lib/command-lib.pl` — command paths, bounded command execution and optional dependency handling.
- `lib/config-lib.pl` — loss-aware configuration parser, key handling, backups and atomic writes.
- `lib/runtime-lib.pl` — runtime dump parsing and start/stop/apply/restart operations.
- `lib/api-ui-lib.pl` — JSON transport, Webmin URLs, formatting and action forms.
- `lib/metrics-lib.pl` — runtime cache, history reads and traffic graph/poller rendering.
- `lib/collector-config-lib.pl` — dependency-free normalization and fingerprinting shared by Webmin CGI code and the standalone collector.
- `stats-collector.pl` — bounded, singleton background metrics collector.
- `diagnostic-worker.pl` — isolated asynchronous diagnostic job worker.

The split deliberately keeps functions in the Webmin module package. Existing CGI files therefore remain compatible while code ownership and tests are separated by concern. A later migration to namespaced Perl packages can be done without changing the CGI contract.


## Persistence and trust boundaries

- `/etc/wireguard/*.conf` is the authoritative configuration.
- `/etc/webmin/wireguard/config` contains module settings.
- `/var/webmin/wireguard` contains bounded runtime state, history, backups,
  CSRF tokens, rate-limit state and diagnostic jobs.
- Webmin ACL checks occur in every CGI endpoint.
- External commands are invoked through fixed/configured executable paths with
  argument arrays and timeouts.
