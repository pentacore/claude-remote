setup() {
  load helpers/common
  TMP=$(mktemp -d)
  printf '#!/bin/sh\nexit %s\n' 0 > "$TMP/claude-ok"; printf '#!/bin/sh\nexit %s\n' 1 > "$TMP/claude-out"
  printf '#!/bin/sh\nexit %s\n' 0 > "$TMP/pgrep-yes"; printf '#!/bin/sh\nexit %s\n' 1 > "$TMP/pgrep-no"
  chmod +x "$TMP"/*
}
teardown() { rm -rf "$TMP"; }
hc() { CLAUDE_BIN=$TMP/$1 PGREP=$TMP/$2 run "$CLAUDE_BIN_DIR/healthcheck"; }

@test "healthy when logged in and remote-control runs" { hc claude-ok pgrep-yes; [ "$status" -eq 0 ]; }
@test "unhealthy when not logged in" { hc claude-out pgrep-yes; [ "$status" -eq 1 ]; [[ $output == *"claude auth login"* ]]; }
@test "unhealthy when remote-control is not running" { hc claude-ok pgrep-no; [ "$status" -eq 1 ]; [[ $output == *"not running"* ]]; }
@test "unhealthy when claude is not installed" { hc missing pgrep-yes; [ "$status" -eq 1 ]; }
