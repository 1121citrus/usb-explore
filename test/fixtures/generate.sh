#!/usr/bin/env bash
# Generate small disk image fixtures for the BATS test suite.
# All disk manipulation runs inside a privileged Docker container so no
# macOS kernel extensions are required.
#
# Images created:
#   single-ext4.img  — GPT, 200 MB EFI + 300 MB ext4
#   dual-ext4.img    — GPT, 200 MB EFI + 300 MB ext4 + 200 MB ext4
#   xfs.img          — GPT, 200 MB EFI + 400 MB xfs
#   mbr.img          — MBR, 500 MB ext4
#   dirty-ext4.img   — GPT, 100 MB EFI + 100 MB ext4 (needs_recovery set)
#   squashfs.img     — GPT, 100 MB EFI + 100 MB squashfs
#   btrfs.img        — GPT, 100 MB EFI + 300 MB btrfs
#   raw.img          — GPT, 100 MB EFI + 16 MB raw (no filesystem)
#   erofs.img        — GPT, 100 MB EFI + 100 MB erofs (read-only)
#   showcase-home.img       — GPT, EFI + ext4 home server (committed as
#                             showcase-home.img.gz; extracted, not rebuilt)
#   showcase-enterprise.img — GPT, EFI + LUKS1 → LVM (root + data); too
#                             large to commit, generated on demand
#
# Usage:
#   generate.sh [IMAGE ...]
#     With no arguments, every missing fixture is generated. Pass one or
#     more image basenames (e.g. "showcase-enterprise.img") to generate
#     only those. Fixtures that already exist are left untouched, so the
#     script is idempotent and safe to re-run.
#
# All disk operations work on /tmp/<img> inside the container (the container's
# own overlay layer) to avoid virtiofs-vs-losetup compatibility issues.
# The finished images are moved to /fixtures at the end.
set -euo pipefail

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional list of image basenames to generate. Empty means "all missing".
SELECTED_IMAGES=("$@")

log()  { echo "fixtures: ${*}" >&2; }
warn() { echo "fixtures: WARNING: ${*}" >&2; }

# sha256_of — print the lowercase sha256 hex digest of a file.
# Args:   $1 = file path
# Stdout: 64-char hex digest, or empty when no hashing tool is available
sha256_of() {
    local file="${1}"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    fi
}

