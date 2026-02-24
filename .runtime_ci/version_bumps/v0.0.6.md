**Decision**: patch

This release addresses CI/CD configuration and test improvements with zero impact on the package's public API surface or runtime behavior.

**Key Changes**:
- **Test Improvements**: Refactored `voxtral_test.dart` from an integration test requiring AWS credentials into a unit test that safely verifies request construction.
- **CI/CD Improvements**: Generated new CI workflow using `runtime_ci_tooling` ^0.12.0, adding an auto-format job and aligning dependency metadata for workspace enablement.
- **Documentation**: Enhanced `autodoc.json` to include the `examples` generation target for `auth`, `client`, and `interceptor` modules.
- **Dependency Updates**: Bumped `runtime_ci_tooling` dev_dependency from `^0.6.0` to `^0.12.0`.

**Breaking Changes**:
- None.

**New Features**:
- None.

**References**:
- Commits since last release tag (v0.0.5):
  - chore(deps): bump runtime_ci_tooling to ^0.12.0
  - chore(ci): update CI templates and enhance autodoc coverage
  - test: make Voxtral tests CI-safe
  - ci: regenerate CI workflow with auto-format job
  - chore: sync runtime_ci templates and dependency metadata
  - chore: align runtime_ci_tooling dependency for workspace enablement