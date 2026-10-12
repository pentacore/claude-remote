#!/usr/bin/env bash
# Proves the loop image caps Docker storage, persists across restarts, grows, and refuses to shrink.
set -euo pipefail
cd "$(dirname "$0")/../.."
IMG=claude-remote-dind:test C=crcap V=crcap-data V2=crcap-raw V3=crcap-ext4
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; docker logs "$C" 2>&1 | tail -n 30; exit 1; }
cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; docker volume rm "$V" "$V2" "$V3" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

start() { # start <size_gb> [volume]
  docker rm -f "$C" >/dev/null 2>&1 || true
  docker run -d --privileged --name "$C" -e DIND_SIZE_GB="$1" -v "${2:-$V}:/dind" "$IMG" >/dev/null
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
backed_by_image() { # is /var/lib/docker backed by /dind/docker.img?
  docker exec "$C" sh -c 'dev=$(awk '"'"'$2 == "/var/lib/docker" { d = $1 } END { print d }'"'"' /proc/mounts); losetup -a | grep "^$dev:" | grep -q /dind/docker.img'
}
backed_by_image || fail "/var/lib/docker is not backed by the loop image"
[ "$(docker exec "$C" stat -f -c %T /var/lib/docker)" = xfs ] || fail "loop image is not xfs (Unraid kernels have no ext4)"
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
# capture first: `cmd | grep -q` under pipefail fails when grep exits early and cmd gets SIGPIPE
logs=$(docker logs "$C" 2>&1)
grep -q "shrinking is not supported" <<<"$logs" || fail "no shrink warning"
[ "$(kib_total)" -gt 1800000 ] || fail "filesystem shrank"
pass "lowering DIND_SIZE_GB warns and keeps size"

docker exec "$C" sh -c 'grep -q JANITOR_IDLE_MIN /etc/janitor.env && pgrep crond >/dev/null' || fail "janitor env/crond missing"
docker exec "$C" janitor.sh sweep >/dev/null || fail "janitor sweep failed"
pass "crond running and janitor executes"

# An image file without a filesystem (first start interrupted between truncate and mkfs) is formatted, not a crash loop
docker run --rm -v "$V2:/dind" alpine sh -c ': > /dind/docker.img && truncate -s 1073741824 /dind/docker.img'
start 1 "$V2"
docker exec "$C" sh -c "awk '\$2 == \"/var/lib/docker\" { print \$1 }' /proc/mounts | tail -n 1 | grep -q '^/dev/loop'" \
  || fail "unformatted image was not recovered"
logs=$(docker logs "$C" 2>&1)
grep -q "no filesystem" <<<"$logs" || fail "no recovery log line"
pass "an unformatted image from an interrupted first start is formatted"

# Unraid keeps Docker's own data on a loop device, so dind's /var/lib/docker volume already sits on
# a /dev/loop*: our image must still be mounted over it (the cap was silently skipped before).
docker rm -f "$C" >/dev/null 2>&1 || true
docker run -d --privileged --name "$C" -e DIND_SIZE_GB=1 -v "$V:/dind" --entrypoint sh "$IMG" -c \
  'truncate -s 300M /tmp/host-docker.img && mkfs.xfs -q -f /tmp/host-docker.img \
   && mount -t xfs -o loop /tmp/host-docker.img /var/lib/docker && exec /usr/local/bin/dind-entrypoint.sh' >/dev/null
for _ in $(seq 60); do docker exec "$C" docker -H unix:///var/run/docker.sock info >/dev/null 2>&1 && break; sleep 2; done
backing=$(docker exec "$C" sh -c 'dev=$(awk '"'"'$2 == "/var/lib/docker" { d = $1 } END { print d }'"'"' /proc/mounts); losetup -a | grep "^$dev:"')
grep -q "/dind/docker.img" <<<"$backing" || fail "/var/lib/docker is not backed by /dind/docker.img (got: $backing)"
pass "our loop image is mounted even when /var/lib/docker already sits on another loop device (Unraid)"

# An existing image with a filesystem the kernel may not mount (ext4 from earlier versions) is reformatted as xfs
docker run --rm -v "$V3:/dind" alpine sh -c 'apk add -q e2fsprogs >/dev/null && truncate -s 1073741824 /dind/docker.img && mkfs.ext4 -q -F /dind/docker.img'
start 1 "$V3"
[ "$(docker exec "$C" stat -f -c %T /var/lib/docker)" = xfs ] || fail "ext4 image was not reformatted as xfs"
logs=$(docker logs "$C" 2>&1)
grep -q "holds ext4" <<<"$logs" || fail "no reformat log line"
pass "an ext4 image from an earlier version is reformatted as xfs"
