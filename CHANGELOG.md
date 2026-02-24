# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.8] - 2026-02-24

### Changed
- Updated .gitignore with custom_lint.log, .dart_tool/, and .claude/ entries

## [0.0.7] - 2026-02-24

### Fixed
- Added `--repo` and org allowlist to `triage.toml` to prevent upstream leakage

## [0.0.6] - 2026-02-24

### Added
- Added 'examples' to auto-documentation generation targets for auth, client, and interceptor modules
- Added auto-format job to the CI workflow to enforce dart formatting conventions

### Changed
- Bumped runtime_ci_tooling dev dependency to ^0.12.0
- Refactored Voxtral tests to be CI-safe unit tests instead of live gRPC integration tests
- Updated CI workflow templates and configuration via manage_cicd update-all
- Aligned runtime_ci_tooling dependency to ^0.10.0 for external package enable-all flow compatibility
- Merged branch 'feat/enterprise-byok-runtime-ci-sync'

### Removed
- Removed GIT_LFS_SKIP_SMUDGE env variables from CI workflow pre-checks

### Fixed
- Fixed the create-release pull --rebase failure related to unstaged changes by picking up runtime_ci_tooling v0.12.1

[0.0.8]: https://github.com/open-runtime/runtime_aot_client_examples/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/open-runtime/runtime_aot_client_examples/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/open-runtime/runtime_aot_client_examples/releases/tag/v0.0.6
