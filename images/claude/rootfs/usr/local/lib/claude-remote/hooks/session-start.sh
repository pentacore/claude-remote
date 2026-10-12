#!/usr/bin/env bash
# SessionStart hook: register the session for cleanup and expose its id to Bash commands.
set -uo pipefail
dir=${CLAUDE_SESSIONS_DIR:-/workspace/.claude-remote/sessions}
input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
[[ -n $sid ]] || exit 0
mkdir -p "$dir"
jq -r '.cwd // ""' <<<"$input" > "$dir/$sid"
if [[ -n ${CLAUDE_ENV_FILE:-} ]]; then
  printf 'export CLAUDE_SESSION_ID=%s\n' "$sid" >> "$CLAUDE_ENV_FILE"
fi
exit 0
