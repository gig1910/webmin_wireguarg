# Configuration reference

Module settings define WireGuard directories, external command paths, runtime
timeouts, graph intervals, diagnostic limits, backup retention and metrics
storage ceilings.

Collector settings are loaded when `webmin-wireguard-stats.service` starts. If
the Webmin page reports that saved settings differ from running settings,
restart the collector. Reduced history retention and byte/point limits are
applied to existing history during collector startup.

Important defaults:

- configurations: `/etc/wireguard`;
- state: `/var/webmin/wireguard`;
- backups: `/var/webmin/wireguard/backups`;
- runtime/history: `/var/webmin/wireguard/stats`;
- diagnostics: `/var/webmin/wireguard/diagnostics`;
- live refresh: 5 seconds;
- per-history-file ceiling: 8 MiB;
- aggregate history ceiling: 256 MiB;
- configuration file ceiling: 4 MiB.

The module stores names and optional client-export metadata in comments so the
standard WireGuard configuration remains the source of truth.

## DNS fields when creating or editing an interface

- **Host DNS (wg-quick)** maps to `DNS = ...` under the local `[Interface]`.
  It changes the host's resolver when that tunnel starts; `wg-quick` on Linux
  requires an executable `resolvconf` command in its PATH. This field is
  optional and should normally be empty on VPN servers. With a nonempty value,
  the module checks the dependency before start or restart, including before
  taking down an active interface for restart. Save-only keeps working so
  previously stored configurations can still be edited or prepared offline.
- **DNS in exported client configurations** is stored separately as the
  `#ClientDNS` metadata comment. It appears as `DNS = ...` in generated
  client configurations only; it does not configure a DNS service or the
  server's resolver. A per-peer client DNS value overrides the interface
  default.

Neither field provisions a DNS server or changes system DNS automatically.

## Persistent peer analytics and Prometheus

The collector still takes live snapshots and maintains a short high-frequency
JSONL cache (one hour by default, capped by `stats_history_retention`) for the
original runtime interface graph. Independently, the standard-library
`analytics-store.py` backend writes a persistent SQLite database at
`stats_dir/analytics.sqlite3`, with restrictive permissions. Each peer is
identified by the SHA-256 fingerprint of its WireGuard **public** key, never
by its name, IP address, or a private key. Disabling or deleting a configured
peer does not delete its records. Replacing the key creates a distinct identity.

Every collector sample updates 10-minute traffic buckets from cumulative
counter deltas. Custom filtering includes all 10-minute buckets intersecting
the requested interval, even when its boundaries are not aligned to 10 minutes.
Small sample intervals crossing bucket boundaries are allocated
proportionally (an approximation). Counter resets and missing samples are
recorded as events. Activity events include first observation, inactive/active
transitions, endpoint changes and newly observed handshake timestamps.
On first sight of a known public key, pre-existing raw JSONL samples are
imported into the SQLite buckets once, without deleting the source file.
Unrecognized historical JSONL files belonging to peers deleted before migration
cannot be mapped back to a public key from their irreversible filename hashes;
these files must be retained separately by an administrator if historical
recovery is required. Never map historical data by reused addresses or names.

The endpoint is the observed remote IP:port, not verified geographic location.
An endpoint change alone cannot prove a connection or disconnection.

Persistent retention defaults to 365 days and is independent of high-frequency
JSONL retention. The analytics page displays up to 20,000 traffic buckets and 2,000 events
per query and explicitly warns when results are truncated. Narrow the requested
period to inspect earlier activity. The page also displays database size.

SQLite WAL transactions serialize writes and maintenance,
including browser-initiated deletions. The SQLite backend uses only Python 3
standard-library modules and does not require Perl DBI/DBD::SQLite.

Prometheus textfile export is **off by default**. Configure the supported
metric groups (traffic, peer_state, handshake, events, collector) using
per-group Webmin settings, interval,
and target file under either
`/var/lib/node_exporter/textfile_collector/` or
`/var/lib/prometheus/node-exporter/`. The directory must exist.
Output is an atomic UTF-8 `.prom` replacement; peer labels are public-key
fingerprints, never private keys, IPs, endpoints, or human-readable peer names.
Retained traffic is exported as a **gauge** (not a lifetime counter), since
purging history can decrease it. A collector restart applies changes.

## Peer traffic consumption by time

The peer details page offers rolling 15-minute, 1-hour, 6-hour, 24-hour and
custom start/end date-time filters. It reads the existing collector JSONL
history by peer public key via `history.cgi?name=...&peer=...&from=...&to=...`.
Times in API requests are UNIX epoch seconds; the browser displays local time.
Custom ranges are bounded to 90 days, but data availability is limited by
the configured collector retention (24 hours by default), point and byte
ceilings. A response is capped at 20,000 samples and marked truncated when
the cap is reached. No new database or collection processes are introduced.

Period totals are sums of monotonic, consecutive RX/TX counter changes within
the recorded samples. They do *not* represent the lifetime counters displayed
by WireGuard. After a peer counter reset, the unknown gap is excluded and a
warning is shown. The observed first and last sample timestamps are displayed
so incomplete coverage or an empty interval is never mistaken for exact billing
data. Period filtering is read-only and never changes retention settings.

## Automatic UFW port lifecycle (opt-in)

An interface may opt into UFW firewall management. For example, with
`ListenPort = 38250` the generated configuration includes an internal
`PostUp` hook to allow UDP/38250 and a `PostDown` hook to remove
only the tagged rules belonging to this particular interface.
The hooks execute under `wg-quick` whether started by Webmin or by
`wg-quick@<name>.service`.

- Runtime start/restart independently rechecks UFW before wg-quick executes;
  an unavailable firewall never causes a preflight-induced tunnel shutdown.
- The same automatically managed UDP port cannot be assigned to two interfaces.
- This feature supports **active UFW** only; it does not enable UFW or
  replace nftables/firewalld rules. Keep the option disabled for an unmanaged
  firewall. Both a fixed ListenPort and `/usr/sbin/ufw` are required.
- Rules carry a `webmin-wg:<interface>` ownership comment. Cleanup looks
  up that exact comment in numbered UFW rules, never issuing a broad
  `ufw delete allow <port>/udp` that could remove a manually created rule.
- The module retains the cleanup hook after opting out so an already-open
  managed rule can be removed at the next normal stop.
- Changing the ListenPort or the management setting is not a hot apply;
  use save-only followed by a full stop/start or Save and restart.
- UFW rules are persistent. An unclean shutdown/power loss may leave an
  orphaned tagged rule until the interface is started again and then stopped;
  audit such rules after abnormal shutdowns.
- External firewalls, cloud security groups, routers and port forwarding
  are outside the scope of this setting.
