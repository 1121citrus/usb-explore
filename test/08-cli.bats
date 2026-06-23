#!/usr/bin/env bats
# 08-cli.bats — host-side CLI flag and routing tests for src/usb-explore.
#
# All tests run the script directly (no Docker required). They cover global
# flags, argument parsing, and the subcommand dispatch that previously had
# zero test coverage (allowing bugs like the BSD sed incompatibility in
# usage() to pass undetected).

bats_require_minimum_version 1.5.0
# shellcheck source=../src/usb-explore
SCRIPT="${BATS_TEST_DIRNAME}/../src/usb-explore"
DISPATCH="${BATS_TEST_DIRNAME}/../src/container/dispatch.sh"
LUKS_DRIVER="${BATS_TEST_DIRNAME}/../src/container/drivers/luks.sh"
LVM_DRIVER="${BATS_TEST_DIRNAME}/../src/container/drivers/lvm.sh"
FIXTURE_GENERATOR="${BATS_TEST_DIRNAME}/fixtures/generate.sh"
SUBCOMMAND_TESTS="${BATS_TEST_DIRNAME}/06-subcommands.bats"

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
    [[ "${output}" == *"mount"*   ]]
    [[ "${output}" == *"unmount"* ]]
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
# --lv flag
# ---------------------------------------------------------------------------

@test "cli: --lv flag is parsed (not a usage error)" {
    run bash "${SCRIPT}" -i /nonexistent.img --lv root info
    [ "${status}" -ne 2 ]
}

@test "cli: --lv without value exits non-zero" {
    run bash "${SCRIPT}" --lv
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

# ---------------------------------------------------------------------------
# --luks-passphrase / --luks-key-file flags
# ---------------------------------------------------------------------------

@test "cli: --luks-passphrase flag is parsed (not a usage error)" {
    run bash "${SCRIPT}" -i /nonexistent.img --luks-passphrase secret info
    [ "${status}" -ne 2 ]
}

@test "cli: --luks-passphrase without value exits non-zero" {
    run bash "${SCRIPT}" --luks-passphrase
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "cli: --luks-passphrase-file flag is parsed (not a usage error)" {
    run bash "${SCRIPT}" -i /nonexistent.img --luks-passphrase-file /tmp/pp info
    [ "${status}" -ne 2 ]
}

@test "cli: --luks-passphrase-file without value exits non-zero" {
    run bash "${SCRIPT}" --luks-passphrase-file
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "cli: --luks-key-file flag is parsed (not a usage error)" {
    run bash "${SCRIPT}" -i /nonexistent.img --luks-key-file /tmp/key info
    [ "${status}" -ne 2 ]
}

@test "cli: --luks-key-file without value exits non-zero" {
    run bash "${SCRIPT}" --luks-key-file
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
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

@test "cli: 'mount' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" --image /nonexistent.img mount --no-open
    [ "${status}" -ne 2 ]
}

@test "cli: 'mount' --port flag is accepted" {
    run bash "${SCRIPT}" --image /nonexistent.img mount --port 44500 --no-open
    [ "${status}" -ne 2 ]
}

@test "cli: 'mount' --port with invalid value exits non-zero" {
    run bash "${SCRIPT}" mount --port notanumber
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"65535"* ]]
}

@test "cli: 'mount' detects port collision via lsof" {
    grep -q 'lsof -i' "${SCRIPT}"
}

@test "cli: 'mount' --no-open flag is accepted" {
    run bash "${SCRIPT}" --image /nonexistent.img mount --no-open
    [ "${status}" -ne 2 ]
}

@test "cli: 'unmount' subcommand is routed (not a usage error)" {
    run bash "${SCRIPT}" unmount
    [ "${status}" -eq 0 ]
}

@test "cli: 'unmount' with no active mounts exits cleanly" {
    run bash "${SCRIPT}" unmount
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"No usb-explore mounts found"* ]]
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

@test "cli: 'serve' --no-open flag is accepted" {
    run bash "${SCRIPT}" --image /nonexistent.img serve --no-open
    [ "${status}" -ne 2 ]
}

