# runtime_aot_client_examples v0.0.11

> Patch release — 2026-03-16

## Chores & Configuration

- **Standalone Lint Baseline** — Removed the workspace-only `runtime_common_codestyle` dev dependency and inlined the recommended lint baseline directly into `analysis_options.yaml`. This enables the package to resolve and analyze cleanly outside the unified monorepo.
- **Ignore pubspec.lock files** — Added `pubspec.lock` to `.gitignore` to prevent committing lockfiles to the repository.

## Issues Addressed

No linked issues for this release.
## Contributors

Thanks to everyone who contributed to this release:
- @tsavo-at-pieces
## Upgrade

```bash
dart pub upgrade runtime_aot_client_examples
```

## Full Changelog

[v0.0.10...v0.0.11](https://github.com/open-runtime/runtime_aot_client_examples/compare/v0.0.10...v0.0.11)
