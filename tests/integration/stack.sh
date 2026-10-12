#!/usr/bin/env bash
# End-to-end checks of the stack: TLS to dind, tagging, ports, janitor, session-end, healthcheck.
set -euo pipefail
cd "$(dirname "$0")/../.."
dc() { docker compose -p crtest -f compose.yaml -f compose.build.yaml -f tests/integration/compose.test.yaml "$@"; }
cx() { dc exec -T -u claude -w "${W:-/workspace}" claude bash -c "$1"; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; dc logs --tail 40; exit 1; }
trap 'dc down -v --remove-orphans >/dev/null 2>&1 || true; rm -rf "${KEYDIR:-}"' EXIT
SID=deadbeef-1111-2222-3333-444455556666
KEYDIR=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -f "$KEYDIR/id" -C stack-test
export SSH_TEST_PUBKEY=$(cat "$KEYDIR/id.pub")

dc up -d --build
for _ in $(seq 90); do cx true 2>/dev/null && break; sleep 2; done
cx 'docker info --format "{{.ServerVersion}}"' >/dev/null || fail "claude cannot reach dind over TLS"
pass "claude reaches dind over TLS"

cx "CLAUDE_SESSION_ID=$SID docker run -d --name t-env alpine sleep 600" >/dev/null
[ "$(cx 'docker inspect -f "{{index .Config.Labels \"claude.session\"}}" t-env')" = deadbeef ] || fail "env tagging"
pass "docker run tagged from CLAUDE_SESSION_ID"

cx 'mkdir -p /workspace/wt/demo-deadbeef && printf "services:\n  web:\n    image: nginx:alpine\n    ports: [\"18000:80\"]\n" > /workspace/wt/demo-deadbeef/compose.yaml'
W=/workspace/wt/demo-deadbeef cx 'docker compose up -d --wait' >/dev/null
projects=$(cx 'docker ps --format "{{.Label \"com.docker.compose.project\"}}"')
grep -qx demo-deadbeef <<<"$projects" || fail "compose project suffix"
pass "compose project tagged from worktree path"

cx 'curl -fsS -o /dev/null http://dind:18000' || fail "published port not reachable at dind:18000"
pass "project port reachable from claude"

cx 'docker run -d --name t-manual alpine sleep 600' >/dev/null
cx 'CLAUDE_SESSION_ID=cafebabe-0 docker run -d --name t-orphan alpine sleep 600' >/dev/null
cx "printf '{\"session_id\":\"$SID\",\"cwd\":\"/workspace\"}' | /usr/local/lib/claude-remote/hooks/session-start.sh"
dc exec -T dind janitor.sh sweep
names=$(cx 'docker ps -a --format "{{.Names}}"')
grep -qx t-orphan <<<"$names" && fail "janitor kept orphan"
grep -qx t-env <<<"$names" || fail "janitor removed active session container"
grep -qx t-manual <<<"$names" || fail "janitor removed manual container"
pass "janitor removes orphans, keeps active and manual"

cx "printf '{\"session_id\":\"$SID\"}' | /usr/local/lib/claude-remote/hooks/session-end.sh"
names=$(cx 'docker ps -a --format "{{.Names}}"')
grep -qx t-env <<<"$names" && fail "session-end left t-env"
grep -q demo-deadbeef <<<"$names" && fail "session-end left compose project"
grep -qx t-manual <<<"$names" || fail "session-end removed manual container"
cx "test ! -e /workspace/.claude-remote/sessions/$SID" || fail "marker not removed"
pass "session-end tears down only its own work"

[ "$(cx 'cd "$(mktemp -d)" && git init -q && git remote add origin https://github.com/acme/api.git && git config user.email')" = work@example.com ] || fail "per-repo identity"
[ "$(cx 'cd "$(mktemp -d)" && git init -q && git config user.email')" = fallback@example.com ] || fail "fallback identity"
pass "commit identities follow the remote"

[ "$(cx 'jq -r .permissions.defaultMode /etc/claude-code/managed-settings.json')" = default ] || fail "invalid PERMISSION_MODE not reset"
pass "invalid PERMISSION_MODE falls back to default"

dc cp "$KEYDIR/id" claude:/tmp/stack-test-key >/dev/null
dc exec -T claude sh -c 'chown claude /tmp/stack-test-key && chmod 600 /tmp/stack-test-key'
sshc() { cx "ssh -p 2222 -i /tmp/stack-test-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $1 claude@localhost '$2'"; }
[ "$(sshc "" 'docker info --format {{.ServerVersion}} >/dev/null && go version >/dev/null && echo ok')" = ok ] || fail "SSH key login with tooling env"
if sshc "-o BatchMode=yes -o PubkeyAuthentication=no" true 2>/dev/null; then fail "SSH accepted a login without a key"; fi
pass "SSH: key login gets docker and toolchains, keyless login refused"

if dc exec -T -u claude claude env HOME=/home/claude /usr/local/bin/healthcheck >/dev/null; then
  fail "healthcheck passed without a claude.ai login"
fi
pass "healthcheck unhealthy before login"
