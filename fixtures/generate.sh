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
#
# All disk operations work on /tmp/<img> inside the container (the container's
# own overlay layer) to avoid virtiofs-vs-losetup compatibility issues.
# The finished images are moved to /fixtures at the end.
set -euo pipefail

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { echo "fixtures: ${*}" >&2; }
warn() { echo "fixtures: WARNING: ${*}" >&2; }

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

    log "Generating ${name}..."

    if docker run --rm --privileged \
        -v "${FIXTURES_DIR}:/fixtures" \
        ubuntu:24.04 \
        bash -euo pipefail -c "
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DEBIAN_FRONTEND=noninteractive apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
       gdisk dosfstools e2fsprogs xfsprogs fdisk util-linux parted jq >/dev/null 2>&1

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
        return 1
    fi
}

ensure_docker

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

log "All fixtures generated."
ls -lh "${FIXTURES_DIR}"/*.img 2>/dev/null || true
