# Version Bump Rationale

- **Decision**: patch
  - **Reason**: The changes since the last release (`v0.0.10`) consist entirely of build, CI, and linting configuration updates. There are no changes to the actual package source code, and thus no public API or behavioral changes. Under semantic versioning rules, configuration and chore-level changes warrant a `patch` release.
- **Key Changes**:
  - Removed the workspace-only `runtime_common_codestyle` dev dependency from `pubspec.yaml`.
  - Inlined standalone lint rules in `analysis_options.yaml` (from `package:lints/recommended.yaml`) to allow the package to resolve and analyze cleanly outside the unified monorepo.
  - Added `pubspec.lock` to `.gitignore`.
- **Breaking Changes**: None
- **New Features**: None
- **References**:
  - Commit: `chore: inline standalone lint baseline`
