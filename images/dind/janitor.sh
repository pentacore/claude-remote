#!/bin/sh
# Cron entry point: janitor.sh sweep | prune-light | prune-full
set -u
[ -f /etc/janitor.env ] && . /etc/janitor.env
. "${JANITOR_LIB:-/usr/local/lib/janitor-lib.sh}"

exec 9>/run/janitor.lock
flock 9

case "${1:-}" in
  sweep) sweep ;;
  prune-light) prune_light ;;
  prune-full) prune_full; log_workspace_size ;;
  *) echo "usage: janitor.sh sweep|prune-light|prune-full" >&2; exit 2 ;;
esac
