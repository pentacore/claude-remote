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
    grep -qE "^\s+directory: $dir\s*$" "$D"
  done
}
