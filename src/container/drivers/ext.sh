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

# Mount the partition.
# In RO mode, noload skips journal replay (required for dirty ext4).
# In RW mode, noload is dropped so journal replay executes — this is
# expected and unavoidable for writable access to dirty filesystems.
# Args:   $1 = block device node, $2 = mountpoint
# Returns: 0 on success
ext_mount() {
    local node="${1}" mp="${2}"
    if [[ "${MOUNT_MODE}" == "rw" ]]; then
        mount -o rw -t ext4 "${node}" "${mp}"
    else
        mount -o ro,noload -t ext4 "${node}" "${mp}"
    fi
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
ext_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
