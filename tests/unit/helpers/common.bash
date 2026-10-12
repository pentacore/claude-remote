ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
CLAUDE_BIN_DIR="$ROOT/images/claude/rootfs/usr/local/bin"
HOOKS_DIR="$ROOT/images/claude/rootfs/usr/local/lib/claude-remote/hooks"
JANITOR_LIB="$ROOT/images/dind/janitor-lib.sh"
HELPERS="$ROOT/tests/unit/helpers"

# minutes_ago <n> → touch -t timestamp n minutes in the past (busybox-compatible)
minutes_ago() { date -d "@$(( $(date +%s) - $1 * 60 ))" +%Y%m%d%H%M.%S; }

# refute <cmd...>: fail the test if cmd succeeds. (A bare `! cmd` never fails a bats test.)
refute() { if "$@"; then echo "expected failure: $*" >&2; return 1; fi; }
LIB_DIR="$ROOT/images/claude/rootfs/usr/local/lib/claude-remote"
