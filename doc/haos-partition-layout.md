# Home Assistant OS (HAOS) partition layout

Reference notes on HAOS image support in `usb-explore`. HAOS images produce a
distinctive eight-partition GPT layout where most partitions are read-only
squashfs filesystems and partition 6 (`hassos-bootstate`) carries no filesystem
at all. This document explains why, what the tool does today, and where a future
enhancement could add value.

---

## Partition layout

A typical HAOS image as reported by `usb-explore info`:

```text
Image:  /disk.img  (28.8 GB)
Scheme: GPT

  #    Filesystem  Size        Label                   UUID        Notes
  1    vfat        32.0 MB     hassos-boot             7A08-EA7    [mountable]
  2    squashfs    24.0 MB     hassos-kernel0                      [mountable]
  3    squashfs    256.0 MB    hassos-system0                      [mountable]
  4    squashfs    24.0 MB     hassos-kernel1                      [mountable]
  5    squashfs    256.0 MB    hassos-system1                      [mountable]
  6    unknown     8.0 MB      hassos-bootstate                    [no recognised filesystem]
  7    ext4        96.0 MB     hassos-overlay          8dfa097c    [mountable]
  8    ext4        28.1 GB     hassos-data             243ebeb3    [mountable]

7 mountable partitions found. Pass -p N to select one.
```

| # | Label | Filesystem | Purpose |
| --- | --- | --- | --- |
| 1 | `hassos-boot` | vfat | EFI/GRUB boot files |
| 2 | `hassos-kernel0` | squashfs | Kernel image, slot A |
| 3 | `hassos-system0` | squashfs | Root filesystem, slot A |
| 4 | `hassos-kernel1` | squashfs | Kernel image, slot B |
| 5 | `hassos-system1` | squashfs | Root filesystem, slot B |
| 6 | `hassos-bootstate` | (raw binary) | A/B boot state — see below |
| 7 | `hassos-overlay` | ext4 | Persistent config, add-ons, supervisor state |
| 8 | `hassos-data` | ext4 | User data, Home Assistant database |

Partitions 2–5 are read-only squashfs images; all four are mountable with
`usb-explore`. Partitions 7 and 8 are ordinary ext4 volumes. Partition 6 is
the only one that requires explanation.

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

The partition stores a small set of key=value boot state variables written as
null-terminated strings at known offsets. Standard probing tools confirm this:

- `blkid` returns no `TYPE=` field — only `PARTLABEL="hassos-bootstate"` and
  the partition GUID
- `lsblk -f` shows a blank FSTYPE column
- `file` reports `data`
- Partclone/Clonezilla fall back to `dd` mode and report the type as `raw`

---

## How `usb-explore` handles it today

`probe_raw_hint()` in `src/container/info.sh` runs two probes on any partition
that has no recognised filesystem:

1. **`file` magic** on the first 4 KB — catches GRUB environment blocks, kernel
   images, and other formats with known magic bytes.
2. **Null-terminated string scan** on the first 256 bytes — extracts printable
   strings separated by null bytes. This is the probe that works for
   `hassos-bootstate`: the key=value boot state variables are stored as
   null-terminated strings at the start of the partition.

For a `hassos-bootstate` partition, probe 1 returns `data` (no recognised magic)
and probe 2 extracts the readable boot state variables. The result appears in
`usb-explore info` output as:

```text
  6    unknown     8.0 MB      hassos-bootstate        [raw: boot_systemslot=A ...]
```

and in `usb-explore info --json` under the `raw_hint` field.

---

## Potential enhancement: structured boot-slot display

The strings extracted by probe 2 are already human-readable, but a future
enhancement could recognise the `hassos-bootstate` partition label specifically
and format the hint more clearly:

```text
  6    unknown     8.0 MB      hassos-bootstate        [A/B state: active=A, a_ok=1, b_ok=0]
```

This would require parsing the known variable names out of the raw hint string.
The null-terminated string scan already surfaces all the data; the remaining
work is label-aware formatting in the display path.

---

## Metadata

```text
generator-name: Claude Code
generator-version: Claude Sonnet 4.6
generator-model-token: claude-sonnet-4-6
generator-provider: Anthropic
generation-date: 2026-06-14
generator-responsibility: design
```
