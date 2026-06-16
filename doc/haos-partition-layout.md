# Home Assistant OS (HAOS) partition layout

Reference notes on HAOS image support in `usb-explore`. HAOS images produce a
distinctive eight-partition GPT layout. This document explains the layout,
documents how it has evolved across HAOS releases, and describes how
`usb-explore` handles each partition type.

---

## Partition layout

All HAOS images follow the same eight-partition GPT scheme regardless of
version. The filesystem types on individual partitions have changed across
releases:

| # | Label | Purpose |
| --- | --- | --- |
| 1 | `hassos-boot` | EFI/GRUB boot files (vfat, always) |
| 2 | `hassos-kernel0` | Kernel image, A-slot (squashfs, always) |
| 3 | `hassos-system0` | Root filesystem, A-slot (squashfs early; erofs later) |
| 4 | `hassos-kernel1` | Kernel image, B-slot (squashfs when written; raw when empty) |
| 5 | `hassos-system1` | Root filesystem, B-slot (squashfs/erofs when written; raw when empty) |
| 6 | `hassos-bootstate` | A/B boot state — raw binary, no filesystem (see below) |
| 7 | `hassos-overlay` | Persistent config, add-ons, supervisor state (ext4, always) |
| 8 | `hassos-data` | User data, Home Assistant database (ext4, always) |

---

## Observed behavior across releases

`usb-explore info` output on four captured HAOS images:

### 20231225 — squashfs system, B-slot empty

```text
Image:  /disk.img  (28.8 GB)
Scheme: GPT

  #    Filesystem  Size        Label                   UUID        Notes
  1    vfat        32.0 MB     hassos-boot             7A08-EA7    [mountable]
  2    squashfs    24.0 MB     hassos-kernel0                      [mountable]
  3    squashfs    256.0 MB    hassos-system0                      [mountable]
  4    raw         24.0 MB     hassos-kernel1                      [no recognised filesystem]
  5    raw         256.0 MB    hassos-system1                      [no recognised filesystem]
  6    raw         8.0 MB      hassos-bootstate                    [raw: BOOT_ORDER=A B MACHINE_ID=eab6c44a257b4d1ea98fdfce0db34888 BOOT_A_LEFT=3]
  7    ext4        96.0 MB     hassos-overlay          8dfa097c    [mountable]
  8    ext4        28.1 GB     hassos-data             243ebeb3    [mountable]

5 mountable partitions found. Pass -p N to select one.
```

### 20240107 — squashfs system, both slots written

```text
Image:  /disk.img  (28.8 GB)
Scheme: GPT

  #    Filesystem  Size        Label                   UUID        Notes
  1    vfat        32.0 MB     hassos-boot             7A08-EA7    [mountable]
  2    squashfs    24.0 MB     hassos-kernel0                      [mountable]
  3    squashfs    256.0 MB    hassos-system0                      [mountable]
  4    squashfs    24.0 MB     hassos-kernel1                      [mountable]
  5    squashfs    256.0 MB    hassos-system1                      [mountable]
  6    raw         8.0 MB      hassos-bootstate                    [raw: BOOT_ORDER=B A MACHINE_ID=2724498e323c46b8b202b3844eabd0e6 BOOT_B_LEFT=3]
  7    ext4        96.0 MB     hassos-overlay          8dfa097c    [mountable]
  8    ext4        28.1 GB     hassos-data             243ebeb3    [mountable]

7 mountable partitions found. Pass -p N to select one.
```

### 20240821 — erofs system, B-slot empty, bootstate uninitialized

```text
Image:  /disk.img  (2.0 GB)
Scheme: GPT

  #    Filesystem  Size        Label                   UUID        Notes
  1    vfat        32.0 MB     hassos-boot             74B3-47D    [mountable]
  2    squashfs    24.0 MB     hassos-kernel0                      [mountable]
  3    erofs       256.0 MB    hassos-system0          7e8dfe31    [mountable]
  4    raw         24.0 MB     hassos-kernel1                      [no recognised filesystem]
  5    raw         256.0 MB    hassos-system1                      [no recognised filesystem]
  6    raw         8.0 MB      hassos-bootstate                    [no recognised filesystem]
  7    ext4        96.0 MB     hassos-overlay          495de63f    [mountable]
  8    ext4        1.2 GB      hassos-data             07e4c7ac    [mountable]

5 mountable partitions found. Pass -p N to select one.
```

### 20250128 — erofs system, both slots written

```text
Image:  /disk.img  (29.7 GB)
Scheme: GPT

  #    Filesystem  Size        Label                   UUID        Notes
  1    vfat        32.0 MB     hassos-boot             2EC6-B0B    [mountable]
  2    squashfs    24.0 MB     hassos-kernel0                      [mountable]
  3    erofs       256.0 MB    hassos-system0          ab1894fd    [mountable]
  4    squashfs    24.0 MB     hassos-kernel1                      [mountable]
  5    erofs       256.0 MB    hassos-system1          e13272e7    [mountable]
  6    raw         8.0 MB      hassos-bootstate                    [raw: BOOT_ORDER=B A MACHINE_ID=ae2b7f5ff2b54a038ef035ba07ea5326 BOOT_B_LEFT=3]
  7    ext4        96.0 MB     hassos-overlay          a6fa2138    [mountable]
  8    ext4        29.0 GB     hassos-data             8b9a66cf    [mountable]

7 mountable partitions found. Pass -p N to select one.
```

