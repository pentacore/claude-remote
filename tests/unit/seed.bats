setup() {
  load helpers/common
  TMP=$(mktemp -d)
  export HOME=$TMP CLAUDE_BIN=$TMP/claude CLAUDE_LOG=$TMP/claude.log
  unset CONTEXT7_API_KEY CLAUDE_SEED
  cat > "$CLAUDE_BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_LOG"
case "$*" in
  "plugin marketplace list") printf '%s\n' "${FAKE_MARKETPLACES:-}" ;;
  *"${FAKE_FAIL:-__none__}"*) exit 1 ;;
esac
exit 0
EOF
  chmod +x "$CLAUDE_BIN"; : > "$CLAUDE_LOG"
}
teardown() { rm -rf "$TMP"; }
seed() { run "$CLAUDE_BIN_DIR/seed-claude"; [ "$status" -eq 0 ]; }
called() { grep -Fxq -- "$1" "$CLAUDE_LOG"; }

@test "first run seeds MCP servers, marketplace and plugins at user scope" {
  seed
  called "mcp add --scope user playwright -- mcp-server-playwright --headless --browser chromium --no-sandbox --isolated"
  called "mcp add --scope user --transport http context7 https://mcp.context7.com/mcp"
  called "plugin marketplace add anthropics/claude-plugins-official"
  called "plugin install -s user superpowers@claude-plugins-official"
  called "plugin install -s user mattpocock-skills@claude-plugins-official"
}
@test "second run seeds nothing new" {
  seed; : > "$CLAUDE_LOG"
  seed
  refute grep -q "add\|install" "$CLAUDE_LOG"
}
@test "items removed by the user are not re-added" {
  seed; : > "$CLAUDE_LOG"
  "$CLAUDE_BIN" mcp remove context7 --scope user   # the user's own action
  seed
  refute grep -q "context7 https" "$CLAUDE_LOG"
}
@test "failed items are retried on the next run, others are not" {
  FAKE_FAIL=superpowers seed
  [[ $output == *"failed to seed plugin:superpowers"* ]]
  : > "$CLAUDE_LOG"
  seed
  called "plugin install -s user superpowers@claude-plugins-official"
  refute grep -q "mattpocock" "$CLAUDE_LOG"
}
@test "existing marketplace is not re-added" {
  FAKE_MARKETPLACES="  ❯ claude-plugins-official" seed
  refute grep -q "marketplace add" "$CLAUDE_LOG"
}
@test "context7 API key is sent as a header" {
  CONTEXT7_API_KEY=ctx7_abc seed
  called "mcp add --scope user --transport http --header CONTEXT7_API_KEY: ctx7_abc context7 https://mcp.context7.com/mcp"
}
@test "CLAUDE_SEED=false disables seeding" {
  CLAUDE_SEED=false seed
  [ ! -s "$CLAUDE_LOG" ]
}
@test "missing claude binary is a no-op" {
  CLAUDE_BIN=$TMP/nope seed
  [[ $output == *"not installed"* ]]
}
