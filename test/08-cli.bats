#!/usr/bin/env bats
# 08-cli.bats — host-side CLI flag and routing tests for src/usb-explore.
#
# All tests run the script directly (no Docker required). They cover global
# flags, argument parsing, and the subcommand dispatch that previously had
# zero test coverage (allowing bugs like the BSD sed incompatibility in
# usage() to pass undetected).

bats_require_minimum_version 1.5.0
SCRIPT="${BATS_TEST_DIRNAME}/../src/usb-explore"
DISPATCH="${BATS_TEST_DIRNAME}/../src/container/dispatch.sh"

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
    [[ "${output}" == *"hash"*    ]]
    [[ "${output}" == *"clean"*   ]]
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
# All tests pass --image /nonexistent.img so check_image_file exits 4 (image
# not found) without invoking any container or host tool. Exit 3 (no Docker)
# is also acceptable. Neither is exit 2 (usage error = unknown subcommand).
# ---------------------------------------------------------------------------

@test "cli: 'archive' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent.img archive /etc ./etc.tar.gz
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

@test "cli: 'browse' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent.img browse
    [ "${status}" -ne 2 ]
}

@test "cli: 'copy' subcommand reports missing arguments" {
    run bash "${SCRIPT}" copy
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* || "${status}" -eq 2 ]]
}

@test "cli: 'diff' subcommand reports missing arguments" {
    run bash "${SCRIPT}" diff
    [ "${status}" -ne 0 ]
}

@test "cli: 'find' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent.img find "*.log"
    [ "${status}" -ne 2 ]
}

@test "cli: 'find' subcommand reports missing pattern" {
    run bash "${SCRIPT}" find
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "cli: 'find' --grep flag is accepted" {
    run bash "${SCRIPT}" --image /nonexistent.img find --grep "ERROR"
    [ "${status}" -ne 2 ]
}

@test "cli: 'info' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent.img info
    [ "${status}" -ne 2 ]
}

@test "cli: 'run' subcommand reports missing command" {
    run bash "${SCRIPT}" run
    [ "${status}" -ne 0 ]
}

@test "cli: 'serve' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent.img serve
    [ "${status}" -ne 2 ]
}

@test "cli: 'serve' --port flag is accepted" {
    run bash "${SCRIPT}" --image /nonexistent.img serve --port 9090
    [ "${status}" -ne 2 ]
}

@test "cli: 'serve' --port with invalid value exits non-zero" {
    run bash "${SCRIPT}" serve --port notanumber
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"65535"* ]]
}

@test "cli: 'shell' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent.img shell
    [ "${status}" -ne 2 ]
}

@test "cli: 'shell' accepts -p after subcommand name" {
    run bash "${SCRIPT}" --image /nonexistent.img shell -p 2
    [ "${status}" -ne 2 ]
}

@test "cli: 'serve' accepts -p after subcommand name" {
    run bash "${SCRIPT}" --image /nonexistent.img serve -p 2
    [ "${status}" -ne 2 ]
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

# ---------------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------------

@test "cli: 'clean' --yes removes the image file" {
    local tmp
    tmp=$(mktemp /tmp/usb-clean-test-XXXXXX)
    run bash "${SCRIPT}" --image "${tmp}" clean --yes
    [ "${status}" -eq 0 ]
    [[ ! -f "${tmp}" ]]
}

@test "cli: 'clean' -y short flag removes the image file" {
    local tmp
    tmp=$(mktemp /tmp/usb-clean-test-XXXXXX)
    run bash "${SCRIPT}" --image "${tmp}" clean -y
    [ "${status}" -eq 0 ]
    [[ ! -f "${tmp}" ]]
}

@test "cli: 'clean' exits 4 when image file is missing" {
    run bash "${SCRIPT}" --image /nonexistent/no.img clean --yes
    [ "${status}" -eq 4 ]
}

@test "cli: 'clean' aborts and exits 0 when user inputs n" {
    local tmp
    tmp=$(mktemp /tmp/usb-clean-test-XXXXXX)
    run bash -c "echo n | bash '${SCRIPT}' --image '${tmp}' clean"
    [ "${status}" -eq 0 ]
    [[ -f "${tmp}" ]]
    rm -f "${tmp}"
}

@test "cli: 'clean' aborts and exits 0 on empty input (no TTY)" {
    local tmp
    tmp=$(mktemp /tmp/usb-clean-test-XXXXXX)
    run bash -c "echo '' | bash '${SCRIPT}' --image '${tmp}' clean"
    [ "${status}" -eq 0 ]
    [[ -f "${tmp}" ]]
    rm -f "${tmp}"
}

# ---------------------------------------------------------------------------
# hash
# ---------------------------------------------------------------------------

@test "cli: 'hash' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent.img hash /etc/hostname
    [ "${status}" -ne 2 ]
}

@test "cli: 'hash' subcommand reports missing path argument" {
    run bash "${SCRIPT}" hash
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "cli: 'hash' rejects a non-absolute path" {
    run bash "${SCRIPT}" hash etc/hostname
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"absolute"* ]]
}