# should_generate — decide whether a fixture must be (re)built.
# Builds only when the image is selected (or no selection was given) AND
# the target file does not already exist in FIXTURES_DIR.
# Args:   $1 = image basename
# Returns: 0 to build, 1 to skip
should_generate() {
    local name="${1}"

    # Honour an explicit selection list when one was provided.
    if (( ${#SELECTED_IMAGES[@]} > 0 )); then
        local wanted match=1
        for wanted in "${SELECTED_IMAGES[@]}"; do
            [[ "${wanted}" == "${name}" ]] && match=0 && break
        done
        (( match == 0 )) || return 1
    fi

    # Never rebuild a fixture that is already present.
    [[ -f "${FIXTURES_DIR}/${name}" ]] && return 1
    return 0
}

# extract_committed_showcase — restore committed showcase images from their
# tracked .img.gz artifacts instead of regenerating them. This preserves the
# exact, pinned bitstring of "nothing up the sleeves" showcase resources.
# A pinned sha256 (showcase-home.img.gz.sha256) is verified when present.
# Args: none
# Returns: 0 (best-effort); exits 1 on a pinned-checksum mismatch
extract_committed_showcase() {
    local gz local_img sha_file expected actual
    for gz in "${FIXTURES_DIR}"/showcase-*.img.gz; do
        [[ -f "${gz}" ]] || continue

        # Verify the committed artifact against its pinned digest, if any.
        sha_file="${gz}.sha256"
        if [[ -f "${sha_file}" ]]; then
            expected=$(awk '{print $1}' "${sha_file}")
            actual=$(sha256_of "${gz}")
            if [[ -n "${actual}" && "${actual}" != "${expected}" ]]; then
                warn "checksum mismatch for $(basename "${gz}")"
                warn "  expected ${expected}"
                warn "  actual   ${actual}"
                exit 1
            fi
        fi

        local_img="${gz%.gz}"
        if [[ ! -f "${local_img}" ]]; then
            log "Extracting committed $(basename "${gz}")..."
            gunzip -k "${gz}"
        fi
    done
}

ensure_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "fixtures: Docker is not running." >&2
        exit 1
    fi
}

# make_image — run a privileged Ubuntu container to partition and format
# a disk image, reading the build script from stdin.
# The script works on /tmp/<name> and copies to /fixtures at the end.
#
# Args:   $1 = output filename (basename only, placed in FIXTURES_DIR)
# Stdin:  bash script executed inside the container as root
make_image() {
    local name="${1}"
    local script
    script=$(cat)

    # Skip fixtures that already exist or were not selected on the command
    # line. stdin is consumed above so skipping never leaks the heredoc.
    if ! should_generate "${name}"; then
        log "Skipping ${name} (already present or not selected)"
        return 0
    fi

    log "Generating ${name}..."

    if docker run --rm --privileged \
        -v "${FIXTURES_DIR}:/fixtures" \
        ubuntu:24.04 \
        bash -euo pipefail -c "
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DEBIAN_FRONTEND=noninteractive apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
       gdisk dosfstools e2fsprogs xfsprogs fdisk util-linux parted jq \
       btrfs-progs cryptsetup-bin erofs-utils lvm2 \
       squashfs-tools >/dev/null 2>&1

# LVM inside Docker: no udev, so disable udev sync and create dm nodes
# directly. Without this, lvcreate fails with 'device not cleared'.
mkdir -p /run/lvm
printf 'activation { udev_sync = 0\\nudev_rules = 0\\n}\\n' \
    > /etc/lvm/lvmlocal.conf

# part_loop — create a read-only loop device for one partition using
# byte offsets computed from sfdisk. Works on any file reachable from
# the container's own overlay layer (e.g. /tmp).
# Args:   \$1 = image file path, \$2 = 1-based partition number
# Returns: 0; writes loop device path to stdout
part_loop() {
    local img=\"\$1\" partnum=\"\$2\"
    local sfdisk_json sector_size start size offset sizelimit candidate lp

    sfdisk_json=\$(sfdisk --json \"\${img}\")
    sector_size=\$(echo \"\${sfdisk_json}\" | jq -r '.partitiontable.sectorsize // 512')
    start=\$(echo \"\${sfdisk_json}\" | jq -r \".partitiontable.partitions[\${partnum}-1].start\")
    size=\$(echo \"\${sfdisk_json}\"  | jq -r \".partitiontable.partitions[\${partnum}-1].size\")
    offset=\$(( start * sector_size ))
    sizelimit=\$(( size * sector_size ))

    # Pre-create the loop device node if losetup --find points beyond /dev/loop66
    candidate=\$(losetup --find 2>/dev/null || true)
    if [[ -n \"\${candidate}\" && ! -b \"\${candidate}\" ]]; then
        local num=\"\${candidate#/dev/loop}\"
        mknod \"\${candidate}\" b 7 \"\${num}\" 2>/dev/null || true
    fi

    lp=\$(losetup --find --show --offset=\"\${offset}\" --sizelimit=\"\${sizelimit}\" \"\${img}\")
    echo \"\${lp}\"
}
${script}
" 2>&1; then
        log "  -> ${FIXTURES_DIR}/${name}"
    else
        warn "${name}: generation failed; skipping."
        rm -f "${FIXTURES_DIR}/${name}"
        return 0
    fi
}

ensure_docker

# Restore committed showcase images from their pinned .img.gz artifacts
# before any generation runs, so they are never rebuilt or clobbered.
extract_committed_showcase

# ---------------------------------------------------------------------------
# single-ext4.img: GPT, EFI (200 MB) + ext4 root (300 MB)
# Work in /tmp to avoid virtiofs/losetup incompatibility; copy to /fixtures.
# ---------------------------------------------------------------------------
make_image single-ext4.img <<'SCRIPT'
IMG=/tmp/single-ext4.img
truncate -s 560M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+200M -t 1:ef00 -c 1:"EFI" \
    -n 2:0:+300M -t 2:8300 -c 2:"Linux root" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'umount /mnt 2>/dev/null||true; losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F32 -n EFI   "${LP1}" >/dev/null
mkfs.ext4 -q -L rootfs "${LP2}"

mount "${LP2}" /mnt
mkdir -p /mnt/etc /mnt/home
echo "usb-explore-test"                  > /mnt/etc/hostname
echo "root:x:0:0:root:/root:/bin/bash"   > /mnt/etc/passwd
umount /mnt
losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/single-ext4.img
SCRIPT

# ---------------------------------------------------------------------------
# dual-ext4.img: GPT, EFI (200 MB) + ext4 root (300 MB) + ext4 data (200 MB)
# ---------------------------------------------------------------------------
make_image dual-ext4.img <<'SCRIPT'
IMG=/tmp/dual-ext4.img
truncate -s 760M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+200M -t 1:ef00 -c 1:"EFI" \
    -n 2:0:+300M -t 2:8300 -c 2:"Linux root" \
    -n 3:0:+200M -t 3:8300 -c 3:"data" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
LP3=$(part_loop "${IMG}" 3)
trap 'umount /mnt 2>/dev/null||true; losetup -d "${LP1}" "${LP2}" "${LP3}" 2>/dev/null||true' EXIT

mkfs.fat -F32 -n EFI   "${LP1}" >/dev/null
mkfs.ext4 -q -L rootfs "${LP2}"
mkfs.ext4 -q -L data   "${LP3}"

mount "${LP2}" /mnt
mkdir -p /mnt/etc
echo "dual-test" > /mnt/etc/hostname
umount /mnt
losetup -d "${LP1}" "${LP2}" "${LP3}"
trap - EXIT
cp "${IMG}" /fixtures/dual-ext4.img
SCRIPT

# ---------------------------------------------------------------------------
# xfs.img: GPT, EFI (200 MB) + xfs root (400 MB, minimum >300 MB)
# ---------------------------------------------------------------------------
make_image xfs.img <<'SCRIPT'
IMG=/tmp/xfs.img
truncate -s 660M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+200M -t 1:ef00 -c 1:"EFI" \
    -n 2:0:+400M -t 2:8300 -c 2:"Linux root" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'umount /mnt 2>/dev/null||true; losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F32 -n EFI   "${LP1}" >/dev/null
mkfs.xfs  -q -f -L rootfs "${LP2}"

# Attempt to load the xfs kernel module then mount and plant /etc/hostname.
# If the module is unavailable (some Docker VMs), the image is still usable
# for partition-discovery tests via blkid; the subcommand test skips gracefully.
modprobe xfs 2>/dev/null || true
if mount -o norecovery "${LP2}" /mnt 2>/dev/null; then
    mkdir -p /mnt/etc
    echo "xfs-test" > /mnt/etc/hostname
    umount /mnt
fi
losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/xfs.img
SCRIPT

# ---------------------------------------------------------------------------
# mbr.img: MBR, ext4 root (500 MB)
# ---------------------------------------------------------------------------
make_image mbr.img <<'SCRIPT'
IMG=/tmp/mbr.img
truncate -s 540M "${IMG}"
parted -s "${IMG}" mklabel msdos mkpart primary ext4 1MiB 100%

LP1=$(part_loop "${IMG}" 1)
trap 'umount /mnt 2>/dev/null||true; losetup -d "${LP1}" 2>/dev/null||true' EXIT

mkfs.ext4 -q -L rootfs "${LP1}"
mount "${LP1}" /mnt
mkdir -p /mnt/etc
echo "mbr-test" > /mnt/etc/hostname
umount /mnt
losetup -d "${LP1}"
trap - EXIT
cp "${IMG}" /fixtures/mbr.img
SCRIPT

# ---------------------------------------------------------------------------
# dirty-ext4.img: GPT, EFI (100 MB) + ext4 root (100 MB) with needs_recovery
# set in the superblock — simulates a USB captured without a clean unmount.
# ---------------------------------------------------------------------------
make_image dirty-ext4.img <<'SCRIPT'
IMG=/tmp/dirty-ext4.img
truncate -s 260M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+100M -t 1:ef00 -c 1:"EFI" \
    -n 2:0:+100M -t 2:8300 -c 2:"dirty-root" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'umount /mnt 2>/dev/null||true; losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F32 -n EFI       "${LP1}" >/dev/null
mkfs.ext4 -q -L dirty-root "${LP2}"

mount "${LP2}" /mnt
mkdir -p /mnt/etc
echo "dirty-ext4-test" > /mnt/etc/hostname
umount /mnt

# Re-set EXT4_FEATURE_INCOMPAT_RECOVER (0x0004) in the superblock to simulate
# a filesystem that was captured without a clean unmount.
#
# The ext4 superblock sits at byte 1024 from the partition start;
# s_feature_incompat is at superblock offset 0x60 (96), so the absolute
# offset into the loop device is 1024 + 96 = 1120.
#
# Direct byte writes (Python struct) invalidate the superblock CRC32c
# checksum when metadata_csum is enabled (the default since Ubuntu 24.04),
# causing blkid to reject the superblock as corrupt. Instead: Python reads
# the current value (read-only, no checksum concern), then debugfs writes
# it back — debugfs always recomputes and updates the checksum.
new_incompat=$(python3 -c "
import struct
with open('${LP2}', 'rb') as f:
    f.seek(1120)
    val = struct.unpack('<I', f.read(4))[0]
    print('0x{:08X}'.format(val | 0x04))
")
debugfs -w -R "set_super_value s_feature_incompat ${new_incompat}" "${LP2}" 2>/dev/null

losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/dirty-ext4.img
SCRIPT

# ---------------------------------------------------------------------------
# squashfs.img: GPT, EFI (100 MB) + squashfs root (100 MB)
# squashfs is a compressed read-only filesystem. mksquashfs creates the image
# from a directory tree; dd writes it to the raw partition so blkid can probe
# the squashfs magic. No kernel module is needed for creation.
# ---------------------------------------------------------------------------
make_image squashfs.img <<'SCRIPT'
IMG=/tmp/squashfs.img
truncate -s 260M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+100M -t 1:ef00 -c 1:"EFI" \
    -n 2:0:+100M -t 2:8300 -c 2:"squashfs-root" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F32 -n EFI "${LP1}" >/dev/null

# Build squashfs content tree and write to the raw partition.
# mksquashfs is a userspace tool; no kernel module required for creation.
SQDIR=/tmp/squashfs-content
mkdir -p "${SQDIR}/etc"
echo "squashfs-test"   > "${SQDIR}/etc/hostname"
echo "ID=squashfs-test" > "${SQDIR}/etc/os-release"

mksquashfs "${SQDIR}" /tmp/content.sfs -noappend -quiet
dd if=/tmp/content.sfs of="${LP2}" bs=4M 2>/dev/null

losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/squashfs.img
SCRIPT

# ---------------------------------------------------------------------------
# btrfs.img: GPT, EFI (100 MB) + btrfs root (300 MB)
# btrfs requires a minimum partition size (~109 MB with default block groups);
# 300 MB is comfortably above that threshold.
# ---------------------------------------------------------------------------
make_image btrfs.img <<'SCRIPT'
IMG=/tmp/btrfs.img
truncate -s 460M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+100M -t 1:ef00 -c 1:"EFI" \
    -n 2:0:+300M -t 2:8300 -c 2:"btrfs-root" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'umount /mnt 2>/dev/null||true; losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F32 -n EFI "${LP1}" >/dev/null
mkfs.btrfs -q -L rootfs "${LP2}"

# Attempt to load the btrfs kernel module then mount and plant /etc/hostname.
# If the module is unavailable (some Docker VMs), the image is still usable
# for partition-discovery tests via blkid; the subcommand test skips gracefully.
modprobe btrfs 2>/dev/null || true
if mount -o degraded "${LP2}" /mnt 2>/dev/null; then
    mkdir -p /mnt/etc
    echo "btrfs-test" > /mnt/etc/hostname
    umount /mnt
fi

losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/btrfs.img
SCRIPT

# ---------------------------------------------------------------------------
# raw.img: GPT, EFI (100 MB) + raw unformatted partition (16 MB)
# No filesystem is created on the second partition so blkid finds nothing.
# Null-terminated key=value pairs are written to the first 256 bytes to
# exercise probe_raw_hint's string-scan fallback path.
# ---------------------------------------------------------------------------
make_image raw.img <<'SCRIPT'
IMG=/tmp/raw.img
truncate -s 160M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+100M -t 1:ef00 -c 1:"EFI" \
    -n 2:0:+16M  -t 2:8300 -c 2:"hassos-bootstate" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F32 -n EFI "${LP1}" >/dev/null

# Write null-terminated key=value pairs at the start of the raw partition.
# No filesystem — blkid will find no recognised type; probe_raw_hint
# must recover the strings via the null-byte scan path.
printf 'BOOT_A_LEFT=3\0BOOT_ORDER=B A\0MACHINE_ID=test1234\0' \
    | dd of="${LP2}" conv=notrunc 2>/dev/null

losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/raw.img
SCRIPT

# ---------------------------------------------------------------------------
# erofs.img: GPT, EFI (100 MB) + erofs root (100 MB)
# erofs is a compressed read-only filesystem used by HAOS system partitions.
# mkfs.erofs creates the image from a directory tree; dd writes it to the
# raw partition so blkid can probe the erofs magic. Mounting requires the
# erofs kernel module in the Docker VM; creation is userspace-only.
# ---------------------------------------------------------------------------
make_image erofs.img <<'SCRIPT'
IMG=/tmp/erofs.img
truncate -s 260M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+100M -t 1:ef00 -c 1:"EFI" \
    -n 2:0:+100M -t 2:8300 -c 2:"erofs-root" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F32 -n EFI "${LP1}" >/dev/null

# Build erofs content tree and write to the raw partition.
# mkfs.erofs is a userspace tool; no kernel module required for creation.
EROOT=/tmp/erofs-content
mkdir -p "${EROOT}/etc"
echo "erofs-test"    > "${EROOT}/etc/hostname"
echo "ID=erofs-test" > "${EROOT}/etc/os-release"

mkfs.erofs "${LP2}" "${EROOT}" >/dev/null 2>&1

losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/erofs.img
SCRIPT

# ---------------------------------------------------------------------------
# lvm.img: GPT, 100 MB LVM PV containing one VG with one ext4 LV
# ---------------------------------------------------------------------------
make_image lvm.img <<'SCRIPT'
IMG=/tmp/lvm.img
truncate -s 200M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+150M -t 1:8e00 -c 1:"Linux LVM" >/dev/null

LP1=$(part_loop "${IMG}" 1)
trap 'umount /mnt 2>/dev/null||true; vgchange -an usb_test_vg 2>/dev/null||true; losetup -d "${LP1}" 2>/dev/null||true' EXIT

pvcreate --force "${LP1}" >/dev/null 2>&1
vgcreate usb_test_vg "${LP1}" >/dev/null 2>&1
lvcreate --zero n --name root --size 100M usb_test_vg >/dev/null 2>&1

mkfs.ext4 -q -L lvm-root /dev/usb_test_vg/root
mount /dev/usb_test_vg/root /mnt
mkdir -p /mnt/etc
echo "lvm-test" > /mnt/etc/hostname
umount /mnt

vgchange -an usb_test_vg >/dev/null 2>&1
losetup -d "${LP1}"
trap - EXIT
cp "${IMG}" /fixtures/lvm.img
SCRIPT

# ---------------------------------------------------------------------------
# luks.img: GPT, 100 MB LUKS-encrypted partition containing ext4
# Test passphrase: "test-passphrase"
# ---------------------------------------------------------------------------
make_image luks.img <<'SCRIPT'
IMG=/tmp/luks.img
truncate -s 200M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+150M -t 1:8300 -c 1:"Linux LUKS" >/dev/null

LP1=$(part_loop "${IMG}" 1)
trap 'umount /mnt 2>/dev/null||true; cryptsetup close usb_test_luks 2>/dev/null||true; losetup -d "${LP1}" 2>/dev/null||true' EXIT

printf 'test-passphrase' \
    | cryptsetup luksFormat --batch-mode --type luks2 "${LP1}" -
printf 'test-passphrase' \
    | cryptsetup open "${LP1}" usb_test_luks

mkfs.ext4 -q -L luks-root /dev/mapper/usb_test_luks
mount /dev/mapper/usb_test_luks /mnt
mkdir -p /mnt/etc
echo "luks-test" > /mnt/etc/hostname
umount /mnt

cryptsetup close usb_test_luks
losetup -d "${LP1}"
trap - EXIT
cp "${IMG}" /fixtures/luks.img
SCRIPT

# ---------------------------------------------------------------------------
# luks-lvm.img: GPT, LUKS → LVM → ext4 (common enterprise stacking)
# Test passphrase: "test-passphrase"
# ---------------------------------------------------------------------------
make_image luks-lvm.img <<'SCRIPT'
IMG=/tmp/luks-lvm.img
truncate -s 250M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+200M -t 1:8300 -c 1:"Linux LUKS+LVM" >/dev/null

LP1=$(part_loop "${IMG}" 1)
trap 'umount /mnt 2>/dev/null||true; vgchange -an usb_test_stack_vg 2>/dev/null||true; cryptsetup close usb_test_stack_luks 2>/dev/null||true; losetup -d "${LP1}" 2>/dev/null||true' EXIT

printf 'test-passphrase' \
    | cryptsetup luksFormat --batch-mode --type luks2 "${LP1}" -
printf 'test-passphrase' \
    | cryptsetup open "${LP1}" usb_test_stack_luks

pvcreate --force /dev/mapper/usb_test_stack_luks >/dev/null 2>&1
vgcreate usb_test_stack_vg /dev/mapper/usb_test_stack_luks >/dev/null 2>&1
lvcreate --zero n --name data --size 100M usb_test_stack_vg >/dev/null 2>&1

mkfs.ext4 -q -L stack-root /dev/usb_test_stack_vg/data
mount /dev/usb_test_stack_vg/data /mnt
mkdir -p /mnt/etc
echo "luks-lvm-test" > /mnt/etc/hostname
umount /mnt

vgchange -an usb_test_stack_vg >/dev/null 2>&1
cryptsetup close usb_test_stack_luks
losetup -d "${LP1}"
trap - EXIT
cp "${IMG}" /fixtures/luks-lvm.img
SCRIPT

# ---------------------------------------------------------------------------
# showcase-home.img: realistic home server — EFI + ext4 root
# Committed as showcase-home.img.gz and restored by
# extract_committed_showcase above, so this block only runs when the
# committed artifact is missing (bootstrap). Regenerating produces a new
# bitstring; the committed .gz and its pinned sha256 are the source of
# truth for the "nothing up the sleeves" showcase resource.
# Small image with representative /etc, /home, /var/log content for
# README examples. Committed as showcase-home.img.gz.
# ---------------------------------------------------------------------------
make_image showcase-home.img <<'SCRIPT'
IMG=/tmp/showcase-home.img
truncate -s 24M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+4M  -t 1:ef00 -c 1:"EFI" \
    -n 2:0:0    -t 2:8300 -c 2:"Linux root" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'umount /mnt 2>/dev/null||true; losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F12 -n EFI "${LP1}" >/dev/null
mkfs.ext4 -q -L rootfs "${LP2}"

mount "${LP2}" /mnt
mkdir -p /mnt/etc/netplan /mnt/home/admin /mnt/var/log /mnt/boot

cat > /mnt/etc/hostname <<'EOF'
citrus-server
EOF

cat > /mnt/etc/os-release <<'EOF'
PRETTY_NAME="Ubuntu 24.04.2 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.2 LTS (Noble Numbat)"
ID=ubuntu
ID_LIKE=debian
EOF

cat > /mnt/etc/fstab <<'EOF'
# <file system>  <mount point>  <type>  <options>         <dump> <pass>
UUID=a1b2c3d4     /              ext4    errors=remount-ro 0      1
UUID=2C3D-AF1B    /boot/efi      vfat    umask=0077        0      1
EOF

cat > /mnt/etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/bash
admin:x:1000:1000:Admin User:/home/admin:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF

cat > /mnt/etc/netplan/01-netcfg.yaml <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      addresses: [10.0.50.10/24]
      gateway4: 10.0.50.1
      nameservers:
        addresses: [10.0.50.5, 1.1.1.1]
EOF

cat > /mnt/home/admin/.bashrc <<'EOF'
export PS1='\u@\h:\w\$ '
alias ll='ls -alF'
EOF

cat > /mnt/var/log/syslog <<'EOF'
Jun 15 08:00:01 citrus-server systemd[1]: Started Daily apt download activities.
Jun 15 08:00:12 citrus-server systemd[1]: docker.service: Main process exited, code=exited, status=0/SUCCESS
Jun 15 08:05:33 citrus-server sshd[1842]: Accepted publickey for admin from 10.0.50.100 port 54321
Jun 15 09:15:00 citrus-server CRON[2105]: (root) CMD (/usr/local/bin/backup-daily)
Jun 15 10:30:44 citrus-server kernel: [86400.123] eth0: link up, 1000 Mbps full duplex
EOF

printf 'LINUX-KERNEL-STUB' > /mnt/boot/vmlinuz

umount /mnt
losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/showcase-home.img
gzip -kf /fixtures/showcase-home.img
SCRIPT

# ---------------------------------------------------------------------------
# showcase-enterprise.img: LUKS → LVM with two LVs (root + data)
# Demonstrates storage layer stacking and --lv selection.
# Passphrase: "showcase"
# Committed as showcase-enterprise.img.gz.
# ---------------------------------------------------------------------------
make_image showcase-enterprise.img <<'SCRIPT'
IMG=/tmp/showcase-enterprise.img
truncate -s 48M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:0:+4M  -t 1:ef00 -c 1:"EFI" \
    -n 2:0:0    -t 2:8300 -c 2:"Linux LUKS+LVM" >/dev/null

LP1=$(part_loop "${IMG}" 1)
LP2=$(part_loop "${IMG}" 2)
trap 'umount /mnt 2>/dev/null||true; vgchange -an vg0 2>/dev/null||true; cryptsetup close showcase_luks 2>/dev/null||true; losetup -d "${LP1}" "${LP2}" 2>/dev/null||true' EXIT

mkfs.fat -F12 -n EFI "${LP1}" >/dev/null

printf 'showcase' | cryptsetup luksFormat --batch-mode --type luks1 "${LP2}" -
printf 'showcase' | cryptsetup open "${LP2}" showcase_luks

pvcreate --force /dev/mapper/showcase_luks >/dev/null 2>&1
vgcreate vg0 /dev/mapper/showcase_luks >/dev/null 2>&1
lvcreate --zero n --name root --size 12M vg0 >/dev/null 2>&1
lvcreate --zero n --name data --size 10M vg0 >/dev/null 2>&1

mkfs.ext4 -q -L root /dev/vg0/root
mkfs.ext4 -q -L data /dev/vg0/data

# Populate root LV
mount /dev/vg0/root /mnt
mkdir -p /mnt/etc /mnt/var/log

cat > /mnt/etc/hostname <<'EOF'
prod-db-01
EOF

cat > /mnt/etc/os-release <<'EOF'
PRETTY_NAME="Red Hat Enterprise Linux 9.4 (Plow)"
NAME="Red Hat Enterprise Linux"
VERSION_ID="9.4"
ID=rhel
ID_LIKE="centos fedora"
EOF

cat > /mnt/etc/fstab <<'EOF'
# <file system>       <mount point>  <type>  <options>         <dump> <pass>
/dev/mapper/vg0-root   /              ext4    defaults          1      1
/dev/mapper/vg0-data   /srv/data      ext4    defaults,nodev    0      2
UUID=2C3D-AF1B         /boot/efi      vfat    umask=0077        0      1
EOF

cat > /mnt/var/log/syslog <<'EOF'
Jun 14 03:00:01 prod-db-01 systemd[1]: Starting PostgreSQL 16 database server...
Jun 14 03:00:05 prod-db-01 postgres[1201]: database system is ready to accept connections
Jun 14 06:00:00 prod-db-01 CRON[3401]: (postgres) CMD (pg_dump -Fc myapp > /srv/data/backups/daily.dump)
Jun 14 12:15:33 prod-db-01 sshd[4502]: Accepted publickey for ops from 10.10.0.50 port 44100
EOF
umount /mnt

# Populate data LV
mount /dev/vg0/data /mnt
mkdir -p /mnt/backups /mnt/exports

cat > /mnt/backups/daily.manifest <<'EOF'
backup_date: 2026-06-14T06:00:00Z
database: myapp
format: custom
size_bytes: 15728640
tables: 42
EOF

cat > /mnt/exports/README <<'EOF'
Data export directory. CSV files are generated nightly by the
reporting pipeline and picked up by the analytics team via SFTP.
EOF
umount /mnt

vgchange -an vg0 >/dev/null 2>&1
cryptsetup close showcase_luks
losetup -d "${LP1}" "${LP2}"
trap - EXIT
cp "${IMG}" /fixtures/showcase-enterprise.img
SCRIPT

log "All fixtures generated."
ls -lh "${FIXTURES_DIR}"/*.img 2>/dev/null || true
