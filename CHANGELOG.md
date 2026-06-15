# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- `erofs` filesystem driver (`src/container/drivers/erofs.sh`): HAOS
  `hassos-system0` / `hassos-system1` partitions use erofs (Enhanced
  Read-Only File System). The new driver adds detection, read-only mount,
  and unmount support, making these partitions fully browsable. erofs is
  already present in the Docker Desktop Linux VM kernel — no `modprobe`
  needed. `erofs-utils` added to the Dockerfile for future tooling.
- `erofs.img` test fixture: GPT, EFI (100 MB) + erofs root (100 MB) with
  planted `/etc/hostname`. Tests cover partition count, `fstype: erofs`,
  mountability, and hostname retrieval via `run cat`.

### Fixed

- `info` / `info --json`: no longer exits silently when the disk image
  has no recognised partition table (e.g. unformatted or blank USB). Now
  prints `info: no recognised partition table in the disk image` followed
  by a suggestion, then exits 1. Previously, `sfdisk --json` exited 1
  with stderr suppressed (`2>/dev/null`) and `set -euo pipefail` caused
  the script to exit immediately with no output.

---

## [1.4.0] — 2026-06-15

### Added

- `info` / `info --json`: raw partition detection via two-stage probe.
  Partitions with no recognised filesystem now show `fstype: "raw"` (was
  `"unknown"`) in JSON output, and carry a new `raw_hint` field containing
  a short description extracted from the partition content. Stage 1 runs
  `file(1)` magic on the first 4 KB (catches GRUB env blocks, kernels);
  Stage 2 scans null-terminated strings in the first 256 bytes (covers
  HAOS-style `key=value` bootstate stores where `file` returns `"data"`).
  Human table output shows `[raw: BOOT_A_LEFT=3 BOOT_ORDER=B A ...]` in
  the Notes column instead of `[no recognised filesystem]`. Partitions for
  which no hint is found still show `fstype: "raw"` with `raw_hint: null`.
- `raw.img` test fixture: GPT, EFI (100 MB) + raw (16 MB) partition with
  planted null-terminated `key=value` strings simulating a HAOS bootstate
  partition. Tests cover partition count, `fstype: raw`, non-mountability,
  `raw_hint` content, and human table `[raw:` annotation.

---

## [1.3.1] — 2026-06-15

---

## [1.3.0] — 2026-06-14

### Changed

- CI pipeline: opt in to `auto-promote: full`. After a successful CI run
  on `dev`, the shared pipeline now automatically bumps the version,
  promotes `[Unreleased]` in the CHANGELOG, fast-forward merges
  `dev→main`, and pushes `dev/main/vX.Y.Z` atomically. Requires
  `PROMOTE_TOKEN` (fine-grained PAT, `contents: write`) as a repository
  secret; absent token degrades to `bump-only`.

---

## [1.2.0] — 2026-06-14

### Added

- btrfs filesystem driver (`src/container/drivers/btrfs.sh`). btrfs
  partitions are now mountable via kernel mount (`mount -t btrfs
  -o ro,degraded`). The `degraded` flag permits mounting single-device
  images that were captured from a multi-device btrfs volume.
  Tests skip gracefully when the btrfs kernel module is absent.
- `btrfs-progs` package added to the Docker image, providing the `btrfs`
  CLI for use in `shell` and `browse` sessions.
- `btrfs.img` test fixture: GPT, EFI (100 MB) + btrfs root (300 MB),
  with `/etc/hostname` planted when the kernel module is available in
  the generation container.

### Tests

- `test/02-image-structure.bats`: verifies `drivers/btrfs.sh` is
  installed and executable; verifies `btrfs` binary is present.
- `test/05-partition-discovery.bats`: three tests covering btrfs
  partition count, mountability, and human-readable `info` output.
- `test/06-subcommands.bats`: btrfs partition identified by `info
  --json`; `run cat /etc/hostname` reads fixture content (skips when
  kernel module unavailable or `/etc/hostname` was not planted).

---

## [1.1.0] — 2026-06-14

### Added

- squashfs filesystem driver (`src/container/drivers/squashfs.sh`). squashfs
  partitions are now mountable via kernel mount (`mount -t squashfs -o ro`).
  Requires the squashfs kernel module in the Docker VM (available in Docker
  Desktop on macOS and Linux); tests skip gracefully when the module is absent.
- `squashfs-tools` package added to the Docker image, providing `unsquashfs`
  and `mksquashfs` for use in `shell` and `browse` sessions.
- `squashfs.img` test fixture: GPT, EFI (100 MB) + squashfs root (100 MB),
  with `/etc/hostname` and `/etc/os-release` planted at build time.

### Tests

- `test/02-image-structure.bats`: verifies `drivers/squashfs.sh` is installed
  and executable; verifies `unsquashfs` binary is present.
- `test/05-partition-discovery.bats`: three tests covering squashfs partition
  count, mountability, and human-readable `info` output.
- `test/06-subcommands.bats`: squashfs partition identified by `info --json`;
  `run cat /etc/hostname` reads fixture content (skips when kernel module
  unavailable).

---

## [1.0.1] — 2026-06-13

### Fixed

- `clean` now accepts `-i|--image PATH` as a per-subcommand flag.
  Previously `usb-explore clean -i path.img` failed with
  "Unknown clean option: -i" even though the SYNOPSIS documented it.
