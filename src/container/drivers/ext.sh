#!/usr/bin/env bash
# Filesystem driver: ext2 / ext3 / ext4

# Detect whether this driver handles the given partition node.
# Args:   $1 = block device node (e.g. /dev/loop0p2)
# Returns: 0 if ext2/3/4, 1 otherwise
ext_detect() {
    local node="${1}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ "${fstype}" == ext* ]]
}

# Mount the partition read-only.
# Args:   $1 = block device node, $2 = mountpoint
# Returns: 0 on success
ext_mount() {
    local node="${1}" mp="${2}"
    # noload skips journal replay, which is required when the filesystem was not
    # cleanly unmounted (needs_recovery flag set). Without noload, the kernel
    # refuses a read-only mount of a dirty ext4 journal. Same rationale as
    # norecovery in xfs_mount.
    mount -o ro,noload -t ext4 "${node}" "${mp}"
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
ext_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
