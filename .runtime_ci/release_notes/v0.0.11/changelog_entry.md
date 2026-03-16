## [0.0.11] - 2026-03-16

### Changed
- Inlined standalone lint baseline to replace workspace-only lint assumptions, enabling the package to resolve cleanly outside the unified monorepo.

### Removed
- Removed runtime_common_codestyle from dev dependencies.

### Fixed
- Added pubspec.lock to .gitignore to prevent committing lockfiles.