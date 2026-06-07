#!/usr/bin/env bash
# Filesystem driver: iso9660 (hybrid ISO/GPT disks)
#
# Ubuntu autoinstall ISOs and similar hybrid images place the ISO9660
# Primary Volume Descriptor at disk sector 16 (byte 8192), before any GPT
# partition starts. Probing at a partition's byte offset misses the PVD.
#
# This driver activates when:
#   - The partition itself has no recognisable filesystem at its offset, AND
#   - The whole disk image has iso9660 at byte 0
#
# It mounts /disk.img directly (from byte 0) rather than the partition's
# loop device, giving access to the full ISO9660 content.

# Detect whether this driver handles the given partition node.
# Args:   $1 = block device node for the partition (not used directly)
# Returns: 0 if iso9660 is appropriate, 1 otherwise
iso9660_detect() {
    local node="${1}"

    # Only activate for partitions with no detectable partition-level filesystem
    local part_fstype
    part_fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ -n "${part_fstype}" ]] && return 1

    # Check whether the whole disk has iso9660 at byte 0
    if blkid --probe -o value -s TYPE /disk.img 2>/dev/null | grep -q "iso9660"; then
        return 0
    fi
    # Fallback: look for CD001 magic at ISO9660 sector 16 (byte offset 32769)
    if dd if=/disk.img bs=2048 skip=16 count=1 2>/dev/null | grep -q "CD001"; then
        return 0
    fi
    return 1
}

# Mount the ISO9660 filesystem from the whole disk image.
# Args:   $1 = block device node (ignored — /disk.img is mounted directly)
#         $2 = mountpoint
# Returns: 0 on success
iso9660_mount() {
    local mp="${2}"
    mount -o ro -t iso9660 /disk.img "${mp}"
}

# Unmount the mountpoint (best-effort).
# Args:   $1 = mountpoint
iso9660_unmount() {
    local mp="${1}"
    umount "${mp}" 2>/dev/null || true
}
