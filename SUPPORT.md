# Support

For defects, open a GitHub issue and attach only sanitized information.

Useful diagnostics:

```bash
webmin --version 2>/dev/null || true
wg --version
systemctl status webmin-wireguard-stats.service --no-pager
systemctl show webmin-wireguard-stats.service \
  -p ActiveState -p SubState -p Result -p MainPID
cat /var/webmin/wireguard/stats/health.json
```

Also include the browser console/network error and the relevant lines from
`/var/webmin/miniserv.error`. Remove session data, keys and sensitive endpoints.
