# runtime_aot_client_examples v0.0.6

> Bug fix release — 2026-02-24

## Bug Fixes

- **CI Pipeline Fix** — Resolved an issue where automated release PRs failed during the `create-release pull --rebase` step due to unstaged changes. This was fixed by upgrading the `runtime_ci_tooling` dependency to `^0.12.0`.
- **Test Infrastructure Stability** — Refactored `voxtral_test.dart` from a live gRPC integration test requiring AWS Bedrock credentials into a self-contained unit test. This prevents the CI pipeline from incorrectly failing or skipping tests when executed in an unauthenticated environment.

## Improvements

- **Documentation Enhancements** — Expanded the `autodoc.json` generation targets to compile functional code `examples` for the `auth`, `client`, and `interceptor` modules automatically.
- **Auto-Formatting Enforcement** — Integrated a new `auto-format` job into the CI workflow to strictly enforce Dart formatting conventions, improving long-term project maintainability.

## Upgrade

```bash
dart pub upgrade runtime_aot_client_examples
```

## Contributors

Thanks to everyone who contributed to this release:
- @tsavo-at-pieces
## Issues Addressed

No linked issues for this release.
## Full Changelog

[v0.0.5...v0.0.6](https://github.com/open-runtime/runtime_aot_client_examples/compare/v0.0.5...v0.0.6)
