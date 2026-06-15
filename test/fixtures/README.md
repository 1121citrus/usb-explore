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

## Regenerating

```bash
./test/fixtures/generate.sh
```

Requirements: Docker Desktop running (images are built inside a privileged
container — the same way `usb-explore` works).
