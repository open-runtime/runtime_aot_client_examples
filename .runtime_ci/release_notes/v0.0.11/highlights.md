* Inlined standalone lint baseline to replace workspace-only lint assumptions, enabling the package to resolve cleanly outside the unified monorepo.
* Removed the workspace-only `runtime_common_codestyle` dev dependency.
* Added `pubspec.lock` to `.gitignore` to prevent committing lockfiles.
