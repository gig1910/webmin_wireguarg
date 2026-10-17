# GitHub repository settings

Repository: `gig1910/webmin_wireguarg` (current name, including its spelling).
Primary development branch: `main`.

## Maintenance settings

- Enable Issues and private vulnerability reports.
- Require the `Regression and Release Gate / tests` status check before
  merging pull requests into `main`.
- Prevent force pushes to `main`.
- Enable Dependabot updates for GitHub Actions.
- Limit repository write access to trusted administrators; code in this
  Webmin module handles privileged operating-system operations.

## Continuous integration

Workflow: `.github/workflows/regression.yml`.
It runs Perl/Python/JavaScript regression tests, verifies release metadata,
and assembles a WBM package. A green workflow is required for a releasable
commit. It does not deploy to servers or create GitHub releases.

The release procedure, tags and checksums are described in
[docs/RELEASE.md](docs/RELEASE.md). Historical instructions to create an
initial `v1.0.0` repository release do not describe the current project.
