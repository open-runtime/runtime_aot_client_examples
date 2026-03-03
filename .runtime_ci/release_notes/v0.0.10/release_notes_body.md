# runtime_aot_client_examples v0.0.10

> Dependency alignments and version bumps — 2026-03-03

This patch release focuses on dependency alignments and maintenance chores, with no public API additions, breakages, or functional changes. It ensures `runtime_aot_client_examples` stays up-to-date with the latest internal packages and tooling.

## Dependency Updates

- **`runtime_isomorphic_library`** — Updated from `^2.0.0` to `^4.0.0` to incorporate the latest upstream changes. ([#3](https://github.com/open-runtime/runtime_aot_client_examples/pull/3), [#2](https://github.com/open-runtime/runtime_aot_client_examples/pull/2))
- **`grpc` (grpc-dart)** — Aligned dependency constraint to `^5.3.8`. ([#2](https://github.com/open-runtime/runtime_aot_client_examples/pull/2))
- **`runtime_ci_tooling`** (dev dependency) — Bumped from `^0.12.0` to `^0.14.1` to align post-merge configurations. ([#2](https://github.com/open-runtime/runtime_aot_client_examples/pull/2))

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

[v0.0.9...v0.0.10](https://github.com/open-runtime/runtime_aot_client_examples/compare/v0.0.9...v0.0.10)
