#!/usr/bin/env bats
# 06-subcommands.bats — end-to-end subcommand tests against fixture images.

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"
FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"

setup() {
    TMPDIR_WORK=$(mktemp -d)
}

teardown() {
    rm -rf "${TMPDIR_WORK}"
}

# Shorthand: run a container subcommand against single-ext4.img
run_single() {
    docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "$@"
}

# ---------------------------------------------------------------------------
# shell (non-interactive: run a command and exit)
# ---------------------------------------------------------------------------

@test "subcommand shell: exit 0 when given an immediate exit command" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" \
        bash -c '
            source /usr/local/lib/usb-explore/drivers/ext.sh
            LOOP=$(losetup --find --partscan --show /disk.img)
            trap "losetup --detach ${LOOP}" EXIT
            mount -o ro "${LOOP}p2" /mnt/part
            ls /mnt/part >/dev/null
        '
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# copy
# ---------------------------------------------------------------------------

@test "subcommand copy: copies /etc/hostname from ext4 partition to host" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local outdir="${TMPDIR_WORK}/copy-out"
    mkdir -p "${outdir}"

    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${outdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" copy /etc/hostname hostname

    [ "${status}" -eq 0 ]
    [[ -f "${outdir}/hostname" ]]
    grep -q "usb-explore-test" "${outdir}/hostname"
}

@test "subcommand copy: copies a directory from the partition" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local outdir="${TMPDIR_WORK}/copy-etc"
    mkdir -p "${outdir}"

    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${outdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" copy /etc etc

    [ "${status}" -eq 0 ]
    [[ -d "${outdir}/etc" ]]
    [[ -f "${outdir}/etc/hostname" ]]
}

@test "subcommand copy: exits 1 for non-existent source path" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local outdir="${TMPDIR_WORK}/copy-missing"
    mkdir -p "${outdir}"

    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${outdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" copy /does/not/exist missing

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------

@test "subcommand run: cat /mnt/part/etc/hostname returns expected content" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run cat /mnt/part/etc/hostname

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"usb-explore-test"* ]]
}

@test "subcommand run: find works on /mnt/part" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run find /mnt/part/etc -name hostname

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"hostname"* ]]
}

# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------

@test "subcommand diff: identical file returns 0" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    # Copy the hostname out, then diff it back — should be identical
    local refdir="${TMPDIR_WORK}/ref"
    mkdir -p "${refdir}"

    docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${refdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" copy /etc/hostname hostname >/dev/null

    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${refdir}:/ref:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" diff /etc/hostname hostname

    [ "${status}" -eq 0 ]
}

@test "subcommand diff: different file returns 1" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local refdir="${TMPDIR_WORK}/ref-diff"
    mkdir -p "${refdir}"
    echo "something-different" > "${refdir}/hostname"

    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${refdir}:/ref:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" diff /etc/hostname hostname

    [ "${status}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# xfs.img (driver test)
# ---------------------------------------------------------------------------

@test "subcommand xfs: can read hostname from xfs partition" {
    [[ -f "${FIXTURES}/xfs.img" ]] || skip "fixture xfs.img not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/xfs.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run cat /mnt/part/etc/hostname

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"xfs-test"* ]]
}

# ---------------------------------------------------------------------------
# mbr.img (MBR layout)
# ---------------------------------------------------------------------------

@test "subcommand mbr: can read hostname from MBR ext4 partition 1" {
    [[ -f "${FIXTURES}/mbr.img" ]] || skip "fixture mbr.img not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/mbr.img:/disk.img:ro" \
        -e "USB_PARTITION=1" \
        "${IMAGE}" run cat /mnt/part/etc/hostname

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"mbr-test"* ]]
}
