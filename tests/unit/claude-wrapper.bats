setup() {
  load helpers/common
  TMP=$(mktemp -d)
  printf '#!/usr/bin/env bash\necho "real $*"\n' > "$TMP/real-claude"
  printf '#!/usr/bin/env bash\necho "runuser $*"\n' > "$TMP/runuser"
  chmod +x "$TMP/real-claude" "$TMP/runuser"
  export CLAUDE_REAL=$TMP/real-claude RUNUSER=$TMP/runuser
}
teardown() { rm -rf "$TMP"; }

@test "from a root shell, claude runs as the claude user with its home" {
  CLAUDE_WRAPPER_UID=0 run "$CLAUDE_BIN_DIR/claude" auth login
  [ "$output" = "runuser -u claude -- env HOME=/home/claude USER=claude LOGNAME=claude $TMP/real-claude auth login" ]
}
@test "as the claude user, claude runs directly" {
  CLAUDE_WRAPPER_UID=99 run "$CLAUDE_BIN_DIR/claude" remote-control --name Babel
  [ "$output" = "real remote-control --name Babel" ]
}
@test "the wrapper comes before ~/.local/bin on PATH, in the image and in login shells" {
  grep -qE 'PATH=/usr/local/bin:/home/claude/.local/bin:' "$ROOT/images/claude/Dockerfile"
  grep -qE 'PATH=/usr/local/bin:/home/claude/.local/bin:' "$ROOT/images/claude/rootfs/etc/profile.d/claude-remote.sh"
}
