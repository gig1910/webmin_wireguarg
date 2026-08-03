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
