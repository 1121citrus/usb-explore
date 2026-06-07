#!/usr/bin/env bash
# Route a subcommand to its handler. Called by entrypoint.sh after the
# loop device has been attached. Responsible for partition mounting and
# delegating to the appropriate operation.
set -euo pipefail

LOOP="${1}"
SUBCOMMAND="${2}"
shift 2

# Source all filesystem drivers. Each driver registers three functions:
#   <name>_detect <node>        – returns 0 if this driver handles the FS
#   <name>_mount  <node> <mp>   – mounts the partition read-only
#   <name>_unmount <mp>         – best-effort unmount
DRIVER_DIR="/usr/local/lib/usb-explore/drivers"
for _drv in "${DRIVER_DIR}"/ext.sh "${DRIVER_DIR}"/xfs.sh \
            "${DRIVER_DIR}"/vfat.sh; do
    # shellcheck source=/dev/null
    source "${_drv}"
done

# Future drivers are added here:
# FS_DRIVERS=(ext xfs vfat squashfs btrfs)
FS_DRIVERS=(ext xfs vfat)

# ---------------------------------------------------------------------------
# Partition mount / unmount helpers
# ---------------------------------------------------------------------------

# Find the driver for a partition node and mount it.
# Args:   $1 = partition node (e.g. /dev/loop0p2), $2 = mountpoint
# Returns: 0 on success; exits with code 5 on unsupported filesystem
mount_partition() {
    local node="${1}" mp="${2}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || echo "unknown")

    for drv in "${FS_DRIVERS[@]}"; do
        if "${drv}_detect" "${node}"; then
            "${drv}_mount" "${node}" "${mp}"
            return 0
        fi
    done

    # No driver matched — emit a helpful error
    case "${fstype}" in
        squashfs)
            echo "error: squashfs is not supported in this version." >&2
            echo "       See CONTRIBUTING.md for how to add a driver." >&2 ;;
        btrfs)
            echo "error: btrfs is not supported in this version." >&2 ;;
        unknown|"")
            echo "error: partition ${USB_PARTITION:-?} contains no" >&2
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
    exec /usr/local/lib/usb-explore/info.sh "${LOOP}" "$@"
}

# ---------------------------------------------------------------------------
# Subcommand: shell
# ---------------------------------------------------------------------------

do_shell() {
    local node="${LOOP}p${USB_PARTITION}"
    mount_partition "${node}" /mnt/part
    export PS1="(usb-explore p${USB_PARTITION}) \w \$ "
    cd /mnt/part
    exec bash --norc --noprofile
}

# ---------------------------------------------------------------------------
# Subcommand: copy
# ---------------------------------------------------------------------------

# Args (passed by host wrapper via container argv):
#   $1 = source path (absolute within the partition, e.g. /etc/fstab)
#   $2 = destination name within /out/
do_copy() {
    local src="${1}" dst_name="${2}"
    local node="${LOOP}p${USB_PARTITION}"
    mount_partition "${node}" /mnt/part

    local src_abs="/mnt/part/${src#/}"
    local dst_abs="/out/${dst_name}"

    if [[ ! -e "${src_abs}" ]]; then
        echo "error: path not found in image: ${src}" >&2
        exit 1
    fi

    rsync -a --no-owner --no-group "${src_abs}" "${dst_abs}"
}

# ---------------------------------------------------------------------------
# Subcommand: run
# ---------------------------------------------------------------------------

# Args: command and arguments, with leading '/' paths rewritten to
# /mnt/part/<path> by the host wrapper before being passed in.
do_run() {
    local node="${LOOP}p${USB_PARTITION}"
    mount_partition "${node}" /mnt/part
    exec "$@"
}

# ---------------------------------------------------------------------------
# Subcommand: diff
# ---------------------------------------------------------------------------

# Args:
#   $1 = image path (absolute within the partition)
#   $2 = reference name within /ref/
do_diff() {
    local img_path="${1}" ref_name="${2}"
    local node="${LOOP}p${USB_PARTITION}"
    mount_partition "${node}" /mnt/part

    local img_abs="/mnt/part/${img_path#/}"
    local ref_abs="/ref/${ref_name}"

    if [[ ! -e "${img_abs}" ]]; then
        echo "error: path not found in image: ${img_path}" >&2
        exit 1
    fi

    # Exit codes propagate: 0 = identical, 1 = differences, 2 = error
    diff -rq "${img_abs}" "${ref_abs}"
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
