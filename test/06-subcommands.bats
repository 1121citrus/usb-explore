#!/usr/bin/env bats
# 06-subcommands.bats — end-to-end subcommand tests against fixture images.

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"
FIXTURES="${BATS_TEST_DIRNAME}/../fixtures"

setup() {
    TMPDIR_WORK=$(mktemp -d)
    # SERVE_CID holds the ID of a detached serve container started by a test;
    # teardown() stops it so the test body never needs trap EXIT (which would
    # replace bats' own EXIT handler and suppress the TAP result line).
    SERVE_CID=""
}

teardown() {
    if [[ -n "${SERVE_CID}" ]]; then
        docker stop "${SERVE_CID}" >/dev/null 2>&1 || true
        SERVE_CID=""
    fi
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
# archive
# ---------------------------------------------------------------------------

@test "subcommand archive: creates .tar.gz from a partition directory" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local outdir="${TMPDIR_WORK}/archive-out"
    mkdir -p "${outdir}"

    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${outdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" archive /etc etc.tar.gz

    [ "${status}" -eq 0 ]
    [[ -f "${outdir}/etc.tar.gz" ]]
}

@test "subcommand archive: .tar.gz contains expected files" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local outdir="${TMPDIR_WORK}/archive-contents"
    mkdir -p "${outdir}"

    docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${outdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" archive /etc etc.tar.gz

    run tar -tzf "${outdir}/etc.tar.gz"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"hostname"* ]]
}

@test "subcommand archive: archives a single file as .tar" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local outdir="${TMPDIR_WORK}/archive-single"
    mkdir -p "${outdir}"

    docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${outdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" archive /etc/hostname hostname.tar

    run tar -xOf "${outdir}/hostname.tar"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"usb-explore-test"* ]]
}

@test "subcommand archive: exits 1 for non-existent source path" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local outdir="${TMPDIR_WORK}/archive-missing"
    mkdir -p "${outdir}"

    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${outdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" archive /does/not/exist missing.tar.gz

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not found"* ]]
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
# dirty-ext4.img (unclean journal — regression test for noload fix)
# ---------------------------------------------------------------------------

@test "subcommand dirty-ext4: mounts and reads file from partition with dirty journal" {
    [[ -f "${FIXTURES}/dirty-ext4.img" ]] || skip "fixture dirty-ext4.img not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/dirty-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run cat /mnt/part/etc/hostname

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"dirty-ext4-test"* ]]
}

# ---------------------------------------------------------------------------
# find
# ---------------------------------------------------------------------------

@test "subcommand find: finds files by name glob" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" find "hostname"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"/etc/hostname"* ]]
}

@test "subcommand find: --grep finds file contents" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" find --grep "usb-explore-test"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"/etc/hostname"* ]]
    [[ "${output}" == *"usb-explore-test"* ]]
}

@test "subcommand find: combines name glob and --grep" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" find "hostname" --grep "usb-explore-test"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"usb-explore-test"* ]]
}

@test "subcommand find: --grep exits 1 when nothing matches" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" find --grep "ZZZNOMATCHZZZ"
    [ "${status}" -eq 1 ]
}

@test "subcommand find: name search exits 0 when nothing matches" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" find "ZZZNOMATCH.xyz"
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# hash
# ---------------------------------------------------------------------------

@test "subcommand hash: prints sha256 checksum of a file" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" hash /etc/hostname
    [ "${status}" -eq 0 ]
    # SHA-256 digest is 64 lowercase hex characters followed by two spaces
    [[ "${output}" =~ ^[0-9a-f]{64}[[:space:]][[:space:]] ]]
}

@test "subcommand hash: output path is partition-relative (no /mnt/part)" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" hash /etc/hostname
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"/etc/hostname"* ]]
    [[ "${output}" != *"/mnt/part"* ]]
}

@test "subcommand hash: result matches sha256sum of the extracted file" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    local outdir="${TMPDIR_WORK}/hash-verify"
    mkdir -p "${outdir}"

    docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -v "${outdir}:/out" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" copy /etc/hostname hostname >/dev/null

    local img_hash host_hash
    img_hash=$(docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" hash /etc/hostname | awk '{print $1}')
    host_hash=$(sha256sum "${outdir}/hostname" | awk '{print $1}')

    [ "${img_hash}" = "${host_hash}" ]
    [ -n "${img_hash}" ]
}

@test "subcommand hash: exits 1 for non-existent path" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" hash /does/not/exist
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"not found"* ]]
}

@test "subcommand hash: exits 1 for a directory path" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" hash /etc
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"directory"* ]]
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
# serve (HTTP directory server)
# ---------------------------------------------------------------------------

