# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed

- `shell` and `serve` subcommands now accept `-p|--partition N` as a
  per-subcommand flag. Previously both functions had no argument parser,
  so a partition specified after the subcommand name (e.g.
  `usb-explore shell -p 4`) was silently ignored and `select-partition`
  fell through to the multi-partition error even when the user had
  explicitly selected a partition.

---

## [1.0.0] — 2026-06-12

### Added

#### Host CLI (`src/usb-explore`)

- `serve` — start a read-only HTTP directory server over the mounted
  partition. Accepts `--port PORT` (default 8080). Opens the browser
  automatically on macOS.
- `browse` — launch Midnight Commander (`mc`) at the partition root for
  visual twin-panel navigation. `ncdu` is also available inside the
  container for disk-usage analysis.
- `archive` — create a compressed archive of a partition path on the
  host. Compression format inferred from extension: `.tar.gz` / `.tgz`,
  `.tar.bz2` / `.tbz2`, `.tar.xz` / `.txz`, `.tar`.
- `find` — search the partition by filename glob, file contents
  (`--grep PATTERN`), or both. Output paths are partition-relative
  and usable directly with `copy`, `archive`, `diff`, and `hash`.
  Exit code 1 when `--grep` finds no matches (standard grep behaviour).
- `hash` — print the SHA-256 checksum of a single file from the
  partition without extracting it. Output is identical to `sha256sum(1)`.
  Exits 1 if the path does not exist or is a directory.
- `clean` — remove the captured disk image file with a confirmation
  prompt. `-y|--yes` skips the prompt. Exits 4 if the file does not
  exist. Does not require Docker.

#### Docker image

- Added packages: `python3` (required by `serve`), `bzip2` and
  `xz-utils` (required by `archive`), `mc` and `ncdu` (required by
  `browse`).

### Security

- Added `apt-get upgrade -y` to the Dockerfile `RUN` layer to pull in
  base-image security fixes at build time. Resolves CVE-2026-45447
  (openssl: heap use-after-free in `PKCS7_verify`, HIGH) by upgrading
  `libssl3t64` from `3.0.13-0ubuntu3.9` to `3.0.13-0ubuntu3.11`.

### Changed

- All subcommand declarations (SYNOPSIS, function definitions, routing
  guard, and dispatch case in `src/usb-explore`; function definitions
  and dispatch case in `src/container/dispatch.sh`) are now in
  lexical order throughout the codebase.
- `resolve_partition` in `src/usb-explore` now delegates all JSON
  processing to a new container-side `select-partition` command,
  eliminating the host-side `jq` dependency that caused `BW01`
  warnings (exit 127) in the BATS test suite when `jq` is absent
  from the host (e.g. the Alpine-based `bats/bats:1.13.0` runner).

### Tests

- Routing tests in `test/08-cli.bats` now pass `--image /nonexistent.img`
  so they exit at `check_image_file` (exit 4) without invoking any
  container or host tool. Previously, a `usb.img` in the working
  directory caused them to proceed into `resolve_partition` and
  trigger BW01 advisory warnings.

### Documentation

- `README.md`: documented all six new subcommands with synopsis,
  option tables, and usage examples; updated table of contents and
  quick-start workflow.
- `README.md`: reorganised the Subcommands section into four functional
  groups — **Core workflow** (capture, clean, copy, info, shell),
  **Exploration and search** (browse, find, run, serve), **Expert
  tools** (archive, diff, hash), and **Developer** (build). Commands
  are lexically sorted within each group. Group headings appear in the
  table of contents with short descriptions.

---

## [0.1.1] — 2026-06-12

### Fixed

- ext2/ext3/ext4 partitions with an unclean journal (`needs_recovery` flag
  set in `s_feature_incompat`) now mount correctly. The ext driver previously
  used `mount -o ro`, which the kernel refuses when journal replay is needed
  but write access is unavailable. Added `noload` to the mount options
  (equivalent to `norecovery` already used by the xfs driver).

### Tests

- Added `dirty-ext4.img` fixture: a GPT image whose ext4 partition has
  `EXT4_FEATURE_INCOMPAT_RECOVER` set in the superblock, simulating a USB
  captured from a live or uncleanly-ejected drive.
