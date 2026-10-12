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
@test "when remote-control is down, the reason from its log is shown (ANSI and rc-loop lines stripped)" {
  printf 'Starting...\r\n\033[31mError: Remote Control is disabled by your organization'"'"'s policy.\033[0m\r\n\nrc-loop: remote-control exited (1) within a minute; retrying in 60s\n' > "$TMP/rc.log"
  RC_LOG=$TMP/rc.log CLAUDE_BIN=$TMP/claude-ok PGREP=$TMP/pgrep-no run "$CLAUDE_BIN_DIR/healthcheck"
  [ "$status" -eq 1 ]
  [ "$output" = "unhealthy: claude remote-control is not running: Error: Remote Control is disabled by your organization's policy." ]
}
@test "rc-loop prefixes its own messages and the supervisor logs the rc pane" {
  grep -q 'rc-loop: remote-control exited' "$CLAUDE_BIN_DIR/rc-loop"
  grep -q 'pipe-pane' "$CLAUDE_BIN_DIR/supervisor"
}
