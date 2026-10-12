#!/bin/sh
# Mount a fixed-size loop image at /var/lib/docker (hard cap on Docker storage),
# start the janitor's crond, then hand over to the stock dind entrypoint.
set -eu
IMG=${DIND_IMG:-/dind/docker.img}
SIZE_GB=${DIND_SIZE_GB:-100}
want=$((SIZE_GB * 1024 * 1024 * 1024))

mkdir -p "$(dirname "$IMG")" /var/lib/docker
if [ ! -f "$IMG" ]; then
  echo "dind: creating ${SIZE_GB}G loop image at $IMG"
  : > "$IMG"
  chattr +C "$IMG" 2>/dev/null || true # no copy-on-write on btrfs pools
  truncate -s "$want" "$IMG"
fi
if ! dumpe2fs -h "$IMG" >/dev/null 2>&1; then
  # new image, or a first start that was interrupted before mkfs: there is nothing to lose
  echo "dind: no filesystem in $IMG; formatting"
  mkfs.ext4 -q -F -m 0 "$IMG"
fi
have=$(stat -c %s "$IMG")
if [ "$have" -lt "$want" ]; then
  echo "dind: growing loop image to ${SIZE_GB}G"
  truncate -s "$want" "$IMG"
  e2fsck -fy "$IMG" >/dev/null || [ $? -lt 4 ]
  resize2fs "$IMG" >/dev/null
elif [ "$have" -gt "$want" ]; then
  echo "dind: WARNING: DIND_SIZE_GB=${SIZE_GB} is below the existing $((have / 1073741824))G image; shrinking is not supported, keeping current size"
fi

# The stock image declares /var/lib/docker a VOLUME, so it is already a mountpoint: mount the
# loop image over it unless a loop device is mounted there already.
current=$(awk '$2 == "/var/lib/docker" { dev = $1 } END { print dev }' /proc/mounts)
case "$current" in
  /dev/loop*) ;;
  *) mount -o loop "$IMG" /var/lib/docker ;;
esac

# busybox crond does not pass the container env to jobs
. /usr/local/lib/janitor-lib.sh
write_env_file /etc/janitor.env
crond -b -l 8

exec dockerd-entrypoint.sh "$@"
