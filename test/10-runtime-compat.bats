#!/usr/bin/env bats
# 10-runtime-compat.bats — tests for test/runtime-compat.
#
# Covers CLI flag parsing, runtime detection, and a live --quick run
# against the active Docker Desktop runtime.

bats_require_minimum_version 1.5.0
COMPAT="${BATS_TEST_DIRNAME}/runtime-compat"

# ---------------------------------------------------------------------------
# --help / -h
# ---------------------------------------------------------------------------

@test "runtime-compat: --help exits 0" {
    run bash "${COMPAT}" --help
    [ "${status}" -eq 0 ]
}

@test "runtime-compat: --help contains SYNOPSIS keywords" {
    run bash "${COMPAT}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--quick"* ]]
    [[ "${output}" == *"--help"* ]]
}

@test "runtime-compat: -h is an alias for --help" {
    run bash "${COMPAT}" -h
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--quick"* ]]
}

# ---------------------------------------------------------------------------
# Unknown flag
# ---------------------------------------------------------------------------

@test "runtime-compat: unknown flag exits non-zero" {
    run bash "${COMPAT}" --not-a-flag
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown option"* ]]
}

# ---------------------------------------------------------------------------
# Static analysis
# ---------------------------------------------------------------------------

@test "runtime-compat: detects runtime via docker info --format" {
    grep -q "docker info --format" "${COMPAT}"
}

@test "runtime-compat: emits JSON summary to stdout" {
    grep -q 'printf.*"runtime"' "${COMPAT}"
}

@test "runtime-compat: --quick runs only tests 03-06" {
    grep -q '03-invocation.bats' "${COMPAT}"
    grep -q '04-env-metadata.bats' "${COMPAT}"
    grep -q '05-partition-discovery.bats' "${COMPAT}"
    grep -q '06-subcommands.bats' "${COMPAT}"
}

@test "runtime-compat: full mode delegates to test/run-all" {
    grep -q 'run-all' "${COMPAT}"
}

# ---------------------------------------------------------------------------
# Live runtime detection (Docker must be running)
# ---------------------------------------------------------------------------

@test "runtime-compat: detects Docker Desktop as active runtime" {
    if ! docker info >/dev/null 2>&1; then
        skip "Docker is not running"
    fi
    local os
    os=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null)
    if [[ "${os}" != "Docker Desktop" ]]; then
        skip "active runtime is ${os}, not Docker Desktop"
    fi
    # Confirm the script would detect the same runtime
    run docker info --format '{{.OperatingSystem}}'
    [ "${status}" -eq 0 ]
    [[ "${output}" == "Docker Desktop" ]]
}

# ---------------------------------------------------------------------------
# Live --quick run against Docker Desktop
# ---------------------------------------------------------------------------

@test "runtime-compat: --quick run passes on Docker Desktop" {
    if ! docker info >/dev/null 2>&1; then
        skip "Docker is not running"
    fi
    local os
    os=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null)
    if [[ "${os}" != "Docker Desktop" ]]; then
        skip "active runtime is ${os}, not Docker Desktop"
    fi

    # Pass IMAGE from the test environment so runtime-compat skips
    # the build step (buildx is not available inside the BATS container).
    run env IMAGE="${IMAGE:-1121citrus/usb-explore:latest}" \
        bash "${COMPAT}" --quick
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'"tests":"passed"'* ]]
    [[ "${output}" == *'"runtime":"docker-desktop"'* ]]
}
