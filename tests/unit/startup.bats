setup() {
  load helpers/common
  TMP=$(mktemp -d)
  unset SSH_AUTHORIZED_KEYS SSH_AUTHORIZED_KEYS_URL PERMISSION_MODE
  cp "$ROOT/images/claude/rootfs/etc/claude-code/managed-settings.json" "$TMP/settings.json"
}
teardown() { rm -rf "$TMP"; }

@test "keys split on ';' and newlines, comments and blanks dropped" {
  export SSH_AUTHORIZED_KEYS=$'ssh-ed25519 AAAA1 mac; ssh-ed25519 AAAA2 phone\n\n# old laptop\nssh-rsa BBBB3 ipad'
  run "$CLAUDE_BIN_DIR/render-authorized-keys"
  [ "$status" -eq 0 ]
  [ "$output" = $'ssh-ed25519 AAAA1 mac\nssh-ed25519 AAAA2 phone\nssh-rsa BBBB3 ipad' ]
}
@test "keys from URLs are merged and deduplicated" {
  printf 'ssh-ed25519 AAAA1 mac\nssh-ed25519 AAAA9 gh\n' > "$TMP/keys"
  export SSH_AUTHORIZED_KEYS='ssh-ed25519 AAAA1 mac' SSH_AUTHORIZED_KEYS_URL="file://$TMP/keys"
  run "$CLAUDE_BIN_DIR/render-authorized-keys"
  [ "$output" = $'ssh-ed25519 AAAA1 mac\nssh-ed25519 AAAA9 gh' ]
}
@test "an unreachable URL warns but keeps static keys" {
  export SSH_AUTHORIZED_KEYS='ssh-ed25519 AAAA1 mac' SSH_AUTHORIZED_KEYS_URL="file://$TMP/missing"
  run "$CLAUDE_BIN_DIR/render-authorized-keys"
  [ "$status" -eq 0 ]
  [[ $output == *"could not fetch"* ]]
  [[ $output == *"ssh-ed25519 AAAA1 mac"* ]]
}
@test "permission mode defaults to auto" {
  run "$CLAUDE_BIN_DIR/apply-permission-mode" "$TMP/settings.json"
  [ "$status" -eq 0 ]; [ "${lines[-1]}" = auto ]
  [ "$(jq -r .permissions.defaultMode "$TMP/settings.json")" = auto ]
}
@test "valid permission mode is applied and hooks are preserved" {
  PERMISSION_MODE=acceptEdits run "$CLAUDE_BIN_DIR/apply-permission-mode" "$TMP/settings.json"
  [ "${lines[-1]}" = acceptEdits ]
  [ "$(jq -r .permissions.defaultMode "$TMP/settings.json")" = acceptEdits ]
  jq -e '.hooks.SessionEnd and .permissions.allow' "$TMP/settings.json"
}
@test "invalid permission mode falls back to default with a warning" {
  PERMISSION_MODE=yolo run "$CLAUDE_BIN_DIR/apply-permission-mode" "$TMP/settings.json"
  [ "$status" -eq 0 ]
  [[ $output == *"invalid PERMISSION_MODE 'yolo'"* ]]
  [ "${lines[-1]}" = default ]
  [ "$(jq -r .permissions.defaultMode "$TMP/settings.json")" = default ]
}
@test "ssh environment is written 0600 with the tooling env when SSH is enabled" {
  export ENABLE_SSH=true GH_TOKEN=ghp_x DOCKER_HOST=tcp://dind:2376
  run "$CLAUDE_BIN_DIR/write-ssh-environment" "$TMP/environment"
  [ "$status" -eq 0 ]
  grep -Fxq "GH_TOKEN=ghp_x" "$TMP/environment"; grep -Fxq "DOCKER_HOST=tcp://dind:2376" "$TMP/environment"
  [ "$(stat -c %a "$TMP/environment")" = 600 ]
}
@test "ssh environment (and its tokens) is removed when SSH is disabled" {
  echo "GH_TOKEN=old" > "$TMP/environment"
  ENABLE_SSH=false run "$CLAUDE_BIN_DIR/write-ssh-environment" "$TMP/environment"
  [ "$status" -eq 0 ]; [ ! -e "$TMP/environment" ]
}
