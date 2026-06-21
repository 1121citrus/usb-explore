#!/usr/bin/env bats
# 05-partition-discovery.bats — partition discovery, mountability, and
# auto-selection logic.
#
# jq is run inside the usb-explore container (bats host may not have it).
# All tests skip gracefully when fixture images are absent.

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

# jq_from_json — pipe JSON through jq inside the usb-explore container.
# Args: $1 = JSON string, $2 = jq filter
jq_from_json() {
    echo "$1" | docker run --rm -i --entrypoint=jq "${IMAGE}" -r "$2"
}

# info_json — run info --json on a fixture and return JSON.
# Args: $1 = fixture filename (basename in FIXTURES dir)
info_json() {
    docker run --rm --privileged \
        -v "${FIXTURES}/${1}:/disk.img:ro" \
        "${IMAGE}" info --json
}

# ---------------------------------------------------------------------------
# single-ext4.img
# ---------------------------------------------------------------------------

@test "discovery: single-ext4.img has 2 partitions" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json count
    json=$(info_json single-ext4.img)
    count=$(jq_from_json "${json}" '.partitions | length')
    [ "${count}" -eq 2 ]
}

@test "discovery: single-ext4.img has 2 mountable partitions (EFI vfat + ext4)" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json count
    json=$(info_json single-ext4.img)
    count=$(jq_from_json "${json}" '[.partitions[] | select(.mountable == true)] | length')
    [ "${count}" -eq 2 ]
}

@test "discovery: single-ext4.img partition 1 (EFI vfat) is mountable" {
    # EFI is no longer excluded: the vfat driver mounts it fine.
    # It is excluded from AUTO-SELECTION (requires -p N) but IS mountable.
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json mountable fstype
    json=$(info_json single-ext4.img)
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .mountable')
    fstype=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .fstype')
    [ "${mountable}" = "true" ]
    [ "${fstype}" = "vfat" ]
}

@test "discovery: single-ext4.img partition 2 is mountable ext4" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json fstype mountable
    json=$(info_json single-ext4.img)
    fstype=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | .fstype')
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | .mountable')
    [ "${fstype}" = "ext4" ]
    [ "${mountable}" = "true" ]
}

@test "discovery: info --json schema has required top-level keys" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json
    json=$(info_json single-ext4.img)
    jq_from_json "${json}" '.image'      >/dev/null
    jq_from_json "${json}" '.size_bytes' >/dev/null
    jq_from_json "${json}" '.size_human' >/dev/null
    jq_from_json "${json}" '.label'      >/dev/null
    jq_from_json "${json}" '.partitions' >/dev/null
}

@test "discovery: each partition record has required keys" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json part
    json=$(info_json single-ext4.img)
    part=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | @json')
    jq_from_json "${part}" '.node'      >/dev/null
    jq_from_json "${part}" '.size_bytes' >/dev/null
    jq_from_json "${part}" '.size_human' >/dev/null
    jq_from_json "${part}" '.fstype'    >/dev/null
    jq_from_json "${part}" '.mountable' >/dev/null
}

# ---------------------------------------------------------------------------
# dual-ext4.img
# ---------------------------------------------------------------------------

@test "discovery: dual-ext4.img has 3 mountable partitions (EFI vfat + 2 ext4)" {
    [[ -f "${FIXTURES}/dual-ext4.img" ]] || skip "fixture not generated"
    local json count
    json=$(info_json dual-ext4.img)
    count=$(jq_from_json "${json}" '[.partitions[] | select(.mountable == true)] | length')
    [ "${count}" -eq 3 ]
}

# ---------------------------------------------------------------------------
# xfs.img
# ---------------------------------------------------------------------------

@test "discovery: xfs.img has an xfs mountable partition" {
    # xfs.img has EFI (vfat, mountable) + xfs (mountable). Verify xfs is present.
    [[ -f "${FIXTURES}/xfs.img" ]] || skip "fixture not generated"
    local json fstype
    json=$(info_json xfs.img)
    fstype=$(jq_from_json "${json}" \
        '[.partitions[] | select(.mountable == true and .fstype == "xfs")][0].fstype')
    [ "${fstype}" = "xfs" ]
}

# ---------------------------------------------------------------------------
# mbr.img
# ---------------------------------------------------------------------------

