# Versioning and release policy

## Current status

`build.zig.zon` currently declares **0.2.0**. A package version, a Git tag, and a GitHub Release are separate objects. Documentation changes do not automatically create tags or releases.

## Proposed conventions

- Tags: `vMAJOR.MINOR.PATCH` (for example, `v0.2.0`).
- Pre-1.0: public API may change; describe breaking changes explicitly.
- 1.0.0: target for a reviewed and documented stable API contract.
- 2.0.0: reserve for a future major release with justified incompatible changes; **do not tag the current code as 2.0.0**.
- Every release: update the package version and changelog, run checks, tag the exact reviewed commit, then publish release notes.

## Release checklist

1. Verify `zig version` and the required toolchain.
2. Run `zig fmt --check build.zig src bench examples`.
3. Run `zig build test` and `zig build integration`, including ReleaseFast integration.
4. Review ownership contracts and public API changes.
5. Update `CHANGELOG.md` and `build.zig.zon`.
6. Confirm the GitHub Actions workflow passed on the release commit.
7. Create an annotated tag and a GitHub Release.

A future release can be created with `git tag -a vX.Y.Z -m "NitroUI X.Y.Z"`, `git push origin vX.Y.Z`, and `gh release create vX.Y.Z --verify-tag --generate-notes`.
