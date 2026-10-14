#!/bin/sh
# Reproducible local validation. No external dependencies or downloads.
set -eu
cd "$(dirname "$0")/.."
if ! command -v zig >/dev/null 2>&1; then
    printf '%s\n' 'ERROR: Zig executable not found in PATH.' >&2
    exit 127
fi
version=$(zig version)
if [ "$version" != '0.17.0' ]; then
    printf 'ERROR: expected Zig 0.17.0, got %s\n' "$version" >&2
    exit 2
fi
printf '%s\n' '[1/6] Formatting'
zig fmt --check build.zig build.zig.zon src bench examples
printf '%s\n' '[2/6] Unit tests: Debug'
zig build test -Doptimize=Debug
printf '%s\n' '[3/6] Unit tests: ReleaseFast'
zig build test -Doptimize=ReleaseFast
printf '%s\n' '[4/6] Headless integration: Debug'
zig build integration -Doptimize=Debug
printf '%s\n' '[5/6] Headless integration: ReleaseFast'
zig build integration -Doptimize=ReleaseFast
printf '%s\n' '[6/6] Headless benchmark: ReleaseFast'
zig build bench -Doptimize=ReleaseFast
printf '%s\n' 'All validation commands completed successfully.'
