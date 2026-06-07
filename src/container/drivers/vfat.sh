#!/usr/bin/env bash
# Filesystem driver: vfat / FAT32 (covers EFI system partitions when the
# user explicitly selects one with -p)

# Detect whether this driver handles the given partition node.
# Args:   $1 = block device node
# Returns: 0 if vfat, 1 otherwise
vfat_detect() {
    local node="${1}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ "${fstype}" == "vfat" ]]
}

# Mount the partition read-only.
# Args:   $1 = block device node, $2 = mountpoint
# Returns: 0 on success
vfat_mount() {
    local node="${1}" mp="${2}"
    mount -o ro -t vfat "${node}" "${mp}"
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
vfat_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
