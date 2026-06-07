#!/usr/bin/env bats
# 01-build.bats — validate build script argument parsing and flag behaviour.
# These tests source the build script with DRY_RUN=true so that no Docker
# commands are actually executed.

# shellcheck disable=SC2030,SC2031   # BATS subshell variable isolation

BUILD="${BATS_TEST_DIRNAME}/../build"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run the build script with DRY_RUN=true and capture output.
run_build() {
    run bash "${BUILD}" --dry-run "$@"
}

# ---------------------------------------------------------------------------
# Basic invocation
# ---------------------------------------------------------------------------

@test "build: --help exits 0 and contains SYNOPSIS" {
    run bash "${BUILD}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"SYNOPSIS"* ]] || [[ "${output}" == *"build ["* ]]
}

@test "build: unknown flag exits non-zero" {
    run bash "${BUILD}" --not-a-real-flag
    [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# --version
# ---------------------------------------------------------------------------

@test "build: --version sets VERSION in dry-run output" {
    run_build --version 1.2.3 --no-lint --no-test --no-scan
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"1.2.3"* ]]
}

@test "build: default version contains dev- prefix" {
    run_build --no-lint --no-test --no-scan
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"dev-"* ]]
}

# ---------------------------------------------------------------------------
# --no-lint
# ---------------------------------------------------------------------------

@test "build: --no-lint suppresses lint stage commands" {
    run_build --no-lint --no-test --no-scan
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"hadolint"* ]]
    [[ "${output}" != *"shellcheck"* ]]
    [[ "${output}" != *"markdownlint"* ]]
}

@test "build: lint runs by default (dry-run shows hadolint)" {
    run_build --no-test --no-scan
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"hadolint"* ]]
}

# ---------------------------------------------------------------------------
# --no-test
# ---------------------------------------------------------------------------

@test "build: --no-test suppresses test stage" {
    run_build --no-lint --no-test --no-scan
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"bats"* ]]
}

@test "build: test stage runs by default (dry-run shows run-all)" {
    run_build --no-lint --no-scan
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"run-all"* ]]
}

# ---------------------------------------------------------------------------
# --no-scan
# ---------------------------------------------------------------------------

@test "build: --no-scan suppresses trivy and grype scan stages" {
    run_build --no-lint --no-test --no-scan
    [ "${status}" -eq 0 ]
    # The header always shows 'Trivy DB:' config; check for absence of the
    # actual scan command (the image name in the aquasec/trivy docker call)
    [[ "${output}" != *"aquasec/trivy"* ]]
    [[ "${output}" != *"anchore/grype"* ]]
}

@test "build: scan runs by default (dry-run shows trivy)" {
    run_build --no-lint --no-test
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"trivy"* ]]
}

# ---------------------------------------------------------------------------
# --push
# ---------------------------------------------------------------------------

@test "build: --push appears in dry-run output" {
    run_build --no-lint --no-test --no-scan --push --version 0.1.0
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--push"* ]]
}

@test "build: --push triggers multi-platform rebuild" {
    run_build --no-lint --no-test --no-scan --push --version 0.1.0
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"linux/amd64"* ]]
    [[ "${output}" == *"linux/arm64"* ]]
}

# ---------------------------------------------------------------------------
# --registry
# ---------------------------------------------------------------------------

@test "build: --registry changes the image prefix" {
    run_build --no-lint --no-test --no-scan --registry myorg
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"myorg/usb-explore"* ]]
}

@test "build: default registry is 1121citrus" {
    run_build --no-lint --no-test --no-scan
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"1121citrus/usb-explore"* ]]
}

# ---------------------------------------------------------------------------
# --advise / --no-advise
# ---------------------------------------------------------------------------

@test "build: --advise dive enables dive in dry-run output" {
    run_build --no-lint --no-test --no-scan --advise dive
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"dive"* ]]
}

@test "build: --no-advise suppresses advisory scans" {
    run_build --no-lint --no-test --no-scan --no-advise
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"wagoodman/dive"* ]]
}

# ---------------------------------------------------------------------------
# --cache
# ---------------------------------------------------------------------------

@test "build: --cache reset=all is accepted" {
    run_build --no-lint --no-test --no-scan --cache "reset=all"
    [ "${status}" -eq 0 ]
}

@test "build: --cache skip-update=grype is accepted" {
    run_build --no-lint --no-test --no-scan --cache "skip-update=grype"
    [ "${status}" -eq 0 ]
}

@test "build: invalid --cache key exits non-zero" {
    run bash "${BUILD}" --no-lint --no-test --no-scan \
        --cache "badkey=trivy"
    [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Image name
# ---------------------------------------------------------------------------

@test "build: image name is usb-explore" {
    run_build --no-lint --no-test --no-scan
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"usb-explore"* ]]
}
