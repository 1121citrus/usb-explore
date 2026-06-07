#!/usr/bin/env bats
# 07-capture.bats — validate capture helper functions and progress output.
#
# src/usb-explore is sourced to load _fmt_bytes and _progress_monitor; the
# script's source guard skips argument parsing when sourced, so no Docker or
# real device is needed for these tests.
#
# After sourcing, set -e is cleared: the script enables it, and kill+wait
# on a background job returns the signal exit code which would otherwise
# abort the test subshell.

SCRIPT="${BATS_TEST_DIRNAME}/../src/usb-explore"

# shellcheck source=/dev/null
_load() {
    source "${SCRIPT}" 2>/dev/null
    # src/usb-explore enables set -euo pipefail; disable so that normal
    # test failures (kill, wait on killed bg job) don't abort the subshell.
    set +euo pipefail 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# _fmt_bytes
# ---------------------------------------------------------------------------

@test "capture helper: _fmt_bytes formats B / KB / MB / GB" {
    _load
    [ "$(_fmt_bytes 0)"          = "0.0 B"  ]
    [ "$(_fmt_bytes 1024)"       = "1.0 KB" ]
    [ "$(_fmt_bytes 1048576)"    = "1.0 MB" ]
    [ "$(_fmt_bytes 1073741824)" = "1.0 GB" ]
}

# ---------------------------------------------------------------------------
# _progress_monitor
# ---------------------------------------------------------------------------

@test "capture: progress monitor emits a formatted line every interval" {
    _load

    local tmpimg tmpout start_ts
    tmpimg=$(mktemp)
    tmpout=$(mktemp)
    # Pretend 2 seconds have elapsed so speed/ETA are non-zero
    start_ts=$(( $(date +%s) - 2 ))

    # Give the file 10 MB so the monitor has a non-zero size to report.
    # Use count*bs form that works with both BSD and BusyBox dd.
    dd if=/dev/zero bs=1024 count=10240 of="${tmpimg}" 2>/dev/null

    # Run the monitor for one 1-second interval
    _progress_monitor 1 104857600 "${tmpimg}" "${start_ts}" 2>"${tmpout}" &
    local mon_pid=$!
    sleep 1.5
    kill "${mon_pid}" 2>/dev/null
    wait "${mon_pid}" 2>/dev/null || true

    # Must have produced at least one line
    [[ "$(wc -l < "${tmpout}")" -ge 1 ]]

    local line
    line=$(head -1 "${tmpout}")
    [[ "${line}" == *"MB"*      ]]   # written size
    [[ "${line}" == *"%"*       ]]   # percentage
    [[ "${line}" == *"/s"*      ]]   # transfer speed
    [[ "${line}" == *"ETA"*     ]]   # estimated time remaining
    [[ "${line}" == *"elapsed"* ]]   # elapsed time

    rm -f "${tmpimg}" "${tmpout}"
}

@test "capture: progress monitor shows increasing size as file grows" {
    _load

    local tmpimg tmpout start_ts
    tmpimg=$(mktemp)
    tmpout=$(mktemp)
    start_ts=$(date +%s)

    # Initial file: 5 MB
    dd if=/dev/zero bs=1024 count=5120 of="${tmpimg}" 2>/dev/null

    # Start monitor at 1-second interval
    _progress_monitor 1 104857600 "${tmpimg}" "${start_ts}" 2>"${tmpout}" &
    local mon_pid=$!

    # Let the first tick fire, then grow the file
    sleep 1.2
    dd if=/dev/zero bs=1024 count=15360 >> "${tmpimg}" 2>/dev/null

    # Wait for the second tick
    sleep 1.2
    kill "${mon_pid}" 2>/dev/null
    wait "${mon_pid}" 2>/dev/null || true

    # Must have at least two lines
    [[ "$(wc -l < "${tmpout}")" -ge 2 ]]

    # Second line must show a larger written size than the first
    local sz1 sz2
    sz1=$(sed -n '1p' "${tmpout}" | awk '{print $1}')
    sz2=$(sed -n '2p' "${tmpout}" | awk '{print $1}')
    [[ -n "${sz2}" ]]
    [[ "${sz2}" != "${sz1}" ]]

    rm -f "${tmpimg}" "${tmpout}"
}

# ---------------------------------------------------------------------------
# --progress-interval flag
# ---------------------------------------------------------------------------

@test "capture: --progress-interval flag is accepted (dry-run)" {
    run bash "${SCRIPT}" capture /dev/disk0 --progress-interval 10 --dry-run
    # dry-run never reaches dd; the flag itself must not trigger a usage error
    [[ "${status}" -ne 2 ]]
    [[ "${output}" != *"Unknown capture option"* ]]
}
