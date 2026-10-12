setup() { load helpers/common; F="$ROOT/.github/workflows/images.yml"; }

@test "only main pushes images (a dispatch on another branch must not overwrite :latest)" {
  run grep -cE "github.event_name != 'pull_request' && github.ref == 'refs/heads/main'" "$F"
  [ "$output" = 2 ]   # the login step and build-push's push:
}