@test "cli: 'serve' --no-open combined with --port is accepted" {
    run bash "${SCRIPT}" --image /nonexistent.img serve --port 9090 --no-open
    [ "${status}" -ne 2 ]
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

# ---------------------------------------------------------------------------
# Static-analysis — browse: terminal reset on exit
#
# mc enables mouse-tracking and alternate-screen modes and does not always
# disable them when it exits.  If 'exec mc' were used, the dispatch process
# would be replaced by mc with no opportunity to clean up.  The fix removes
# 'exec' so dispatch.sh stays alive after mc exits and can emit \033c (VT100
# Reset to Initial State) before the container exits.  \033c disables mouse
# tracking, exits the alternate screen, and resets SGR attributes, preventing
# stray escape sequences from leaking into the host terminal.
# ---------------------------------------------------------------------------

@test "browse: dispatch.sh do_browse emits VT100 RIS escape before exit" {
    grep -q 'printf.*\\033c' "${DISPATCH}"
}

@test "browse: dispatch.sh do_browse does not exec mc (allows RIS cleanup to run)" {
    run ! grep -qE '^[[:space:]]*exec mc' "${DISPATCH}"
}

# ---------------------------------------------------------------------------
# Static-analysis — cleanup: _cleanup only calls docker stop when a container
# was actually started
#
# Prior to this fix, _cleanup unconditionally ran 'docker stop' on every
# exit, including argument-parsing failures (die() -> exit 1).  When Docker
# Desktop is starting or under load, docker stop blocks for several seconds
# even for non-existent containers, making the script appear to hang after
# an error.  The fix adds a CONTAINER_STARTED guard variable (false by
# default, set to true in run_container immediately before docker run) so
# that _cleanup skips the docker stop entirely when no container was launched.
# ---------------------------------------------------------------------------

@test "cleanup: CONTAINER_STARTED guards docker stop in _cleanup" {
    grep -q 'CONTAINER_STARTED' "${SCRIPT}"
}

@test "cleanup: run_container sets CONTAINER_STARTED=true before docker invocation" {
    grep -q 'CONTAINER_STARTED=true' "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# clean: -i|--image accepted as per-subcommand flag; rm -f skips
# write-protected prompt
#
# 'clean' documents -i|--image in its SYNOPSIS but the argument parser did
# not handle it, producing "Unknown clean option: -i" and exiting 1.  The
# fix adds the -i|--image case to do_clean's while loop.
#
# The file removal used plain 'rm' which prompts before removing
# write-protected files (files owned by root with mode 0644 are common when
# the image was written via sudo dd).  With the user having already confirmed
# the deletion, the secondary 'rm: remove write-protected file?' prompt is
# unexpected.  The fix uses 'rm -f' to suppress it.
# ---------------------------------------------------------------------------

@test "clean: do_clean accepts -i|--image as a per-subcommand flag" {
    local tmp
    tmp=$(mktemp /tmp/usb-clean-test-XXXXXX)
    run bash "${SCRIPT}" clean --image "${tmp}" --yes
    [ "${status}" -eq 0 ]
    [[ ! -f "${tmp}" ]]
}

@test "clean: rm uses -f to skip write-protected prompt after confirmation" {
    grep -q 'rm -f' "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# Static-analysis — serve: --no-open flag and SSH auto-suppression
#
# In headless or SSH sessions, 'open http://...' fails or produces a
# confusing error. The fix adds --no-open to suppress the browser launch
# explicitly, and auto-detects SSH sessions via SSH_CONNECTION/SSH_TTY.
# ---------------------------------------------------------------------------

@test "serve: do_serve checks no_open before calling open" {
    grep -q 'no_open.*false.*&&.*open' "${SCRIPT}"
}

@test "serve: do_serve auto-suppresses open in SSH sessions" {
    grep -q 'SSH_CONNECTION' "${SCRIPT}"
    grep -q 'SSH_TTY' "${SCRIPT}"
}

@test "serve: --no-open suppresses browser launch via docker stub" {
    local tmp stub
    tmp=$(mktemp /tmp/usb-serve-test-XXXXXX)
    stub=$(_make_docker_stub 130)
    run env PATH="${stub}:${PATH}" \
        bash "${SCRIPT}" --image "${tmp}" -p 1 serve --no-open
    rm -f "${tmp}"; rm -rf "${stub}"
    [ "${status}" -eq 0 ]
}

@test "serve: SSH_CONNECTION auto-suppresses browser launch via docker stub" {
    local tmp stub
    tmp=$(mktemp /tmp/usb-serve-test-XXXXXX)
    stub=$(_make_docker_stub 130)
    run env PATH="${stub}:${PATH}" SSH_CONNECTION="1.2.3.4 5678 5.6.7.8 22" \
        bash "${SCRIPT}" --image "${tmp}" -p 1 serve
    rm -f "${tmp}"; rm -rf "${stub}"
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Static-analysis — dm cleanup is scoped, not global
#
# dmsetup remove_all nukes every dm mapping in the kernel, including
# those owned by other containers. The cleanup must be scoped to
# usb-explore's own mappings only.
# ---------------------------------------------------------------------------

@test "dm cleanup: dispatch.sh does not use dmsetup remove_all" {
    run ! grep -q 'dmsetup remove_all' "${DISPATCH}"
}

@test "dm cleanup: dispatch.sh uses _cleanup_stale_dm for scoped cleanup" {
    grep -q '_cleanup_stale_dm' "${DISPATCH}"
}

@test "dm cleanup: host passes USB_EXPLORE_RUN_SCOPE to container" {
    grep -q 'USB_EXPLORE_RUN_SCOPE=${CONTAINER_NAME}' "${SCRIPT}"
}

@test "dm cleanup: dispatch.sh scopes cleanup by run prefix" {
    grep -q 'USB_EXPLORE_DM_SCOPE_PREFIX' "${DISPATCH}"
}

@test "dm cleanup: luks driver does not use fixed mapper name" {
    grep -q 'luks_dm_name' "${LUKS_DRIVER}"
    run ! grep -q 'usb-explore-luks' "${LUKS_DRIVER}"
}

@test "lvm driver: activate errors deactivate VG before exit" {
    grep -q 'lvm_fail()' "${LVM_DRIVER}"
    grep -q 'vg_activated=true' "${LVM_DRIVER}"
    grep -q 'vgchange --activate n "${vg_name}"' "${LVM_DRIVER}"
}

@test "fixtures: generator fails fast on image creation errors" {
    grep -q 'generation failed; aborting' "${FIXTURE_GENERATOR}"
    grep -q 'return 1' "${FIXTURE_GENERATOR}"
}

@test "fixtures: enterprise helper does not swallow generator failures" {
    run ! grep -q 'generate.sh" showcase-enterprise.img.*|| true' \
        "${SUBCOMMAND_TESTS}"
}

# ---------------------------------------------------------------------------
# _fmt_bytes — pure formatting function (no Docker, no I/O)
# ---------------------------------------------------------------------------

@test "_fmt_bytes: formats bytes (small)" {
    source "${SCRIPT}"
    run _fmt_bytes 512
    [ "${status}" -eq 0 ]
    [[ "${output}" == "512.0 B" ]]
}

@test "_fmt_bytes: formats kilobytes" {
    source "${SCRIPT}"
    run _fmt_bytes 1024
    [ "${status}" -eq 0 ]
    [[ "${output}" == "1.0 KB" ]]
}

@test "_fmt_bytes: formats megabytes" {
    source "${SCRIPT}"
    run _fmt_bytes 1048576
    [ "${status}" -eq 0 ]
    [[ "${output}" == "1.0 MB" ]]
}

@test "_fmt_bytes: formats gigabytes" {
    source "${SCRIPT}"
    run _fmt_bytes 1073741824
    [ "${status}" -eq 0 ]
    [[ "${output}" == "1.0 GB" ]]
}

@test "_fmt_bytes: handles question mark passthrough" {
    source "${SCRIPT}"
    run _fmt_bytes "?"
    [ "${status}" -eq 0 ]
    [[ "${output}" == "?" ]]
}

@test "_fmt_bytes: formats fractional values" {
    source "${SCRIPT}"
    run _fmt_bytes 1536
    [ "${status}" -eq 0 ]
    [[ "${output}" == "1.5 KB" ]]
}

# ---------------------------------------------------------------------------
# capture — device validation (no Docker, no sudo, no disk access)
# ---------------------------------------------------------------------------

@test "capture: rejects partition slice device" {
    run bash "${SCRIPT}" capture /dev/disk4s1
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"whole-disk"* ]]
}

@test "capture: rejects non-device path" {
    run bash "${SCRIPT}" capture /tmp/not-a-device
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"whole-disk"* ]]
}

