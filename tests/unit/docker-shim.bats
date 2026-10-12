setup() {
  load helpers/common
  export DOCKER_REAL="$HELPERS/print-args"
  unset CLAUDE_SESSION_ID COMPOSE_PROJECT_NAME
  TMP=$(mktemp -d); mkdir -p "$TMP/plain dir"; cd "$TMP/plain dir"
}
teardown() { rm -rf "$TMP"; }
shim() { run "$CLAUDE_BIN_DIR/docker" "$@"; [ "$status" -eq 0 ]; out=$(echo "$output" | paste -sd' ' -); }

@test "no session and no worktree → manual label" {
  shim run --rm alpine true;  [ "$out" = "run --label claude.session=manual --rm alpine true" ]
}
@test "session id from env, cut to 8" {
  export CLAUDE_SESSION_ID=deadbeef-1111-2222-3333-444455556666
  shim run alpine;  [ "$out" = "run --label claude.session=deadbeef alpine" ]
}
@test "session id from worktree path" {
  mkdir -p "$TMP/workspace/wt/api-cafebabe/src"; cd "$TMP/workspace/wt/api-cafebabe/src"
  shim create alpine;  [ "$out" = "create --label claude.session=cafebabe alpine" ]
}
@test "global options before the command are skipped" {
  shim --context x -l debug run alpine
  [ "$out" = "--context x -l debug run --label claude.session=manual alpine" ]
}
@test "two-word commands" {
  shim container run alpine;   [ "$out" = "container run --label claude.session=manual alpine" ]
  shim network create n1;      [ "$out" = "network create --label claude.session=manual n1" ]
  shim volume create v1;       [ "$out" = "volume create --label claude.session=manual v1" ]
  shim buildx build .;         [ "$out" = "buildx build --label claude.session=manual ." ]
  shim image build .;          [ "$out" = "image build --label claude.session=manual ." ]
  shim build -t x .;           [ "$out" = "build --label claude.session=manual -t x ." ]
}
@test "other commands pass through untouched" {
  shim ps -a;              [ "$out" = "ps -a" ]
  shim network ls;         [ "$out" = "network ls" ]
  shim rm -f c1;           [ "$out" = "rm -f c1" ]
  shim;                    [ "$out" = "" ]
}
@test "compose: project from sanitised directory name" {
  mkdir -p "$TMP/My App"; cd "$TMP/My App"
  export CLAUDE_SESSION_ID=deadbeef-1
  shim compose up -d;  [ "$out" = "compose -p my-app-deadbeef up -d" ]
}
@test "compose: explicit -p, --project-name= and -pNAME get the suffix" {
  export CLAUDE_SESSION_ID=deadbeef-1
  shim compose -p foo up;                [ "$out" = "compose -p foo-deadbeef up" ]
  shim compose --project-name=foo down;  [ "$out" = "compose -p foo-deadbeef down" ]
  shim compose -pfoo ps;                 [ "$out" = "compose -p foo-deadbeef ps" ]
}
@test "compose: other global options kept in order" {
  export CLAUDE_SESSION_ID=deadbeef-1
  shim compose -f a.yml --env-file .env.test -p foo up -d
  [ "$out" = "compose -p foo-deadbeef -f a.yml --env-file .env.test up -d" ]
}
@test "compose: subcommand -p (publish) is not mistaken for project name" {
  export CLAUDE_SESSION_ID=deadbeef-1
  shim compose run -p 8080:80 web
  [ "$out" = "compose -p plain-dir-deadbeef run -p 8080:80 web" ]
}
@test "compose: COMPOSE_PROJECT_NAME is used as base" {
  export CLAUDE_SESSION_ID=deadbeef-1 COMPOSE_PROJECT_NAME=Bar
  shim compose up;  [ "$out" = "compose -p bar-deadbeef up" ]
}
@test "compose: no double suffix" {
  export CLAUDE_SESSION_ID=deadbeef-1
  shim compose -p foo-deadbeef up;  [ "$out" = "compose -p foo-deadbeef up" ]
}
@test "compose: manual suffix without a session" {
  shim compose up;  [ "$out" = "compose -p plain-dir-manual up" ]
}
