# Changelog

All notable changes to this project are documented here.

## [1.0.0] - 2026-08-03

### Added

- First stable release.
- Reproducible release builder, WBM manifest and GitHub Actions workflows.
- Bilingual project documentation, installation, ACL, security and release
  guides.
- Safe uninstall regression: foreign same-named systemd units and operational
  data are preserved.
- Release-version consistency and package-content checks.

### Security

- Final regression of Webmin ACL boundaries, CSRF tokens, same-origin checks,
  request throttling, diagnostic job ownership, atomic writes and bounded
  collector storage.
- Release artifacts are built from an explicit allowlist and scanned for common
  secret patterns before packaging.

### Changed

- Version promoted from the `0.4.x` stabilization series to `1.0.0`.
- Installation and removal hooks now follow the same ownership rule for the
  managed collector unit.

## [0.4.5] - 2026-08-03

- Kept client configuration and QR viewers inside the normal Webmin/Authentic
  Theme shell.
- Kept raw `.conf` downloads separate from SPA and clipboard handlers.

## [0.4.4] - 2026-08-03

- Made collector shutdown interrupt blocked `wg`, sleep and compaction.
- Applied reduced retention, point and byte limits to existing history at start.
- Added collector settings fingerprints and restart warnings.

## [0.4.3] - 2026-08-03

- Fixed Webmin menu visibility through the required `install_check.pl` result.

## [0.4.2] - 2026-08-03

- Preserved settings, history and systemd drop-ins during upgrades.
- Refused to overwrite foreign same-named collector units.
- Added systemd-backed collector status and console output for control actions.
- Removed the client-private-key column from peer lists.

## [0.4.0] - 2026-08-03

- Completed the security, ACL, parser, collector and UI regression.
- Split the shared library by responsibility.
- Added CSRF, same-origin checks, rate limits, atomic validated writes, bounded
  backups and bounded metrics history.

## [0.3.16] - 2026-08-03

- Fixed fresh-install collector startup and added a missing-cache runtime fallback.

## [0.3.0–0.3.15] - 2026-08-02

- Stabilized asynchronous state loading, traffic graphs, diagnostics, QR export,
  peer enable/disable, free-address allocation, overlap validation, journals,
  Authentic Theme navigation and MiniServ JSON handling.

## [0.2.0] - 2026-08-02

- Initial interface/peer CRUD, client export, live traffic and diagnostics test
  release.
