# Changelog

## [Unreleased]

### Unified admin console UX

- Add a reusable Webmin UI foundation for inline SVG icon actions, accessible
  hints, shared toolbars, non-sensitive copy controls, compact status cards,
  collapsed danger panels and modal confirmations. Confirmation tokens are
  supplied in a popup; existing server-side CSRF, ACL and typed DELETE/CLEAR
  validation remain authoritative.
- Add a manual WHOIS/GeoIP inspector dialog directly to peer-table rows,
  reusing `peer_ip_info.cgi` (POST+CSRF+rate limiting); no automatic WHOIS
  requests are introduced by opening the interface.
- Move peer history into its own icon column and keep names separate; use
  icon-only edit and toggle actions with accessible text in tooltips.
- Align primary and secondary interface/dashboard actions, provide copy
  actions for public endpoint metadata and exported client configuration.
- Present analytics totals as labelled cards, separate interface/peer/public
  key into event columns, and collapse destructive SQLite maintenance.
- Compact PresharedKey status/removal, collapse peer diagnostics, and use
  the shared network-cache reset and row deletion interaction.
- Expand source and packaged-WBM smoke regressions for shared controls and
  the protected WHOIS/GeoIP dialog.


### Network directory navigation

- Treat navigation to `network_icons.cgi` as read-only when no mutation action
  is supplied, including Webmin/Authentic Theme requests that arrive as POST.
  Only explicit `set_icon`, `delete_icon` and `clear_cache` actions can
  mutate storage; every such request still requires POST, same-origin checks,
  a valid CSRF token and rate limiting.
- Add a regression test for read-only GET/POST navigation, blocked GET mutations,
  rejected CSRF-less POST mutations and successful authorized updates.


### Browser UI consolidation and SPA reliability

- Add `lib/ui-transport-lib.pl` for shared same-origin JSON transport,
  Content-Type validation and non-JSON error classification. Runtime, analytics,
  diagnostics, peer activity and traffic charts retain their independent
  polling, cancellation and authorization semantics.
- Move collector/dashboard UI to `lib/index-page-ui-lib.pl` and manual network
  directory UI to `lib/network-icons-ui-lib.pl`. Keep CGI entry points focused
  on ACL, server-side HTML and persistence.
- Scope dashboard and network directory DOM to unique page instances. Dispose
  runtime event listeners, collector timers and button handlers when Authentic
  Theme replaces a page.
- Add transport, rendered dashboard, dashboard/collector SPA lifecycle,
  network-editor and packaged-WBM smoke regressions.


### Shared browser components

- Consolidate chart units, Authentic Theme palette and mirrored-axis scaling
  across live interface traffic, peer usage and SQLite analytics, while
  preserving their distinct rate, sample and aggregate data models.
- Reuse text-only DOM table-row construction alongside the existing accessible
  shared sorter for peer activities and analytics event rows.
- Extract interface peer-list controller into `lib/interface-page-ui-lib.pl`
  with its existing root-scoped lifecycle, badges and peer actions.
- Extend build gates to syntax-check all `lib/*.pl`, exercise chart/table
  primitives and test the packaged controller via the WBM smoke test.
- Describe frontend module responsibilities and further reuse opportunities in
  `docs/UI-ARCHITECTURE.md`.


### UI controller isolation and legacy API retirement

- Extract analytics chart/filter/events controller into `lib/analytics-page-ui-lib.pl`
  and peer activity/diagnostics controllers into dedicated UI modules, keeping
  CGI routing and server-side data authorization independent from browser logic.
- Retire `stats.cgi`: current Webmin pages use `runtime.cgi` for live state
  and `history.cgi` for short-interval history. No production code in this
  repository calls the retired CGI; CI now checks for internal references.
  **Compatibility:** third-party clients using `stats.cgi` must migrate, as
  the old URL is no longer shipped. External consumers cannot be inferred from
  the repository and must be inventoried before server deployment.


### Domain separation

- Move network WHOIS cache and administrator icon logic into `network_store.py`
  without migrating or removing existing SQLite data.
- Store GeoIP ISO-country observations by exact IP, not by WHOIS CIDR;
  expose GeoIP/WHOIS origin separately in the lookup API and show observed
  GeoIP country codes separately in the merged network directory table.
- Use an asynchronous, ACL-bound and rate-limited dependency installation job
  with a bounded subprocess and single-installer lock.

### Reliability and security hardening

- Use one bounded, nonblocking subprocess adapter for Python/SQLite calls from
  CGI and the background collector. Drain stdout/stderr concurrently; enforce
  time, input and output limits, and terminate stalled children.
- Add regression coverage for pipe pressure, exit status, output limits,
  early stdin closure and Perl-heredoc GeoIP JavaScript interpolation.
- Add GitHub Actions tests and WBM build gate for every push and pull request.
- Require cryptographically strong randomness for CSRF tokens and diagnostic
  job identifiers; do not fall back to a predictable generator.

### Added

- On-demand WHOIS CIDR cache and independent manually assigned IPv4/IPv6 subnet icons. Live endpoint badges read local data only; a protected cache reset preserves icon assignments.
- Three peer-detail tabs for settings, consumption history, and confirmed IP activities.

### Fixed

- Corrected GeoIP/QR dependency installation confirmation to use the complete
  Webmin form lifecycle and an absolute, module-aware POST URL. Updated
  installer navigation for Authentic Theme and added a hermetic GET-to-POST
  CSRF regression for both dependency packages (including invalid and
  cross-origin submissions). Existing ACL/CSRF safeguards remain enforced.
- Preserved existing peer `PresharedKey` on ordinary saves and on toggling
  peer enabled/disabled state. Moved PSK handling into the explicit peer-save
  pipeline instead of relying on the CGI executable name (`$0`) and
  replacing shared functions at runtime.
- Restored explicit peer-form rendering for the PSK status and removal action.
  PSK values continue to be omitted from HTML and logs.
- Added round-trip configuration regressions covering preserved, imported,
  generated and removed keys, including disabled peers and MiniServ execution.

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

### Added

- On-demand WHOIS CIDR cache and independent manually assigned IPv4/IPv6 subnet icons. Live endpoint badges read local data only; a protected cache reset preserves icon assignments.
- Three peer-detail tabs for settings, consumption history, and confirmed IP activities.

### Fixed

- Corrected GeoIP/QR dependency installation confirmation to use the complete
  Webmin form lifecycle and an absolute, module-aware POST URL. Updated
  installer navigation for Authentic Theme and added a hermetic GET-to-POST
  CSRF regression for both dependency packages (including invalid and
  cross-origin submissions). Existing ACL/CSRF safeguards remain enforced.
- Preserved existing peer `PresharedKey` on ordinary saves and on toggling
  peer enabled/disabled state. Moved PSK handling into the explicit peer-save
  pipeline instead of relying on the CGI executable name (`$0`) and
  replacing shared functions at runtime.
- Restored explicit peer-form rendering for the PSK status and removal action.
  PSK values continue to be omitted from HTML and logs.
- Added round-trip configuration regressions covering preserved, imported,
  generated and removed keys, including disabled peers and MiniServ execution.

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
