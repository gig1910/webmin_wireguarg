# Release procedure

The current tracked base version is `0.2.0` (see `VERSION` and `module.info`).
Development builds are uniquely stamped with UTC timestamp and the Git SHA.

## Prepare

```bash
git status --short
./tests/run-tests.sh
./scripts/check-release.sh
./scripts/build-release.sh
```

The `Regression and Release Gate` GitHub Actions workflow runs the same
checks on pushes to `main` and on pull requests. Inspect its result before
deploying a newly built module. The build writes release packages into
`dist/`, not into the running Webmin installation.

## Release an existing version

1. Confirm that `VERSION` and `module.info` agree.
2. Confirm `docs/RELEASE-NOTES-<VERSION>.md` exists and describes the release.
3. Run the test/build gate on the exact commit to be released.
4. Inspect `dist/SHA256SUMS`, `dist/SHA512SUMS`, package manifest and build
   metadata, including the full commit SHA.
5. Create and push a signed annotated `v<VERSION>` tag only when that version
   is actually being published; do not reuse existing tags.
6. Create the GitHub release and explicitly upload the corresponding
   `.wbm.gz`, source archive, release notes and checksum files from `dist/`.
   The CI gate currently validates and builds packages but **does not publish**
   them automatically.

Do not upload local Webmin configuration, WireGuard keys, production endpoint
data or runtime state. A module upgrade must never implicitly rewrite live
`/etc/wireguard/*.conf` or restart WireGuard interfaces.

## Unique build identifiers

Each `./scripts/build-release.sh` invocation stamps a version such as
`0.2.0+<UTC nanosecond timestamp>.g<Git SHA>`. The WBM package contains the
exact `module.info` version and `build.info`; source files remain unchanged.
Set `SOURCE_DATE_EPOCH` to reproduce an intentionally fixed build timestamp.

Use the new timestamped `.wbm.gz` on upgrade and verify the identity shown
by Webmin. A successful build does **not** deploy or activate the package.
