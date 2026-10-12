setup() {
  load helpers/common
  export HOME=$(mktemp -d) IDE_KEEP_VERSIONS=2 CACHE_MAX_GB=20
  d=$HOME/.cache/JetBrains/RemoteDev/dist
  mkdir -p "$d/v1" "$d/v2" "$d/v3"
  touch -t "$(minutes_ago 300)" "$d/v1"; touch -t "$(minutes_ago 200)" "$d/v2"; touch -t "$(minutes_ago 100)" "$d/v3"
  mkdir -p "$HOME/.npm/_cacache" "$HOME/go/pkg/mod/x" && echo data > "$HOME/.npm/_cacache/f"
  chmod -R a-w "$HOME/go/pkg/mod"
}
teardown() { chmod -R u+w "$HOME"; rm -rf "$HOME"; }

@test "keeps only the newest IDE backends" {
  run "$CLAUDE_BIN_DIR/maintenance"
  [ "$status" -eq 0 ]
  d=$HOME/.cache/JetBrains/RemoteDev/dist
  [ ! -e "$d/v1" ]; [ -d "$d/v2" ]; [ -d "$d/v3" ]
}
@test "caches under the limit are kept" {
  run "$CLAUDE_BIN_DIR/maintenance"
  [ "$status" -eq 0 ]; [[ $output == *"package caches:"* ]]
  [ -f "$HOME/.npm/_cacache/f" ]; [ -d "$HOME/go/pkg/mod/x" ]
}
@test "caches over the limit are wiped, including read-only go modules" {
  CACHE_MAX_GB=0 run "$CLAUDE_BIN_DIR/maintenance"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.npm/_cacache" ]; [ ! -e "$HOME/go/pkg/mod" ]
  [[ $output == *"clearing"* ]]
}
@test "missing directories are fine" {
  rm -rf "$HOME/.cache" "$HOME/.npm"; chmod -R u+w "$HOME/go"; rm -rf "$HOME/go"
  run "$CLAUDE_BIN_DIR/maintenance"; [ "$status" -eq 0 ]
}
