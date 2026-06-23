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

# Mount the partition.
# In RO mode, norecovery skips log replay (required for dirty xfs).
# In RW mode, norecovery is dropped so log replay executes.
# Args:   $1 = block device node, $2 = mountpoint
# Returns: 0 on success
xfs_mount() {
    local node="${1}" mp="${2}"
    if [[ "${MOUNT_MODE}" == "rw" ]]; then
        mount -o rw -t xfs "${node}" "${mp}"
    else
        mount -o ro,norecovery -t xfs "${node}" "${mp}"
    fi
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
xfs_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
