# janitor-lib.sh — cleanup policy for the dind daemon. POSIX sh (busybox ash); sourced by janitor.sh.

: "${SESSIONS_DIR:=/workspace/.claude-remote/sessions}"
: "${DOCKER_ROOT:=/var/lib/docker}"
: "${WORKSPACE_DIR:=/workspace}"
: "${JANITOR_IDLE_MIN:=120}"
: "${JANITOR_MAX_AGE_MIN:=1440}"
: "${JANITOR_UNTAGGED_MAX_AGE_MIN:=60}"
: "${JANITOR_MARKER_MAX_AGE_MIN:=10080}"
: "${JANITOR_SOFT_PCT:=75}"
: "${JANITOR_HARD_PCT:=90}"

log() { printf '%s janitor: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }

# run <cmd...>: run quietly, log failures, never abort the caller
run() { "$@" >/dev/null 2>&1 || log "failed: $*"; }

list_containers_json() {
  curl -fsS --unix-socket /var/run/docker.sock 'http://localhost/containers/json?all=1'
}

# One line per container: id|created_epoch|session_label|compose_project
containers_psv() {
  list_containers_json | jq -r '.[] | [.Id, (.Created | tostring),
    (.Labels["claude.session"] // ""), (.Labels["com.docker.compose.project"] // "")] | join("|")'
}

# owner_of <session_label> <compose_project> → id8, "manual", or "" (untagged)
owner_of() {
  if [ -n "$1" ]; then
    case "$1" in
      manual) printf 'manual' ;;
      [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) printf '%.8s' "$1" ;;
    esac
    return
  fi
  case "$2" in
    *-manual) printf 'manual' ;;
    *-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) printf '%s' "${2##*-}" ;;
  esac
}

session_exists() {
  [ -n "$(find "$SESSIONS_DIR" -maxdepth 1 -type f -name "$1*" 2>/dev/null | head -n 1)" ]
}

session_active() {
  [ -n "$(find "$SESSIONS_DIR" -maxdepth 1 -type f -name "$1*" -mmin -"$JANITOR_IDLE_MIN" 2>/dev/null | head -n 1)" ]
}

# decide <owner> <age_min> → keep | remove:<reason>
decide() {
  if [ "$2" -ge "$JANITOR_MAX_AGE_MIN" ]; then echo remove:max-age; return; fi
  case "$1" in
    manual) echo keep ;;
    "")
      if [ "$2" -ge "$JANITOR_UNTAGGED_MAX_AGE_MIN" ]; then echo remove:untagged; else echo keep; fi ;;
    *)
      if ! session_exists "$1"; then echo remove:orphan
      elif ! session_active "$1"; then echo remove:idle
      else echo keep
      fi ;;
  esac
}

remove_container() { # <id> <reason> <project>
  log "removing $(printf '%.12s' "$1") (reason=$2${3:+ project=$3})"
  run docker rm -f -v "$1"
}

sweep() {
  now=$(date +%s)
  containers_psv | while IFS='|' read -r id created session project; do
    [ -n "$id" ] || continue
    verdict=$(decide "$(owner_of "$session" "$project")" $(( (now - created) / 60 )))
    case "$verdict" in remove:*) remove_container "$id" "${verdict#remove:}" "$project" ;; esac
  done
  run docker network prune -f
  expire_markers
  disk_check
}

emergency_cleanup() {
  containers_psv | while IFS='|' read -r id created session project; do
    [ -n "$id" ] || continue
    owner=$(owner_of "$session" "$project")
    case "$owner" in
      ""|manual) remove_container "$id" emergency "$project" ;;
      *) session_active "$owner" || remove_container "$id" emergency "$project" ;;
    esac
  done
}

expire_markers() {
  find "$SESSIONS_DIR" -maxdepth 1 -type f -mmin +"$JANITOR_MARKER_MAX_AGE_MIN" 2>/dev/null |
    while read -r f; do log "expiring stale session marker $(basename "$f")"; rm -f "$f"; done
}

docker_usage_pct() { df -P "$DOCKER_ROOT" | awk 'NR == 2 { sub(/%/, "", $5); print $5 }'; }

prune_light() {
  log "hourly prune"
  run docker container prune -f
  run docker image prune -f
  run docker network prune -f
  run docker volume prune -af
}

prune_full() {
  log "full prune (docker storage at $(docker_usage_pct)%)"
  run docker system prune -af --volumes
  run docker builder prune -af
  log "full prune done (docker storage at $(docker_usage_pct)%)"
}

disk_check() {
  pct=$(docker_usage_pct)
  if [ "$pct" -ge "$JANITOR_HARD_PCT" ]; then
    log "docker storage at ${pct}% (>= ${JANITOR_HARD_PCT}%): emergency cleanup"
    emergency_cleanup
    prune_full
  elif [ "$pct" -ge "$JANITOR_SOFT_PCT" ]; then
    log "docker storage at ${pct}% (>= ${JANITOR_SOFT_PCT}%): full prune"
    prune_full
  fi
}

# write_env_file <file>: janitor settings from the environment, single-quoted so cron can source them
write_env_file() {
  env | grep -E '^(JANITOR_[A-Z_]+|SESSIONS_DIR|WORKSPACE_DIR|TZ)=' | while IFS= read -r line; do
    printf "export %s='%s'\n" "${line%%=*}" "$(printf '%s' "${line#*=}" | sed "s/'/'\\\\''/g")"
  done > "$1"
}

log_workspace_size() { log "workspace size: $(du -sh "$WORKSPACE_DIR" 2>/dev/null | cut -f1)"; }
