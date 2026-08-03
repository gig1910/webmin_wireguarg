# Security policy

## Supported versions

Security fixes are provided for the current stable release. Upgrade to the
latest release before reporting a problem that may already be fixed.

## Reporting a vulnerability

Use GitHub private vulnerability reporting in the repository **Security** tab.
Do not create a public issue for an exploitable vulnerability.

Include:

- module and Webmin versions;
- Linux distribution and systemd version;
- exact ACL assigned to the affected Webmin user;
- a minimal reproduction using synthetic keys and addresses;
- expected and actual behaviour;
- relevant logs with secrets removed.

Never submit real WireGuard private keys, preshared keys, full production
configuration files, session cookies, CSRF tokens or public server credentials.

## Security model

- Webmin authentication is the outer trust boundary.
- Every CGI checks its own ACL; menu visibility is not treated as authorization.
- State-changing actions require POST, a session-bound CSRF token and request
  throttling.
- `manage` is root-equivalent because wg-quick hook commands execute as root.
- Client configuration/QR export is separately controlled by `export_clients`.
- Configuration writes are validated, backed up and atomically replaced.
- Metrics and diagnostic storage are bounded and protected with restrictive
  permissions.

See [docs/SECURITY-REVIEW.md](docs/SECURITY-REVIEW.md).
