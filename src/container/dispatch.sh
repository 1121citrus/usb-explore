#!/usr/bin/env bash
# Route a subcommand to its handler.
# Manages all loop-device lifecycle: opens, mounts, and guarantees cleanup
# via a single EXIT trap so no devices are leaked regardless of exit path.
#
# Partition access uses per-partition loop devices created from sfdisk byte
# offsets. This avoids relying on losetup --partscan, which is unreliable
# inside Docker VMs on macOS.
set -euo pipefail

SUBCOMMAND="${1}"
shift

# Source filesystem drivers
DRIVER_DIR="/usr/local/lib/usb-explore/drivers"
# shellcheck source=/dev/null
for _drv in "${DRIVER_DIR}"/*.sh; do source "${_drv}"; done
# Driver registry: each entry must have <name>_detect, <name>_mount, and
# <name>_unmount functions defined in src/container/drivers/<name>.sh, plus
# the corresponding package added to the Dockerfile.
# To add a driver: append its name here and follow CONTRIBUTING.md.
# Known candidates: squashfs (uses unsquashfs extraction, not kernel mount),
#                   btrfs (needs btrfs-progs and btrfs kernel module).
FS_DRIVERS=(ext xfs vfat)

# ---------------------------------------------------------------------------
# Loop device tracking (populated by attach_partition)
# ---------------------------------------------------------------------------

PART_LOOP=""    # partition-specific loop device, set by attach_partition

cleanup() {
    local rc=$?
    umount /mnt/part 2>/dev/null || true
    [[ -n "${PART_LOOP}" ]] && losetup --detach "${PART_LOOP}" 2>/dev/null || true
    exit "${rc}"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Partition loop helpers
# ---------------------------------------------------------------------------

# attach_partition — create a read-only loop device for one partition.
# Uses sfdisk byte-offset arithmetic so no kernel partition-scan is needed.
# Args:   $1 = 1-based partition number
# Side effect: sets global PART_LOOP
# Returns: 0 on success; exits 5 on out-of-range partition number
attach_partition() {
    local partnum="${1}"
    local sfdisk_json sector_size n_parts start size

    sfdisk_json=$(sfdisk --json /disk.img 2>/dev/null)
    sector_size=$(echo "${sfdisk_json}" | jq -r '.partitiontable.sectorsize // 512')
    n_parts=$(echo "${sfdisk_json}" | jq '.partitiontable.partitions | length')

    if [[ "${partnum}" -lt 1 || "${partnum}" -gt "${n_parts}" ]]; then
        echo "error: partition ${partnum} does not exist" \
             "(image has ${n_parts} partitions)." >&2
        echo "       Run 'usb-explore info' to see the partition table." >&2
        exit 5
    fi

    start=$(echo "${sfdisk_json}" \
        | jq -r ".partitiontable.partitions[${partnum}-1].start")
    size=$(echo "${sfdisk_json}" \
        | jq -r ".partitiontable.partitions[${partnum}-1].size")

    # Docker Desktop VMs pre-create loop nodes only up to a fixed limit.
    # When losetup --find returns a node above that limit (e.g. /dev/loop77),
    # the node doesn't exist in /dev and losetup fails. Pre-create nodes
    # 67-127 to cover any gap, then attach.
    local offset sizelimit candidate attempt
    offset=$(( start * sector_size ))
    sizelimit=$(( size * sector_size ))

    candidate=$(losetup --find 2>/dev/null || true)
    if [[ -n "${candidate}" && ! -b "${candidate}" ]]; then
        local num="${candidate#/dev/loop}"
        mknod "${candidate}" b 7 "${num}" 2>/dev/null || true
    fi

    for attempt in 1 2 3 4 5; do
        PART_LOOP=$(losetup --find --show --read-only \
            --offset="${offset}" \
            --sizelimit="${sizelimit}" \
            /disk.img 2>/dev/null) && break
        [[ "${attempt}" -lt 5 ]] || {
            echo "error: no loop device available after ${attempt} attempts." >&2
            exit 5
        }
        # Allow any just-exited container to release its loop device
        sleep "0.${attempt}"
        candidate=$(losetup --find 2>/dev/null || true)
        if [[ -n "${candidate}" && ! -b "${candidate}" ]]; then
            local num="${candidate#/dev/loop}"
            mknod "${candidate}" b 7 "${num}" 2>/dev/null || true
        fi
    done
}

# mount_partition — attach and mount the selected partition read-only.
# Reads USB_PARTITION from the environment.
# Returns: 0 on success; exits 5 on unsupported or unrecognised filesystem
mount_partition() {
    attach_partition "${USB_PARTITION:?USB_PARTITION is not set}"

    local fstype
    fstype=$(blkid -o value -s TYPE "${PART_LOOP}" 2>/dev/null || echo "unknown")

    for drv in "${FS_DRIVERS[@]}"; do
        if "${drv}_detect" "${PART_LOOP}"; then
            "${drv}_mount" "${PART_LOOP}" /mnt/part
            return 0
        fi
    done

    case "${fstype}" in
        squashfs)
            echo "error: squashfs is not supported in this version." >&2
            echo "       See CONTRIBUTING.md for how to add a driver." >&2 ;;
        btrfs)
            echo "error: btrfs is not supported in this version." >&2 ;;
        unknown|"")
            echo "error: partition ${USB_PARTITION} contains no" >&2
            echo "       recognised filesystem." >&2 ;;
        *)
            echo "error: no driver found for filesystem '${fstype}'." >&2 ;;
    esac
    exit 5
}

# ---------------------------------------------------------------------------
# Subcommand: info
# ---------------------------------------------------------------------------

do_info() {
    exec /usr/local/lib/usb-explore/info.sh "$@"
}

# ---------------------------------------------------------------------------
# Subcommand: shell
# ---------------------------------------------------------------------------

do_shell() {
    mount_partition
    export PS1="(usb-explore p${USB_PARTITION}) \w \$ "
    cd /mnt/part
    exec bash --norc --noprofile
}

# ---------------------------------------------------------------------------
# Subcommand: copy
# ---------------------------------------------------------------------------

do_copy() {
    local src="${1}" dst_name="${2}"
    mount_partition

    local src_abs="/mnt/part/${src#/}"
    if [[ ! -e "${src_abs}" ]]; then
        echo "error: path not found in image: ${src}" >&2
        exit 1
    fi

    # Trailing slash on source dir copies its CONTENTS into dest, avoiding
    # the rsync "copy-into" behaviour that would create dest/basename/.
    if [[ -d "${src_abs}" ]]; then
        mkdir -p "/out/${dst_name}"
        rsync -a --no-owner --no-group "${src_abs}/" "/out/${dst_name}/"
    else
        rsync -a --no-owner --no-group "${src_abs}" "/out/${dst_name}"
    fi
}

# ---------------------------------------------------------------------------
# Subcommand: run
# ---------------------------------------------------------------------------

# Args: command and arguments, with leading / paths already rewritten to
# /mnt/part/<path> by the host wrapper before being passed in.
# CWD is set to /mnt/part so that bare commands like 'ls' or 'find .'
# operate on the partition root rather than the container root.
do_run() {
    mount_partition
    cd /mnt/part
    exec "$@"
}

# ---------------------------------------------------------------------------
# Subcommand: diff
# ---------------------------------------------------------------------------

do_diff() {
    local img_path="${1}" ref_name="${2}"
    mount_partition

    local img_abs="/mnt/part/${img_path#/}"
    if [[ ! -e "${img_abs}" ]]; then
        echo "error: path not found in image: ${img_path}" >&2
        exit 1
    fi

    # Exit codes propagate: 0=identical, 1=differences, 2=error
    diff -rq "${img_abs}" "/ref/${ref_name}"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${SUBCOMMAND}" in
    info)  do_info  "$@" ;;
    shell) do_shell "$@" ;;
    copy)  do_copy  "$@" ;;
    run)   do_run   "$@" ;;
    diff)  do_diff  "$@" ;;
    *)
        echo "error: unknown subcommand '${SUBCOMMAND}'" >&2
        exit 2 ;;
esac
