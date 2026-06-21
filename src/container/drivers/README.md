# Filesystem and storage-layer drivers

Each driver is a single shell script sourced by `dispatch.sh` at
container startup. Drivers are registered in two arrays in
`dispatch.sh`:

- `FS_DRIVERS` — filesystem drivers (ext, xfs, vfat, btrfs, etc.)
- `LAYER_DRIVERS` — storage-layer drivers (luks, lvm)

## Filesystem driver API

A filesystem driver must define three functions:

```bash
<name>_detect <device>
```

Exit 0 if the device contains this filesystem. Typically checks
`blkid` output.

```bash
<name>_mount <device> <mountpoint>
```

Mount the device read-only at the given mountpoint. Return non-zero
on failure.

```bash
<name>_unmount <mountpoint>
```

Unmount and clean up. Called during normal exit and on errors.

## Storage-layer driver API

A layer driver transforms one block device into another (e.g.,
decrypts a LUKS volume to produce a cleartext device).

```bash
<name>_detect <device>
```

Exit 0 if this layer is present on the device.

```bash
<name>_activate <device>
```

Activate the layer. Print the resulting device path to stdout.
Return non-zero on failure.

```bash
<name>_deactivate
```

Tear down the layer. Called in LIFO order during cleanup.

## Current drivers

### Filesystem

| Driver | File | Mount options | Notes |
| --- | --- | --- | --- |
| ext | `ext.sh` | `ro,noload` | ext2, ext3, ext4; `noload` skips journal replay |
| xfs | `xfs.sh` | `ro,norecovery` | Skips log replay on captured images |
| vfat | `vfat.sh` | `ro` | EFI system partitions |
| btrfs | `btrfs.sh` | `ro,degraded` | `degraded` for single-device captures |
| squashfs | `squashfs.sh` | `ro` | Live ISO root filesystems |
| erofs | `erofs.sh` | `ro` | HAOS system partitions |
| iso9660 | `iso9660.sh` | `ro` | Mounts `/disk.img` directly (must be last in `FS_DRIVERS`) |

### Storage layers

| Driver | File | Notes |
| --- | --- | --- |
| luks | `luks.sh` | LUKS1 and LUKS2; credentials via file, key, or passphrase |
| lvm | `lvm.sh` | LVM2 PVs; activates VG read-only; `--lv` selects when multiple LVs exist |

## Adding a new driver

See `CONTRIBUTING.md` in the repository root.
