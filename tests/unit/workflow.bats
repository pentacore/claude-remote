setup() { load helpers/common; F="$ROOT/.github/workflows/images.yml"; }

@test "only main pushes images (a dispatch on another branch must not overwrite :latest)" {
  run grep -cE "github.event_name != 'pull_request' && github.ref == 'refs/heads/main'" "$F"
  [ "$output" = 2 ]   # the login step and build-push's push:
}

@test "Dockerfiles use literal FROM tags (Dependabot cannot resolve build ARGs)" {
  run grep -nE '^FROM .*\$\{' "$ROOT"/images/*/Dockerfile "$ROOT"/tests/Dockerfile
  [ "$status" -eq 1 ]
}
@test "Dependabot watches the workflow and every Dockerfile" {
  D="$ROOT/.github/dependabot.yml"
  grep -q 'package-ecosystem: github-actions' "$D"
  for dir in /images/claude /images/dind /tests; do
    grep -qE "^\s+- \"?$dir\"?\s*$" "$D"
  done
}
@test "Dependabot groups updates: one PR for actions, one for base images" {
  D="$ROOT/.github/dependabot.yml"
  [ "$(grep -cE '^\s+groups:' "$D")" = 2 ]
  grep -qE '^\s+github-actions:' "$D"
  grep -qE '^\s+base-images:' "$D"
}
@test "images are based on Debian trixie (13), not bookworm" {
  run grep -n bookworm "$ROOT/images/claude/Dockerfile"
  [ "$status" -eq 1 ]
  grep -q '^FROM debian:trixie-slim' "$ROOT/images/claude/Dockerfile"
}
