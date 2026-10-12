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
