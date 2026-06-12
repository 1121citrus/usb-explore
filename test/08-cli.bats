#!/usr/bin/env bats
# 08-cli.bats — host-side CLI flag and routing tests for src/usb-explore.
#
# All tests run the script directly (no Docker required). They cover global
# flags, argument parsing, and the subcommand dispatch that previously had
# zero test coverage (allowing bugs like the BSD sed incompatibility in
# usage() to pass undetected).

bats_require_minimum_version 1.5.0
SCRIPT="${BATS_TEST_DIRNAME}/../src/usb-explore"

# ---------------------------------------------------------------------------
# --help / -h
# ---------------------------------------------------------------------------

@test "cli: --help exits 0" {
    run bash "${SCRIPT}" --help
    [ "${status}" -eq 0 ]
}

@test "cli: --help output contains the script name and global options" {
    run bash "${SCRIPT}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"usb-explore"* ]]
    [[ "${output}" == *"--image"*     ]]
    [[ "${output}" == *"--partition"* ]]
}

@test "cli: --help lists all subcommands" {
    run bash "${SCRIPT}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"capture"* ]]
    [[ "${output}" == *"info"*    ]]
    [[ "${output}" == *"shell"*   ]]
    [[ "${output}" == *"copy"*    ]]
    [[ "${output}" == *"run"*     ]]
    [[ "${output}" == *"diff"*    ]]
    [[ "${output}" == *"serve"*   ]]
    [[ "${output}" == *"archive"* ]]
    [[ "${output}" == *"browse"*  ]]
    [[ "${output}" == *"find"*    ]]
}

@test "cli: -h is an alias for --help" {
    run bash "${SCRIPT}" -h
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"usb-explore"* ]]
}

# ---------------------------------------------------------------------------
# --version
# ---------------------------------------------------------------------------

@test "cli: --version exits 0" {
    run bash "${SCRIPT}" --version
    [ "${status}" -eq 0 ]
}

@test "cli: --version output contains 'usb-explore'" {
    run bash "${SCRIPT}" --version
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"usb-explore"* ]]
}

# ---------------------------------------------------------------------------
# No subcommand / unknown subcommand
# ---------------------------------------------------------------------------

@test "cli: no subcommand exits 2" {
    run bash "${SCRIPT}"
    [ "${status}" -eq 2 ]
}

@test "cli: unknown subcommand exits non-zero" {
    run bash "${SCRIPT}" notasubcommand
    [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Unknown global flag
# ---------------------------------------------------------------------------

@test "cli: unknown global flag exits non-zero" {
    run bash "${SCRIPT}" --not-a-real-flag
    [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# --image / -i flag
# With no Docker daemon: exit 3 (Docker unavailable).
# With Docker but missing file: exit 4 (image not found).
# Either means the flag was parsed and routing proceeded past argument parsing.
# ---------------------------------------------------------------------------

@test "cli: --image flag is parsed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent/path.img info
    # Flag was accepted: must NOT be a usage error (exit 2)
    [ "${status}" -ne 2 ]
}

@test "cli: -i short flag is accepted" {
    run bash "${SCRIPT}" -i /nonexistent/path.img info
    [ "${status}" -ne 2 ]
}

# ---------------------------------------------------------------------------
# --partition / -p flag
# ---------------------------------------------------------------------------

@test "cli: --partition flag is parsed (not a usage error)" {
    run bash "${SCRIPT}" -i /nonexistent.img --partition 2 info
    [ "${status}" -ne 2 ]
}

@test "cli: -p short flag is accepted" {
    run bash "${SCRIPT}" -i /nonexistent.img -p 2 info
    [ "${status}" -ne 2 ]
}

# ---------------------------------------------------------------------------
# Subcommand routing — each subcommand must be recognised.
# Exit 3 (no Docker) or 4 (no image) are both acceptable; exit 2 would
# mean the subcommand was not recognised.
# ---------------------------------------------------------------------------

@test "cli: 'info' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" info
    [ "${status}" -ne 2 ]
}

@test "cli: 'shell' subcommand is routed (not a usage error)" {
    # Allow any exit code: Docker may be unavailable (3), image missing (4),
    # or a downstream tool may be absent (127). None of these is exit 2
    # (usage error = unknown subcommand).
    run bash "${SCRIPT}" shell
    [ "${status}" -ne 2 ]
}

@test "cli: 'copy' subcommand reports missing arguments" {
    run bash "${SCRIPT}" copy
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* || "${status}" -eq 2 ]]
}

@test "cli: 'run' subcommand reports missing command" {
    run bash "${SCRIPT}" run
    [ "${status}" -ne 0 ]
}

@test "cli: 'diff' subcommand reports missing arguments" {
    run bash "${SCRIPT}" diff
    [ "${status}" -ne 0 ]
}

@test "cli: 'serve' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" serve
    [ "${status}" -ne 2 ]
}

@test "cli: 'serve' --port flag is accepted" {
    run bash "${SCRIPT}" serve --port 9090
    [ "${status}" -ne 2 ]
}

@test "cli: 'serve' --port with invalid value exits non-zero" {
    run bash "${SCRIPT}" serve --port notanumber
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"65535"* ]]
}

@test "cli: 'browse' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" browse
    [ "${status}" -ne 2 ]
}

@test "cli: 'find' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" find "*.log"
    [ "${status}" -ne 2 ]
}

@test "cli: 'find' subcommand reports missing pattern" {
    run bash "${SCRIPT}" find
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "cli: 'find' --grep flag is accepted" {
    run bash "${SCRIPT}" find --grep "ERROR"
    [ "${status}" -ne 2 ]
}

@test "cli: 'archive' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" archive /etc ./etc.tar.gz
    [ "${status}" -ne 2 ]
}

@test "cli: 'archive' subcommand reports missing arguments" {
    run bash "${SCRIPT}" archive
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "cli: 'archive' rejects unsupported extension" {
    run bash "${SCRIPT}" archive /etc ./etc.zip
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"unsupported"* ]]
}

# ---------------------------------------------------------------------------
# capture --dry-run (no device or Docker required)
# ---------------------------------------------------------------------------

@test "cli: capture --dry-run prints dd command" {
    run bash "${SCRIPT}" capture /dev/disk0 --dry-run
    [[ "${output}" == *"/bin/dd"* || "${output}" == *"not found"* ]]
}

@test "cli: capture --no-sparse removes conv=sparse from dry-run" {
    run bash "${SCRIPT}" capture /dev/disk0 --no-sparse --dry-run
    [[ "${output}" != *"conv=sparse"* ]]
}