@test "capture: rejects capture without device argument" {
    run bash "${SCRIPT}" capture
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "capture: rejects unknown capture option" {
    run bash "${SCRIPT}" capture --bogus
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown"* ]]
}

# ---------------------------------------------------------------------------
# archive — additional argument validation
# ---------------------------------------------------------------------------

@test "archive: rejects non-absolute src path" {
    run bash "${SCRIPT}" archive etc/hosts ./out.tar.gz
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"absolute"* ]]
}

@test "archive: accepts .tgz extension" {
    run bash "${SCRIPT}" --image /nonexistent.img archive /etc ./etc.tgz
    [ "${status}" -ne 2 ]
}

@test "archive: accepts .tar.bz2 extension" {
    run bash "${SCRIPT}" --image /nonexistent.img archive /etc ./etc.tar.bz2
    [ "${status}" -ne 2 ]
}

@test "archive: accepts .tar.xz extension" {
    run bash "${SCRIPT}" --image /nonexistent.img archive /etc ./etc.tar.xz
    [ "${status}" -ne 2 ]
}

@test "archive: accepts bare .tar extension" {
    run bash "${SCRIPT}" --image /nonexistent.img archive /etc ./etc.tar
    [ "${status}" -ne 2 ]
}

@test "archive: rejects .zip extension" {
    run bash "${SCRIPT}" archive /etc ./etc.zip
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"unsupported"* ]]
}

