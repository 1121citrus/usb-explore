#!/usr/bin/env bats
# 03-invocation.bats — container entrypoint and subcommand routing.
# jq is run inside the usb-explore container (not on the bats host).

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"

# ---------------------------------------------------------------------------
# Unknown subcommand
# ---------------------------------------------------------------------------

@test "container: unknown subcommand exits 2" {
    # Test dispatch.sh directly with a dummy /disk.img to get past the
    # entrypoint check, then verify dispatch rejects the bad subcommand.
    run docker run --rm --privileged \
        --entrypoint=bash "${IMAGE}" \
        -c 'truncate -s 10M /disk.img
            /usr/local/lib/usb-explore/dispatch.sh notasubcommand 2>&1; echo "exit:$?"' \
        2>&1
    [[ "${output}" == *"exit:2"* || "${output}" == *"unknown subcommand"* ]]
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
    [[ -f "${BATS_TEST_DIRNAME}/fixtures/single-ext4.img" ]] \
        || skip "fixture single-ext4.img not generated"

    run docker run --rm --privileged \
        -v "${BATS_TEST_DIRNAME}/fixtures/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info --json

    [ "${status}" -eq 0 ]
    # Validate JSON and partition count inside the container (jq is in the image)
    local part_count
    part_count=$(docker run --rm --privileged \
        -v "${BATS_TEST_DIRNAME}/fixtures/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info --json | \
        docker run --rm -i --entrypoint=jq "${IMAGE}" '.partitions | length')
    [[ "${part_count}" -gt 0 ]]
}

@test "container: info (human table) on single-ext4.img shows EFI and ext4" {
    [[ -f "${BATS_TEST_DIRNAME}/fixtures/single-ext4.img" ]] \
        || skip "fixture single-ext4.img not generated"

    run docker run --rm --privileged \
        -v "${BATS_TEST_DIRNAME}/fixtures/single-ext4.img:/disk.img:ro" \
        "${IMAGE}" info

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"vfat"* ]]
    [[ "${output}" == *"ext4"* ]]
}
