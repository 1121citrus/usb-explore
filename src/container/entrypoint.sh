#!/usr/bin/env bash
# Container PID 1: validate /disk.img and hand off to dispatch.
# All loop-device lifecycle management lives in dispatch.sh so that the
# EXIT trap and cleanup are in the same process that opens the devices.
set -euo pipefail

if [[ ! -f /disk.img ]]; then
    echo "error: /disk.img not found." >&2
    echo "       Mount a disk image with: -v /path/to/image:/disk.img:ro" >&2
    exit 1
fi

SUBCOMMAND="${1:-info}"
shift || true

exec /usr/local/lib/usb-explore/dispatch.sh "${SUBCOMMAND}" "$@"