- Fixture generation uses `debugfs set_super_value` (via e2fsprogs) to write
  the modified `s_feature_incompat` value so that the superblock CRC32c
  checksum is recomputed correctly. Direct byte writes invalidate the checksum
  when `metadata_csum` is enabled (the Ubuntu 24.04 mkfs.ext4 default), causing
  `blkid` to reject the superblock and report the filesystem type as unknown.
- Added regression test: "subcommand dirty-ext4: mounts and reads file from
  partition with dirty journal".

### Documentation

- Added explanation to the `capture` section of `README.md` describing why
  direct USB device access is not possible: Docker Desktop on macOS runs a
  Linux VM and does not expose macOS `/dev/diskN` block devices to containers.

---

## [0.1.0] — 2026-06-07

### Added

#### Host CLI (`src/usb-explore`)

- `capture` — copy a USB device to a flat disk image with `/bin/dd`.
  Sparse copy (`conv=sparse`) on APFS reduces physical file size to the
  non-zero data footprint. Progress: file-size heartbeat every
  `--progress-interval` seconds plus dd SIGINFO on each interval.
  Post-capture validation reports logical and physical (sparse) size.
- `info` — show partition table with filesystem type, size, label, UUID,
  and mountability for each partition. Detects disk-level filesystems
  (ISO9660 on hybrid ISO/GPT images). `--json` emits machine-readable JSON.
- `shell` — interactive bash session inside a Docker container with the
  selected partition mounted read-only at `/mnt/part`.
- `copy` — copy a file or directory tree from the image to the host.
- `run` — execute a command against the mounted partition. Arguments
  starting with `/` are rewritten to `/mnt/part/<path>`; CWD inside the
  container is `/mnt/part` so bare commands (`ls`, `find .`) work naturally.
- `diff` — compare an image path against a local reference.
- `build` — rebuild the Docker image from local source.
- Global options: `-i|--image`, `-p|--partition` (auto-selects when exactly
  one mountable partition exists), `--debug`, `--version`, `--help`.
- `-p` accepted before or after the subcommand name and before `--`.

#### Docker image

- Ubuntu 24.04 base; packages: `util-linux`, `fdisk`, `e2fsprogs`,
  `xfsprogs`, `rsync`, `diffutils`, `file`, `jq`.
- Multi-platform: `linux/amd64` and `linux/arm64`.
- Filesystem drivers: ext2/ext3/ext4, xfs (`norecovery` for captured
  images), vfat, iso9660 (mounts `/disk.img` directly for hybrid ISO/GPT
  disks where the PVD is at disk byte 0 before any GPT partition).
- Partition detection uses `blkid --probe --offset` (no loop device
  required for info), avoiding loop pool exhaustion in Docker Desktop VMs.
- Offset-based loop devices for mounting (no `--partscan` dependency);
  pre-creates missing loop device nodes for Docker Desktop on macOS.

#### Partition classification

- EFI System Partitions are mountable via `-p N` (vfat driver); auto-
  selection skips them to prefer Linux data partitions.
- BIOS Boot, swap, and LVM partitions excluded from auto-selection.
- xorriso hybrid ISO/GPT: Microsoft Basic Data partitions with GPT
  attribute `GUID:60` identified as ISO data regions; large regions
  (≥1 MB) mountable as iso9660 via whole-disk mount.
- ISO9660 at disk level detected via PVD magic (CD001 at sector 16).

#### CI/CD

- Five-stage GitHub Actions pipeline: lint (hadolint, shellcheck,
  markdownlint), build, test (BATS), scan (Trivy HIGH/CRITICAL), push.
- Multi-platform push with SBOM and provenance attestation.
- 98 BATS tests across 8 test files covering build flags, image
  structure, container invocation, OCI metadata, partition discovery,
  subcommands, capture helpers, and CLI routing.
- Test fixtures generated by `fixtures/generate.sh` inside a privileged
  Docker container; no host kernel extensions required.

[Unreleased]: https://github.com/1121citrus/usb-explore/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/1121citrus/usb-explore/compare/v0.1.1...v1.0.0
[0.1.1]: https://github.com/1121citrus/usb-explore/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/1121citrus/usb-explore/releases/tag/v0.1.0
