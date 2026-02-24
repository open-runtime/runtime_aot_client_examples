# Version Bump Decision: patch

**Decision**: patch

This release warrants a `patch` bump. The only change since the `v0.0.6` release is a fix to the internal `triage.toml` Gemini CLI command configuration. This change modifies the underlying script instructions to use `--repo` and implements an organizational allowlist to prevent upstream issue modification in a forked context.

Because this is purely an internal tooling fix that does not affect any public API, feature surface, or the package's distributed code, it clearly falls under the criteria for a patch release.

## Key Changes
* Fixed `triage.toml` by strictly enforcing `--repo <owner/repo>` usage on all `gh` issue commands.
* Added a hard stop organizational allowlist (restricting issue operations to the `open-runtime` and `pieces-app` organizations).
* Added checks to ensure duplicate triage comments are not posted on existing issues.

## Breaking Changes
None.

## New Features
None.

## References
* **Commit**: `fix(triage): add --repo + org allowlist to triage.toml to prevent upstream leakage`
