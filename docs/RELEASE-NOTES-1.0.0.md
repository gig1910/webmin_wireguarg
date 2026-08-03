# WireGuard VPN for Webmin 1.0.0

First stable release after the `0.4.x` security and reliability stabilization
cycle.

Highlights:

- standard `.conf` files remain the source of truth;
- interface and peer CRUD plus runtime apply/restart;
- secure client configuration and QR export;
- live and bounded historical traffic graphs;
- asynchronous diagnostics and runtime state;
- Webmin ACL, CSRF and request-throttling enforcement;
- validated atomic writes and bounded backups;
- controlled systemd metrics collector with storage/resource limits;
- English and Russian UI/documentation;
- reproducible WBM build and full regression suite.

Upgrade from `0.4.5` is in-place. The installer does not restart WireGuard
interfaces or rewrite their configuration.
