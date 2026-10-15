# WireGuard peer analytics — operations

## Storage

Live traffic keeps its original short-interval runtime updates and a short JSONL cache (one hour by default). A separate SQLite database at `/var/webmin/wireguard/stats/analytics.sqlite3` stores 10-minute usage buckets and timestamped events, with a 365-day default retention.

Each peer is identified by SHA-256 of its **public key**, never by name/IP or private key. Disabling/removing a peer does not erase its records. A different key reusing the same IP gets a separate history. Traffic is calculated from cumulative RX/TX deltas; counter resets and sampling gaps are flagged. Boundary-crossing deltas are time-proportioned estimates.

Activity is compact: the peer row preserves the last nonzero handshake time and its confirmed IP across disable/removal. The event journal only records the first IP observed during a handshake and subsequent **IP changes confirmed by new handshakes**. Routine handshakes at the same IP, source-port changes, active/inactive transitions, counter resets and gaps do not create new events. Reset/gap counts remain in 10-minute buckets.

## Migration and retention

For currently known public keys, legacy JSONL files are imported once without being deleted by the import process. Later the short-lived cache retention applies. **Back up the original stats directory before upgrading.** Legacy filename hashes for peers whose public keys were lost before migration cannot be reliably resolved. Never assign those histories by matching an IP or name.

Use `analytics_retention_days` to control automated aging. The Analytics tab supports peer/time filters, traffic charts, latest handshake/IP and compact IP-change history (20,000 buckets and 2,000 events per request, with truncation warnings). Arbitrary date bounds include intersecting 10-minute buckets.

## Maintenance

The Analytics admin section (Webmin `manage` ACL, POST/CSRF and rate limits) supports: delete before a timestamp, delete one peer by key fingerprint, purge and VACUUM. Typed `DELETE` confirmation is required for destructive operations. Before deletion, an SQLite online backup is made in `stats/backups/` (last five retained). Time-cutoff deletion preserves buckets intersecting the cutoff, and removes timestamped events precisely. WAL transactions coordinate with the running collector. Purging does not stop new observations arriving on the following cycle.

Back up a live database with SQLite's online backup rather than copying only the main DB file without its WAL.

## Prometheus and requirements

Webmin module settings expose metric selection (`traffic`, `peer_state`, `handshake`, `events`, `collector`), refresh interval, and the target `.prom` file under either `/var/lib/node_exporter/textfile_collector/` or `/var/lib/prometheus/node-exporter/`. Paths are allowlisted; the directory must exist. The exporter writes atomically, with peer public-key fingerprints as labels and no private keys/endpoints. Retained traffic is a **gauge** because deletion can decrease it.

Requires `/usr/bin/python3` with its built-in `sqlite3` module; no Perl DBI dependency. Settings require restarting the collector, not the live VPN. Verify using `python3 tests/analytics-store-test.py`, `./tests/run-tests.sh` and `stats/health.json` (`analytics_error`).

## Finding the history in Webmin

Open **Networking → WireGuard VPN → Analytics** to inspect all peers, including archived peers. An interface page has a prominent analytics link, each peer row has a **History** link bound to that peer's public-key fingerprint, and the peer editor links to the same filtered analytics view. Reinstall the newly built Webmin package to update the UI and CGI files; restarting the metrics collector alone does not update them.

### One-time legacy event compaction

On the first collector sample after upgrading, a consistent SQLite online backup is created if old events exist. Existing `handshake_observed` events are folded into first confirmed IP and true IP changes using handshake epochs stored in event details; other old noisy events are removed transactionally. Traffic buckets and their reset/gap counters are unaffected. No network reconnection is inferred merely from a source-port change; both IPv4 and IPv6 are supported.
