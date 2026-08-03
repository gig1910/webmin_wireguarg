#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(tr -d '[:space:]' < VERSION)
case "$VERSION" in
  ''|*[!0-9A-Za-z.+-]*) echo "Invalid VERSION: $VERSION" >&2; exit 1 ;;
esac

./tests/run-tests.sh
./scripts/check-release.sh

BUILD="$ROOT/build"
DIST="$ROOT/dist"
STAGE="$BUILD/wireguard"
SOURCE_STAGE="$BUILD/webmin-wireguard-$VERSION"
rm -rf "$BUILD" "$DIST"
mkdir -p "$STAGE" "$DIST" "$SOURCE_STAGE"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ -f "$path" ] || { echo "Missing manifest file: $path" >&2; exit 1; }
  mkdir -p "$STAGE/$(dirname "$path")"
  cp -p "$path" "$STAGE/$path"
done < MANIFEST.wbm
find "$STAGE" -type d -exec chmod g-s {} + -exec chmod 0755 {} +

# Stable metadata gives identical archives for identical source.
EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || printf 0)}
TZ=UTC tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
  -czf "$DIST/webmin-wireguard-$VERSION.wbm.gz" -C "$BUILD" wireguard

# Verify that the installable archive contains exactly the allowlisted files.
sort MANIFEST.wbm > "$BUILD/manifest.expected"
tar -tzf "$DIST/webmin-wireguard-$VERSION.wbm.gz" | \
  sed -n 's#^wireguard/##p' | sed '/\/$/d;/^$/d' | sort > "$BUILD/manifest.actual"
cmp "$BUILD/manifest.expected" "$BUILD/manifest.actual"

# GitHub/source archive excludes generated output and VCS metadata.
find . -mindepth 1 -maxdepth 1 \
  ! -name .git ! -name build ! -name dist \
  -exec cp -a {} "$SOURCE_STAGE/" \;
find "$SOURCE_STAGE" -type d -exec chmod g-s {} + -exec chmod 0755 {} +
TZ=UTC tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
  -czf "$DIST/webmin-wireguard-$VERSION-source.tar.gz" -C "$BUILD" "webmin-wireguard-$VERSION"

cp "docs/RELEASE-NOTES-$VERSION.md" "$DIST/RELEASE-NOTES-$VERSION.md"
touch -d "@$EPOCH" "$DIST/webmin-wireguard-$VERSION.wbm.gz" \
  "$DIST/webmin-wireguard-$VERSION-source.tar.gz" "$DIST/RELEASE-NOTES-$VERSION.md"
(
  cd "$DIST"
  sha256sum "webmin-wireguard-$VERSION.wbm.gz" \
            "webmin-wireguard-$VERSION-source.tar.gz" \
            "RELEASE-NOTES-$VERSION.md" > SHA256SUMS
  sha512sum "webmin-wireguard-$VERSION.wbm.gz" \
            "webmin-wireguard-$VERSION-source.tar.gz" \
            "RELEASE-NOTES-$VERSION.md" > SHA512SUMS
  touch -d "@$EPOCH" SHA256SUMS SHA512SUMS
)

# One convenience bundle for manual GitHub release upload.
if command -v zip >/dev/null 2>&1; then
  (cd "$DIST" && zip -X -q "webmin-wireguard-$VERSION-release-assets.zip" \
    "webmin-wireguard-$VERSION.wbm.gz" \
    "webmin-wireguard-$VERSION-source.tar.gz" \
    "RELEASE-NOTES-$VERSION.md" SHA256SUMS SHA512SUMS)
fi

printf 'Release %s built in %s\n' "$VERSION" "$DIST"
