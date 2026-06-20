#!/usr/bin/env bats
# 09-install.bats — tests for bin/install.
#
# All tests use --prefix with a temporary directory and --dry-run where
# appropriate so nothing is written outside /tmp. No Docker or network
# access required.

bats_require_minimum_version 1.5.0
INSTALL="${BATS_TEST_DIRNAME}/../bin/install"

# ---------------------------------------------------------------------------
# --help / -h
# ---------------------------------------------------------------------------

@test "install: --help exits 0" {
    run bash "${INSTALL}" --help
    [ "${status}" -eq 0 ]
}

@test "install: --help output contains SYNOPSIS keywords" {
    run bash "${INSTALL}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--prefix"* ]]
    [[ "${output}" == *"--uninstall"* ]]
}

@test "install: -h is an alias for --help" {
    run bash "${INSTALL}" -h
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--prefix"* ]]
}

# ---------------------------------------------------------------------------
# Unknown flag
# ---------------------------------------------------------------------------

@test "install: unknown flag exits non-zero" {
    run bash "${INSTALL}" --not-a-flag
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown option"* ]]
}

# ---------------------------------------------------------------------------
# --prefix requires a value
# ---------------------------------------------------------------------------

@test "install: --prefix without value exits non-zero" {
    run bash "${INSTALL}" --prefix
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"requires"* ]]
}

# ---------------------------------------------------------------------------
# Install to a temporary prefix
# ---------------------------------------------------------------------------

@test "install: installs usb-explore to PREFIX/bin" {
    local tmp
    tmp=$(mktemp -d /tmp/usb-install-test-XXXXXX)
    run bash "${INSTALL}" --prefix "${tmp}"
    [ "${status}" -eq 0 ]
    [ -f "${tmp}/bin/usb-explore" ]
    [ -x "${tmp}/bin/usb-explore" ]
    rm -rf "${tmp}"
}

@test "install: installed script contains shebang" {
    local tmp
    tmp=$(mktemp -d /tmp/usb-install-test-XXXXXX)
    bash "${INSTALL}" --prefix "${tmp}"
    head -1 "${tmp}/bin/usb-explore" | grep -q '#!/usr/bin/env bash'
    rm -rf "${tmp}"
}

@test "install: creates PREFIX/bin if it does not exist" {
    local tmp
    tmp=$(mktemp -d /tmp/usb-install-test-XXXXXX)
    rmdir "${tmp}"
    run bash "${INSTALL}" --prefix "${tmp}"
    [ "${status}" -eq 0 ]
    [ -d "${tmp}/bin" ]
    rm -rf "${tmp}"
}

@test "install: replaces existing installation" {
    local tmp
    tmp=$(mktemp -d /tmp/usb-install-test-XXXXXX)
    mkdir -p "${tmp}/bin"
    echo "old" > "${tmp}/bin/usb-explore"
    run bash "${INSTALL}" --prefix "${tmp}"
    [ "${status}" -eq 0 ]
    [[ "$(cat "${tmp}/bin/usb-explore")" != "old" ]]
    rm -rf "${tmp}"
}

# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------

@test "install: --dry-run does not create files" {
    local tmp
    tmp=$(mktemp -d /tmp/usb-install-test-XXXXXX)
    rmdir "${tmp}"
    run bash "${INSTALL}" --prefix "${tmp}" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"dry-run"* ]]
    [ ! -d "${tmp}" ]
}

# ---------------------------------------------------------------------------
# --uninstall
# ---------------------------------------------------------------------------

@test "install: --uninstall removes the script" {
    local tmp
    tmp=$(mktemp -d /tmp/usb-install-test-XXXXXX)
    mkdir -p "${tmp}/bin"
    touch "${tmp}/bin/usb-explore"
    run bash "${INSTALL}" --prefix "${tmp}" --uninstall
    [ "${status}" -eq 0 ]
    [ ! -f "${tmp}/bin/usb-explore" ]
    rm -rf "${tmp}"
}

@test "install: --uninstall succeeds when not installed" {
    local tmp
    tmp=$(mktemp -d /tmp/usb-install-test-XXXXXX)
    run bash "${INSTALL}" --prefix "${tmp}" --uninstall
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"nothing to remove"* ]]
    rm -rf "${tmp}"
}

@test "install: --uninstall --dry-run does not delete" {
    local tmp
    tmp=$(mktemp -d /tmp/usb-install-test-XXXXXX)
    mkdir -p "${tmp}/bin"
    touch "${tmp}/bin/usb-explore"
    run bash "${INSTALL}" --prefix "${tmp}" --uninstall --dry-run
    [ "${status}" -eq 0 ]
    [ -f "${tmp}/bin/usb-explore" ]
    rm -rf "${tmp}"
}

# ---------------------------------------------------------------------------
# Static analysis — resolve_source prefers local src/usb-explore
# ---------------------------------------------------------------------------

@test "install: resolve_source uses src/usb-explore from repo" {
    grep -q 'src/usb-explore' "${INSTALL}"
}

# ---------------------------------------------------------------------------
# Static analysis — script sets mode 0755 on installed file
# ---------------------------------------------------------------------------

@test "install: uses install -m 0755 for correct permissions" {
    grep -q 'install -m 0755' "${INSTALL}"
}

# ---------------------------------------------------------------------------
# Homebrew formula exists at expected path
# ---------------------------------------------------------------------------

@test "install: Homebrew formula exists at install/homebrew/Formula/" {
    [ -f "${BATS_TEST_DIRNAME}/../install/homebrew/Formula/usb-explore.rb" ]
}

@test "install: Homebrew formula contains class UsbExplore" {
    grep -q 'class UsbExplore < Formula' \
        "${BATS_TEST_DIRNAME}/../install/homebrew/Formula/usb-explore.rb"
}

@test "install: Homebrew formula sha256 is not a placeholder (tagged releases only)" {
    local tag
    tag=$(git -C "${BATS_TEST_DIRNAME}/.." describe --exact-match --tags HEAD 2>/dev/null || true)
    if [[ -z "${tag}" ]]; then
        skip "not a tagged commit"
    fi
    run grep 'sha256 "0\{64\}"' \
        "${BATS_TEST_DIRNAME}/../install/homebrew/Formula/usb-explore.rb"
    [ "${status}" -ne 0 ]
}
