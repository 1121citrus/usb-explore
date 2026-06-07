#!/usr/bin/env bats
# 05-partition-discovery.bats — partition discovery, mountability, and
# auto-selection logic.  All tests that use fixtures skip gracefully when
# the fixture images are absent.

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"
FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"

# Run info --json on a fixture and return the JSON
info_json() {
    local img="${1}"
    docker run --rm --privileged \
        -v "${FIXTURES}/${img}:/disk.img:ro" \
        "${IMAGE}" info --json
}

# ---------------------------------------------------------------------------
# single-ext4.img
# ---------------------------------------------------------------------------

@test "discovery: single-ext4.img has 2 partitions" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json count
    json=$(info_json single-ext4.img)
    count=$(echo "${json}" | jq '.partitions | length')
    [ "${count}" -eq 2 ]
}

@test "discovery: single-ext4.img has 1 mountable partition" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json count
    json=$(info_json single-ext4.img)
    count=$(echo "${json}" | jq '[.partitions[] | select(.mountable == true)] | length')
    [ "${count}" -eq 1 ]
}

@test "discovery: single-ext4.img partition 1 (EFI) is not mountable" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json mountable
    json=$(info_json single-ext4.img)
    mountable=$(echo "${json}" \
        | jq -r '.partitions[] | select(.number == 1) | .mountable')
    [ "${mountable}" = "false" ]
}

@test "discovery: single-ext4.img partition 2 is mountable ext4" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json fstype mountable
    json=$(info_json single-ext4.img)
    fstype=$(echo "${json}" \
        | jq -r '.partitions[] | select(.number == 2) | .fstype')
    mountable=$(echo "${json}" \
        | jq -r '.partitions[] | select(.number == 2) | .mountable')
    [ "${fstype}" = "ext4" ]
    [ "${mountable}" = "true" ]
}

@test "discovery: info --json schema has required top-level keys" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json
    json=$(info_json single-ext4.img)
    echo "${json}" | jq -e '.image'          >/dev/null
    echo "${json}" | jq -e '.size_bytes'     >/dev/null
    echo "${json}" | jq -e '.size_human'     >/dev/null
    echo "${json}" | jq -e '.label'          >/dev/null
    echo "${json}" | jq -e '.partitions'     >/dev/null
}

@test "discovery: each partition record has required keys" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local json
    json=$(info_json single-ext4.img)
    # Check the second partition (the ext4 one)
    local part
    part=$(echo "${json}" | jq '.partitions[] | select(.number == 2)')
    echo "${part}" | jq -e '.node'             >/dev/null
    echo "${part}" | jq -e '.size_bytes'       >/dev/null
    echo "${part}" | jq -e '.size_human'       >/dev/null
    echo "${part}" | jq -e '.fstype'           >/dev/null
    echo "${part}" | jq -e '.mountable'        >/dev/null
}

# ---------------------------------------------------------------------------
# dual-ext4.img — auto-selection must refuse and print the table
# ---------------------------------------------------------------------------

@test "discovery: dual-ext4.img has 2 mountable partitions" {
    [[ -f "${FIXTURES}/dual-ext4.img" ]] || skip "fixture not generated"
    local json count
    json=$(info_json dual-ext4.img)
    count=$(echo "${json}" | jq '[.partitions[] | select(.mountable == true)] | length')
    [ "${count}" -eq 2 ]
}

# ---------------------------------------------------------------------------
# xfs.img
# ---------------------------------------------------------------------------

@test "discovery: xfs.img mountable partition is xfs" {
    [[ -f "${FIXTURES}/xfs.img" ]] || skip "fixture not generated"
    local json fstype
    json=$(info_json xfs.img)
    fstype=$(echo "${json}" \
        | jq -r '[.partitions[] | select(.mountable == true)][0].fstype')
    [ "${fstype}" = "xfs" ]
}

# ---------------------------------------------------------------------------
# mbr.img
# ---------------------------------------------------------------------------

@test "discovery: mbr.img label is dos (MBR)" {
    [[ -f "${FIXTURES}/mbr.img" ]] || skip "fixture not generated"
    local json label
    json=$(info_json mbr.img)
    label=$(echo "${json}" | jq -r '.label')
    [ "${label}" = "dos" ]
}

@test "discovery: mbr.img has 1 mountable ext4 partition" {
    [[ -f "${FIXTURES}/mbr.img" ]] || skip "fixture not generated"
    local json count fstype
    json=$(info_json mbr.img)
    count=$(echo "${json}" | jq '[.partitions[] | select(.mountable == true)] | length')
    fstype=$(echo "${json}" | jq -r '[.partitions[] | select(.mountable == true)][0].fstype')
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
    [[ "${output}" == *"not mountable"* || "${output}" == *"excluded"* ]]
}

@test "discovery: info (human) summary line mentions mountable count" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"1 mountable"* ]]
}