@test "discovery: mbr.img label is dos (MBR)" {
    [[ -f "${FIXTURES}/mbr.img" ]] || skip "fixture not generated"
    local json label
    json=$(info_json mbr.img)
    label=$(jq_from_json "${json}" '.label')
    [ "${label}" = "dos" ]
}

@test "discovery: mbr.img has 1 mountable ext4 partition" {
    [[ -f "${FIXTURES}/mbr.img" ]] || skip "fixture not generated"
    local json count fstype
    json=$(info_json mbr.img)
    count=$(jq_from_json "${json}" '[.partitions[] | select(.mountable == true)] | length')
    fstype=$(jq_from_json "${json}" '[.partitions[] | select(.mountable == true)][0].fstype')
    [ "${count}" -eq 1 ]
    [ "${fstype}" = "ext4" ]
}

# ---------------------------------------------------------------------------
# Human table output
# ---------------------------------------------------------------------------

@test "discovery: info (human) shows EFI partition as mountable" {
    # EFI is no longer excluded: vfat driver handles it. It shows [mountable].
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"EFI"* ]]
    [[ "${output}" == *"vfat"* ]]
    [[ "${output}" == *"mountable"* ]]
}

@test "discovery: info (human) summary line shows 2 mountable partitions" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"2 mountable"* ]]
}

# ---------------------------------------------------------------------------
# squashfs.img
# ---------------------------------------------------------------------------

@test "discovery: squashfs.img has 2 partitions" {
    [[ -f "${FIXTURES}/squashfs.img" ]] || skip "fixture squashfs.img not generated"
    local json count
    json=$(info_json squashfs.img)
    count=$(jq_from_json "${json}" '.partitions | length')
    [ "${count}" -eq 2 ]
}

@test "discovery: squashfs.img partition 2 is mountable squashfs" {
    [[ -f "${FIXTURES}/squashfs.img" ]] || skip "fixture squashfs.img not generated"
    local json fstype mountable
    json=$(info_json squashfs.img)
    fstype=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | .fstype')
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | .mountable')
    [ "${fstype}" = "squashfs" ]
    [ "${mountable}" = "true" ]
}

@test "discovery: squashfs.img info shows squashfs as mountable" {
    [[ -f "${FIXTURES}/squashfs.img" ]] || skip "fixture squashfs.img not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/squashfs.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"squashfs"* ]]
    [[ "${output}" == *"mountable"* ]]
}

# ---------------------------------------------------------------------------
# btrfs.img
# ---------------------------------------------------------------------------

@test "discovery: btrfs.img has 2 partitions" {
    [[ -f "${FIXTURES}/btrfs.img" ]] || skip "fixture btrfs.img not generated"
    local json count
    json=$(info_json btrfs.img)
    count=$(jq_from_json "${json}" '.partitions | length')
    [ "${count}" -eq 2 ]
}

@test "discovery: btrfs.img partition 2 is mountable btrfs" {
    [[ -f "${FIXTURES}/btrfs.img" ]] || skip "fixture btrfs.img not generated"
    local json fstype mountable
    json=$(info_json btrfs.img)
    fstype=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | .fstype')
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | .mountable')
    [ "${fstype}" = "btrfs" ]
    [ "${mountable}" = "true" ]
}

@test "discovery: btrfs.img info shows btrfs as mountable" {
    [[ -f "${FIXTURES}/btrfs.img" ]] || skip "fixture btrfs.img not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/btrfs.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"btrfs"* ]]
    [[ "${output}" == *"mountable"* ]]
}

# ---------------------------------------------------------------------------
# raw.img
# ---------------------------------------------------------------------------

@test "discovery: raw.img has 2 partitions" {
    [[ -f "${FIXTURES}/raw.img" ]] || skip "fixture raw.img not generated"
    local json count
    json=$(info_json raw.img)
    count=$(jq_from_json "${json}" '.partitions | length')
    [ "${count}" -eq 2 ]
}

@test "discovery: raw.img partition 2 has fstype raw" {
    [[ -f "${FIXTURES}/raw.img" ]] || skip "fixture raw.img not generated"
    local json fstype
    json=$(info_json raw.img)
    fstype=$(jq_from_json "${json}" \
        '.partitions[] | select(.number == 2) | .fstype')
    [ "${fstype}" = "raw" ]
}

