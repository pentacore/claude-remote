#!/usr/bin/env bash
# PostToolUse hook: mark the session as active for the janitor's idle rule.
sid=$(jq -r '.session_id // empty' 2>/dev/null)
[[ -n $sid ]] && touch "${CLAUDE_SESSIONS_DIR:-/workspace/.claude-remote/sessions}/$sid" 2>/dev/null
exit 0
