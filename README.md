# usb-explore

Look inside a Linux USB drive from a Mac, without installing anything extra.

You copy the drive to a file once, then browse it as many times as you
like — list files, copy things out, compare them to a reference. The
Mac never needs to understand the Linux filesystem; a Docker container
handles that part.

---

## Contents

- [Quick start](#quick-start)
- [Prerequisites](#prerequisites)
- [Architecture overview](#architecture-overview)
- [Subcommands](#subcommands)
  - [Core workflow](#core-workflow)
    - [capture — copy a USB drive to a disk image](#capture--copy-a-usb-drive-to-a-disk-image)
    - [clean — remove the disk image](#clean--remove-the-disk-image)
    - [copy — copy files out of the image](#copy--copy-files-out-of-the-image)
    - [info — show the partition table](#info--show-the-partition-table)
    - [shell — open an interactive bash shell](#shell--open-an-interactive-bash-shell)
  - [Exploration and search](#exploration-and-search)
    - [browse — visual file manager](#browse--visual-file-manager)
    - [find — search for files or content](#find--search-for-files-or-content)
    - [run — run a command against the image](#run--run-a-command-against-the-image)
    - [serve — browse the partition over HTTP](#serve--browse-the-partition-over-http)
  - [Expert tools](#expert-tools)
    - [archive — create a compressed archive](#archive--create-a-compressed-archive)
    - [diff — compare the image against a local reference](#diff--compare-the-image-against-a-local-reference)
    - [hash — verify file integrity](#hash--verify-file-integrity)
  - [Developer](#developer)
    - [build — rebuild the Docker image from source](#build--rebuild-the-docker-image-from-source)
- [Partition selection](#partition-selection)
- [Configuration](#configuration)
- [Building from source](#building-from-source)
- [Testing](#testing)
- [CI/CD](#cicd)
- [Security considerations](#security-considerations)
- [Contributing](#contributing)

---

## Quick start

### Install

Pick one method:

```bash
# Option 1: install script (from a clone)
./bin/install

# Option 2: install script (standalone download)
curl -fsSL https://raw.githubusercontent.com/1121citrus/usb-explore/main/bin/install | bash

# Option 3: Homebrew
brew install --formula ./install/homebrew/Formula/usb-explore.rb

# Option 4: manual — just add src/ to your PATH
export PATH="$PWD/src:$PATH"
```

`bin/install` copies `src/usb-explore` to `/usr/local/bin` by default.
Pass `--prefix ~/.local` to install elsewhere. Run `bin/install --help`
for all options.

### Use

With a USB drive plugged in:

```bash
# 1. Find your USB drive
diskutil list
# Look for your drive, e.g. /dev/disk4

# 2. Copy it to a disk image (run once — takes a few minutes for a 32 GB drive)
usb-explore capture /dev/disk4

# 3. See what is on it
usb-explore info

# 4. Browse interactively (shell or visual file manager)
usb-explore shell
usb-explore browse

# 5. — or — copy a specific file out
usb-explore copy /etc/fstab ./fstab

# 6. — or — run a command against the image
usb-explore run -- find /home -name '*.log'

# 7. When you are done, remove the image file
usb-explore clean
```

The drive image is saved as `usb.img` in the current directory. You can
unplug the USB drive after step 2.

---

## Prerequisites

| Requirement | How to get it |
| --- | --- |
| macOS 13 (Ventura) or later | System update |
| Docker-compatible runtime | See [container runtime options](#container-runtime-options) below |
| `dd` and `diskutil` | Included in macOS |

No Homebrew packages required. The Docker image is pulled automatically
on first use.

### Container runtime options

Any Docker-compatible runtime that supports `--privileged` containers
works. The container needs real root inside the VM for `losetup` and
`mount`.

| Runtime | Status | Notes |
| --- | --- | --- |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | **Tested in CI** | Primary development and CI runtime |
| [OrbStack](https://orbstack.dev/) | Verified compatible | Drop-in Docker Desktop replacement; no code changes needed |
| [Colima](https://github.com/abiosoft/colima) | Verified compatible | Use dockerd mode (default). Multi-platform `buildx` push requires QEMU binfmt registration |
| [Rancher Desktop](https://rancherdesktop.io/) | Verified compatible | Must use dockerd mode, not containerd mode |
| Podman Desktop | Not supported | Requires rootful mode; no `buildx`; ~50 call sites would need abstraction |
| Rootless Docker | Not compatible | `losetup` and `mount` require real `CAP_SYS_ADMIN`; rootless cannot provide it |

To verify your runtime, run the compatibility test:

```bash
# Quick subset — exercises --privileged, losetup, bind mounts (~2 min)
./test/runtime-compat --quick

# Full test suite (~5 min)
./test/runtime-compat
```

The script detects the active runtime, runs the test suite, and prints
a JSON summary with the result.

---

## Architecture overview

Because Docker Desktop for macOS virtualizes Linux but does not expose raw host block devices (e.g., `/dev/disk4`) to containers, direct mounting of a USB drive is not possible. `usb-explore` uses a two-stage approach to bypass this limitation:

1. **Host capture**: A native macOS script uses `dd` to copy the physical USB drive to a sparse image file block-by-block.
2. **Container isolation**: The image file is bind-mounted into a minimal Ubuntu-based Docker container. The container uses standard Linux utilities (`sfdisk`, `losetup`, `blkid`, `mount`) to parse the partition table and attach loop devices.

Filesystem support is implemented via a modular driver system inside the container:

| Filesystem | Typical use |
| --- | --- |
| ext2 / ext3 / ext4 | Ubuntu, Debian, most Linux installs |
| xfs | RHEL, Rocky Linux, AlmaLinux |
| vfat | EFI system partitions, legacy boot media |
| btrfs | openSUSE, Fedora (default since F33), NAS appliances |
| squashfs | Live ISOs (Ubuntu `/casper/filesystem.squashfs`), embedded root filesystems |
| erofs | Home Assistant OS system partitions (`hassos-system0`/`hassos-system1`) |
| iso9660 | Hybrid bootable ISO/GPT images |

Storage abstraction layers are handled transparently via a layered
driver pipeline that activates each layer before mounting:

| Layer | Typical use | Notes |
| --- | --- | --- |
| LVM | Enterprise Linux, RHEL default installer | VG activated read-only; `--lv` selects when multiple LVs exist |
| LUKS | Full-disk encryption (Ubuntu, Fedora) | Decrypt with `--luks-passphrase-file` (recommended), `--luks-key-file`, or `--luks-passphrase` |

Layers can stack (e.g. LUKS → LVM → ext4). `info` reports the
detected storage layer in the Notes column and the `storage_layer`
field in JSON output.

All partition mounts are strictly read-only, guaranteeing the captured disk image remains immutable. While the container requires `--privileged` to manage loop devices, its access is bounded by the Docker Desktop Linux VM, safely isolating the macOS host.

---

## Subcommands

### Core workflow

Capture the drive once, inspect its contents, extract what you need, and
clean up when finished.

#### `capture` — copy a USB drive to a disk image

```text
usb-explore capture <device> [options]
```

Copies the USB device to a flat image file using `dd`. The device must be
a whole-disk node (e.g. `/dev/disk4`, not `/dev/disk4s1`).

| Option | Default | Description |
| --- | --- | --- |
| `-o, --output PATH` | `./usb.img` | Destination image file |
| `--no-sparse` | off | Write every block, even zero blocks |
| `--progress-interval N` | 5 | Seconds between progress reports |
| `--dry-run` | off | Print the `dd` command without running it |

**Example:**

```bash
usb-explore capture /dev/disk4 --output /Volumes/backup/my-usb.img
```

On APFS volumes, the image file is sparse: a 64 GB drive with 8 GB of
data will occupy about 8–10 GB of disk space, not 64 GB. The image is
complete and exact — the Mac's filesystem just skips writing zero blocks.

Progress is reported every 5 seconds. On a large drive, capturing can
take 15–30 minutes. You can unplug the drive when it finishes.

##### Why capture is required — and why direct device access is not possible

Docker Desktop on macOS runs a Linux VM (via Hypervisor.framework or
HyperKit). macOS block device nodes such as `/dev/disk4` do not exist
inside that VM. Docker's file-sharing layer handles regular files, not
raw block devices, so passing `-v /dev/disk4:/disk.img` or
`--device /dev/disk4` to a container does not work.

`capture` exists to bridge this gap: it runs `dd` natively on macOS
(no Docker involved) and writes the device contents to a plain file.
Every other subcommand then bind-mounts that file into the container as
`/disk.img` — the mechanism that does work across the macOS-to-Docker
boundary.

The I/O cost is a one-time overhead. Once the image file exists, all
explore operations (`info`, `copy`, `run`, `diff`, `shell`) read only
what they need and are fast regardless of the original drive size.

---

#### `clean` — remove the disk image

```text
usb-explore clean [-i usb.img] [-y|--yes]
```

Removes the captured disk image file. Prompts for confirmation unless
`-y` / `--yes` is given. Does not require Docker.

```bash
# Interactive confirmation prompt
usb-explore clean

# Skip the prompt (useful in scripts)
usb-explore clean --yes

# Remove a specific image file
usb-explore --image /Volumes/backup/my-usb.img clean --yes
```

Exit code: 0 on success or when the user declines; 4 if the file does
not exist.

---

#### `copy` — copy files out of the image

```text
usb-explore copy [-i usb.img] [-p N] <src-path> <dest>
```

Copies `<src-path>` (absolute path within the partition) to `<dest>` on
your Mac. Works for both individual files and directories.

```bash
# Copy a single file
usb-explore copy /etc/nginx/nginx.conf ./nginx.conf

# Copy a whole directory
usb-explore copy /etc ./etc-backup
```

---

#### `info` — show the partition table

```text
usb-explore info [-i usb.img] [--json]
```

Prints a table of all partitions, their filesystem type, size, and
whether they can be mounted. Useful for understanding what is on the
drive before deciding which partition to explore.

**Example — home server (ext4 root):**

```text
Image:  /disk.img  (24.0 MB)
Scheme: GPT

  #    Filesystem  Size        Label                   UUID        Notes
  1    vfat        4.0 MB      EFI                     13FD-321    [mountable]
  2    ext4        19.0 MB     rootfs                  2ca3ba92    [mountable]

2 mountable partitions found. Pass -p N to select one.
```

**Example — enterprise server (LUKS + LVM):**

```text
Image:  /disk.img  (48.0 MB)
Scheme: GPT

  #    Filesystem  Size        Label                   UUID        Notes
  1    vfat        4.0 MB      EFI                     1492-B18    [mountable]
  2    crypto_LUKS  43.0 MB     Linux LUKS+LVM          d9fd98d2    [mountable via luks]

2 mountable partitions found. Pass -p N to select one.
```

The **Notes** column shows:

- `[mountable]` — a filesystem driver is available; the partition can be
  used with `shell`, `copy`, `run`, etc.
- `[mountable via lvm]`, `[mountable via luks]` — a storage abstraction
  layer is detected. The layer is activated transparently before
  mounting. LUKS partitions require `--luks-passphrase-file` or
  `--luks-passphrase`. LVM partitions with multiple LVs require `--lv`.
- `[raw: ...]` — no recognised filesystem (`blkid` found nothing).
  `usb-explore` runs a two-stage probe to extract a short description:
  first `file(1)` magic, then a null-terminated string scan. The extracted
  strings appear in the note. These partitions cannot be mounted.
- `[BIOS Boot Partition excluded]`, `[Linux swap excluded]`, etc. —
  partition type is explicitly excluded from mounting.

`--json` emits machine-readable JSON for scripting. Each partition record
includes `fstype` (`"raw"` when no filesystem is detected), `mountable`,
`mountable_reason`, `storage_layer` (`"lvm"`, `"luks"`, or
`null`), and — for raw partitions — `raw_hint` (the same content shown
in the Notes column, or `null` when nothing was found).

---

#### `shell` — open an interactive bash shell

```text
usb-explore shell [-i usb.img] [-p N]
```

Starts a bash shell inside a container with the partition mounted at
`/mnt/part`. Type `exit` or press Ctrl-D to leave. Ctrl-C interrupts the current
command but keeps the shell open — it does not exit the session.

```bash
usb-explore shell
# (usb-explore p2) /mnt/part $  ls
# bin  boot  dev  etc  home  lib  ...
# (usb-explore p2) /mnt/part $  cat etc/hostname
# my-server
# (usb-explore p2) /mnt/part $  exit
```

The partition is mounted **read-only**. You cannot modify the image.

---

### Exploration and search

Navigate and search the partition without extracting files to the host.

#### `browse` — visual file manager

```text
usb-explore browse [-i usb.img] [-p N]
```

Opens [Midnight Commander](https://midnight-commander.org/) (`mc`) at the
partition root inside the container. Useful for visually navigating
directories, previewing files, and comparing directory trees without
typing paths by hand. `ncdu` is also available inside the shell for
interactive disk-usage analysis.

```bash
usb-explore browse
# Midnight Commander opens, rooted at the partition
# Press F10 or q to quit
```

Requires a terminal (TTY). Cannot be used in a pipe or non-interactive script.

---

#### `find` — search for files or content

```text
usb-explore find [-i usb.img] [-p N] [NAME-GLOB] [--grep PATTERN]
```

Searches the partition by filename, file contents, or both. Output paths
are partition-relative and can be passed directly to `copy`, `archive`,
`diff`, or `hash`.

| Option | Description |
| --- | --- |
| `NAME-GLOB` | Match filenames (e.g. `"*.log"`, `"hostname"`) |
| `--grep PATTERN` | Search inside files (grep `-E` syntax) |

At least one of `NAME-GLOB` or `--grep` is required; both may be
combined to restrict content matches to a specific filename pattern.

```bash
# Find all .conf files
usb-explore find "*.conf"

# Find files containing a specific string
usb-explore find --grep "PermitRootLogin"

# Find only sshd_config files that mention PermitRootLogin
usb-explore find "sshd_config" --grep "PermitRootLogin"
```

Exit code: 0 for a name search regardless of matches; 1 when `--grep`
finds no matches (standard `grep` behaviour).

---

#### `run` — run a command against the image

```text
usb-explore run [-i usb.img] [-p N] [--] <command> [args…]
```

Runs a command inside the container with the partition mounted. Arguments
that start with `/` are treated as partition-relative paths. Output paths
are also partition-relative, so you can pipe them directly into `copy`,
`archive`, `hash`, or `diff`.

```bash
# Find all config files
usb-explore run -- find /etc -name '*.conf'

# Check disk usage
usb-explore run -- du -sh /home/*

# Pipe the output through local tools
usb-explore run -- cat /etc/os-release | grep VERSION
```

---

#### `serve` — browse the partition over HTTP

```text
usb-explore serve [-i usb.img] [-p N] [--port PORT] [--no-open]
```

Starts a read-only HTTP file server on your Mac. Open the printed URL in
any browser to navigate the partition as a directory listing and download
individual files. Press Ctrl-C to stop the server.

| Option | Default | Description |
| --- | --- | --- |
| `--port PORT` | 8080 | Host port for the HTTP server |
| `--no-open` | off | Suppress automatic browser launch |

```bash
# Start on the default port 8080
usb-explore serve
# Serving partition 2 at http://localhost:8080/
# Press Ctrl-C to stop.

# Use a different port
usb-explore serve --port 9090

# Suppress automatic browser launch (e.g. in an SSH session)
usb-explore serve --no-open
```

The browser opens automatically on macOS when a local display is
available. It is suppressed automatically in SSH sessions
(`SSH_CONNECTION` or `SSH_TTY` set) and can be suppressed explicitly
with `--no-open`. The partition is served read-only; no files can be
modified or uploaded.

---

### Expert tools

For forensic verification, structured archiving, and scripting use cases.

#### `archive` — create a compressed archive

```text
usb-explore archive [-i usb.img] [-p N] <src-path> <dest>
```

Creates a compressed archive of `<src-path>` (absolute path within the
partition) at `<dest>` on your Mac. The compression format is determined
by the file extension.

| Extension | Compression |
| --- | --- |
| `.tar.gz`, `.tgz` | gzip |
| `.tar.bz2`, `.tbz2` | bzip2 |
| `.tar.xz`, `.txz` | xz |
| `.tar` | none |

```bash
# Archive the /etc directory as a gzip tarball
usb-explore archive /etc ./usb-etc.tar.gz

# Archive a single log file with bzip2
usb-explore archive /var/log/syslog ./syslog.tar.bz2

# Uncompressed tar of the home directory
usb-explore archive /home ./usb-home.tar
```

The archive preserves the top-level directory name (e.g. archiving `/etc`
produces a `etc/…` tree inside the tarball).

---

#### `diff` — compare the image against a local reference

```text
usb-explore diff [-i usb.img] [-p N] <image-path> <reference-path>
```

Diffs a path inside the partition against a path on your Mac. Exit code
follows `diff`: 0 = identical, 1 = differences found, 2 = error.

```bash
# Compare the image /etc against a known-good reference
usb-explore diff /etc ./reference/etc

# Check whether a config file changed
usb-explore diff /etc/fstab ./expected-fstab
```

---

#### `hash` — verify file integrity

```text
usb-explore hash [-i usb.img] [-p N] <path>
```

Prints the SHA-256 checksum of a single file from the partition without
extracting it to disk first. Useful for forensic verification or
confirming that a configuration file matches a known-good value.

Output format is identical to `sha256sum(1)`:

```text
<64-hex-digits>  <path>
```

```bash
# Verify a kernel image
usb-explore hash /boot/vmlinuz

# Compare the result against a reference hash
usb-explore hash /etc/passwd | sha256sum --check expected-hashes.txt
```

The `<path>` argument must be absolute and must point to a file, not a
directory.

---

### Developer

Only needed when modifying `usb-explore` itself.

#### `build` — rebuild the Docker image from source

```text
usb-explore build [--no-cache]
```

Rebuilds the container image from the local `Dockerfile`. Only needed if
you are modifying the tool itself. See [Building from source](#building-from-source).

---

## Partition selection

Most drives have one main data partition and one EFI (boot) partition.
Both are considered mountable — the vfat driver handles EFI partitions.
When exactly one mountable partition is found, it is selected
automatically. When two or more are found, `usb-explore info` is printed
and you must select one with `-p`:

```bash
usb-explore shell -p 2       # use partition 2
usb-explore copy -p 3 /etc ./etc-from-p3
```

BIOS Boot, Linux swap, and raw (unrecognised filesystem) partitions are
excluded from the mountable count. LVM and LUKS partitions are
mountable — storage layers are activated automatically before mounting.

### Storage layer options

When a partition uses LVM or LUKS, additional flags may be
needed:

```bash
# LVM: auto-selects the single LV; use --lv when multiple exist
usb-explore shell -p 2
usb-explore shell -p 2 --lv data

# LUKS: read passphrase from a file (recommended — not exposed in
# process args or docker inspect)
usb-explore shell -p 2 --luks-passphrase-file /path/to/passphrase.txt

# LUKS: supply passphrase directly (visible in docker inspect)
usb-explore shell -p 2 --luks-passphrase 'my secret'

# LUKS: use a binary key file
usb-explore shell -p 2 --luks-key-file /path/to/keyfile

# Stacked LUKS → LVM: both flags work together
usb-explore shell -p 1 --luks-passphrase-file ~/pp.txt --lv root
```

> **Prefer `--luks-passphrase-file` for LUKS credentials.** The file is
> bind-mounted read-only into the container and read there; the secret
> never appears in the process argument list or the container
> environment, so it is not visible to `ps`, `docker inspect`, or shell
> history. `--luks-key-file` is equally safe for binary keys. Use
> `--luks-passphrase` only for throwaway test images — the value is
> passed as an environment variable and is visible in `docker inspect`
> and process listings.

---

## Configuration

| Environment variable | Default | Description |
| --- | --- | --- |
| `USB_EXPLORE_REGISTRY` | `1121citrus` | Docker Hub registry prefix |
| `USB_EXPLORE_TAG` | `latest` | Image tag to use |
| `USB_EXPLORE_IMAGE` | `./usb.img` | Default disk image path |

---

## Building from source

Requires a Docker-compatible runtime and bash 4+. macOS ships bash 3.2;
install a newer version via [Homebrew](https://brew.sh/)
(`brew install bash`) or [pkgin](https://pkgin.net/) if you do not
already have one.

```bash
git clone https://github.com/1121citrus/usb-explore.git
cd usb-explore

# Build image and run tests (skip vulnerability scans for speed)
./build --no-scan

# Full build with scans
./build

# Build and push a release
./build --push --version 1.2.3
```

See `./build --help` for all options.

---

## Testing

Tests use [BATS](https://bats-core.readthedocs.io/) and run inside
Docker so no additional tools are needed on the host. The suite
currently has ~290 tests across 10 test files. See
[test/README.md](test/README.md) for the full breakdown.

```bash
# Generate fixture disk images (run once; requires Docker)
bash test/fixtures/generate.sh

# Run the full test suite
./build --no-scan

# Run a single test file
docker run --rm \
    -v "$PWD:$PWD" -w "$PWD" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e "IMAGE=1121citrus/usb-explore:dev-latest" \
    bats/bats:1.13.0 \
    test/08-cli.bats
```

`generate.sh` is idempotent: it only builds fixtures that are missing,
and accepts image basenames to build a specific one (for example
`bash test/fixtures/generate.sh showcase-enterprise.img`).

The `showcase-*` fixtures double as the README example images and are
deliberately "nothing up the sleeves" — real, burnable disk images you
could `dd` to a USB stick and mount on any Linux system:

- **`showcase-home.img.gz`** is committed to the repository (<30 KB
  gzipped). Because it is small, it ships as a genuine, fixed resource
  rather than something generated on the fly; its contents are pinned by
  `showcase-home.img.gz.sha256` and verified by the test suite.
- **`showcase-enterprise.img`** (LUKS1 → LVM, ~50 MB) is far too large
  to commit, so it is generated on demand the first time a test needs
  it. Its LUKS layer uses random salts, so it is not bit-reproducible
  and is intentionally not pinned.

---

## CI/CD

The GitHub Actions pipeline (`ci.yml`) runs on every push and pull
request:

| Stage | What runs |
| --- | --- |
| Lint | hadolint, shellcheck, markdownlint |
| Build | Single-platform image build |
| Test | BATS test suite |
| Scan | Trivy CVE scan (HIGH/CRITICAL) |
| Push | Multi-platform push, SBOM + provenance (tag and main only) |

Required repository secrets for the push stage:

| Secret | Purpose |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub login |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

---

## Security considerations

`usb-explore` runs its Docker container with `--privileged` because
`losetup` (associating the disk image with a loop device) and `mount`
both require `CAP_SYS_ADMIN` at the Linux kernel level. There is no
userspace alternative.

On macOS, Docker containers run inside an isolated Linux VM managed by
Docker Desktop. A container escape from `--privileged` reaches that VM,
not your Mac's filesystem or your files. This is a real but bounded risk.

The disk image is always mounted **read-only**. The container cannot
modify the source image. The container is removed immediately on exit
(`--rm`).

If you are not comfortable running a privileged container, this tool is
not for you.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

Licence: [AGPL-3.0-or-later](LICENSE.md)
