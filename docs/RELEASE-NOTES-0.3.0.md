# WireGuard VPN for Webmin 0.3.0

This minor release consolidates the Webmin/Authentic Theme administration UI
and improves peer management, network information and diagnostics.

Highlights:

- unify action colors and icon/button components across interface and peer pages;
- share navigation, collapsible panels and grouped module settings in English and Russian;
- present complete IP/CIDR and endpoint values consistently in tables;
- improve IPv4/IPv6 endpoint sorting and on-demand WHOIS/GeoIP inspection;
- support local GeoLite2 City, per-IP city observations, short city codes and
  manual per-CIDR city overrides in the network directory;
- show city codes next to country and IP in peer and activity tables and
  retain aligned fixed-position peer action controls;
- consolidate analytics event tables and frontend controllers;
- add browser/UI regression coverage, including sorting and theme contracts;
- retain the existing authenticated API, ACL and CSRF protections.

This package is intended as an in-place upgrade. Back up the current module
configuration before installing, and verify its pages in Authentic Theme.
Automated tests and packaging checks are run by scripts/build-release.sh;
browser and deployment verification remain separate steps.

City names are approximate GeoIP data. Short codes such as MSK are UI
abbreviations, not standardized ISO city identifiers. Automatic City results
require the MaxMind GeoLite2-City.mmdb dataset (not Country-only) and are
cached on explicit WHOIS/GeoIP lookups. Existing SQLite installations gain
city fields through a non-destructive migration.
