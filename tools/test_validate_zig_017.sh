#!/bin/sh
# Offline contract tests for validate_zig_017.sh; does not compile NitroUI.
set -eu
cd "$(dirname "$0")/.."
project_dir=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/bin" "$tmp/empty" "$tmp/no-zig"
cat > "$tmp/bin/zig" <<'MOCK'
#!/bin/sh
if [ "$1" = version ]; then
    if [ "${MOCK_VERSION_FAIL:-0}" = 1 ]; then exit 19; fi
    printf '%s\n' "${MOCK_VERSION:-0.17.0}"
    exit 0
fi
printf '%s\n' "$*" >> "$MOCK_LOG"
printf '%s\n' "$PWD" >> "$MOCK_CWD_LOG"
if [ "${MOCK_FAIL_ON:-}" = "$*" ]; then exit 42; fi
exit 0
MOCK
chmod +x "$tmp/bin/zig"
export MOCK_LOG="$tmp/log"
export MOCK_CWD_LOG="$tmp/cwd-log"
run_validator() {
    (cd "$tmp/empty" && PATH="$tmp/bin:/usr/bin:/bin" sh "$project_dir/tools/validate_zig_017.sh") > "$tmp/out" 2>&1
}
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
# Wrong version must reject without invoking any build operation.
export MOCK_VERSION=0.16.0
: > "$MOCK_LOG"
status=0
run_validator || status=$?
[ "$status" -eq 2 ] && [ ! -s "$MOCK_LOG" ] || fail 'version guard'
# A failed `zig version` must stop before any build command.
export MOCK_VERSION_FAIL=1
: > "$MOCK_LOG"
status=0
run_validator || status=$?
[ "$status" -eq 19 ] && [ ! -s "$MOCK_LOG" ] || fail 'version command failure'
unset MOCK_VERSION_FAIL
export MOCK_VERSION=0.17.0
# Every formatting/build step must stop the pipeline immediately on failure.
commands=$(printf '%s\n' 'fmt --check build.zig build.zig.zon src bench examples' 'build test -Doptimize=Debug' 'build test -Doptimize=ReleaseFast' 'build integration -Doptimize=Debug' 'build integration -Doptimize=ReleaseFast' 'build bench -Doptimize=ReleaseFast')
expected=''
while IFS= read -r command; do
    if [ -z "$expected" ]; then expected=$command; else expected=$(printf '%s\n%s' "$expected" "$command"); fi
    export MOCK_FAIL_ON="$command"
    : > "$MOCK_LOG"
    status=0
    run_validator || status=$?
    [ "$status" -eq 42 ] || fail "failure propagation: $command"
    [ "$(cat "$MOCK_LOG")" = "$expected" ] || fail "stop-on-error order: $command"
done <<EOF_COMMANDS
$commands
EOF_COMMANDS
# Success must execute all six validation commands in the project root, regardless of caller cwd.
unset MOCK_FAIL_ON
: > "$MOCK_LOG"
: > "$MOCK_CWD_LOG"
run_validator || fail 'success path'
[ "$(cat "$MOCK_LOG")" = "$commands" ] || fail 'full command order'
# Verify the documented project-root behavior, not just command order.
# Each of the six invocations must run in the root, despite caller cwd.
[ "$(wc -l < "$MOCK_CWD_LOG" | tr -d ' ')" -eq 6 ] || fail 'command working-directory count'
while IFS= read -r cwd; do
    [ "$cwd" = "$project_dir" ] || fail "command executed outside project root: $cwd"
done < "$MOCK_CWD_LOG"
# The validator must report missing Zig before attempting a build. Use a PATH
# containing only the shell and essential utilities, without a zig executable.
# /usr/bin and /bin may contain Zig on some machines, so this case is checked
# only when both locations are Zig-free.
if [ ! -x /usr/bin/zig ] && [ ! -x /bin/zig ]; then
    status=0
    (cd "$tmp/empty" && PATH='/usr/bin:/bin' sh "$project_dir/tools/validate_zig_017.sh") > "$tmp/out" 2>&1 || status=$?
    [ "$status" -eq 127 ] || fail 'missing compiler exit code'
    grep -q 'Zig executable not found' "$tmp/out" || fail 'missing compiler diagnostic'
fi
# The validation tooling must be included when NitroUI is distributed as a Zig package.
# Otherwise a package consumer receives the build but not its validation entry point.
grep -Eq '"tools"' "$project_dir/build.zig.zon" || fail 'package manifest omits validation tools'
[ -f "$project_dir/tools/validate_zig_017.sh" ] || fail 'validation entry point missing'
[ -f "$project_dir/tools/test_validate_zig_017.sh" ] || fail 'validation self-test missing'
echo 'PASS: version guard, version failure, each validation failure, order, project cwd, and success (mocked Zig).'
