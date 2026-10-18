# Test suite audit — 2026-10-18

Scope: full GitHub tree under `tests/` on `main` (57 Perl/Python/JavaScript/shell files including the runner, a fixture and the JavaScript helper), plus `.github/workflows/regression.yml`. This is a static audit; no tests were executed during this review.

## Summary

- The existing runner invokes the main Perl, Python and shell regressions; `ui-behavior-test.js` is invoked indirectly by `ui-behavior-test.pl`. `install-dependency-csrf-fixture.pl` is an indirectly invoked fixture, not a standalone test.
- Release-specific literals in `build-info-test.pl`, `async-js-test.pl`, `api-json-test.pl` and `miniserv-json-test.pl` were replaced with the runtime module version in preceding commits.
- `network-icons-request-test.pl` contained a misleading `0.2.0+fixture` navigation value. It was changed to a clearly non-version fixture value.
- The most significant ongoing maintenance cost is source-text/regex testing of exact JavaScript and HTML implementation, rather than rendered semantics and behavior.
- Fixed IP addresses, numeric counters, timestamps, dummy public keys and attack payloads are *legitimate fixtures*. Do not mechanically eliminate them.

## Findings and priorities

| Priority | Area | Evidence / action |
| --- | --- | --- |
| P0 | Release version regressions | Version markers must come from `VERSION` / `$WIREGUARD_WEBMIN_VERSION`; keep `version-consistency-test.pl` as the cross-file invariant. Add a CI guard against old release numbers in assertions, excluding fixtures. |
| P1 | HTML and CSS implementation coupling | `analytics-ui-test.pl` and `ui-theme-contract-test.pl` assert specific string fragments and markup selectors. Multiple false positives were triggered by extracting common navigation and adopting semantic actions. Replace these assertions incrementally with rendered DOM/component behavior tests. |
| P1 | JavaScript controller coupling | `network-icons-ui-test.pl`, `diagnostic-js-test.pl`, `interface-controller-root-test.pl`, `index-page-ui-test.pl` and related lifecycle tests mix legitimate behavior checks with regex checks of function bodies and selector spellings. Keep lifecycle tests but move fragile assertions to DOM-driven tests. |
| P1 | Source slicing and eval | `network-icons-request-test.pl` extracts the CGI dispatch by exact sentinel strings and evals it. That test will break on safe reorganization. Extract dispatch into a callable module function with explicit dependencies, then exercise it without source surgery. |
| P1 | Full browser/Webmin integration | CI renders an isolated component gallery, not real Authentic Theme/Webmin. Integration checks on an installed disposable Webmin are still required, especially for installation, ACL, navigation and SPA disposal. |
| P2 | Test utilities duplication | Several tests independently extract inline scripts, build mock DOM nodes and inspect source text. Introduce shared helpers for extracting scripts and browser fixtures only where duplication is meaningful. |
| P2 | UI contract breadth | Keep shared visual/semantic assertions in one authoritative location; prefer accessibility roles, state transitions and outcomes over exact CSS class strings except where theme class mapping is the actual requirement. |
| P2 | Runner and toolchain | `run-tests.sh` is a manual invocation list. Add a lightweight test-discovery or manifest-coverage check to prevent new test files being silently excluded, while respecting helper fixtures and JS indirectly invoked by Perl. |
| P3 | Test warning hygiene | Existing Perl “used only once” messages in DNS, firewall and PresharedKey tests merit separate review; they are warnings, not failed tests. |

## Recommended conversion strategy

1. Preserve genuine security checks: POST/CSRF/ACL, data isolation, command invocation boundaries and destructive-operation confirmations.
2. Decouple tests from release numbers (completed for known live assertions) and from layout implementation, keeping exact markup checks only for deliberate HTML/CSS contracts.
3. Make UI behavioral tests verify rendered controls, navigation targets, keyboard use, repeated initialization and request cancellation.
4. Refactor production CGI dispatch into testable units before replacing source-slicing tests.
5. Keep package build/smoke checks and add a disposable Webmin/Authentic Theme integration gate before declaring installation safe.

## Audit limitations

This review inspected the source of all test-language files, the runner, repository tree and the CI workflow; it is not a claim of new test execution or complete behavioral coverage. Static pattern counts are triage signals, not a count of defects. The user-provided successful `0.2.0` build is distinct from a verified `0.3.0` build.
