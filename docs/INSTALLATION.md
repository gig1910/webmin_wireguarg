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
