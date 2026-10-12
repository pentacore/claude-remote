SID=deadbeef-1111-2222-3333-444455556666

setup() {
  load helpers/common
  TMP=$(mktemp -d)
  export HOME=$TMP/home; mkdir -p "$HOME"
  export CLAUDE_SESSIONS_DIR=$TMP/sessions CLAUDE_REMOTE_LOG_DIR=$TMP/logs CLAUDE_WORKTREES_DIR=$TMP/wt
  mkdir -p "$CLAUDE_SESSIONS_DIR" "$CLAUDE_WORKTREES_DIR"
  export FAKE_DOCKER_LOG=$TMP/docker.log; : > "$FAKE_DOCKER_LOG"
  mkdir -p "$TMP/bin"; ln -s "$HELPERS/fake-docker" "$TMP/bin/docker"; export PATH="$TMP/bin:$PATH"
  git config --global user.email t@example.com; git config --global user.name test
  git config --global init.defaultBranch main
}
teardown() { rm -rf "$TMP"; }
hook() { printf '{"session_id":"%s","cwd":"/workspace"}' "$SID" | "$HOOKS_DIR/$1"; }

@test "session-start writes marker and env file" {
  export CLAUDE_ENV_FILE=$TMP/env
  run hook session-start.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_SESSIONS_DIR/$SID")" = /workspace ]
  grep -Fxq "export CLAUDE_SESSION_ID=$SID" "$CLAUDE_ENV_FILE"
}
@test "session-start without CLAUDE_ENV_FILE still writes marker" {
  unset CLAUDE_ENV_FILE
  run hook session-start.sh
  [ "$status" -eq 0 ]; [ -f "$CLAUDE_SESSIONS_DIR/$SID" ]
}
@test "heartbeat refreshes marker mtime" {
  touch -t "$(minutes_ago 300)" "$CLAUDE_SESSIONS_DIR/$SID"
  run hook heartbeat.sh
  [ "$status" -eq 0 ]
  [ -n "$(find "$CLAUDE_SESSIONS_DIR" -name "$SID" -mmin -1)" ]
}
@test "hooks ignore input without a session id" {
  run sh -c "echo '{}' | '$HOOKS_DIR/session-start.sh'"; [ "$status" -eq 0 ]
  run sh -c "echo '{}' | '$HOOKS_DIR/heartbeat.sh'"; [ "$status" -eq 0 ]
  run sh -c "echo '{}' | '$HOOKS_DIR/session-end.sh'"; [ "$status" -eq 0 ]
  [ -z "$(ls "$CLAUDE_SESSIONS_DIR")" ]
}
@test "session-end removes the session's containers, networks and volumes only" {
  cat > "$TMP/respond" <<'EOF'
case "$*" in
  "ps -aq --filter label=claude.session=deadbeef") echo c-run ;;
  'ps -a --format {{.Label "com.docker.compose.project"}}') printf '%s\n' api-deadbeef api-deadbeef other-cafebabe "" ;;
  "ps -aq --filter label=com.docker.compose.project=api-deadbeef") printf '%s\n' c-web c-db ;;
  "network ls -q --filter label=com.docker.compose.project=api-deadbeef") echo n1 ;;
  "volume ls -q --filter label=com.docker.compose.project=api-deadbeef") echo v1 ;;
  "network ls -q --filter label=claude.session=deadbeef") echo n2 ;;
  "volume ls -q --filter label=claude.session=deadbeef") echo v2 ;;
esac
EOF
  export FAKE_DOCKER_RESPOND=$TMP/respond
  touch "$CLAUDE_SESSIONS_DIR/$SID"
  run hook session-end.sh
  [ "$status" -eq 0 ]
  grep -Fxq "rm -f -v c-run c-web c-db" "$FAKE_DOCKER_LOG"
  grep -Fxq "network rm n1" "$FAKE_DOCKER_LOG"; grep -Fxq "volume rm v1" "$FAKE_DOCKER_LOG"
  grep -Fxq "network rm n2" "$FAKE_DOCKER_LOG"; grep -Fxq "volume rm v2" "$FAKE_DOCKER_LOG"
  refute grep -q other-cafebabe "$FAKE_DOCKER_LOG"
  [ ! -e "$CLAUDE_SESSIONS_DIR/$SID" ]
  grep -q "removed 3 container" "$CLAUDE_REMOTE_LOG_DIR/session-end.log"
}

# --- worktree tidying -------------------------------------------------------
mkrepo() { # → $TMP/repos/api with origin $TMP/origin.git
  git init -q --bare "$TMP/origin.git"
  git clone -q "$TMP/origin.git" "$TMP/repos/api" 2>/dev/null
  (cd "$TMP/repos/api" && echo a > a && git add a && git commit -qm init && git push -q origin main)
}
mkwt() { # mkwt <name> → worktree $CLAUDE_WORKTREES_DIR/<name>-deadbeef on its own branch
  git -C "$TMP/repos/api" worktree add -q -b "claude/$1-deadbeef" "$CLAUDE_WORKTREES_DIR/$1-deadbeef" main
}