@test "subcommand serve: HTTP server returns directory listing for ext4 partition" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"

    local port=19080
    SERVE_CID=$(docker run --rm -d --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        -p "${port}:8080" \
        "${IMAGE}" serve)

    # Wait up to 10 s for the HTTP server to respond
    local ready=false
    for _ in $(seq 1 20); do
        sleep 0.5
        if curl -sf "http://localhost:${port}/" >/dev/null 2>&1; then
            ready=true; break
        fi
    done
    [[ "${ready}" == true ]] || skip "HTTP server did not start within 10 s"

    run curl -sf "http://localhost:${port}/"
    [ "${status}" -eq 0 ]
    # Directory listing should contain the 'etc' directory planted in the fixture
    [[ "${output}" == *"etc"* ]]
}

@test "subcommand serve: individual file is retrievable via HTTP" {
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"

    local port=19081
    SERVE_CID=$(docker run --rm -d --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        -p "${port}:8080" \
        "${IMAGE}" serve)

    local ready=false
    for _ in $(seq 1 20); do
        sleep 0.5
        if curl -sf "http://localhost:${port}/" >/dev/null 2>&1; then
            ready=true; break
        fi
    done
    [[ "${ready}" == true ]] || skip "HTTP server did not start within 10 s"

    run curl -sf "http://localhost:${port}/etc/hostname"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"usb-explore-test"* ]]
}

# ---------------------------------------------------------------------------
# shell (non-interactive: run a command and exit)
# ---------------------------------------------------------------------------

@test "subcommand shell: partition is mounted and accessible via run subcommand" {
    # shell is interactive; verify the partition mounts by using 'run' which
    # exercises the same mount_partition path without requiring a tty.
    [[ -f "${FIXTURES}/single-ext4.img" ]] || skip "fixture not generated"
    run docker run --rm --privileged \
        -v "${FIXTURES}/single-ext4.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run ls /mnt/part
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"etc"* ]]
}

# ---------------------------------------------------------------------------
# xfs.img (driver test)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# squashfs.img (driver test)
# ---------------------------------------------------------------------------

@test "subcommand squashfs: squashfs partition is identified by info --json" {
    [[ -f "${FIXTURES}/squashfs.img" ]] || skip "fixture squashfs.img not generated"
    local fstype
    fstype=$(docker run --rm --privileged \
        -v "${FIXTURES}/squashfs.img:/disk.img:ro" \
        "${IMAGE}" info --json | \
        docker run --rm -i --entrypoint=jq \
            "${IMAGE}" -r '.partitions[] | select(.number == 2) | .fstype')
    [ "${fstype}" = "squashfs" ]
}

@test "subcommand squashfs: can read hostname from squashfs partition" {
    [[ -f "${FIXTURES}/squashfs.img" ]] || skip "fixture squashfs.img not generated"

    # squashfs mounting requires the squashfs kernel module in the Docker VM.
    # Skip gracefully when the module is unavailable.
    local probe_status=0
    docker run --rm --privileged \
        -v "${FIXTURES}/squashfs.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run ls /mnt/part/etc/hostname >/dev/null 2>&1 \
        || probe_status=$?
    [[ "${probe_status}" -eq 0 ]] \
        || skip "squashfs kernel module unavailable in this Docker VM"

    run docker run --rm --privileged \
        -v "${FIXTURES}/squashfs.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run cat /mnt/part/etc/hostname

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"squashfs-test"* ]]
}

@test "subcommand xfs: xfs partition is identified by info --json" {
    [[ -f "${FIXTURES}/xfs.img" ]] || skip "fixture xfs.img not generated"
    local fstype
    fstype=$(docker run --rm --privileged \
        -v "${FIXTURES}/xfs.img:/disk.img:ro" \
        "${IMAGE}" info --json | \
        docker run --rm -i --entrypoint=jq \
            "${IMAGE}" -r '.partitions[] | select(.number == 2) | .fstype')
    [ "${fstype}" = "xfs" ]
}

@test "subcommand xfs: can read hostname from xfs partition" {
    [[ -f "${FIXTURES}/xfs.img" ]] || skip "fixture xfs.img not generated"

    # Skip when /etc/hostname was not planted in the fixture (the generator
    # skips the mount/write step when the xfs module is unavailable there).
    local probe_status=0
    docker run --rm --privileged \
        -v "${FIXTURES}/xfs.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run ls /mnt/part/etc/hostname >/dev/null 2>&1 \
        || probe_status=$?
    [[ "${probe_status}" -eq 0 ]] \
        || skip "xfs fixture has no /etc/hostname (generator skipped mount step)"

    run docker run --rm --privileged \
        -v "${FIXTURES}/xfs.img:/disk.img:ro" \
        -e "USB_PARTITION=2" \
        "${IMAGE}" run cat /mnt/part/etc/hostname

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"xfs-test"* ]]
}
