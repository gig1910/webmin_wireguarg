# Installation and upgrade

## Install

1. Install WireGuard tools and Webmin.
2. Download `webmin-wireguard-0.2.0.wbm.gz`.
3. In Webmin open **Webmin Configuration → Webmin Modules**.
4. Install from the downloaded file and grant access only to intended users.
5. Open **Network → WireGuard VPN**.
6. Review command paths and storage limits in module settings.

The installer creates and enables `webmin-wireguard-stats.service` only when no
foreign same-named unit exists. It creates `/var/webmin/wireguard` with
restricted permissions and takes an initial runtime snapshot.

## Upgrade

Back up WireGuard configuration first:

```bash
sudo tar -C /etc -czf \
  /root/wireguard-before-webmin-upgrade-$(date +%F-%H%M%S).tar.gz \
  wireguard
```

Install the newer WBM over the existing module. Upgrades preserve:

- `/etc/wireguard/*.conf`;
- `/etc/webmin/wireguard/config`;
- metrics history, diagnostics state and backups;
- systemd drop-ins.

Only the managed metrics collector may be restarted when its unit changes.
WireGuard interfaces are not restarted by the installer.

## Analytics prerequisites

Persistent peer analytics uses `/usr/bin/python3` and standard-library `sqlite3`.
The collector manages `stats/analytics.sqlite3` with WAL and restricted access.
Back up the existing statistics directory before upgrading, particularly to
preserve legacy JSONL files for removed peers. To export Prometheus textfiles,
create one of the supported node_exporter textfile directories and configure
output path, interval and metric selection in Webmin. No WireGuard interface
restart is needed; only the statistics collector may be restarted.

See `docs/ANALYTICS.md` or `docs/ANALYTICS.ru.md`.

## Verify

```bash
systemctl status webmin-wireguard-stats.service --no-pager
ls -l /var/webmin/wireguard/stats/runtime.json
cat /var/webmin/wireguard/stats/health.json
```

## Uninstall

Webmin removal disables and removes only a unit recognized as module-managed.
WireGuard configuration, module settings, backups and collected history are
kept intentionally. Remove them manually only after reviewing their contents.

## Installed build identity

Each `./scripts/build-release.sh` run stamps an independent build version:
`<release>+<UTC timestamp with nanoseconds>.g<Git SHA>` (with `.dirty` when tracked source modifications are present). The `dist/webmin-wireguard-<build-version>.wbm.gz` filename is unique per build, and `module.info` in that archive contains the build version; the source checkout's release `VERSION` stays unchanged. The packaged `build.info` records the full commit SHA and UTC build time. Webmin displays this identity below the page heading on Interfaces, Analytics, interface details and peer details. `X-WireGuard-Webmin-Build` in JSON CGI responses can be used to verify deployment without relying on browser caches. A source checkout without a generated archive displays an explicit unstamped marker.

**Always select the new build-specific `.wbm.gz`**, not an older `webmin-wireguard-0.2.0.wbm.gz` from a previous build. After installation verify that the build string on the Webmin page matches the filename. Installation does not restart live WireGuard interfaces; the separate metrics collector may restart when its unit changes.
 
## Scheduled local GeoIP database updates

GeoIP requires a periodically refreshed local database. Install the distribution `geoipupdate` and `mmdb-bin` packages, obtain a MaxMind account ID and license key, and keep them in `/etc/GeoIP.conf` with mode `0600` (not in the WireGuard module config). The file must contain `EditionIDs GeoLite2-City GeoLite2-Country` to fetch both city and country datasets. Open an existing peer's WHOIS/GeoIP block to inspect database age and enable the **vendor-supplied** `geoipupdate.timer` using the protected Webmin button, if it is disabled. The module does not install competing jobs or touch an administrator's timer on uninstall. GeoLite2 downloads depend on MaxMind credentials and network availability.

### Webmin package installation for WHOIS and GeoIP

On a peer detail page, a user with the **Install dependencies** ACL may choose **Install WHOIS and GeoIP components**. After explicit confirmation, Webmin runs apt-get for the fixed set: `geoipupdate mmdb-bin geoip-bin geoip-database whois`. The legacy country database works immediately without MaxMind credentials; modern GeoLite2 City still requires its own key in `/etc/GeoIP.conf`. Package operations are not performed on ordinary page views and do not restart WireGuard.
