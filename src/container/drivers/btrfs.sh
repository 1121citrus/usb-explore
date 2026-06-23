#!/usr/bin/env bash
# Filesystem driver: btrfs

# Detect whether this driver handles the given partition node.
# Args:   $1 = block device node
# Returns: 0 if btrfs, 1 otherwise
btrfs_detect() {
    local node="${1}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ "${fstype}" == "btrfs" ]]
}

# Mount the partition read-only.
# degraded allows mounting an image that was part of a multi-device
# btrfs volume when the other devices are not present, which is the
# normal situation for a captured disk image.
# Args:   $1 = block device node, $2 = mountpoint
# Returns: 0 on success
btrfs_mount() {
    local node="${1}" mp="${2}"
    mount -o "${MOUNT_MODE}",degraded -t btrfs "${node}" "${mp}"
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
btrfs_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
