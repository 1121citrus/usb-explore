#!/usr/bin/env bash
# Container PID 1: attach disk image to a loop device, dispatch subcommand,
# guarantee cleanup regardless of how the container exits.
set -euo pipefail

SUBCOMMAND="${1:-info}"
shift || true

# Attach the disk image read-only with partition scanning (-P creates
# /dev/loop0p1, /dev/loop0p2, … for each partition automatically).
LOOP=$(losetup --find)
losetup --read-only --partscan "${LOOP}" /disk.img

# Guaranteed cleanup: unmount and detach the loop device on any exit path,
# including normal exit, error, Ctrl-C, and docker stop (SIGTERM).
cleanup() {
    local rc=$?
    umount /mnt/part 2>/dev/null || true
    losetup --detach "${LOOP}" 2>/dev/null || true
    exit "${rc}"
}
trap cleanup EXIT INT TERM

exec /usr/local/lib/usb-explore/dispatch.sh "${LOOP}" "${SUBCOMMAND}" "$@"
