# WireGuard VPN for Webmin 0.2.0

This release adds peer-level `PresharedKey` management and includes the peer
state and live-table fixes merged from PR #1.

Highlights:

- create or import a WireGuard `PresharedKey` for a peer;
- generate a PSK with `wg genpsk`;
- show only the concise `Installed / Установлен` state for an existing PSK;
- explicitly remove an existing PSK with confirmation;
- never render the stored PSK in the editor or Webmin logs;
- include the PSK automatically in generated client configurations and QR codes;
- apply active-peer changes through the existing `wg syncconf` path;
- correct peer activate/deactivate state handling under Authentic Theme;
- immediately refresh endpoint, handshake and RX/TX data;
- provide a manual runtime refresh action;
- preserve native JSON booleans across Webmin API responses.

Upgrade is in-place. The installer does not restart WireGuard interfaces or
rewrite their configuration outside actions explicitly requested in the module.