@test "discovery: raw.img partition 2 is not mountable" {
    [[ -f "${FIXTURES}/raw.img" ]] || skip "fixture raw.img not generated"
    local json mountable
    json=$(info_json raw.img)
    mountable=$(jq_from_json "${json}" \
        '.partitions[] | select(.number == 2) | .mountable')
    [ "${mountable}" = "false" ]
}

@test "discovery: raw.img partition 2 raw_hint contains key=value strings" {
    [[ -f "${FIXTURES}/raw.img" ]] || skip "fixture raw.img not generated"
    local json hint
    json=$(info_json raw.img)
    hint=$(jq_from_json "${json}" \
        '.partitions[] | select(.number == 2) | .raw_hint')
    [[ "${hint}" == *"BOOT_A_LEFT"* ]]
}

@test "discovery: raw.img info shows [raw: in Notes column" {
    [[ -f "${FIXTURES}/raw.img" ]] || skip "fixture raw.img not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/raw.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"[raw:"* ]]
}

# ---------------------------------------------------------------------------
# erofs.img
# ---------------------------------------------------------------------------

@test "discovery: erofs.img has 2 partitions" {
    [[ -f "${FIXTURES}/erofs.img" ]] || skip "fixture erofs.img not generated"
    local json count
    json=$(info_json erofs.img)
    count=$(jq_from_json "${json}" '.partitions | length')
    [ "${count}" -eq 2 ]
}

@test "discovery: erofs.img partition 2 is mountable erofs" {
    [[ -f "${FIXTURES}/erofs.img" ]] || skip "fixture erofs.img not generated"
    local json fstype mountable
    json=$(info_json erofs.img)
    fstype=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | .fstype')
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 2) | .mountable')
    [ "${fstype}" = "erofs" ]
    [ "${mountable}" = "true" ]
}

@test "discovery: erofs.img info shows erofs as mountable" {
    [[ -f "${FIXTURES}/erofs.img" ]] || skip "fixture erofs.img not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/erofs.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"erofs"* ]]
    [[ "${output}" == *"mountable"* ]]
}

# ---------------------------------------------------------------------------
# lvm.img
# ---------------------------------------------------------------------------

@test "discovery: lvm.img partition 1 is mountable via lvm" {
    [[ -f "${FIXTURES}/lvm.img" ]] || skip "fixture not generated"
    local json fstype mountable layer
    json=$(info_json lvm.img)
    fstype=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .fstype')
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .mountable')
    layer=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .storage_layer')
    [ "${fstype}" = "LVM2_member" ]
    [ "${mountable}" = "true" ]
    [ "${layer}" = "lvm" ]
}

@test "discovery: lvm.img info shows [mountable via lvm]" {
    [[ -f "${FIXTURES}/lvm.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/lvm.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"mountable via lvm"* ]]
}

# ---------------------------------------------------------------------------
# luks.img
# ---------------------------------------------------------------------------

@test "discovery: luks.img partition 1 is mountable via luks" {
    [[ -f "${FIXTURES}/luks.img" ]] || skip "fixture not generated"
    local json fstype mountable layer
    json=$(info_json luks.img)
    fstype=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .fstype')
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .mountable')
    layer=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .storage_layer')
    [ "${fstype}" = "crypto_LUKS" ]
    [ "${mountable}" = "true" ]
    [ "${layer}" = "luks" ]
}

@test "discovery: luks.img info shows [mountable via luks]" {
    [[ -f "${FIXTURES}/luks.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/luks.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"mountable via luks"* ]]
}

# ---------------------------------------------------------------------------
# luks-lvm.img
# ---------------------------------------------------------------------------

@test "discovery: luks-lvm.img partition 1 is mountable via luks" {
    [[ -f "${FIXTURES}/luks-lvm.img" ]] || skip "fixture not generated"
    local json mountable layer
    json=$(info_json luks-lvm.img)
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .mountable')
    layer=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .storage_layer')
    [ "${mountable}" = "true" ]
    [ "${layer}" = "luks" ]
}

# ---------------------------------------------------------------------------
# Blank image (no partition table)
# ---------------------------------------------------------------------------

@test "discovery: blank image exits non-zero with a clear error message" {
    local blank
    blank=$(mktemp /tmp/usb-blank-XXXXXX)
    truncate -s 32M "${blank}"
    run docker run --rm --privileged \
        -v "${blank}:/disk.img:ro" \
        "${IMAGE}" info
    rm -f "${blank}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"no recognised partition table"* ]]
}
