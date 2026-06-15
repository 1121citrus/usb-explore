#!/usr/bin/env bash
# Filesystem driver: erofs (Enhanced Read-Only File System)

# Detect whether this driver handles the given partition node.
# Args:   $1 = block device node
# Returns: 0 if erofs, 1 otherwise
erofs_detect() {
    local node="${1}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ "${fstype}" == "erofs" ]]
}

# Mount the partition read-only.
# erofs is inherently read-only; -o ro is included for explicitness.
# Args:   $1 = block device node, $2 = mountpoint
# Returns: 0 on success
erofs_mount() {
    local node="${1}" mp="${2}"
    mount -o ro -t erofs "${node}" "${mp}"
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
erofs_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