# ---------------------------------------------------------------------------
# Exit-code normalisation — interactive subcommands map 130 (SIGINT) to 0
#
# A docker stub exits 130 from 'run' (simulating Ctrl-C from inside the
# interactive session). Passing -p 1 globally skips resolve_partition's own
# docker call so only the final run_container invocation fires.
# ---------------------------------------------------------------------------

# _make_docker_stub — write a minimal docker stub into a temp dir and print
# the dir path.  The stub exits $1 for 'docker run'; 0 for info and image.
_make_docker_stub() {
    local run_exit="${1:-130}"
    local dir
    dir=$(mktemp -d /tmp/usb-stub-XXXXXX)
    cat > "${dir}/docker" << EOF
#!/bin/sh
case "\$1" in
    info)  exit 0 ;;
    image) exit 0 ;;
    run)   exit ${run_exit} ;;
    *)     exit 1 ;;
esac
EOF
    chmod +x "${dir}/docker"
    echo "${dir}"
}

@test "cli: 'shell' maps docker exit 130 (Ctrl-C) to exit 0" {
    local tmp stub
    tmp=$(mktemp /tmp/usb-sigint-XXXXXX)
    stub=$(_make_docker_stub 130)
    run env PATH="${stub}:${PATH}" bash "${SCRIPT}" --image "${tmp}" -p 1 shell
    rm -f "${tmp}"; rm -rf "${stub}"
    [ "${status}" -eq 0 ]
}

@test "cli: 'shell' propagates non-130 docker exit codes" {
    local tmp stub
    tmp=$(mktemp /tmp/usb-sigint-XXXXXX)
    stub=$(_make_docker_stub 1)
    run env PATH="${stub}:${PATH}" bash "${SCRIPT}" --image "${tmp}" -p 1 shell
    rm -f "${tmp}"; rm -rf "${stub}"
    [ "${status}" -eq 1 ]
}

@test "cli: 'browse' maps docker exit 130 (Ctrl-C) to exit 0" {
    local tmp stub
    tmp=$(mktemp /tmp/usb-sigint-XXXXXX)
    stub=$(_make_docker_stub 130)
    run env PATH="${stub}:${PATH}" bash "${SCRIPT}" --image "${tmp}" -p 1 browse
    rm -f "${tmp}"; rm -rf "${stub}"
    [ "${status}" -eq 0 ]
}

@test "cli: 'serve' maps docker exit 130 (Ctrl-C) to exit 0" {
    local tmp stub
    tmp=$(mktemp /tmp/usb-sigint-XXXXXX)
    stub=$(_make_docker_stub 130)
    run env PATH="${stub}:${PATH}" bash "${SCRIPT}" --image "${tmp}" -p 1 serve
    rm -f "${tmp}"; rm -rf "${stub}"
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Static-analysis — shell: bracketed-paste suppression and cursor cleanup
#
# When 'shell' exits (typed 'exit' or Ctrl-D), bash's interactive shutdown
# prints a spurious 'exit' line to the terminal.  Two invariants prevent
# regression:
#   1. dispatch.sh do_shell sets enable-bracketed-paste off via INPUTRC so
#      readline does not emit [?2004h/l sequences that shift cursor position.
#   2. src/usb-explore do_shell emits \033[1A\033[2K\r after run_container
#      returns to erase the trailing artefact line.
# ---------------------------------------------------------------------------

@test "shell: dispatch.sh do_shell disables bracketed-paste via INPUTRC" {
    grep -q 'enable-bracketed-paste off' "${DISPATCH}"
}

@test "shell: dispatch.sh do_shell exports INPUTRC before exec bash" {
    grep -q 'INPUTRC=.*exec bash' "${DISPATCH}"
}

@test "shell: host do_shell emits cursor-up+clear-line escape after normal exit" {
    grep -q '\\033\[1A\\033\[2K' "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# Static-analysis — DOCKER_CLI_HINTS suppression
#
# Docker Desktop's Gordon integration appends a multi-line "What's next:"
# block after interactive sessions that exit via Ctrl-D.  This block shifts
# the terminal cursor past the single 'exit' line that do_shell's cleanup
# escape targets, causing the artefact to remain visible.  Setting
# DOCKER_CLI_HINTS=false in run_container suppresses the block entirely.
# ---------------------------------------------------------------------------

@test "run_container: sets DOCKER_CLI_HINTS=false to suppress hint block" {
    grep -q 'DOCKER_CLI_HINTS=false' "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# Static-analysis — /mnt/part path stripping
#
# 'run' output (and 'shell' session paths) include the container-internal
# /mnt/part prefix.  copy/archive/hash/diff must strip that prefix before
# passing the path to the container, otherwise the container prepends
# /mnt/part again and the lookup fails.  container do_run must strip the
# prefix from its own output so callers can pipe run output into those
# subcommands without manual editing.
# ---------------------------------------------------------------------------

@test "copy: strips /mnt/part prefix from src path before container call" {
    grep -q 'src#/mnt/part' "${SCRIPT}"
}

@test "diff: strips /mnt/part prefix from img_path before container call" {
    grep -q 'img_path#/mnt/part' "${SCRIPT}"
}

@test "container do_run: filters /mnt/part from output via sed" {
    grep -q "sed 's|/mnt/part/|/|g'" "${DISPATCH}"
}