@test "archive: strips /mnt/part prefix from src" {
    grep -q 'src#/mnt/part' "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# copy — argument validation
# ---------------------------------------------------------------------------

@test "copy: rejects missing src argument" {
    run bash "${SCRIPT}" copy
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "copy: rejects missing dest argument" {
    run bash "${SCRIPT}" copy /etc/hosts
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "copy: rejects non-absolute src path" {
    run bash "${SCRIPT}" copy etc/hosts ./out
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"absolute"* ]]
}

# ---------------------------------------------------------------------------
# diff — argument validation
# ---------------------------------------------------------------------------

@test "diff: rejects missing image-path argument" {
    run bash "${SCRIPT}" diff
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "diff: rejects missing ref-path argument" {
    run bash "${SCRIPT}" diff /etc/hosts
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "diff: rejects non-absolute image-path" {
    run bash "${SCRIPT}" diff etc/hosts /tmp
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"absolute"* ]]
}

@test "diff: rejects nonexistent ref-path" {
    run bash "${SCRIPT}" diff /etc/hosts /nonexistent/ref
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# find — argument validation
# ---------------------------------------------------------------------------

@test "find: accepts --grep without name glob" {
    run bash "${SCRIPT}" --image /nonexistent.img find --grep "ERROR"
    [ "${status}" -ne 2 ]
}

@test "find: rejects --grep without pattern value" {
    run bash "${SCRIPT}" find --grep
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "find: rejects unknown option" {
    run bash "${SCRIPT}" find --bogus
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown"* ]]
}

# ---------------------------------------------------------------------------
# run — argument validation and path rewriting
# ---------------------------------------------------------------------------

@test "run: rejects missing command after --" {
    run bash "${SCRIPT}" run --
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

@test "run: rejects unknown option before --" {
    run bash "${SCRIPT}" run --bogus -- ls
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown"* ]]
}

@test "run: accepts -p between subcommand and --" {
    run bash "${SCRIPT}" --image /nonexistent.img run -p 2 -- ls
    [ "${status}" -ne 2 ]
}

@test "run: path rewriting converts / prefix to /mnt/part" {
    # shellcheck disable=SC2016
    grep -q '/mnt/part${arg}' "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# info — argument parsing
# ---------------------------------------------------------------------------

@test "info: accepts --json flag" {
    run bash "${SCRIPT}" --image /nonexistent.img info --json
    [ "${status}" -ne 2 ]
}

@test "info: rejects unknown option" {
    run bash "${SCRIPT}" info --bogus
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown"* ]]
}

# ---------------------------------------------------------------------------
# build — argument parsing
# ---------------------------------------------------------------------------

@test "build: rejects unknown option" {
    run bash "${SCRIPT}" build --bogus
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown"* ]]
}

# ---------------------------------------------------------------------------
# serve — port validation edge cases
# ---------------------------------------------------------------------------

@test "serve: rejects port 0" {
    run bash "${SCRIPT}" serve --port 0
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"65535"* ]]
}

@test "serve: rejects port above 65535" {
    run bash "${SCRIPT}" serve --port 70000
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"65535"* ]]
}

@test "serve: rejects negative port" {
    run bash "${SCRIPT}" serve --port -1
    [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# check_docker — function-level test
# ---------------------------------------------------------------------------

@test "check_docker: exits non-zero when docker is absent" {
    run env PATH=/usr/bin:/bin bash "${SCRIPT}" --image /tmp/x.img info
    [[ "${status}" -ne 0 ]]
}

# ---------------------------------------------------------------------------
# set_tty_flags — static analysis
# ---------------------------------------------------------------------------

@test "set_tty_flags: uses -t 0 and -t 1 for TTY detection" {
    grep -q '\-t 0' "${SCRIPT}"
    grep -q '\-t 1' "${SCRIPT}"
}
