#!/usr/bin/env bats
# 02-image-structure.bats — verify Docker image structure and contents.
# Requires IMAGE env var (e.g. 1121citrus/usb-explore:dev-latest).

IMAGE="${IMAGE:-1121citrus/usb-explore:latest}"

# ---------------------------------------------------------------------------
# Required binaries
# ---------------------------------------------------------------------------

@test "image: losetup is present" {
    run docker run --rm "${IMAGE}" which losetup
    [ "${status}" -eq 0 ]
}

@test "image: blkid is present" {
    run docker run --rm "${IMAGE}" which blkid
    [ "${status}" -eq 0 ]
}

@test "image: sfdisk is present" {
    run docker run --rm "${IMAGE}" which sfdisk
    [ "${status}" -eq 0 ]
}

@test "image: rsync is present" {
    run docker run --rm "${IMAGE}" which rsync
    [ "${status}" -eq 0 ]
}

@test "image: diff is present" {
    run docker run --rm "${IMAGE}" which diff
    [ "${status}" -eq 0 ]
}

@test "image: jq is present" {
    run docker run --rm "${IMAGE}" which jq
    [ "${status}" -eq 0 ]
}

@test "image: bash is present" {
    run docker run --rm "${IMAGE}" which bash
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Required directories
# ---------------------------------------------------------------------------

@test "image: /mnt/part directory exists" {
    run docker run --rm "${IMAGE}" test -d /mnt/part
    [ "${status}" -eq 0 ]
}

@test "image: /out directory exists" {
    run docker run --rm "${IMAGE}" test -d /out
    [ "${status}" -eq 0 ]
}

@test "image: /ref directory exists" {
    run docker run --rm "${IMAGE}" test -d /ref
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Container scripts
# ---------------------------------------------------------------------------

@test "image: entrypoint.sh is installed and executable" {
    run docker run --rm "${IMAGE}" \
        test -x /usr/local/lib/usb-explore/entrypoint.sh
    [ "${status}" -eq 0 ]
}

@test "image: info.sh is installed and executable" {
    run docker run --rm "${IMAGE}" \
        test -x /usr/local/lib/usb-explore/info.sh
    [ "${status}" -eq 0 ]
}

@test "image: dispatch.sh is installed and executable" {
    run docker run --rm "${IMAGE}" \
        test -x /usr/local/lib/usb-explore/dispatch.sh
    [ "${status}" -eq 0 ]
}

@test "image: drivers/ext.sh is installed and executable" {
    run docker run --rm "${IMAGE}" \
        test -x /usr/local/lib/usb-explore/drivers/ext.sh
    [ "${status}" -eq 0 ]
}

@test "image: drivers/xfs.sh is installed and executable" {
    run docker run --rm "${IMAGE}" \
        test -x /usr/local/lib/usb-explore/drivers/xfs.sh
    [ "${status}" -eq 0 ]
}

@test "image: drivers/vfat.sh is installed and executable" {
    run docker run --rm "${IMAGE}" \
        test -x /usr/local/lib/usb-explore/drivers/vfat.sh
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Default CMD
# ---------------------------------------------------------------------------

@test "image: default CMD is 'info'" {
    # Without --privileged and /disk.img, the entrypoint will fail trying
    # to run losetup, but the error message should reference 'info', not
    # an unknown subcommand. We just verify the CMD is set correctly.
    local cmd
    cmd=$(docker inspect --format '{{json .Config.Cmd}}' "${IMAGE}")
    [[ "${cmd}" == *'"info"'* ]]
}