- `clean` no longer double-prompts when the image file is write-protected
  (e.g. owned by root after `sudo dd`). The user confirms once at the
  `usb-explore` prompt; `rm -f` handles the rest.
- Errors during argument parsing (and any other early `die()` path) no
  longer cause a visible hang before returning to the shell prompt. The
  `_cleanup` exit-trap previously called `docker stop` unconditionally;
  it now skips the Docker call unless a container was actually started.

### Tests

- Static-analysis and functional tests in `test/08-cli.bats` cover all
  three fixes. Total tests: 58 (up from 53).

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

### Fixed

- `shell` and `serve` subcommands now accept `-p|--partition N` as a
  per-subcommand flag. Previously both functions had no argument parser,
  so a partition specified after the subcommand name (e.g.
  `usb-explore shell -p 4`) was silently ignored and `select-partition`
  fell through to the multi-partition error even when the user had
  explicitly selected a partition.
- Interactive subcommands (`shell`, `browse`, `serve`) now return exit 0
  when the user presses Ctrl-C. Docker exits 130 on SIGINT; the previous
  code propagated that exit code, triggering Docker Desktop's error prompt
  even though the user intentionally ended the session. The `|| rc=$?`
  idiom is required because `set -e` exits the script before a plain
  `rc=$?` assignment is reached.
- `shell` sessions no longer leave a spurious `exit` line in the host
  terminal when the session ends. Bash's interactive shutdown handler
  always prints `exit`; the fix disables bash 5.1+ bracketed-paste mode
  (via `INPUTRC`) so readline's escape sequences do not displace the
  cursor, then erases the trailing line with `\033[1A\033[2K\r` after
  `docker run` returns.
- Docker Desktop's "What's next:" hint block no longer appears after
  interactive sessions that exit via Ctrl-D. `DOCKER_CLI_HINTS=false` is
  now set in `run_container` before invoking docker. Without it, the
  multi-line hint block shifted the cursor past the cleanup target,
  leaving the spurious `exit` line visible.
- `run` output no longer includes the container-internal `/mnt/part/`
  prefix. All path output from `run` is now partition-relative, matching
  the output of `find` and `hash`, and can be piped directly into `copy`,
  `archive`, `diff`, and `hash` without manual editing. The host-side
  subcommands also accept `/mnt/part`-prefixed paths as a compatibility
  fallback (e.g. paths pasted from a `shell` session).
- `browse` now resets the terminal state before the container exits.
  `mc` enables mouse-tracking and alternate-screen modes and does not
  always disable them — in particular when its Ctrl-O subshell is active.
  Without an explicit reset, pending mouse-tracking escape sequences were
  received as text by processes still in the container, producing phantom
  commands at the host prompt (e.g. `bash: 10: command not found`). The
  fix emits `\033c` (VT100 Reset to Initial State) after `mc` exits. The
  `exec` before `mc` was removed so that the dispatch process survives
  long enough to perform the reset.

### Tests

- Routing tests in `test/08-cli.bats` now pass `--image /nonexistent.img`
  so they exit at `check_image_file` (exit 4) without invoking any
  container or host tool. Previously, a `usb.img` in the working
  directory caused them to proceed into `resolve_partition` and
  trigger BW01 advisory warnings.
- Exit-code normalisation: four tests verify that `shell`, `browse`, and
  `serve` map docker exit 130 (SIGINT) to exit 0 and propagate other
  non-zero codes. Tests use a minimal docker stub to avoid requiring a
  live container.
- Static-analysis tests cover terminal-cleanup invariants: bracketed-paste
  disabled in container `do_shell` via `INPUTRC`; cursor-up+clear escape
  (`\033[1A\033[2K`) present in host `do_shell`; `DOCKER_CLI_HINTS=false`
  present in `run_container`.
- Static-analysis tests cover `/mnt/part` stripping: `copy` and `diff`
  strip the container prefix from path arguments; container `do_run`
  filters `/mnt/part/` from output via `sed`.
- Static-analysis tests cover `browse` terminal reset: `printf '\033c'`
  present and `exec mc` absent in container `do_browse`.
- `test/08-cli.bats` adds a `DISPATCH` constant pointing at
  `src/container/dispatch.sh` for container-side static-analysis. Total
  tests in the file: 53 (up from 42 in the initial 1.0.0 draft).

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
- `README.md` `shell` section: clarified that Ctrl-C interrupts the
  current command but keeps the session open; it does not exit the
  shell.
- `README.md` `run` section: removed the mention of the container-internal
  `/mnt/part` prefix. Path arguments and output are now described as
  partition-relative; output can be piped directly into `copy`, `archive`,
  `hash`, and `diff`.

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
- Test fixtures generated by `test/fixtures/generate.sh` inside a privileged
  Docker container; no host kernel extensions required.

[Unreleased]: https://github.com/1121citrus/usb-explore/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/1121citrus/usb-explore/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/1121citrus/usb-explore/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/1121citrus/usb-explore/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/1121citrus/usb-explore/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/1121citrus/usb-explore/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/1121citrus/usb-explore/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/1121citrus/usb-explore/compare/v0.1.1...v1.0.0
[0.1.1]: https://github.com/1121citrus/usb-explore/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/1121citrus/usb-explore/releases/tag/v0.1.0
