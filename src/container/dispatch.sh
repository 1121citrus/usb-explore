#!/usr/bin/env bash
# Route a subcommand to its handler.
# Manages all loop-device lifecycle: opens, mounts, and guarantees cleanup
# via a single EXIT trap so no devices are leaked regardless of exit path.
#
# Partition access uses per-partition loop devices created from sfdisk byte
# offsets. This avoids relying on losetup --partscan, which is unreliable
# inside Docker VMs on macOS.
set -euo pipefail

SUBCOMMAND="${1}"
shift

# Source filesystem drivers
DRIVER_DIR="/usr/local/lib/usb-explore/drivers"
# shellcheck source=/dev/null
for _drv in "${DRIVER_DIR}"/*.sh; do source "${_drv}"; done
# Driver registry: each entry must have <name>_detect, <name>_mount, and
# <name>_unmount functions defined in src/container/drivers/<name>.sh, plus
# the corresponding package added to the Dockerfile.
# To add a driver: append its name here and follow CONTRIBUTING.md.
# iso9660 must come AFTER vfat: it activates only for partitions with NO
# partition-level filesystem, so vfat (EFI) is handled first and wins.
FS_DRIVERS=(ext xfs vfat squashfs btrfs iso9660)

# ---------------------------------------------------------------------------
# Loop device tracking (populated by attach_partition)
# ---------------------------------------------------------------------------

PART_LOOP=""    # partition-specific loop device, set by attach_partition

cleanup() {
    local rc=$?
    umount /mnt/part 2>/dev/null || true
    [[ -n "${PART_LOOP}" ]] && losetup --detach "${PART_LOOP}" 2>/dev/null || true
    exit "${rc}"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Partition loop helpers
# ---------------------------------------------------------------------------

# attach_partition — create a read-only loop device for one partition.
# Uses sfdisk byte-offset arithmetic so no kernel partition-scan is needed.
# Args:   $1 = 1-based partition number
# Side effect: sets global PART_LOOP
# Returns: 0 on success; exits 5 on out-of-range partition number
attach_partition() {
    local partnum="${1}"
    local sfdisk_json sector_size n_parts start size

    sfdisk_json=$(sfdisk --json /disk.img 2>/dev/null)
    sector_size=$(echo "${sfdisk_json}" | jq -r '.partitiontable.sectorsize // 512')
    n_parts=$(echo "${sfdisk_json}" | jq '.partitiontable.partitions | length')

    if [[ "${partnum}" -lt 1 || "${partnum}" -gt "${n_parts}" ]]; then
        echo "error: partition ${partnum} does not exist" \
             "(image has ${n_parts} partitions)." >&2
        echo "       Run 'usb-explore info' to see the partition table." >&2
        exit 5
    fi

    start=$(echo "${sfdisk_json}" \
        | jq -r ".partitiontable.partitions[${partnum}-1].start")
    size=$(echo "${sfdisk_json}" \
        | jq -r ".partitiontable.partitions[${partnum}-1].size")

    # Docker Desktop VMs pre-create loop nodes only up to a fixed limit.
    # When losetup --find returns a node above that limit (e.g. /dev/loop77),
    # the node doesn't exist in /dev and losetup fails. Pre-create nodes
    # 67-127 to cover any gap, then attach.
    local offset sizelimit candidate attempt
    offset=$(( start * sector_size ))
    sizelimit=$(( size * sector_size ))

    candidate=$(losetup --find 2>/dev/null || true)
    if [[ -n "${candidate}" && ! -b "${candidate}" ]]; then
        local num="${candidate#/dev/loop}"
        mknod "${candidate}" b 7 "${num}" 2>/dev/null || true
    fi

    for attempt in 1 2 3 4 5; do
        PART_LOOP=$(losetup --find --show --read-only \
            --offset="${offset}" \
            --sizelimit="${sizelimit}" \
            /disk.img 2>/dev/null) && break
        [[ "${attempt}" -lt 5 ]] || {
            echo "error: no loop device available after ${attempt} attempts." >&2
            exit 5
        }
        # Allow any just-exited container to release its loop device
        sleep "0.${attempt}"
        candidate=$(losetup --find 2>/dev/null || true)
        if [[ -n "${candidate}" && ! -b "${candidate}" ]]; then
            local num="${candidate#/dev/loop}"
            mknod "${candidate}" b 7 "${num}" 2>/dev/null || true
        fi
    done
}

# mount_partition — attach and mount the selected partition read-only.
# Reads USB_PARTITION from the environment.
# Returns: 0 on success; exits 5 on unsupported or unrecognised filesystem
mount_partition() {
    # Pre-check: for xorriso ISO data regions (GPT attribute GUID:60), the
    # iso9660 filesystem starts at disk byte 0 (before any partition offset).
    # Creating a partition loop device and THEN a full-disk loop for the same
    # file causes a kernel "overlapping loop device" error. Detect this case
    # first and mount /disk.img directly without a partition loop.
    local sfdisk_json part_attrs part_idx
    sfdisk_json=$(sfdisk --json /disk.img 2>/dev/null)
    part_idx=$(( USB_PARTITION - 1 ))
    part_attrs=$(echo "${sfdisk_json}" | jq -r ".partitiontable.partitions[${part_idx}].attrs // \"\"")

    if [[ "${part_attrs}" == *"GUID:60"* ]]; then
        # Detach any stale loop devices pointing at /disk.img. Loop devices
        # persist across container exits when exec() replaces bash (EXIT trap
        # never fires). A stale partition-offset loop overlaps the full-disk
        # range and causes 'overlapping loop device exists' on the iso9660 mount.
        while IFS= read -r _stale; do
            [[ -n "${_stale}" ]] && losetup --detach "${_stale}" 2>/dev/null || true
        done < <(losetup --associated /disk.img 2>/dev/null | awk -F: '{print $1}')

        # Check for ISO9660 magic at sector 16 (byte 32769)
        if dd if=/disk.img bs=2048 skip=16 count=1 2>/dev/null | grep -q "CD001"; then
            mount -o ro -t iso9660 /disk.img /mnt/part
            return 0
        fi
        echo "error: partition ${USB_PARTITION} is an ISO data region but" >&2
        echo "       the disk does not contain a readable ISO9660 filesystem." >&2
        exit 5
    fi

    attach_partition "${USB_PARTITION:?USB_PARTITION is not set}"

    local fstype
    fstype=$(blkid -o value -s TYPE "${PART_LOOP}" 2>/dev/null || echo "unknown")

    for drv in "${FS_DRIVERS[@]}"; do
        if "${drv}_detect" "${PART_LOOP}"; then
            "${drv}_mount" "${PART_LOOP}" /mnt/part
            return 0
        fi
    done

    case "${fstype}" in
        unknown|"")
            echo "error: partition ${USB_PARTITION} contains no" >&2
            echo "       recognised filesystem." >&2 ;;
        *)
            echo "error: no driver found for filesystem '${fstype}'." >&2 ;;
    esac
    exit 5
}

# ---------------------------------------------------------------------------
# Subcommand: archive
# ---------------------------------------------------------------------------

# Create a compressed archive of a partition path and write it to /out/.
# Args:
#   $1  src-path — absolute path within the mounted partition
#   $2  archive-name — output filename; compression from extension
#         .tar.gz / .tgz  → gzip
#         .tar.bz2 / .tbz2 → bzip2
#         .tar.xz / .txz   → xz
#         .tar              → no compression
# Returns:
#   0 on success; 1 on path-not-found or unrecognised extension
do_archive() {
    local src="${1}" archive_name="${2}"
    mount_partition

    local src_abs="/mnt/part/${src#/}"
    if [[ ! -e "${src_abs}" ]]; then
        echo "error: path not found in image: ${src}" >&2
        exit 1
    fi

    # Infer compression flag from archive name extension
    local compress=""
    case "${archive_name}" in
        *.tar.gz|*.tgz)   compress="-z" ;;
        *.tar.bz2|*.tbz2) compress="-j" ;;
        *.tar.xz|*.txz)   compress="-J" ;;
        *.tar)             compress=""   ;;
        *)
            echo "error: unrecognised archive extension: ${archive_name}" >&2
            echo "       Supported: .tar.gz .tgz .tar.bz2 .tbz2 .tar.xz .txz .tar" >&2
            exit 1 ;;
    esac

    # Build tar argument list; preserve the source entry name at archive root
    local tar_args=()
    [[ -n "${compress}" ]] && tar_args+=("${compress}")
    tar_args+=(-f "/out/${archive_name}" \
                -C "$(dirname "${src_abs}")" \
                "$(basename "${src_abs}")")
    tar -c "${tar_args[@]}"
}

# ---------------------------------------------------------------------------
# Subcommand: browse
# ---------------------------------------------------------------------------

# Launch Midnight Commander (mc) rooted at the mounted partition.
# Requires a TTY; the host wrapper always passes -i -t.
# Args:
#   None
# Returns:
#   Exit code from mc; runs until the user quits the file manager.
do_browse() {
    mount_partition
    cd /mnt/part
    local _mc_rc=0
    mc /mnt/part || _mc_rc=$?
    # mc enables mouse tracking and alternate-screen mode and does not always
    # disable them cleanly on exit (e.g. when its Ctrl-O subshell is still
    # running).  \033c is the VT100 "Reset to Initial State" sequence: it
    # exits the alternate screen, disables all mouse-tracking modes, and
    # resets SGR attributes.  Emitting it here ensures the host terminal is
    # clean before the container process exits and Docker kills any lingering
    # mc subprocesses.
    printf '\033c'
    return "${_mc_rc}"
}

# ---------------------------------------------------------------------------
# Subcommand: copy
# ---------------------------------------------------------------------------

do_copy() {
    local src="${1}" dst_name="${2}"
    mount_partition

    local src_abs="/mnt/part/${src#/}"
    if [[ ! -e "${src_abs}" ]]; then
        echo "error: path not found in image: ${src}" >&2
        exit 1
    fi

    # Trailing slash on source dir copies its CONTENTS into dest, avoiding
    # the rsync "copy-into" behaviour that would create dest/basename/.
    if [[ -d "${src_abs}" ]]; then
        mkdir -p "/out/${dst_name}"
        rsync -a --no-owner --no-group "${src_abs}/" "/out/${dst_name}/"
    else
        rsync -a --no-owner --no-group "${src_abs}" "/out/${dst_name}"
    fi
}

# ---------------------------------------------------------------------------
# Subcommand: diff
# ---------------------------------------------------------------------------

do_diff() {
    local img_path="${1}" ref_name="${2}"
    mount_partition

    local img_abs="/mnt/part/${img_path#/}"
    if [[ ! -e "${img_abs}" ]]; then
        echo "error: path not found in image: ${img_path}" >&2
        exit 1
    fi

    # Exit codes propagate: 0=identical, 1=differences, 2=error
    diff -rq "${img_abs}" "/ref/${ref_name}"
}

# ---------------------------------------------------------------------------
# Subcommand: find
# ---------------------------------------------------------------------------

# Search the mounted partition by filename glob, file contents, or both.
# Strips the /mnt/part prefix from all output so paths are usable directly
# with other subcommands (copy, archive, diff).
# Args:
#   [NAME-GLOB]     glob matched against file basenames
#   [--grep PAT]    pattern searched in file contents (grep -E syntax)
# Returns:
#   0 on success; 1 when --grep finds no matches (standard grep exit)
do_find() {
    local name_pattern="" grep_pattern=""
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --grep)
                [[ -n "${2:-}" ]] \
                    || { echo "error: --grep requires a pattern" >&2; exit 1; }
                grep_pattern="${2}"; shift ;;
            -*)
                echo "error: unknown find option: ${1}" >&2; exit 1 ;;
            *)
                if [[ -z "${name_pattern}" ]]; then
                    name_pattern="${1}"
                else
                    echo "error: unexpected argument: ${1}" >&2; exit 1
                fi ;;
        esac
        shift
    done

    [[ -n "${name_pattern}" || -n "${grep_pattern}" ]] \
        || { echo "error: find requires a NAME-GLOB and/or --grep PATTERN" >&2
             exit 1; }

    mount_partition

    if [[ -n "${grep_pattern}" ]]; then
        # Build grep args; --include restricts to filenames when combined
        local grep_args=(-r -H)
        [[ -n "${name_pattern}" ]] \
            && grep_args+=(--include="${name_pattern}")
        grep_args+=(-- "${grep_pattern}" /mnt/part)
        grep "${grep_args[@]}" | sed 's|^/mnt/part||'
    else
        find /mnt/part -name "${name_pattern}" | sed 's|^/mnt/part||'
    fi
}

# ---------------------------------------------------------------------------
# Subcommand: hash
# ---------------------------------------------------------------------------

# Print the SHA-256 checksum of a single file from the mounted partition.
# The output path is rewritten to partition-relative so users can paste it
# directly into copy/archive/diff without stripping /mnt/part manually.
# Args:
#   $1  path — absolute path within the partition
# Returns:
#   0 on success; 1 if the path does not exist or is a directory
do_hash() {
    local src="${1}"
    mount_partition

    local src_abs="/mnt/part/${src#/}"
    if [[ ! -e "${src_abs}" ]]; then
        echo "error: path not found in image: ${src}" >&2
        exit 1
    fi
    if [[ -d "${src_abs}" ]]; then
        echo "error: ${src} is a directory; hash requires a file" >&2
        exit 1
    fi

    # sha256sum output: "<digest>  <path>" — rewrite container path to
    # the partition-relative form the user supplied.
    sha256sum "${src_abs}" | sed "s| ${src_abs}$| ${src}|"
}

# ---------------------------------------------------------------------------
# Subcommand: info
# ---------------------------------------------------------------------------

do_info() {
    exec /usr/local/lib/usb-explore/info.sh "$@"
}

# ---------------------------------------------------------------------------
# Subcommand: run
# ---------------------------------------------------------------------------

# Args: command and arguments, with leading / paths already rewritten to
# /mnt/part/<path> by the host wrapper before being passed in.
# CWD is set to /mnt/part so that bare commands like 'ls' or 'find .'
# operate on the partition root rather than the container root.
# Output is filtered to strip the /mnt/part prefix from any paths so that
# callers can pipe run output directly into copy/archive/hash/diff.
do_run() {
    mount_partition
    cd /mnt/part
    "$@" | sed 's|/mnt/part/|/|g'
    return "${PIPESTATUS[0]}"
}

# ---------------------------------------------------------------------------
# Subcommand: select-partition
# ---------------------------------------------------------------------------

# Auto-select a mountable partition and print its metadata to stdout.
# Runs info.sh internally; no loop device setup is performed.
# Called by the host wrapper's resolve_partition so that all jq processing
# stays inside the container (jq is guaranteed installed; host may not have it).
# Args:
#   None
# Returns:
#   0 and writes "<number> <fstype> <size_human>" to stdout (exactly 1 match)
#   5 if no mountable or multiple mountable partitions (table/error to stderr)
do_select_partition() {
    local json mountable count
    json=$(/usr/local/lib/usb-explore/info.sh --json 2>/dev/null)
    mountable=$(echo "${json}" | jq '[.partitions[] | select(.mountable == true)]')
    count=$(echo "${mountable}" | jq 'length')

    case "${count}" in
        0)
            echo "error: no mountable partitions found in /disk.img" >&2
            echo "       Run 'usb-explore info' to see the full partition table" >&2
            exit 5 ;;
        1)
            local num fs size
            num=$(echo "${mountable}" | jq -r '.[0].number')
            fs=$(echo "${mountable}"  | jq -r '.[0].fstype')
            size=$(echo "${mountable}" | jq -r '.[0].size_human')
            echo "${num} ${fs} ${size}" ;;
        *)
            /usr/local/lib/usb-explore/info.sh >&2
            echo "error: multiple mountable partitions found" >&2
            echo "       Pass -p|--partition N to select one" >&2
            exit 5 ;;
    esac
}

# ---------------------------------------------------------------------------
# Subcommand: serve
# ---------------------------------------------------------------------------

# Serve the mounted partition as a read-only HTTP directory index on port 8080.
# The host wrapper maps a host port to this container port via -p.
do_serve() {
    mount_partition
    exec python3 -m http.server 8080 --directory /mnt/part
}

# ---------------------------------------------------------------------------
# Subcommand: shell
# ---------------------------------------------------------------------------

do_shell() {
    mount_partition
    export PS1="(usb-explore p${USB_PARTITION}) \w \$ "
    cd /mnt/part
    # Disable bracketed-paste mode (bash 5.1+ default).  Without this,
    # readline emits [?2004h/[?2004l escape sequences around each accepted
    # command, which changes the CRLF structure of the output and breaks
    # the host-side cursor cleanup that erases the trailing 'exit' line.
    local _rc
    _rc=$(mktemp)
    printf 'set enable-bracketed-paste off\n' > "${_rc}"
    INPUTRC="${_rc}" exec bash --norc --noprofile
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${SUBCOMMAND}" in
    archive) do_archive "$@" ;;
    browse)  do_browse  "$@" ;;
    copy)    do_copy    "$@" ;;
    diff)    do_diff    "$@" ;;
    find)    do_find    "$@" ;;
    hash)    do_hash    "$@" ;;
    info)    do_info    "$@" ;;
    run)              do_run              "$@" ;;
    select-partition) do_select_partition "$@" ;;
    serve)            do_serve            "$@" ;;
    shell)   do_shell   "$@" ;;
    *)
        echo "error: unknown subcommand '${SUBCOMMAND}'" >&2
        exit 2 ;;
esac
