# WireGuard Webmin 1.0.0 regression and security review

## Scope

The review covered the accumulated requirements through 3 August 2026: interface and peer CRUD, runtime apply/restart, disabled peers stored in `.conf`, names and client private keys in comments, QR/client export, traffic history, diagnostics, journals, IP overlap checks, free-address allocation, Authentic Theme navigation, Webmin ACLs and collector installation.

## Security findings and changes

### Request integrity

Earlier versions relied mainly on `POST`. That is not sufficient CSRF protection. The stabilized implementation adds a per-Webmin-session unpredictable token, same-origin checking, constant-time-style token comparison and POST enforcement to every state-changing endpoint. HTML forms and AJAX actions carry the same token. Tokens and limiter state are stored below `/var/webmin/wireguard` with mode `0700/0600`.

### ACL boundaries

The ACL model remains split into `view`, `manage`, `export_clients`, `diagnostics`, `logs` and `install_dependencies`. Every CGI is checked independently, including direct URL access. Client configuration and QR export require `export_clients`; diagnostics do not imply management; read-only users cannot invoke save, delete, start/stop, peer toggle, collector control or package installation.

Static endpoint coverage and a dynamic read-only ACL denial test are now part of `tests/security-regression-test.pl`.

### Enumeration and abuse resistance

State-changing operations are rate-limited per authenticated Webmin session/user and source address. Destructive operations, diagnostics, dependency installation and collector control have separate limits. Diagnostic jobs use random 256-bit identifiers, are bound to their creator, have a per-user concurrency limit, output-size limit, idle timeout and retention cleanup.

### Secrets

Private keys are never rendered into HTML, hidden fields, runtime JSON, metrics files or Webmin action logs. Export and QR remain explicitly ACL-protected. The accepted design still stores client private keys in `.conf` comments and in configuration backups, so those files remain sensitive and are forced to mode `0600`.

## Configuration parser and write safety

- Interface names are constrained to the Linux/WireGuard 15-character form used by the module.
- Configuration writes reject symbolic-link targets, NUL bytes, empty content, oversized files and more than one `[Interface]` section.
- The exact temporary file is parsed again before it can replace the live file.
- Writes use a same-directory exclusive temporary file, flush/sync, atomic rename, directory sync and final mode `0600`.
- Optimistic digest checking rejects stale forms after a manual or concurrent edit.
- A backup is mandatory before modifying an existing file. Backup names are collision-resistant and retention is bounded.
- Unknown directives and comments in an edited section are preserved. Unedited sections remain byte-for-byte unchanged. Known fields inside an edited section are intentionally normalized; exact whitespace placement inside that edited section is not guaranteed.
- Disabled peer containers, repeated hook commands, IPv4/IPv6, client metadata and public/private-key comments are covered by regression tests.
- A randomized 150-iteration parser/preservation test and malformed/symlink rejection tests were added.

## Metrics collector reliability

Earlier history files could grow until periodic retention compaction, and aggregate storage had no hard limit. The stabilized implementation adds:

- a singleton collector lock;
- maximum points per interface/peer;
- maximum bytes per history file;
- maximum aggregate metric storage;
- retention compaction and oldest-history eviction only when required;
- atomic `runtime.json` and `health.json` snapshots;
- explicit health data containing timestamp, PID, storage and configured ceiling;
- an ACL-protected collector panel for start, stop and restart;
- systemd `MemoryMax=96M`, `MemorySwapMax=32M`, `CPUQuota=10%`, `TasksMax=32`, low priority and idle I/O scheduling;
- systemd filesystem/kernel hardening and a private temporary directory.

Runtime status remains usable through a throttled cache refresh if the service is unavailable. Persistent history requires the service.

## UI/UX review

- Interface and peer names remain the primary navigation links; redundant “Open” actions are not used.
- Active/disabled peer state is color-coded separately from handshake freshness.
- Start, stop, restart, deactivate and delete actions have distinct semantics and confirmations.
- Russian restart labels were shortened to “Перезапустить”; malformed “Вернуться к Отмена/Вернуться” strings are regression-tested.
- Collector health and storage limits are visible on the module index, with management buttons only for users with `manage` ACL.
- Static configuration is rendered first; runtime/history data remain asynchronous.

## Test suite

The complete suite validates Perl syntax for all CGI/library/service files, parser round trips, randomized preservation, IP allocation and overlap, key derivation and client configuration, atomic writes, `SaveConfig` protection, UTF-8 JSON under MiniServ, Authentic Theme JavaScript, API routing, peer actions, CSRF/ACL coverage, diagnostic lifecycle and forced stop, fresh installation, bounded collector history, service hardening and UI labels.

## Accepted residual risks

- `PreUp/PostUp/PreDown/PostDown` are root shell commands by WireGuard design. Any account with `manage` ACL must therefore be treated as root-equivalent for this module.
- Client private keys and backups are deliberately stored server-side by requirement. Filesystem/root compromise exposes them.
- The module preserves unknown data but normalizes known lines in the section being edited. It does not promise a byte-identical edited section.
- Availability still depends on Webmin/MiniServ, systemd and the configured external WireGuard utilities.

## Collector lifecycle and retention addendum

The collector shutdown path was reworked after a real systemd stop timed out and
required SIGKILL. The main process no longer blocks in a pipe read or a long
sleep: the `wg show all dump` child is supervised through a non-blocking pipe,
TERM is checked at sub-second intervals, and history compaction checks the stop
flag while scanning and rewriting files. Interrupted compaction never replaces
the original history file.

Collector settings are normalized by a dependency-free shared library and
fingerprinted. The running fingerprint is written to `health.json`; the Webmin
page compares it with the currently saved configuration and displays an
explicit restart warning when they differ.

Retention, maximum points, per-file bytes and aggregate history bytes are now
applied immediately on collector startup. The compactor uses two passes and
constant-size buffers rather than storing retained JSON lines in memory. The
aggregate limit is enforced across all peer and interface histories, and the
before/after byte counts are exposed in collector health data.

Regression coverage includes TERM during a blocked `wg` command, TERM during a
deliberately slowed compaction, preservation of the original file on interrupted
compaction, reduced retention, reduced point count, reduced per-file size and
reduced aggregate size.

## Client export navigation addendum

The client configuration and QR viewer CGI programs remain ordinary Webmin
pages (`ui_print_header`/`ui_print_footer`). Their controls now use normal
same-origin module links so Authentic Theme can perform its standard SPA
navigation and keep the Webmin shell. Only the raw `.conf` attachment bypasses
SPA navigation. The QR image source is generated with the module/webprefix URL
helper rather than a document-relative URL.

Regression coverage verifies:

- the viewer CGI programs emit Webmin page headers and footers;
- viewer links do not force `window.location.assign()`;
- the raw attachment keeps explicit direct-download behaviour;
- the embedded SVG uses a module-absolute URL.


## 1.0.0 release gate

The stable release additionally verifies version consistency, explicit WBM
package contents, safe removal of only module-managed systemd units,
preservation of operational data on uninstall, absence of common secret
patterns in production files and reproducible release checksums.
