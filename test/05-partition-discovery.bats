#!/usr/bin/env bats
# 05-partition-discovery.bats — partition discovery, mountability, and
# auto-selection logic.
#
# jq is run inside the usb-explore container (bats host may not have it).
# All tests skip gracefully when fixture images are absent.

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"
FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"

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

@test "discovery: single-ext4.img has 1 mountable partition" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json count
    json=$(info_json single-ext4.img)
    count=$(jq_from_json "${json}" '[.partitions[] | select(.mountable == true)] | length')
    [ "${count}" -eq 1 ]
}

@test "discovery: single-ext4.img partition 1 (EFI) is not mountable" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json mountable
    json=$(info_json single-ext4.img)
    mountable=$(jq_from_json "${json}" '.partitions[] | select(.number == 1) | .mountable')
    [ "${mountable}" = "false" ]
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

@test "discovery: dual-ext4.img has 2 mountable partitions" {
    [[ -f "${FIXTURES}/dual-ext4.img" ]] || skip "fixture not generated"
    local json count
    json=$(info_json dual-ext4.img)
    count=$(jq_from_json "${json}" '[.partitions[] | select(.mountable == true)] | length')
    [ "${count}" -eq 2 ]
}

# ---------------------------------------------------------------------------
# xfs.img
# ---------------------------------------------------------------------------

@test "discovery: xfs.img mountable partition is xfs" {
    [[ -f "${FIXTURES}/xfs.img" ]] || skip "fixture not generated"
    local json fstype
    json=$(info_json xfs.img)
    fstype=$(jq_from_json "${json}" '[.partitions[] | select(.mountable == true)][0].fstype')
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

@test "discovery: info (human) shows EFI as not mountable" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"EFI"* ]]
    # EFI is excluded from auto-selection; message may say "excluded" or
    # guide the user to -p for explicit mounting.
    [[ "${output}" == *"EFI"* && ("${output}" == *"excluded"* || "${output}" == *"-p"*) ]]
}

@test "discovery: info (human) summary line mentions mountable count" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"1 mountable"* ]]
}
