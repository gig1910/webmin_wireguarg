# WireGuard VPN for Webmin 0.3.0

This minor release consolidates the Webmin/Authentic Theme administration UI
and improves peer management, network information and diagnostics.

Highlights:

- unify action colors and icon/button components across interface and peer pages;
- share navigation, collapsible panels and grouped module settings in English and Russian;
- present complete IP/CIDR and endpoint values consistently in tables;
- improve IPv4/IPv6 endpoint sorting and on-demand WHOIS/GeoIP inspection;
- consolidate analytics event tables and frontend controllers;
- add browser/UI regression coverage, including sorting and theme contracts;
- retain the existing authenticated API, ACL and CSRF protections.

This package is intended as an in-place upgrade. Back up the current module
configuration before installing, and verify its pages in Authentic Theme.
Automated tests and packaging checks are run by scripts/build-release.sh;
browser and deployment verification remain separate steps.
