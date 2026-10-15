#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(tr -d '[:space:]' < VERSION)

perl tests/version-consistency-test.pl

# Manifest must be unique, normalized and complete.
DUP=$(sed '/^$/d' MANIFEST.wbm | sort | uniq -d)
[ -z "$DUP" ] || { echo "Duplicate manifest entries:" >&2; echo "$DUP" >&2; exit 1; }
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in /*|*'..'*) echo "Unsafe manifest path: $path" >&2; exit 1;; esac
  [ -f "$path" ] || { echo "Missing manifest path: $path" >&2; exit 1; }
done < MANIFEST.wbm

# Production files must not contain common private-key or host artifacts.
# Synthetic values under tests/ are intentionally excluded.
if sed '/^$/d' MANIFEST.wbm | xargs grep -nEI \
  'BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|(^|[^A-Za-z])PrivateKey[[:space:]]*=[[:space:]]*[A-Za-z0-9+/]{40,}={0,2}|vps\.kulikow\.ru|k\.alex\.serg@gmail\.com' \
  >/tmp/webmin-wireguard-secret-scan.$$ 2>/dev/null; then
  cat /tmp/webmin-wireguard-secret-scan.$$ >&2
  rm -f /tmp/webmin-wireguard-secret-scan.$$
  echo "Potential secret or private deployment data found" >&2
  exit 1
fi
rm -f /tmp/webmin-wireguard-secret-scan.$$

# No world-writable production files and all CGI/hooks are executable.
while IFS= read -r path; do
  [ -n "$path" ] || continue
  mode=$(stat -c '%a' "$path")
  case "$mode" in *2|*3|*6|*7) echo "World-writable file: $path ($mode)" >&2; exit 1;; esac
  case "$path" in
    *.cgi|acl_security.pl|install_check.pl|postinstall.pl|uninstall.pl|postuninstall.pl|stats-collector.pl|diagnostic-worker.pl|wireguard-lib.pl)
      [ -x "$path" ] || { echo "Executable bit missing: $path" >&2; exit 1; } ;;
  esac
done < MANIFEST.wbm

# Required release documentation.
for path in README.md README.ru.md CHANGELOG.md LICENSE SECURITY.md \
            "docs/RELEASE-NOTES-$VERSION.md"; do
  [ -s "$path" ] || { echo "Missing release document: $path" >&2; exit 1; }
done

echo "release content checks passed"
