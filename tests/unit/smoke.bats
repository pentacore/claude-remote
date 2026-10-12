setup() { load helpers/common; }

@test "test image has the tools the scripts need" {
  run sh -c 'command -v git jq curl find flock'
  [ "$status" -eq 0 ]
}
