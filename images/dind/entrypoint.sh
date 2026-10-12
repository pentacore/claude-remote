#!/bin/sh
# Mount a fixed-size loop image at /var/lib/docker (hard cap on Docker storage),
# start the janitor's crond, then hand over to the stock dind entrypoint.
set -eu
IMG=${DIND_IMG:-/dind/docker.img}
SIZE_GB=${DIND_SIZE_GB:-100}
want=$((SIZE_GB * 1024 * 1024 * 1024))

mkdir -p "$(dirname "$IMG")" /var/lib/docker
fs_type() { blkid "$IMG" 2>/dev/null | sed -n 's/.* TYPE="\([^"]*\)".*/\1/p'; }

if [ ! -f "$IMG" ]; then
  echo "dind: creating ${SIZE_GB}G loop image at $IMG"
  : > "$IMG"
  chattr +C "$IMG" 2>/dev/null || true # no copy-on-write on btrfs pools
  truncate -s "$want" "$IMG"
fi
# xfs: Unraid kernels ship xfs/btrfs/zfs but no ext4. Anything else in the image (nothing yet, an
# interrupted first start, or ext4 from an earlier version) only held dind's cache: reformat it.
type=$(fs_type)
if [ "$type" != xfs ]; then
  if [ -n "$type" ]; then
    echo "dind: $IMG holds $type, which not every kernel can mount; reformatting as xfs (cached images are dropped)"
  else
    echo "dind: no filesystem in $IMG; formatting"
  fi
  mkfs.xfs -q -f "$IMG"
fi
grow=
have=$(stat -c %s "$IMG")
if [ "$have" -lt "$want" ]; then
  echo "dind: growing loop image to ${SIZE_GB}G"
  truncate -s "$want" "$IMG"
  grow=1
elif [ "$have" -gt "$want" ]; then
  echo "dind: WARNING: DIND_SIZE_GB=${SIZE_GB} is below the existing $((have / 1073741824))G image; shrinking is not supported, keeping current size"
fi

# Mount our image over /var/lib/docker unless it is already backed by it. The stock image declares
# /var/lib/docker a VOLUME, and on Unraid that volume itself sits on a loop device (Docker's own
# docker.img), so "is a mountpoint" or "is a /dev/loop*" says nothing about our cap.
current=$(awk '$2 == "/var/lib/docker" { dev = $1 } END { print dev }' /proc/mounts)
if ! losetup -a 2>/dev/null | grep "^$current:" | grep -qF "$IMG"; then
  mount -o loop "$IMG" /var/lib/docker
fi
if [ -n "$grow" ]; then
  # Grow xfs online to exactly the image size. Without -D, xfs_growfs sizes the device from the
  # first /proc/mounts entry for /var/lib/docker, which is the VOLUME underneath, not our loop.
  xfs_growfs -D $((want / $(stat -f -c %S /var/lib/docker))) /var/lib/docker >/dev/null
fi

# busybox crond does not pass the container env to jobs
. /usr/local/lib/janitor-lib.sh
write_env_file /etc/janitor.env
crond -b -l 8

exec dockerd-entrypoint.sh "$@"
