#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(tr -d '[:space:]' < VERSION)
case "$VERSION" in
  ''|*[!0-9A-Za-z.+-]*) echo "Invalid VERSION: $VERSION" >&2; exit 1 ;;
esac

# Keep the whole build/test toolchain executable. Detect Git mode regressions
# explicitly rather than failing later with an opaque "Permission denied".
for path in \
    scripts/build-release.sh scripts/check-release.sh tests/run-tests.sh \
    tests/diagnostic-test.sh tests/collector-test.sh \
    tests/bin/wg tests/bin/wg-quick tests/bin/ping
do
    if [ ! -x "$path" ]; then
        echo "Build prerequisite is not executable: $path (Git mode must be 100755)" >&2
        exit 1
    fi
done

# Test the sources once before packaging. Nothing tracked is modified.
./tests/run-tests.sh
./scripts/check-release.sh

# A new UTC nanosecond timestamp differentiates every build, even when the
# release VERSION and Git commit do not change. An explicit SOURCE_DATE_EPOCH
# allows reproducible releases.
SOURCE_DATE_EPOCH=$(printenv SOURCE_DATE_EPOCH 2>/dev/null || true)
if [ -n "$SOURCE_DATE_EPOCH" ]; then
    case "$SOURCE_DATE_EPOCH" in
        *[!0-9]*) echo "Invalid SOURCE_DATE_EPOCH" >&2; exit 1 ;;
    esac
    BUILD_TIME=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d%H%M%S%N)
    BUILT_AT=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
    EPOCH="$SOURCE_DATE_EPOCH"
else
    BUILD_TIME=$(date -u +%Y%m%d%H%M%S%N)
    BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    EPOCH=$(date -u +%s)
fi

COMMIT=$(git rev-parse --verify HEAD 2>/dev/null || true)
case "$COMMIT" in
    *[!0-9a-f]*|'') COMMIT=unknown; SHORT=nogit ;;
    *) SHORT=$(printf '%.12s' "$COMMIT") ;;
esac
DIRTY=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if ! git diff --quiet HEAD --; then DIRTY=1; fi
fi
SUFFIX=''
[ "$DIRTY" -eq 0 ] || SUFFIX='.dirty'
BUILD_VERSION="$VERSION+$BUILD_TIME.g$SHORT$SUFFIX"
PACKAGE="webmin-wireguard-$BUILD_VERSION.wbm.gz"
SOURCE="webmin-wireguard-$BUILD_VERSION-source.tar.gz"
NOTES="RELEASE-NOTES-$VERSION.md"

BUILD="$ROOT/build"
DIST="$ROOT/dist"
STAGE="$BUILD/wireguard"
SOURCE_STAGE="$BUILD/webmin-wireguard-$BUILD_VERSION"
rm -rf "$BUILD" "$DIST"
mkdir -p "$STAGE" "$DIST" "$SOURCE_STAGE"

while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -f "$path" ] || { echo "Missing manifest file: $path" >&2; exit 1; }
    mkdir -p "$STAGE/$(dirname "$path")"
    cp -p "$path" "$STAGE/$path"
done < MANIFEST.wbm
find "$STAGE" -type d -exec chmod g-s {} + -exec chmod 0755 {} +

# Stamp only package staging; the checkout's VERSION/module.info are untouched.
cat > "$STAGE/build.info" <<EOF
build_version=$BUILD_VERSION
git_commit=$COMMIT
built_at_utc=$BUILT_AT
source_dirty=$DIRTY
EOF
chmod 0644 "$STAGE/build.info"
awk -v v="$BUILD_VERSION" '/^version=/{print "version=" v;next} {print}' \
    "$STAGE/module.info" > "$STAGE/module.info.tmp"
mv "$STAGE/module.info.tmp" "$STAGE/module.info"
chmod 0644 "$STAGE/module.info"

grep -Fqx "version=$BUILD_VERSION" "$STAGE/module.info"
grep -Fqx "build_version=$BUILD_VERSION" "$STAGE/build.info"
grep -Fqx "git_commit=$COMMIT" "$STAGE/build.info"

TZ=UTC tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
    -czf "$DIST/$PACKAGE" -C "$BUILD" wireguard

sort MANIFEST.wbm > "$BUILD/manifest.expected"
tar -tzf "$DIST/$PACKAGE" | \
    sed -n 's#^wireguard/##p' | sed '/\/$/d;/^$/d' | sort > "$BUILD/manifest.actual"
cmp "$BUILD/manifest.expected" "$BUILD/manifest.actual"

# Fail early if an old or unmarked module somehow got into the package.
tar -xOzf "$DIST/$PACKAGE" wireguard/module.info | grep -Fqx "version=$BUILD_VERSION"
tar -xOzf "$DIST/$PACKAGE" wireguard/build.info | grep -Fqx "build_version=$BUILD_VERSION"
tar -xOzf "$DIST/$PACKAGE" wireguard/index.cgi | grep -Fq 'wg_build_banner()'
tar -xOzf "$DIST/$PACKAGE" wireguard/analytics.cgi | grep -Fq 'wg_build_banner()'

# Source archive carries matching provenance.
find . -mindepth 1 -maxdepth 1 \
    ! -name .git ! -name build ! -name dist \
    -exec cp -a {} "$SOURCE_STAGE/" \;
cp -p "$STAGE/build.info" "$SOURCE_STAGE/build.info"
cp -p "$STAGE/module.info" "$SOURCE_STAGE/module.info"
find "$SOURCE_STAGE" -type d -exec chmod g-s {} + -exec chmod 0755 {} +
TZ=UTC tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner \
    -czf "$DIST/$SOURCE" -C "$BUILD" "webmin-wireguard-$BUILD_VERSION"

cp "docs/RELEASE-NOTES-$VERSION.md" "$DIST/$NOTES"
touch -d "@$EPOCH" "$DIST/$PACKAGE" "$DIST/$SOURCE" "$DIST/$NOTES"
(
    cd "$DIST"
    sha256sum "$PACKAGE" "$SOURCE" "$NOTES" > SHA256SUMS
    sha512sum "$PACKAGE" "$SOURCE" "$NOTES" > SHA512SUMS
    touch -d "@$EPOCH" SHA256SUMS SHA512SUMS
)
if command -v zip >/dev/null 2>&1; then
    (cd "$DIST" && zip -X -q "webmin-wireguard-$BUILD_VERSION-release-assets.zip" \
        "$PACKAGE" "$SOURCE" "$NOTES" SHA256SUMS SHA512SUMS)
fi

printf '\nBuild version: %s\nCommit: %s\nBuilt at: %s\nWorking tree modified: %s\n' \
    "$BUILD_VERSION" "$COMMIT" "$BUILT_AT" "$DIRTY"
printf 'Webmin package: %s\n' "$DIST/$PACKAGE"
printf 'Release assets: %s\n' "$DIST"
