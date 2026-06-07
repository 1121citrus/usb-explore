#!/usr/bin/env bats
# 03-invocation.bats — container entrypoint and subcommand routing.

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"

# ---------------------------------------------------------------------------
# Unknown subcommand
# ---------------------------------------------------------------------------

@test "container: unknown subcommand exits 2" {
    # We need a disk.img placeholder; use /dev/null as a zero-size image.
    # losetup will fail before dispatch gets to the unknown-command check,
    # so we pass a tiny valid image via stdin instead, using a named pipe.
    # Simplest approach: test the exit code from dispatch.sh directly.
    run docker run --rm "${IMAGE}" \
        bash -c \
        'exec /usr/local/lib/usb-explore/dispatch.sh /dev/null notasubcommand'
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"unknown subcommand"* ]]
}

# ---------------------------------------------------------------------------
# ENTRYPOINT
# ---------------------------------------------------------------------------

@test "container: ENTRYPOINT is entrypoint.sh" {
    local ep
    ep=$(docker inspect --format '{{json .Config.Entrypoint}}' "${IMAGE}")
    [[ "${ep}" == *"entrypoint.sh"* ]]
}

# ---------------------------------------------------------------------------
# info --json (needs --privileged and a valid image)
# ---------------------------------------------------------------------------

@test "container: info --json on single-ext4.img returns valid JSON" {
    [[ -f "${BATS_TEST_DIRNAME}/../fixtures/single-ext4.img" ]] \
        || skip "fixture single-ext4.img not generated"

    run docker run --rm --privileged \
        -v "${BATS_TEST_DIRNAME}/../fixtures/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info --json

    [ "${status}" -eq 0 ]
    # Must be valid JSON
    echo "${output}" | jq . >/dev/null
    # Must have a partitions array
    [[ "$(echo "${output}" | jq '.partitions | length')" -gt 0 ]]
}

@test "container: info (human table) on single-ext4.img shows EFI and ext4" {
    [[ -f "${BATS_TEST_DIRNAME}/../fixtures/single-ext4.img" ]] \
        || skip "fixture single-ext4.img not generated"

    run docker run --rm --privileged \
        -v "${BATS_TEST_DIRNAME}/../fixtures/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"vfat"* ]]
    [[ "${output}" == *"ext4"* ]]
}
