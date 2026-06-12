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
- [Partition selection](#partition-selection)
- [Configuration](#configuration)
- [Building from source](#building-from-source)
- [Testing](#testing)
- [CI/CD](#cicd)
- [Security considerations](#security-considerations)
- [Contributing](#contributing)

---

## Quick start

```bash
# Install the wrapper script somewhere on your PATH
curl -o /usr/local/bin/usb-explore \
    https://raw.githubusercontent.com/1121citrus/usb-explore/main/src/usb-explore
chmod +x /usr/local/bin/usb-explore

# Or, if you have the repository cloned:
export PATH="$PWD/src:$PATH"
```

Then, with a USB drive plugged in:

```bash
# 1. Find your USB drive
diskutil list
# Look for your drive, e.g. /dev/disk4

# 2. Copy it to a disk image (run once — takes a few minutes for a 32 GB drive)
usb-explore capture /dev/disk4

# 3. See what is on it
usb-explore info

# 4. Browse interactively
usb-explore shell

# 5. — or — copy a specific file out
usb-explore copy /etc/fstab ./fstab

# 6. — or — run a command against the image
usb-explore run -- find /home -name '*.log'
```

The drive image is saved as `usb.img` in the current directory. You can
unplug the USB drive after step 2.

---

## Prerequisites

| Requirement | How to get it |
| --- | --- |
| macOS 13 (Ventura) or later | System update |
| Docker Desktop | [docker.com](https://www.docker.com/products/docker-desktop/) |
| `dd` and `diskutil` | Included in macOS |

No Homebrew packages required. The Docker image is pulled automatically
on first use.

---

## Architecture overview

Because Docker Desktop for macOS virtualizes Linux but does not expose raw host block devices (e.g., `/dev/disk4`) to containers, direct mounting of a USB drive is not possible. `usb-explore` uses a two-stage approach to bypass this limitation:

1. **Host capture**: A native macOS script uses `dd` to copy the physical USB drive to a sparse image file block-by-block.
2. **Container isolation**: The image file is bind-mounted into a minimal Ubuntu-based Docker container. The container uses standard Linux utilities (`sfdisk`, `losetup`, `blkid`, `mount`) to parse the partition table and attach loop devices.

Filesystem support (ext4, xfs, vfat, iso9660) is implemented via a modular driver system inside the container. All partition mounts are strictly read-only, guaranteeing the captured disk image remains immutable. While the container requires `--privileged` to manage loop devices, its access is bounded by the Docker Desktop Linux VM, safely isolating the macOS host.

---

## Subcommands

### `capture` — copy a USB drive to a disk image

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

#### Why capture is required — and why direct device access is not possible

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

### `info` — show the partition table

```text
usb-explore info [-i usb.img] [--json]
```

Prints a table of all partitions, their filesystem type, size, and
whether they can be mounted. Useful for understanding what is on the
drive before deciding which partition to explore.

**Example output:**

```text
Image:  usb.img  (29.8 GB)
Scheme: GPT

  #   Filesystem   Size      Label              UUID          Notes
  1   vfat         200 MB    EFI                2C3D-AF1B     [EFI — not mountable]
  2   ext4         29.0 GB   cloudimg-rootfs    a1b2c3d4      [mountable]

1 mountable partition found. Omit -p to auto-select, or pass -p 2 explicitly.
```

`--json` emits machine-readable JSON for scripting.

---

### `shell` — browse interactively

```text
usb-explore shell [-i usb.img] [-p N]
```

Starts a bash shell inside a container with the partition mounted at
`/mnt/part`. Type `exit` or press Ctrl-D to leave.

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

### `copy` — copy files out of the image

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

### `run` — run a command against the image

```text
usb-explore run [-i usb.img] [-p N] [--] <command> [args…]
```

Runs a command inside the container with the partition mounted. Arguments
that start with `/` are automatically prefixed with `/mnt/part` so you
can write natural Linux paths.

```bash
# Find all config files
usb-explore run -- find /etc -name '*.conf'

# Check disk usage
usb-explore run -- du -sh /home/*

# Pipe the output through local tools
usb-explore run -- cat /etc/os-release | grep VERSION
```

---

### `diff` — compare the image against a local reference

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

### `build` — rebuild the Docker image from source

```text
usb-explore build [--no-cache]
```

Rebuilds the container image from the local `Dockerfile`. Only needed if
you are modifying the tool itself. See [Building from source](#building-from-source).

---

## Partition selection

Most drives have one main partition and one EFI (boot) partition. The
EFI partition is automatically excluded. When only one mountable
partition is found, it is selected automatically.

When a drive has two or more mountable partitions, `usb-explore info` is
printed and you must specify which one with `-p`:

```bash
usb-explore shell -p 2       # use partition 2
usb-explore copy -p 3 /etc ./etc-from-p3
```

---

## Configuration

| Environment variable | Default | Description |
| --- | --- | --- |
| `USB_EXPLORE_REGISTRY` | `1121citrus` | Docker Hub registry prefix |
| `USB_EXPLORE_TAG` | `latest` | Image tag to use |
| `USB_EXPLORE_IMAGE` | `./usb.img` | Default disk image path |

---

## Building from source

Requires Docker Desktop and bash 4+.

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
Docker so no additional tools are needed on the host.

```bash
# Generate fixture disk images (run once; requires Docker)
bash fixtures/generate.sh

# Run the full test suite
./build --no-scan

# Run a single test file
docker run --rm \
    -v "$PWD:$PWD" -w "$PWD" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e "IMAGE=1121citrus/usb-explore:dev-latest" \
    bats/bats:1.13.0 \
    bats test/03-invocation.bats
```

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