---

## What varies across images

### System partition filesystem: squashfs → erofs

The A-slot and B-slot root filesystem partitions (3 and 5) migrated from
squashfs to erofs (Enhanced Read-Only File System) sometime between the January
2024 and August 2024 images. The kernel partitions (2 and 4) have remained
squashfs across all observed versions.

`usb-explore` handles both transparently: the `squashfs` driver and the `erofs`
driver are both registered, and `blkid` identifies the correct type at probe
time.

### B-slot occupancy: empty vs. written

Partitions 4 and 5 (B-slot kernel and system) are empty on a freshly written
HAOS USB or a disk that has never received an OTA update. An empty B-slot
contains no filesystem — `blkid` finds nothing, and the first megabyte is all
zeros. `usb-explore` correctly reports these as `raw` with
`[no recognised filesystem]`.

After at least one OTA update, the bootloader writes the new image to the B
slot and flips the `BOOT_ORDER` in the bootstate partition. A disk with both
slots written shows 7 mountable partitions; one with an empty B-slot shows 5.

### Bootstate raw hint: present vs. absent

The `hassos-bootstate` partition (6) carries null-terminated key=value strings
at its start when the system has been booted. The hint extracted by
`probe_raw_hint()` typically contains `BOOT_ORDER`, `MACHINE_ID`, and either
`BOOT_A_LEFT` or `BOOT_B_LEFT`.

`BOOT_ORDER=A B` means A is the active slot (primary boot target). `BOOT_ORDER=B A`
means B is active (the system has OTA-updated at least once). The `LEFT` counter
tracks remaining boot attempts before the bootloader rolls back to the other slot.

The 20240821 image (2 GB) shows no hint at all — the bootstate block was never
written, indicating the image was captured before the system's first boot from
that USB. The `[no recognised filesystem]` note is correct in that case.

---

## `hassos-bootstate` — why it has no filesystem

The bootstate partition is **intentionally raw binary**. It is not corrupted,
and mount attempts are expected to fail. This is by design:

HAOS maintains two complete boot slots — A (partitions 2–3) and B (partitions
4–5). On an OTA update, the new image is written to the standby slot, the
bootstate partition is updated atomically, and the system reboots into the new
slot. If the new slot fails to boot, the bootloader reads the bootstate and
rolls back to the previous slot automatically.

The bootloader (GRUB or U-Boot depending on target platform) reads and writes
this 8 MB partition directly at fixed byte offsets during the early boot stage,
before any operating system is running. A filesystem layer is unnecessary and
would only introduce failure modes at the worst possible moment.

Standard probing tools confirm the raw nature:

- `blkid` returns no `TYPE=` field — only `PARTLABEL="hassos-bootstate"` and
  the partition GUID
- `lsblk -f` shows a blank FSTYPE column
- `file` reports `data`
- Partclone/Clonezilla fall back to `dd` mode and report the type as `raw`

---

## How `usb-explore` handles it

### Filesystem detection

`blkid --probe --offset --size` identifies the correct filesystem type for each
partition without requiring a loop device. This is how `usb-explore` detects
squashfs vs. erofs vs. empty vs. raw without mounting anything.

### Raw partition hint

`probe_raw_hint()` in `src/container/info.sh` runs two probes on any partition
that has no recognised filesystem:

1. **`file` magic** on the first 4 KB — catches GRUB environment blocks, kernel
   images, and other formats with known magic bytes.
2. **Null-terminated string scan** on the first 256 bytes — extracts printable
   strings separated by null bytes. This is the probe that recovers the
   bootstate key=value variables.

For a written `hassos-bootstate` partition, probe 1 returns `data` (opaque
4-byte magic, not a known format) and probe 2 extracts the readable boot state
variables. For an uninitialized bootstate (all zeros), both probes return
nothing and the note shows `[no recognised filesystem]`.

### Summary of current usb-explore behavior

| Partition | Condition | fstype | Notes column |
| --- | --- | --- | --- |
| 3 — system0 | squashfs era | squashfs | `[mountable]` |
| 3 — system0 | erofs era | erofs | `[mountable]` |
| 4 — kernel1 | slot written | squashfs | `[mountable]` |
| 4 — kernel1 | slot empty | raw | `[no recognised filesystem]` |
| 5 — system1 | squashfs era, written | squashfs | `[mountable]` |
| 5 — system1 | erofs era, written | erofs | `[mountable]` |
| 5 — system1 | slot empty | raw | `[no recognised filesystem]` |
| 6 — bootstate | system has booted | raw | `[raw: BOOT_ORDER=... MACHINE_ID=...]` |
| 6 — bootstate | never booted | raw | `[no recognised filesystem]` |

All behaviors are correct. Partition 6 will never be mountable by design.

---

## Metadata

```text
generator-name: Claude Code
generator-version: Claude Sonnet 4.6
generator-model-token: claude-sonnet-4-6
generator-provider: Anthropic
generation-date: 2026-06-15
generator-responsibility: design
```
