# Release procedure

## Prepare

```bash
./tests/run-tests.sh
./scripts/check-release.sh
./scripts/build-release.sh
```

The version in `VERSION`, `module.info`, API markers and release tag must match.

## Create repository and first release

```bash
git init
git add .
git commit -m "Release 1.0.0"
git branch -M main
git remote add origin git@github.com:OWNER/webmin-wireguard.git
git push -u origin main
git tag -s v1.0.0 -m "WireGuard Webmin 1.0.0"
git push origin v1.0.0
```

The release workflow builds and uploads the WBM, source archive, checksums and
release notes. Signed tags require a locally configured signing key.

## Manual GitHub release

Upload the files from `dist/` and use `docs/RELEASE-NOTES-1.0.0.md` as the
release description. Do not upload private test configurations or runtime
state.

## Unique build identifiers

Running `./scripts/build-release.sh` automatically generates a new build version and filename for the Webmin package and source bundle (release VERSION + UTC timestamp/nanoseconds + Git commit). The archive's `module.info` and `build.info` are stamped, but tracked source files are not rewritten. You can inspect the installed build number in the module UI and in the `X-WireGuard-Webmin-Build` API response header. `SOURCE_DATE_EPOCH` can be supplied to reproduce an explicitly timestamped build. The release notes remain tied to the base VERSION.
