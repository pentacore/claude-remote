setup() {
  load helpers/common
  TMP=$(mktemp -d); OUT=$TMP/git
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$TMP/gitconfig
  printf '[include]\n\tpath = %s/identities.gitconfig\n' "$OUT" > "$GIT_CONFIG_GLOBAL"
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  export GIT_NAME="Fallback Person" GIT_EMAIL=me@example.com
  export GIT_IDENTITIES='github.com=Jane Personal <jane@personal.example>; github.com/acme=Jane Doe <jane@acme.example>'
}
teardown() { rm -rf "$TMP"; }
render() { run "$CLAUDE_BIN_DIR/render-git-identities" "$OUT"; [ "$status" -eq 0 ]; }
cfg() { # cfg <origin-url|""> <key>
  local r; r=$(mktemp -d "$TMP/r.XXXXXX"); git init -q "$r"
  if [ -n "$1" ]; then git -C "$r" remote add origin "$1"; fi
  git -C "$r" config "$2"
}

@test "most specific prefix wins regardless of order" {
  render
  run cfg https://github.com/acme/api.git user.email; [ "$output" = jane@acme.example ]
  run cfg https://github.com/acme/api.git user.name;  [ "$output" = "Jane Doe" ]
}
@test "host-wide prefix" {
  render
  run cfg https://github.com/someone/x.git user.email; [ "$output" = jane@personal.example ]
}
@test "no match falls back to GIT_NAME/GIT_EMAIL" {
  render
  run cfg https://gitlab.com/g/app.git user.email; [ "$output" = me@example.com ]
  run cfg "" user.name;                             [ "$output" = "Fallback Person" ]
}
@test "invalid entries are skipped with a warning" {
  GIT_IDENTITIES='nonsense;github.com=No Email' render
  [[ $output == *"skipping invalid entry 'nonsense'"* ]]
  run cfg https://github.com/x/y.git user.email; [ "$output" = me@example.com ]
}
@test "re-rendering drops stale identities" {
  render
  GIT_IDENTITIES= render
  [ -z "$(ls "$OUT"/id-*.gitconfig 2>/dev/null)" ]
  run cfg https://github.com/acme/api.git user.email; [ "$output" = me@example.com ]
}
@test "quotes and backslashes in names survive" {
  GIT_IDENTITIES='github.com=Ann "Annie" O\Neil <ann@example.com>' render
  run cfg https://github.com/x/y.git user.name; [ "$output" = 'Ann "Annie" O\Neil' ]
}
