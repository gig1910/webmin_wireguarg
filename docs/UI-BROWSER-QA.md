# WireGuard UI: browser acceptance checklist

This checklist separates **automated component verification** from **real Webmin /
Authentic Theme verification**. A screenshot of the isolated component gallery
does not establish visual correctness on an installed server.

## CI evidence and tested package

The `Regression and Release Gate` workflow runs the full regression suite,
checks the release manifest, builds the WBM, checks the unpacked module with the
Webmin test stubs, and renders a dark/light HTML component gallery in Chrome.
On successful `main` builds, the workflow publishes a short-lived GitHub
Actions artifact, `webmin-wireguard-verified-<commit>`, containing:

- the versioned `.wbm.gz` and source archive;
- release notes plus `SHA256SUMS` and `SHA512SUMS`;
- `UI-COMPONENTS.html` and (when Chrome is installed) `UI-COMPONENTS.png`.

Verify archive checksums and the `build.info` commit against the workflow run.
The gallery covers shared SVG, color roles, action bars, compact peer rows,
summary cards, field controls, and collapsed service/danger panels. It does
**not** include the actual Authentic Theme CSS or real WireGuard state.

## Safe verification environment

Install the WBM only on a disposable test Webmin instance or an explicitly
approved test server. Do **not** deploy to the production VPN as part of CI.
Keep production interface/peer configuration, systemd services, firewall rules,
and collector state untouched during this UI review.

Use the same browser and Authentic Theme version as the target installation.
Capture desktop views around 1600 × 900 and 1280 × 720, checking both light
and dark appearances. Test RU and EN localization where available.

Before sharing screenshots of client configuration, private keys, preshared
keys, or QR codes, redact sensitive material. Do not put these in CI artifacts.

## Read-only navigation and visual inspection

| Page | Checkpoints |
| --- | --- |
| Dashboard / Interfaces | Status chips, compact start/stop glyphs, matching tooltips, primary green Add, secondary navigation, collapsed collector and dependency panels |
| Interface / Peer table | Distinct name/history/actions columns, centered fixed-size icons, consistent country and network badges; no network question mark for an absent Endpoint |
| Peer editor | Save and activation controls share a row, PSK removal is warning-colored, diagnostic controls are collapsed and readable, form labels and hints align |
| Analytics / Graph | Summary cards are labelled, tabs and filters align, chart remains usable on narrow screens |
| Analytics / Events | Distinct interface/name/short PublicKey cells, fixed-width timestamp and Endpoint, no horizontal overlap |
| Network directory | Edit icon prefills the form, flags match country codes, row actions have hints, cache maintenance is collapsed by default |
| WHOIS / GeoIP modal | Lookup occurs only on user request; flag matches ISO code; no fabricated city if Country database only; **Close** and Escape dismiss and restore focus |
| Peer activity/history | Empty states are readable, all tab changes work under SPA navigation, repeated navigation does not create duplicate polling |
| Client config / QR | Navigation works; exported secrets are not included in screenshot evidence |
| Journal, dependencies, settings | Controls match shared design where module-owned; stock Webmin `config.cgi` remains managed by Webmin itself |

## Interactions and safety checks

1. Use keyboard Tab/Shift+Tab to navigate the icon-only buttons. Check their
   focus outline and accessible label. Hover each to verify the hint.
2. Open and close the read-only WHOIS/GeoIP modal, including Escape, and check
   that repeated page navigation does not leave stale overlays.
3. Confirm the cache and analytics maintenance sections start **closed** after
   a fresh page load. Opening a section must not modify the database.
4. On a **disposable test dataset only**, exercise modal Cancel, Escape and
   typed confirmation for destructive actions; verify the backend still rejects
   forged GET and CSRF-less POST requests.
5. Check client-side form feedback for invalid IPv4/IPv6 CIDR, port 0 and
   65536, malformed Endpoint, and trailing empty lines in a multi-line list.
   Backend checks remain authoritative.
6. Verify controls do not move or duplicate after navigation inside Authentic
   Theme. Review browser Console and Network for failed requests and malformed
   JavaScript.

When a visual discrepancy is found, report the installed `build.info` version,
page URL without secret parameters, browser/Authentic Theme version, viewport
size, screenshot with sensitive fields redacted, and the console error if any.

## Exit criteria

Do not mark integration as verified until **both** the automated CI/release
gate and the real Authentic Theme checklist pass. An isolated Chromium component
gallery is an intermediate consistency check, not proof of installed UX.
