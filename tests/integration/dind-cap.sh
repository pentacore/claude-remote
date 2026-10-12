#!/usr/bin/env bash
# Proves the loop image caps Docker storage, persists across restarts, grows, and refuses to shrink.
set -euo pipefail
cd "$(dirname "$0")/../.."
IMG=claude-remote-dind:test C=crcap V=crcap-data
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; docker logs "$C" 2>&1 | tail -n 30; exit 1; }
cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; docker volume rm "$V" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

start() { # start <size_gb>
  docker rm -f "$C" >/dev/null 2>&1 || true
  docker run -d --privileged --name "$C" -e DIND_SIZE_GB="$1" -v "$V:/dind" "$IMG" >/dev/null
  for _ in $(seq 60); do
    docker exec "$C" docker -H unix:///var/run/docker.sock info >/dev/null 2>&1 && return 0
    sleep 2
  done
  fail "dind did not become ready"
}
kib_total() { docker exec "$C" df -P /var/lib/docker | awk 'NR == 2 { print $2 }'; }

docker build -q -t "$IMG" images/dind >/dev/null

start 1
[ "$(docker exec "$C" stat -c %s /dind/docker.img)" = 1073741824 ] || fail "image is not 1 GiB"
docker exec "$C" sh -c "awk '\$2 == \"/var/lib/docker\" { print \$1 }' /proc/mounts | tail -n 1 | grep -q '^/dev/loop'" \
  || fail "/var/lib/docker is not the loop image"
pass "1 GiB loop image mounted"

docker exec "$C" touch /var/lib/docker/persist-marker
out=$(docker exec "$C" sh -c 'dd if=/dev/zero of=/var/lib/docker/fill bs=1M count=2048 2>&1' || true)
[[ $out == *"No space left"* ]] || fail "writing 2 GiB did not hit ENOSPC: $out"
[ "$(docker exec "$C" stat -c %s /dind/docker.img)" = 1073741824 ] || fail "image grew past cap"
docker exec "$C" rm -f /var/lib/docker/fill
pass "writes stop at the cap"

start 1
docker exec "$C" test -e /var/lib/docker/persist-marker || fail "data lost on restart (reformatted?)"
pass "restart remounts without reformatting"

start 2
[ "$(kib_total)" -gt 1800000 ] || fail "filesystem did not grow to ~2 GiB"
docker exec "$C" test -e /var/lib/docker/persist-marker || fail "data lost on grow"
pass "raising DIND_SIZE_GB grows the filesystem"

start 1
docker logs "$C" 2>&1 | grep -q "shrinking is not supported" || fail "no shrink warning"
[ "$(kib_total)" -gt 1800000 ] || fail "filesystem shrank"
pass "lowering DIND_SIZE_GB warns and keeps size"

docker exec "$C" sh -c 'grep -q JANITOR_IDLE_MIN /etc/janitor.env && pgrep crond >/dev/null' || fail "janitor env/crond missing"
docker exec "$C" janitor.sh sweep >/dev/null || fail "janitor sweep failed"
pass "crond running and janitor executes"
