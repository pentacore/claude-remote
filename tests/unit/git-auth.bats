setup() {
  load helpers/common
  export CLAUDE_REMOTE_LIB=$LIB_DIR
  unset GH_TOKEN GITLAB_TOKEN GITLAB_HOST
  export GIT_TOKENS='github.com/acme=ghp_work; github.com=ghp_personal ;gitlab.com/acme-group=glpat_a;https://git.example.se/=glpat_b'
  TMP=$(mktemp -d)
  printf '#!/usr/bin/env bash\necho "token=${GH_TOKEN:-} args=$*"\n' > "$TMP/gh-real"
  printf '#!/usr/bin/env bash\necho "host=${GITLAB_HOST:-} token=${GITLAB_TOKEN:-} args=$*"\n' > "$TMP/glab-real"
  chmod +x "$TMP/gh-real" "$TMP/glab-real"
  export GH_REAL=$TMP/gh-real GLAB_REAL=$TMP/glab-real
}
teardown() { rm -rf "$TMP"; }
lib() { run bash -c ". '$LIB_DIR/tokens.sh'; $1"; }
cred() { printf 'protocol=https\nhost=%s\npath=%s\n\n' "$1" "$2" | "$CLAUDE_BIN_DIR/git-credential-env" "${3:-get}"; }
inrepo() { git init -q "$TMP/r"; git -C "$TMP/r" remote add origin "$1"; cd "$TMP/r"; }

@test "longest prefix wins" {
  lib 'token_for github.com acme/api.git'; [ "$output" = ghp_work ]
  lib 'token_for github.com someone/x';    [ "$output" = ghp_personal ]
}
@test "prefixes match on path boundaries only" {
  lib 'token_for github.com acmex/api'; [ "$output" = ghp_personal ]
}
@test "scheme, trailing slash and whitespace in GIT_TOKENS are ignored" {
  lib 'token_for git.example.se team/app.git'; [ "$output" = glpat_b ]
}
@test "falls back to GH_TOKEN and GITLAB_TOKEN" {
  GIT_TOKENS= GH_TOKEN=ghp_fb lib 'token_for github.com x/y'; [ "$output" = ghp_fb ]
  GIT_TOKENS= GITLAB_TOKEN=glpat_fb GITLAB_HOST=https://gl.example.se/ lib 'token_for gl.example.se x/y'; [ "$output" = glpat_fb ]
}
@test "unknown host gets nothing" {
  lib 'token_for bitbucket.org a/b'; [ -z "$output" ]
}
@test "parse_remote handles https, embedded credentials and scp-style" {
  lib 'parse_remote https://github.com/acme/api.git';       [ "$output" = "github.com acme/api.git" ]
  lib 'parse_remote https://x:tok@gitlab.com/g/sub/app.git'; [ "$output" = "gitlab.com g/sub/app.git" ]
  lib 'parse_remote git@github.com:acme/api.git';            [ "$output" = "github.com acme/api.git" ]
}
@test "credential helper: github uses x-access-token" {
  run cred github.com acme/api.git; [ "$output" = $'username=x-access-token\npassword=ghp_work' ]
}
@test "credential helper: gitlab uses oauth2" {
  run cred gitlab.com acme-group/sub/app.git; [ "$output" = $'username=oauth2\npassword=glpat_a' ]
}
@test "credential helper: unknown host and store/erase are silent" {
  run cred bitbucket.org a/b.git;            [ "$status" -eq 0 ]; [ -z "$output" ]
  run cred github.com acme/api.git store;    [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "gh picks the token from origin" {
  inrepo https://github.com/acme/api.git
  run "$CLAUDE_BIN_DIR/gh" pr list; [ "$output" = "token=ghp_work args=pr list" ]
}
@test "gh -R overrides origin" {
  inrepo https://github.com/acme/api.git
  run "$CLAUDE_BIN_DIR/gh" pr list -R someone/x; [ "$output" = "token=ghp_personal args=pr list -R someone/x" ]
}
@test "gh repo clone outside a repo uses the clone target" {
  cd "$TMP"
  run "$CLAUDE_BIN_DIR/gh" repo clone acme/api; [ "$output" = "token=ghp_work args=repo clone acme/api" ]
}
@test "glab sets host and token from origin" {
  inrepo https://git.example.se/team/app.git
  run "$CLAUDE_BIN_DIR/glab" mr list; [ "$output" = "host=git.example.se token=glpat_b args=mr list" ]
}
@test "glab -R group path uses GITLAB_HOST" {
  cd "$TMP"
  GITLAB_HOST=gitlab.com run "$CLAUDE_BIN_DIR/glab" mr list -R acme-group/app
  [ "$output" = "host=gitlab.com token=glpat_a args=mr list -R acme-group/app" ]
}
@test "system gitconfig sends the repo path to the helper" {
  git config -f "$ROOT/images/claude/rootfs/etc/gitconfig" --get credential.useHttpPath | grep -qx true
}
