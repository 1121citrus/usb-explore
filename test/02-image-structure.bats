#!/usr/bin/env bats
# 02-image-structure.bats — verify Docker image structure and contents.
# Uses --entrypoint=bash to bypass the /disk.img check in entrypoint.sh.
# Requires IMAGE env var (e.g. 1121citrus/usb-explore:dev-latest).

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"

# Run a command inside the image, bypassing the entrypoint.
# Args: command and arguments
run_in_image() {
    docker run --rm --entrypoint=bash "${IMAGE}" -c "$*"
}

# ---------------------------------------------------------------------------
# Required binaries
# ---------------------------------------------------------------------------

@test "image: bash is present" {
    run run_in_image 'command -v bash'
    [ "${status}" -eq 0 ]
}

@test "image: blkid is present" {
    run run_in_image 'command -v blkid || ls /usr/sbin/blkid'
    [ "${status}" -eq 0 ]
}

@test "image: diff is present" {
    run run_in_image 'command -v diff'
    [ "${status}" -eq 0 ]
}

@test "image: jq is present" {
    run run_in_image 'command -v jq'
    [ "${status}" -eq 0 ]
}

@test "image: losetup is present" {
    run run_in_image 'command -v losetup || ls /usr/sbin/losetup'
    [ "${status}" -eq 0 ]
}

@test "image: mc is present" {
    run run_in_image 'command -v mc'
    [ "${status}" -eq 0 ]
}

@test "image: ncdu is present" {
    run run_in_image 'command -v ncdu'
    [ "${status}" -eq 0 ]
}

@test "image: rsync is present" {
    run run_in_image 'command -v rsync'
    [ "${status}" -eq 0 ]
}

@test "image: sfdisk is present" {
    run run_in_image 'command -v sfdisk || ls /usr/sbin/sfdisk'
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Required directories
# ---------------------------------------------------------------------------

@test "image: /mnt/part directory exists" {
    run run_in_image 'test -d /mnt/part'
    [ "${status}" -eq 0 ]
}

@test "image: /out directory exists" {
    run run_in_image 'test -d /out'
    [ "${status}" -eq 0 ]
}

@test "image: /ref directory exists" {
    run run_in_image 'test -d /ref'
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Container scripts
# ---------------------------------------------------------------------------

@test "image: entrypoint.sh is installed and executable" {
    run run_in_image 'test -x /usr/local/lib/usb-explore/entrypoint.sh'
    [ "${status}" -eq 0 ]
}

@test "image: info.sh is installed and executable" {
    run run_in_image 'test -x /usr/local/lib/usb-explore/info.sh'
    [ "${status}" -eq 0 ]
}

@test "image: dispatch.sh is installed and executable" {
    run run_in_image 'test -x /usr/local/lib/usb-explore/dispatch.sh'
    [ "${status}" -eq 0 ]
}

@test "image: drivers/ext.sh is installed and executable" {
    run run_in_image 'test -x /usr/local/lib/usb-explore/drivers/ext.sh'
    [ "${status}" -eq 0 ]
}

@test "image: drivers/xfs.sh is installed and executable" {
    run run_in_image 'test -x /usr/local/lib/usb-explore/drivers/xfs.sh'
    [ "${status}" -eq 0 ]
}

@test "image: drivers/squashfs.sh is installed and executable" {
    run run_in_image 'test -x /usr/local/lib/usb-explore/drivers/squashfs.sh'
    [ "${status}" -eq 0 ]
}

@test "image: drivers/vfat.sh is installed and executable" {
    run run_in_image 'test -x /usr/local/lib/usb-explore/drivers/vfat.sh'
    [ "${status}" -eq 0 ]
}

@test "image: unsquashfs is present" {
    run run_in_image 'command -v unsquashfs'
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Default CMD
# ---------------------------------------------------------------------------

@test "image: default CMD is 'info'" {
    local cmd
    cmd=$(docker inspect --format '{{json .Config.Cmd}}' "${IMAGE}")
    [[ "${cmd}" == *'"info"'* ]]
}
