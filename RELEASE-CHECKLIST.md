# Release checklist 1.0.0

- [ ] Review `git diff` and confirm the intended version.
- [ ] Run `./tests/run-tests.sh`.
- [ ] Run `./scripts/check-release.sh`.
- [ ] Run `./scripts/build-release.sh`.
- [ ] Install the WBM on a disposable Webmin host.
- [ ] Verify module menu visibility and read-only ACL.
- [ ] Verify interface/peer pages, client config, download and QR.
- [ ] Verify collector start/restart/stop and retention reduction.
- [ ] Verify SHA-256/SHA-512 checksums.
- [ ] Create and push signed tag `v1.0.0`.
- [ ] Publish release assets and notes.
