# Contributing

## Before opening a pull request

1. Do not include real WireGuard keys, endpoints or production configurations.
2. Keep all user-visible strings in both `lang/en` and `lang/ru`.
3. Add regression coverage for every bug fix.
4. Run:

   ```bash
   ./tests/run-tests.sh
   ./scripts/check-release.sh
   ```

5. Keep state-changing endpoints behind Webmin ACL, POST, CSRF and rate-limit
   checks.
6. Preserve unknown `.conf` directives and comments whenever possible.
7. Never add shell-string command execution with user-controlled input; use
   argument arrays and existing command helpers.

## Code layout

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The CGI contract remains in
the Webmin module package; internal libraries are split by responsibility.

## Commit and release policy

Use focused commits. User-facing changes belong in `CHANGELOG.md`. A release
tag must match `VERSION` and `module.info`.
