#!/usr/bin/env bats
# 04-env-metadata.bats — APP_* env vars and OCI image labels.
# Uses --entrypoint=bash to bypass the /disk.img check in entrypoint.sh.

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"

# ---------------------------------------------------------------------------
# Environment variables
# ---------------------------------------------------------------------------

@test "image: APP_VERSION env var is set" {
    run docker run --rm --entrypoint=bash "${IMAGE}" -c 'echo "${APP_VERSION}"'
    [ "${status}" -eq 0 ]
    [[ -n "${output}" ]]
}

@test "image: APP_COMMIT env var is set" {
    run docker run --rm --entrypoint=bash "${IMAGE}" -c 'echo "${APP_COMMIT}"'
    [ "${status}" -eq 0 ]
    [[ -n "${output}" ]]
}

@test "image: APP_BUILD_DATE env var is set" {
    run docker run --rm --entrypoint=bash "${IMAGE}" -c 'echo "${APP_BUILD_DATE}"'
    [ "${status}" -eq 0 ]
    [[ -n "${output}" ]]
}

@test "image: APP_BASE_IMAGE env var is set" {
    run docker run --rm --entrypoint=bash "${IMAGE}" -c 'echo "${APP_BASE_IMAGE}"'
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"ubuntu"* ]]
}

# ---------------------------------------------------------------------------
# OCI labels
# ---------------------------------------------------------------------------

_label() {
    docker inspect --format \
        "{{index .Config.Labels \"${1}\"}}" "${IMAGE}"
}

@test "image: OCI label title is usb-explore" {
    local val; val=$(_label "org.opencontainers.image.title")
    [[ "${val}" == "usb-explore" ]]
}

@test "image: OCI label version is set" {
    local val; val=$(_label "org.opencontainers.image.version")
    [[ -n "${val}" ]]
}

@test "image: OCI label revision is set" {
    local val; val=$(_label "org.opencontainers.image.revision")
    [[ -n "${val}" ]]
}

@test "image: OCI label created is set" {
    local val; val=$(_label "org.opencontainers.image.created")
    [[ -n "${val}" ]]
}

@test "image: OCI label source is set" {
    local val; val=$(_label "org.opencontainers.image.source")
    [[ "${val}" == *"usb-explore"* ]]
}

@test "image: OCI label licenses is AGPL-3.0-or-later" {
    local val; val=$(_label "org.opencontainers.image.licenses")
    [[ "${val}" == "AGPL-3.0-or-later" ]]
}