@test "session-end removes clean, pushed worktrees" {
  mkrepo; mkwt pushed
  (cd "$CLAUDE_WORKTREES_DIR/pushed-deadbeef" && echo b > b && git add b && git commit -qm b && git push -q -u origin HEAD)
  run hook session-end.sh
  [ ! -d "$CLAUDE_WORKTREES_DIR/pushed-deadbeef" ]
  grep -q "removed worktree" "$CLAUDE_REMOTE_LOG_DIR/session-end.log"
}
@test "session-end keeps worktrees with uncommitted changes" {
  mkrepo; mkwt dirty
  echo x > "$CLAUDE_WORKTREES_DIR/dirty-deadbeef/x"
  run hook session-end.sh
  [ -d "$CLAUDE_WORKTREES_DIR/dirty-deadbeef" ]
  grep -q "kept .*dirty-deadbeef: uncommitted changes" "$CLAUDE_REMOTE_LOG_DIR/session-end.log"
}
@test "session-end keeps worktrees with no upstream or unpushed commits" {
  mkrepo; mkwt local; mkwt ahead
  (cd "$CLAUDE_WORKTREES_DIR/ahead-deadbeef" && git push -q -u origin HEAD && echo c > c && git add c && git commit -qm c)
  run hook session-end.sh
  [ -d "$CLAUDE_WORKTREES_DIR/local-deadbeef" ]; [ -d "$CLAUDE_WORKTREES_DIR/ahead-deadbeef" ]
  grep -q "local-deadbeef: branch has no upstream" "$CLAUDE_REMOTE_LOG_DIR/session-end.log"
  grep -q "ahead-deadbeef: unpushed commits" "$CLAUDE_REMOTE_LOG_DIR/session-end.log"
}
@test "session-end keeps a worktree it cannot remove (e.g. root-owned files) and logs it" {
  mkrepo; mkwt locked
  (cd "$CLAUDE_WORKTREES_DIR/locked-deadbeef" && git push -q -u origin HEAD)
  git -C "$TMP/repos/api" worktree lock "$CLAUDE_WORKTREES_DIR/locked-deadbeef"
  run hook session-end.sh
  [ "$status" -eq 0 ]
  [ -d "$CLAUDE_WORKTREES_DIR/locked-deadbeef" ]
  grep -q "locked-deadbeef: worktree remove failed" "$CLAUDE_REMOTE_LOG_DIR/session-end.log"
}
@test "session-end leaves other sessions' worktrees alone" {
  mkrepo
  git -C "$TMP/repos/api" worktree add -q -b other "$CLAUDE_WORKTREES_DIR/api-cafebabe" main
  run hook session-end.sh
  [ "$status" -eq 0 ]
  [ -d "$CLAUDE_WORKTREES_DIR/api-cafebabe" ]
}
@test "managed settings register all three hooks" {
  f="$ROOT/images/claude/rootfs/etc/claude-code/managed-settings.json"
  for e in SessionStart PostToolUse SessionEnd; do
    jq -e --arg e "$e" '.hooks[$e][0].hooks[0].command | startswith("/usr/local/lib/claude-remote/hooks/")' "$f"
  done
}

@test "session-end keeps worktrees containing files it does not own (root-owned build output)" {
  mkrepo; mkwt owned
  wt=$CLAUDE_WORKTREES_DIR/owned-deadbeef
  (cd "$wt" && echo "build/" > .gitignore && git add .gitignore && git commit -qm ignore && git push -q -u origin HEAD)
  mkdir -p "$wt/build" && touch "$wt/build/out" && chown 12345 "$wt/build/out"
  run hook session-end.sh
  [ "$status" -eq 0 ]
  [ -f "$wt/a" ]; [ -f "$wt/build/out" ]
  git -C "$TMP/repos/api" worktree list | grep -q owned-deadbeef
  grep -q "kept .*owned-deadbeef: contains files not owned by" "$CLAUDE_REMOTE_LOG_DIR/session-end.log"
}
@test "session-end on /clear leaves everything to the janitor's idle rule" {
  cat > "$TMP/respond" <<'R'
case "$*" in
  "ps -aq --filter label=claude.session=deadbeef") echo c-run ;;
esac
R
  export FAKE_DOCKER_RESPOND=$TMP/respond
  mkrepo; mkwt cleared
  (cd "$CLAUDE_WORKTREES_DIR/cleared-deadbeef" && git push -q -u origin HEAD)
  touch "$CLAUDE_SESSIONS_DIR/$SID"
  run sh -c "printf '{\"session_id\":\"$SID\",\"reason\":\"clear\"}' | '$HOOKS_DIR/session-end.sh'"
  [ "$status" -eq 0 ]
  refute grep -q "^rm " "$FAKE_DOCKER_LOG"
  [ -d "$CLAUDE_WORKTREES_DIR/cleared-deadbeef" ]; [ -e "$CLAUDE_SESSIONS_DIR/$SID" ]
  grep -q "cleared" "$CLAUDE_REMOTE_LOG_DIR/session-end.log"
}
