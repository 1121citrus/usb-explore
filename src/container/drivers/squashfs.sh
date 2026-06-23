#!/usr/bin/env bash
# Filesystem driver: squashfs

# Detect whether this driver handles the given partition node.
# Args:   $1 = block device node
# Returns: 0 if squashfs, 1 otherwise
squashfs_detect() {
    local node="${1}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ "${fstype}" == "squashfs" ]]
}

# Mount the partition read-only.
# squashfs is inherently read-only; -o ro is included for explicitness.
# Args:   $1 = block device node, $2 = mountpoint
# Returns: 0 on success
squashfs_mount() {
    local node="${1}" mp="${2}"
    if [[ "${USB_EXPLORE_RW:-}" == "true" ]]; then
        echo "error: squashfs is inherently read-only;" \
             "--rw and edit are not supported" >&2
        exit 5
    fi
    mount -o ro -t squashfs "${node}" "${mp}"
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
squashfs_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
