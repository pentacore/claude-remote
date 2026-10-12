setup() { load helpers/common; MD="$ROOT/images/claude/rootfs/etc/claude-code/CLAUDE.md"; }

@test "managed CLAUDE.md worktree recipe fails loudly without a session id" {
  grep -Fq 'id8=${CLAUDE_SESSION_ID:?' "$MD"
  refute grep -Fq 'CLAUDE_SESSION_ID:0:8' "$MD"
}
