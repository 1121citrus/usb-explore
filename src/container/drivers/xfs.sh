#!/usr/bin/env bash
# Filesystem driver: xfs

# Detect whether this driver handles the given partition node.
# Args:   $1 = block device node
# Returns: 0 if xfs, 1 otherwise
xfs_detect() {
    local node="${1}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ "${fstype}" == "xfs" ]]
}

# Mount the partition read-only.
# Args:   $1 = block device node, $2 = mountpoint
# Returns: 0 on success
xfs_mount() {
    local node="${1}" mp="${2}"
    # norecovery is required to mount an xfs filesystem read-only when the
    # journal has not been cleanly flushed (common with captured disk images).
    mount -o ro,norecovery -t xfs "${node}" "${mp}"
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
xfs_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
