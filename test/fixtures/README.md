# Test fixtures

This directory holds small disk images used by the BATS test suite.
Binary `.img` files are not committed to the repository.

Run `./test/fixtures/generate.sh` to create them before running the
tests, or let `./build` generate them automatically.

## Images created

| File | Scheme | Contents |
| --- | --- | --- |
| `single-ext4.img` | GPT | EFI (200 MB) + ext4 root (300 MB) |
| `dual-ext4.img` | GPT | EFI (200 MB) + ext4 root (300 MB) + ext4 data (200 MB) |
| `xfs.img` | GPT | EFI (200 MB) + xfs root (400 MB) |
| `mbr.img` | MBR | ext4 root (500 MB) |
| `dirty-ext4.img` | GPT | EFI (100 MB) + ext4 root (100 MB) with `needs_recovery` flag set |
| `squashfs.img` | GPT | EFI (100 MB) + squashfs root (100 MB) |
| `btrfs.img` | GPT | EFI (100 MB) + btrfs root (300 MB) |
| `raw.img` | GPT | EFI (100 MB) + raw unformatted partition (16 MB) |
| `erofs.img` | GPT | EFI (100 MB) + erofs root (100 MB) |
| `lvm.img` | GPT | EFI (100 MB) + LVM PV (250 MB) with `root` and `data` LVs |
| `luks.img` | GPT | EFI (100 MB) + LUKS2-encrypted ext4 (150 MB) |
| `luks-lvm.img` | GPT | EFI (100 MB) + LUKS1 → LVM with `root` + `data` LVs |
| `showcase-home.img.gz` | GPT | EFI + ext4 home server; committed (<30 KB gzipped) |
| `showcase-enterprise.img` | GPT | EFI + LUKS1 → LVM (~50 MB); generated on demand |

`dirty-ext4.img` simulates a USB captured without a clean unmount. The
`EXT4_FEATURE_INCOMPAT_RECOVER` bit is set in the superblock after
generation, which causes `mount -o ro` to fail without the `noload`
mount option. It is the regression fixture for the ext driver's `noload`
fix (analogous to `norecovery` in the xfs driver).

`raw.img` has a second partition with no filesystem — `blkid` finds
nothing. It exercises `probe_raw_hint()` in `info.sh`: null-terminated
key=value pairs are planted in the first 256 bytes, which the string-scan
fallback recovers and displays as `[raw: BOOT_A_LEFT=3 ...]` in the Notes
column.

`erofs.img` has an erofs root partition — the filesystem used by HAOS
`hassos-system0`/`hassos-system1` slots. It exercises the `erofs` driver
in `src/container/drivers/erofs.sh`. Mounting is attempted at test time;
the test skips gracefully when the erofs kernel module is unavailable in
the Docker VM.

`lvm.img` has an LVM2 physical volume. The volume group contains two
logical volumes (`root` and `data`), exercising the `--lv` selection
logic and auto-selection when exactly one LV would be ambiguous.

`luks.img` has a LUKS2-encrypted partition with a known test passphrase.
It exercises the `luks` layer driver with `--luks-passphrase` and
`--luks-passphrase-file`.

`luks-lvm.img` stacks LUKS1 encryption over LVM, exercising the full
layer pipeline (LUKS → LVM → ext4). The LUKS1 format is used because
it is the more common format on enterprise Linux installs.

`showcase-home.img.gz` is a committed fixture — the only `.img.gz` file
tracked in the repository. It ships as a genuine, burnable GPT image
rather than a generated artifact. Its contents are pinned by
`showcase-home.img.gz.sha256` and verified by the test suite.

`showcase-enterprise.img` is too large to commit (~50 MB) and is
generated on demand by `generate.sh showcase-enterprise.img`. Its LUKS
layer uses random salts, so it is not bit-reproducible and is
intentionally not checksum-pinned.

## Regenerating

```bash
./test/fixtures/generate.sh
```

Requirements: Docker Desktop running (images are built inside a privileged
container — the same way `usb-explore` works).
