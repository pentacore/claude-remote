setup() {
  load helpers/common
  TMP=$(mktemp -d)
  export SESSIONS_DIR=$TMP/sessions FIXTURE=$TMP/containers.json FAKE_DOCKER_LOG=$TMP/docker.log
  mkdir -p "$SESSIONS_DIR" "$TMP/bin"; : > "$FAKE_DOCKER_LOG"
  ln -s "$HELPERS/fake-docker" "$TMP/bin/docker"
  export PATH="$TMP/bin:$PATH"
  export JANITOR_IDLE_MIN=120 JANITOR_MAX_AGE_MIN=1440 JANITOR_UNTAGGED_MAX_AGE_MIN=60 \
         JANITOR_MARKER_MAX_AGE_MIN=10080 JANITOR_SOFT_PCT=75 JANITOR_HARD_PCT=90
}
teardown() { rm -rf "$TMP"; }

# lib <code>: run code under busybox sh with the lib loaded and docker data faked
lib() {
  sh -c ". '$JANITOR_LIB'
list_containers_json() { cat \"\$FIXTURE\"; }
docker_usage_pct() { echo \"\${FAKE_USAGE:-10}\"; }
$1"
}
marker() { touch -t "$(minutes_ago "$2")" "$SESSIONS_DIR/$1"; }   # marker <session_id> <idle_min>
# containers "id|age_min|session_label|compose_project" ...
containers() {
  printf '%s\n' "$@" | jq -R -s --argjson now "$(date +%s)" '
    split("\n") | map(select(length > 0) | split("|")) | map({
      Id: .[0], Created: ($now - ((.[1] | tonumber) * 60)),
      Labels: ({}
        + (if (.[2] // "") != "" then {"claude.session": .[2]} else {} end)
        + (if (.[3] // "") != "" then {"com.docker.compose.project": .[3]} else {} end))})' > "$FIXTURE"
}
removed() { grep -Fxq "rm -f -v $1" "$FAKE_DOCKER_LOG"; }

@test "owner_of: label wins and is cut to 8 chars" {
  run lib 'owner_of deadbeef-1111 api-cafebabe'; [ "$output" = deadbeef ]
}
@test "owner_of: compose project suffix" {
  run lib 'owner_of "" api-cafebabe'; [ "$output" = cafebabe ]
}
@test "owner_of: manual label and manual compose suffix" {
  run lib 'owner_of manual ""'; [ "$output" = manual ]
  run lib 'owner_of "" web-manual'; [ "$output" = manual ]
}
@test "owner_of: untagged" {
  run lib 'owner_of "" my-project'; [ "$output" = "" ]
  run lib 'owner_of "" ""'; [ "$output" = "" ]
}
@test "decide: anything past max age is removed" {
  marker deadbeef-x 1
  run lib 'decide deadbeef 1440'; [ "$output" = remove:max-age ]
  run lib 'decide manual 1500'; [ "$output" = remove:max-age ]
}
@test "decide: untagged kept under an hour, removed after" {
  run lib 'decide "" 59'; [ "$output" = keep ]
  run lib 'decide "" 60'; [ "$output" = remove:untagged ]
}
@test "decide: manual survives until the ceiling" {
  run lib 'decide manual 1000'; [ "$output" = keep ]
}
@test "decide: orphan when no marker" {
  run lib 'decide cafebabe 5'; [ "$output" = remove:orphan ]
}
@test "decide: idle when marker older than idle limit" {
  marker cafebabe-1 121
  run lib 'decide cafebabe 5'; [ "$output" = remove:idle ]
}
@test "decide: active session kept" {
  marker cafebabe-1 3
  run lib 'decide cafebabe 5'; [ "$output" = keep ]
}
@test "sweep removes exactly the doomed containers" {
  marker aaaaaaaa-1 1
  marker bbbbbbbb-1 300
  containers "c-active|10|aaaaaaaa|" "c-idle|10||api-bbbbbbbb" "c-orphan|10|cccccccc|" \
             "c-untagged-old|90||" "c-untagged-new|5||" "c-manual|600|manual|" "c-ancient|2000|aaaaaaaa|"
  run lib 'sweep'
  [ "$status" -eq 0 ]
  removed c-idle; removed c-orphan; removed c-untagged-old; removed c-ancient
  refute removed c-active; refute removed c-untagged-new; refute removed c-manual
  grep -Fxq "network prune -f" "$FAKE_DOCKER_LOG"
}
@test "sweep logs reasons" {
  containers "c-orphan|10|cccccccc|"
  run lib 'sweep'
  [[ $output == *"reason=orphan"* ]]
}
@test "disk_check below soft threshold does nothing" {
  FAKE_USAGE=50 run lib 'disk_check'
  [ "$status" -eq 0 ]
  refute grep -q "system prune" "$FAKE_DOCKER_LOG"
}
@test "disk_check at soft threshold runs a full prune but removes no containers" {
  containers "c-manual|10|manual|"
  FAKE_USAGE=80 run lib 'disk_check'
  grep -Fxq "system prune -af --volumes" "$FAKE_DOCKER_LOG"
  grep -Fxq "builder prune -af" "$FAKE_DOCKER_LOG"
  refute removed c-manual
}
@test "disk_check at hard threshold removes everything not owned by an active session" {
  marker aaaaaaaa-1 1
  marker bbbbbbbb-1 300
  containers "c-active|10|aaaaaaaa|" "c-idle|10|bbbbbbbb|" "c-manual|10|manual|" "c-untagged|1||"
  FAKE_USAGE=95 run lib 'disk_check'
  removed c-idle; removed c-manual; removed c-untagged
  refute removed c-active
  grep -Fxq "system prune -af --volumes" "$FAKE_DOCKER_LOG"
}
@test "expire_markers deletes week-old markers only" {
  marker old-session 10081
  marker new-session 10
  run lib 'expire_markers'
  [ ! -e "$SESSIONS_DIR/old-session" ]; [ -e "$SESSIONS_DIR/new-session" ]
}
@test "prune_light runs the hourly prunes" {
  run lib 'prune_light'
  for c in "container prune -f" "image prune -f" "network prune -f" "volume prune -af"; do
    grep -Fxq "$c" "$FAKE_DOCKER_LOG"
  done
}
@test "owner_of: labels that are not 8 hex chars or manual count as untagged (no glob tricks)" {
  run lib 'owner_of "*" ""';        [ "$output" = "" ]
  run lib 'owner_of "zzzzzzzz" ""'; [ "$output" = "" ]
  run lib 'owner_of "dead*" ""';    [ "$output" = "" ]
}
@test "a container labelled '*' does not ride on another session's marker" {
  marker aaaaaaaa-1 1
  containers "c-glob|90|*|"
  run lib 'sweep'
  removed c-glob
}
@test "write_env_file quotes values so cron can source them safely" {
  export TZ="Europe/Stockholm\$(touch $TMP/pwned)'\`x\`\"" JANITOR_IDLE_MIN=7
  run lib "write_env_file '$TMP/env'"
  [ "$status" -eq 0 ]
  run sh -c ". '$TMP/env'; printf '%s|%s' \"\$TZ\" \"\$JANITOR_IDLE_MIN\""
  [ "$output" = "Europe/Stockholm\$(touch $TMP/pwned)'\`x\`\"|7" ]
  [ ! -e "$TMP/pwned" ]
}
