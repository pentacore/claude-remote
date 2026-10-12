#!/usr/bin/env bash
# SessionEnd hook: tear down everything this session started in dind, then tidy its worktrees.
set -uo pipefail
sessions_dir=${CLAUDE_SESSIONS_DIR:-/workspace/.claude-remote/sessions}
wt_dir=${CLAUDE_WORKTREES_DIR:-/workspace/wt}
log_dir=${CLAUDE_REMOTE_LOG_DIR:-/workspace/.claude-remote/logs}
mkdir -p "$log_dir"

input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
[[ -n $sid ]] || exit 0
id8=${sid:0:8}
log() { printf '%s session-end[%s]: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$id8" "$*" >> "$log_dir/session-end.log"; }

# /clear ends the session id but not the conversation: its containers and worktree are still in use.
# Leave them (and the marker) to the janitor's idle rule.
if [[ $(jq -r '.reason // empty' <<<"$input" 2>/dev/null) == clear ]]; then
  log "session cleared; leaving containers, worktrees and marker to the janitor"
  exit 0
fi

# Containers: labelled directly, or belonging to a compose project with this session's suffix.
mapfile -t ids < <(docker ps -aq --filter "label=claude.session=$id8")
mapfile -t projects < <(docker ps -a --format '{{.Label "com.docker.compose.project"}}' | grep -E -- "-${id8}\$" | sort -u)
for p in "${projects[@]}"; do
  mapfile -t pids < <(docker ps -aq --filter "label=com.docker.compose.project=$p")
  ids+=("${pids[@]}")
done
if ((${#ids[@]})); then
  docker rm -f -v "${ids[@]}" >/dev/null 2>&1
  log "removed ${#ids[@]} container(s)"
fi

remove_by_label() { # remove_by_label <network|volume> <label>
  local found
  mapfile -t found < <(docker "$1" ls -q --filter "label=$2")
  ((${#found[@]})) && docker "$1" rm "${found[@]}" >/dev/null 2>&1
  return 0
}
for p in "${projects[@]}"; do
  remove_by_label network "com.docker.compose.project=$p"
  remove_by_label volume "com.docker.compose.project=$p"
done
remove_by_label network "claude.session=$id8"
remove_by_label volume "claude.session=$id8"

# Worktrees: remove only when clean and fully pushed.
shopt -s nullglob
for wt in "$wt_dir"/*-"$id8"; do
  [[ -d $wt ]] || continue
  if ! status=$(git -C "$wt" status --porcelain 2>/dev/null); then
    log "kept $wt: git status failed"; continue
  fi
  if [[ -n $status ]]; then
    log "kept $wt: uncommitted changes"; continue
  fi
  # git deletes ignored files too and stops half-way on ones it cannot remove (e.g. root-owned
  # build output from project containers), leaving a broken tree: never start in that case.
  if [[ -n $(find "$wt" ! -user "$(id -u)" -print -quit 2>/dev/null) ]]; then
    log "kept $wt: contains files not owned by $(id -un) (fix with: sudo chown -R claude:users $wt)"; continue
  fi
  if ! git -C "$wt" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    log "kept $wt: branch has no upstream"; continue
  fi
  if [[ $(git -C "$wt" rev-list --count '@{u}..HEAD') != 0 ]]; then
    log "kept $wt: unpushed commits"; continue
  fi
  common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
  if git -C "${common%/.git}" worktree remove "$wt" >/dev/null 2>&1; then
    log "removed worktree $wt"
  else
    log "kept $wt: worktree remove failed (root-owned or locked files?)"
  fi
done

rm -f "$sessions_dir/$sid"
exit 0
