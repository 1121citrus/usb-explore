#!/usr/bin/env bash
# Generate small disk image fixtures for the BATS test suite.
# All disk manipulation runs inside a privileged Docker container so no
# macOS kernel extensions are required.
#
# Images created:
#   single-ext4.img  — GPT, 200 MB EFI + 300 MB ext4
#   dual-ext4.img    — GPT, 200 MB EFI + 300 MB ext4 + 200 MB ext4
#   xfs.img          — GPT, 200 MB EFI + 300 MB xfs
#   mbr.img          — MBR, 500 MB ext4
set -euo pipefail

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "fixtures: ${*}" >&2; }

# ensure_docker — require a running Docker daemon
ensure_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "fixtures: Docker is not running." >&2
        exit 1
    fi
}

# make_image — run a privileged Ubuntu container to partition and format
# a disk image file, then place it in FIXTURES_DIR.
#
# Args:
#   $1 = output filename (e.g. single-ext4.img)
#   $2 = inline bash script to run inside the container
make_image() {
    local name="${1}" script="${2}"
    local out="${FIXTURES_DIR}/${name}"

    log "Generating ${name}..."

    docker run --rm --privileged \
        -v "${FIXTURES_DIR}:/fixtures" \
        ubuntu:24.04 \
        bash -euo pipefail -c "
apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    gdisk dosfstools e2fsprogs xfsprogs util-linux >/dev/null 2>&1
${script}
"
    log "  → ${out}"
}

ensure_docker

# ---------------------------------------------------------------------------
# single-ext4.img: GPT, EFI (200 MB) + ext4 root (300 MB)
# ---------------------------------------------------------------------------
make_image single-ext4.img '
IMG=/fixtures/single-ext4.img
truncate -s 530M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:2048:411647   -t 1:ef00 -c 1:"EFI" \
    -n 2:411648:1089535 -t 2:8300 -c 2:"Linux root" >/dev/null

LOOP=$(losetup --find --partscan --show "${IMG}")
trap "losetup --detach ${LOOP}" EXIT

mkfs.fat -F32 -n EFI "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L rootfs "${LOOP}p2"

# Plant a known file for copy/run/diff tests
mount "${LOOP}p2" /mnt
mkdir -p /mnt/etc /mnt/home
echo "usb-explore-test" > /mnt/etc/hostname
echo "root:x:0:0:root:/root:/bin/bash" > /mnt/etc/passwd
umount /mnt
'

# ---------------------------------------------------------------------------
# dual-ext4.img: GPT, EFI (200 MB) + ext4 root (300 MB) + ext4 data (200 MB)
# ---------------------------------------------------------------------------
make_image dual-ext4.img '
IMG=/fixtures/dual-ext4.img
truncate -s 740M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:2048:411647    -t 1:ef00 -c 1:"EFI" \
    -n 2:411648:1089535  -t 2:8300 -c 2:"Linux root" \
    -n 3:1089536:1499135 -t 3:8300 -c 3:"data" >/dev/null

LOOP=$(losetup --find --partscan --show "${IMG}")
trap "losetup --detach ${LOOP}" EXIT

mkfs.fat -F32 -n EFI "${LOOP}p1" >/dev/null
mkfs.ext4 -q -L rootfs "${LOOP}p2"
mkfs.ext4 -q -L data   "${LOOP}p3"

mount "${LOOP}p2" /mnt
mkdir -p /mnt/etc
echo "dual-test" > /mnt/etc/hostname
umount /mnt
'

# ---------------------------------------------------------------------------
# xfs.img: GPT, EFI (200 MB) + xfs root (300 MB)
# ---------------------------------------------------------------------------
make_image xfs.img '
IMG=/fixtures/xfs.img
truncate -s 530M "${IMG}"
sgdisk -Z "${IMG}" \
    -n 1:2048:411647    -t 1:ef00 -c 1:"EFI" \
    -n 2:411648:1089535  -t 2:8300 -c 2:"Linux root" >/dev/null

LOOP=$(losetup --find --partscan --show "${IMG}")
trap "losetup --detach ${LOOP}" EXIT

mkfs.fat -F32 -n EFI "${LOOP}p1" >/dev/null
mkfs.xfs -q -L rootfs "${LOOP}p2"

mount -o norecovery "${LOOP}p2" /mnt
mkdir -p /mnt/etc
echo "xfs-test" > /mnt/etc/hostname
umount /mnt
'

# ---------------------------------------------------------------------------
# mbr.img: MBR, ext4 root (500 MB)
# ---------------------------------------------------------------------------
make_image mbr.img '
IMG=/fixtures/mbr.img
truncate -s 510M "${IMG}"
echo -e "o\nn\np\n1\n\n\nw" | fdisk "${IMG}" >/dev/null 2>&1 || true

LOOP=$(losetup --find --partscan --show "${IMG}")
trap "losetup --detach ${LOOP}" EXIT

mkfs.ext4 -q -L rootfs "${LOOP}p1"
mount "${LOOP}p1" /mnt
mkdir -p /mnt/etc
echo "mbr-test" > /mnt/etc/hostname
umount /mnt
'

log "All fixtures generated."
