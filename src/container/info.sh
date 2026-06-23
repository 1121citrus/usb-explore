#!/usr/bin/env bash
# Partition discovery: read the disk image via sfdisk + blkid --probe and
# emit either a human-readable table or JSON.
#
# Uses sfdisk directly on /disk.img for the partition table, then
# blkid --probe --offset for per-partition filesystem detection.
# Neither step requires a loop device, avoiding loop pool exhaustion
# in Docker VMs where most loop slots are occupied by overlay layers.
set -euo pipefail

JSON_MODE="${1:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# bytes_human — format a byte count as a human-readable string.
# Args: $1 = bytes (integer)
# Returns: 0; writes formatted string to stdout
bytes_human() {
    local bytes=$1
    awk -v b="${bytes}" 'BEGIN {
        split("B KB MB GB TB", s)
        i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf "%.1f %s\n", b, s[i]
    }'
}

# gpt_type_name — human name for a known GPT partition type GUID.
# Args: $1 = GUID (case-insensitive)
# Returns: 0; writes name to stdout
gpt_type_name() {
    case "${1^^}" in
        C12A7328-F81F-11D2-BA4B-00A0C93EC93B) echo "EFI System Partition" ;;
        21686148-4986-4286-8C98-94BB91B8B7AE) echo "BIOS Boot Partition" ;;
        0657FD6D-A4AB-43C4-84E5-0933C84B4F4F) echo "Linux swap" ;;
        E6D6D379-F507-44C2-A23C-238F2A3DF928) echo "LVM physical volume" ;;
        0FC63DAF-8483-4772-8E79-3D69D8477DE4) echo "Linux filesystem" ;;
        EBD0A0A2-B9E5-4433-87C0-68B6B72699C7) echo "Microsoft Basic Data" ;;
        *) echo "Unknown type" ;;
    esac
}

# classify_partition — set MOUNTABLE, MOUNTABLE_REASON, and
# STORAGE_LAYER globals.
# Args: $1 = GPT type GUID or MBR hex type; $2 = blkid TYPE value;
#       $3 = attrs string from sfdisk; $4 = partition size in bytes
classify_partition() {
    local type_id="${1^^}" fstype="${2}" attrs="${3:-}" size_bytes="${4:-0}"
    MOUNTABLE=true
    MOUNTABLE_REASON="null"
    STORAGE_LAYER=""

    case "${type_id}" in
        # EFI is NOT excluded: the vfat driver mounts it fine. It is excluded
        # only from AUTO-SELECTION (resolved via the mountable count in the
        # summary line), but explicitly selecting it with -p N always works.
        21686148-*) MOUNTABLE=false; MOUNTABLE_REASON="BIOS Boot Partition excluded"; return ;;
        0657FD6D-*) MOUNTABLE=false; MOUNTABLE_REASON="Linux swap excluded"; return ;;
        E6D6D379-*) MOUNTABLE=true; STORAGE_LAYER="lvm"; return ;;
        00|82|EE) MOUNTABLE=false; MOUNTABLE_REASON="partition type excluded (${type_id})"; return ;;
        8E) MOUNTABLE=true; STORAGE_LAYER="lvm"; return ;;
    esac

    # xorriso hybrid ISO disks: Microsoft Basic Data (EBD0A0A2) + GUID:60
    # (RequiredPartition) on both the main ISO region and the BIOS boot gap.
    # Large regions (≥1 MB) contain the ISO9660 content and can be mounted
    # via the iso9660 driver which mounts the whole disk from byte 0.
    # Small regions (e.g. 300 KB GRUB core.img) are raw binary, not mountable.
    if [[ "${type_id}" == EBD0A0A2-* && "${attrs}" == *"GUID:60"* ]]; then
        if [[ "${size_bytes}" -ge 1048576 ]]; then
            # fstype is set to iso9660 by the caller when DISK_FSTYPE is iso9660
            MOUNTABLE=true
            return
        else
            MOUNTABLE=false
            MOUNTABLE_REASON="BIOS boot sector — raw binary, no filesystem"
            return
        fi
    fi

    # Storage abstraction layers detected by blkid
    case "${fstype}" in
        crypto_LUKS)       MOUNTABLE=true; STORAGE_LAYER="luks"; return ;;
        LVM2_member)       MOUNTABLE=true; STORAGE_LAYER="lvm"; return ;;
    esac

    case "${fstype}" in
        swap|"") MOUNTABLE=false; MOUNTABLE_REASON="no recognised filesystem"; return ;;
    esac
}

# disk_level_fstype — detect filesystem spanning the whole disk image.
# ISO9660 hybrid disks have the PVD at sector 16 (byte 8192), before any
# GPT partition starts. blkid --probe on the disk as a whole may miss it
# (GPT takes priority), so also check for the CD001 magic directly.
# Returns: 0; writes type to stdout (empty if not detected)
disk_level_fstype() {
    local t
    t=$(blkid --probe -o value -s TYPE /disk.img 2>/dev/null || true)
    if [[ -n "${t}" ]]; then
        echo "${t}"; return
    fi
    # ISO9660 Primary Volume Descriptor: magic "CD001" at byte offset
    # 32769 (sector 16, byte 1 within the descriptor).
    if dd if=/disk.img bs=1 skip=32769 count=5 2>/dev/null \
            | grep -qP "^CD001"; then
        echo "iso9660"; return
    fi
    # Check for Joliet/ISO9660 using a broader match (no perl regex)
    if dd if=/disk.img bs=2048 skip=16 count=1 2>/dev/null \
            | grep -q "CD001"; then
        echo "iso9660"
    fi
}

# probe_partition — detect filesystem type using blkid --probe with byte offset.
# No loop device is created; this avoids loop pool exhaustion in Docker VMs.
# Args: $1 = byte offset, $2 = byte size, $3 = field (TYPE, LABEL, UUID, etc.)
# Returns: 0; writes field value to stdout (empty string if not detected)
probe_partition() {
    local offset="$1" size="$2" field="$3"
    blkid --probe \
        --offset="${offset}" \
        --size="${size}" \
        -o value -s "${field}" \
        /disk.img 2>/dev/null || true
}

# probe_raw_hint — extract a short display hint for a partition with no
# recognised filesystem. Two-stage fallback:
#   1. file(1) magic on the first 4 KB (catches GRUB env blocks, kernels).
#   2. Null-terminated string scan on the first 256 bytes (covers HAOS-style
#      key=value bootstate stores where file(1) returns "data").
# Args: $1 = byte offset
# Returns: 0; writes hint string to stdout (empty if nothing found)
probe_raw_hint() {
    local offset="${1}"

    # Stage 1: file(1) magic on first 4 KB.
    local magic
    magic=$(dd if=/disk.img iflag=skip_bytes skip="${offset}" \
               bs=4096 count=1 2>/dev/null \
            | file -b - 2>/dev/null) || true
    case "${magic}" in
        data|empty|"") ;;
        *) echo "${magic}"; return ;;
    esac

    # Stage 2: null-terminated string scan on first 256 bytes.
    local strings
    strings=$(dd if=/disk.img iflag=skip_bytes skip="${offset}" \
                 bs=256 count=1 2>/dev/null \
              | tr '\000' '\n' \
              | grep -E '^[[:print:]]{3,}$' \
              | head -5 \
              | tr '\n' ' ' \
              | sed 's/ *$//') || true
    [[ -n "${strings}" ]] && echo "${strings}" || true
}

# disk_image_size_bytes — return the size of /disk.img in bytes.
# Returns: 0; writes byte count to stdout
disk_image_size_bytes() {
    stat -c '%s' /disk.img 2>/dev/null || wc -c < /disk.img
}

# classify_whole_disk — classify a filesystem that starts at byte 0.
# Args: $1 = blkid TYPE value
# Sets globals: MOUNTABLE, MOUNTABLE_REASON, STORAGE_LAYER
classify_whole_disk() {
    local fstype="${1}"
    MOUNTABLE=true
    MOUNTABLE_REASON="null"
    STORAGE_LAYER=""

    case "${fstype}" in
        crypto_LUKS) MOUNTABLE=true; STORAGE_LAYER="luks"; return ;;
        LVM2_member) MOUNTABLE=true; STORAGE_LAYER="lvm"; return ;;
        ext2|ext3|ext4|xfs|vfat|squashfs|btrfs|erofs|iso9660) return ;;
        swap|"")
            MOUNTABLE=false
            MOUNTABLE_REASON="no recognised filesystem"
            return ;;
        *)
            MOUNTABLE=false
            MOUNTABLE_REASON="no driver found for filesystem '${fstype}'"
            return ;;
    esac
}

# whole_disk_partition_json — synthesize a single pseudo-partition record
# when the image has no partition table but has a filesystem at byte 0.
# Args: $1 = sector size, $2 = image size bytes, $3 = human size, $4 = fstype
# Returns: 0; writes JSON array with one partition-like record to stdout
whole_disk_partition_json() {
    local sector_size="${1}" image_size_bytes="${2}" image_size_human="${3}" fstype="${4}"
    local fs_label uuid uuid_short size_sectors

    fs_label=$(blkid --probe -o value -s LABEL /disk.img 2>/dev/null || true)
    uuid=$(blkid --probe -o value -s UUID /disk.img 2>/dev/null || true)
    uuid_short="${uuid:0:8}"
    size_sectors=$(( image_size_bytes / sector_size ))

    classify_whole_disk "${fstype}"

    jq -n \
        --argjson num     "1" \
        --arg     node    "/disk.img" \
        --argjson start   "0" \
        --argjson size_s  "${size_sectors}" \
        --argjson size_b  "${image_size_bytes}" \
        --arg     size_h  "${image_size_human}" \
        --arg     type    "00" \
        --arg     tname   "Whole-disk filesystem" \
        --arg     fstype  "${fstype}" \
        --arg     label   "${fs_label}" \
        --arg     uuid    "${uuid}" \
        --arg     uuid_s  "${uuid_short}" \
        --argjson mount   "${MOUNTABLE}" \
        --arg     mreason "${MOUNTABLE_REASON}" \
        --arg     slayer  "${STORAGE_LAYER}" \
        '[{
            number:           $num,
            node:             $node,
            start_sector:     $start,
            size_sectors:     $size_s,
            size_bytes:       $size_b,
            size_human:       $size_h,
            type_id:          $type,
            type_name:        $tname,
            fstype:           (if $fstype == "" then "raw" else $fstype end),
            raw_hint:         null,
            storage_layer:    (if $slayer == "" then null else $slayer end),
            label:            $label,
            uuid:             $uuid,
            uuid_short:       $uuid_s,
            mountable:        $mount,
            mountable_reason: (if $mreason == "null" then null else $mreason end)
        }]'
}

# ---------------------------------------------------------------------------
# Read partition table (or synthesize a whole-disk filesystem record)
# ---------------------------------------------------------------------------

SFDISK_JSON=$(sfdisk --json /disk.img 2>/dev/null || true)

if [[ -n "${SFDISK_JSON}" ]]; then
    LABEL=$(echo "${SFDISK_JSON}" | jq -r '.partitiontable.label')
    SECTOR_SIZE=$(echo "${SFDISK_JSON}" | jq -r '.partitiontable.sectorsize // 512')

    IMAGE_SIZE_SECTORS=$(echo "${SFDISK_JSON}" | jq -r '.partitiontable.lastlba + 1')
    IMAGE_SIZE_BYTES=$(( IMAGE_SIZE_SECTORS * SECTOR_SIZE ))
    IMAGE_SIZE_HUMAN=$(bytes_human "${IMAGE_SIZE_BYTES}")

    # Detect disk-level filesystem before the partition loop so that ISO data
    # regions can inherit the disk fstype (e.g. iso9660) during classification.
    DISK_FSTYPE=$(disk_level_fstype)

    # -----------------------------------------------------------------------
    # Build partition records from sfdisk output
    # -----------------------------------------------------------------------

    PARTITIONS_JSON="[]"
    PART_COUNT=$(echo "${SFDISK_JSON}" | jq '.partitiontable.partitions | length')

    for (( idx=0; idx<PART_COUNT; idx++ )); do
        PART_NUM=$(( idx + 1 ))
        PART_JSON=$(echo "${SFDISK_JSON}" | jq -c ".partitiontable.partitions[${idx}]")

    NODE=$(echo "${PART_JSON}"  | jq -r '.node')
    START=$(echo "${PART_JSON}" | jq -r '.start')
    SIZE_S=$(echo "${PART_JSON}"| jq -r '.size')
    TYPE=$(echo "${PART_JSON}"  | jq -r '.type // "00"')
    ATTRS=$(echo "${PART_JSON}" | jq -r '.attrs // ""')
    PNAME=$(echo "${PART_JSON}" | jq -r '.name  // ""')

    SIZE_BYTES=$(( SIZE_S * SECTOR_SIZE ))
    SIZE_HUMAN=$(bytes_human "${SIZE_BYTES}")
    OFFSET=$(( START * SECTOR_SIZE ))

    # Probe filesystem metadata directly from the image file at the
    # partition's byte offset — no loop device required.
    FSTYPE=$(probe_partition "${OFFSET}" "${SIZE_BYTES}" "TYPE")
    FS_LABEL=$(probe_partition "${OFFSET}" "${SIZE_BYTES}" "LABEL")
    UUID=$(probe_partition "${OFFSET}" "${SIZE_BYTES}" "UUID")
    UUID_SHORT="${UUID:0:8}"

    # ISO data regions (EBD0A0A2 + GUID:60) have no partition-level filesystem;
    # the ISO9660 structure starts at disk byte 0, before the partition. Inherit
    # the disk-level fstype so classify_partition can make them mountable.
    if [[ -z "${FSTYPE}" && "${ATTRS}" == *"GUID:60"* && -n "${DISK_FSTYPE}" ]]; then
        FSTYPE="${DISK_FSTYPE}"
    fi

    # Use partition name as label fallback (xorriso sets Gap0, Gap1 etc.)
    if [[ -z "${FS_LABEL}" && -n "${PNAME}" ]]; then
        FS_LABEL="${PNAME}"
    fi

    if [[ "${LABEL}" == "gpt" ]]; then
        TYPE_NAME=$(gpt_type_name "${TYPE}")
    else
        TYPE_NAME="MBR type 0x${TYPE}"
    fi

    MOUNTABLE=true
    MOUNTABLE_REASON="null"
    STORAGE_LAYER=""
    classify_partition "${TYPE}" "${FSTYPE}" "${ATTRS}" "${SIZE_BYTES}"

    RAW_HINT=""
    if [[ "${MOUNTABLE}" == "false" \
          && "${MOUNTABLE_REASON}" == "no recognised filesystem" ]]; then
        RAW_HINT=$(probe_raw_hint "${OFFSET}")
    fi

    RECORD=$(jq -n \
        --argjson num     "${PART_NUM}" \
        --arg     node    "${NODE}" \
        --argjson start   "${START}" \
        --argjson size_s  "${SIZE_S}" \
        --argjson size_b  "${SIZE_BYTES}" \
        --arg     size_h  "${SIZE_HUMAN}" \
        --arg     type    "${TYPE}" \
        --arg     tname   "${TYPE_NAME}" \
        --arg     fstype  "${FSTYPE}" \
        --arg     label   "${FS_LABEL}" \
        --arg     uuid    "${UUID}" \
        --arg     uuid_s  "${UUID_SHORT}" \
        --argjson mount   "${MOUNTABLE}" \
        --arg     mreason "${MOUNTABLE_REASON}" \
        --arg     rhint   "${RAW_HINT}" \
        --arg     slayer  "${STORAGE_LAYER}" \
        '{
            number:           $num,
            node:             $node,
            start_sector:     $start,
            size_sectors:     $size_s,
            size_bytes:       $size_b,
            size_human:       $size_h,
            type_id:          $type,
            type_name:        $tname,
            fstype:           (if $fstype == "" then "raw" else $fstype end),
            raw_hint:         (if $rhint == "" then null else $rhint end),
            storage_layer:    (if $slayer == "" then null else $slayer end),
            label:            $label,
            uuid:             $uuid,
            uuid_short:       $uuid_s,
            mountable:        $mount,
            mountable_reason: (if $mreason == "null" then null else $mreason end)
        }')

        PARTITIONS_JSON=$(echo "${PARTITIONS_JSON}" \
            | jq --argjson r "${RECORD}" '. + [$r]')
    done
else
    DISK_FSTYPE=$(disk_level_fstype)
    if [[ -z "${DISK_FSTYPE}" ]]; then
        printf 'info: no recognised partition table in the disk image\n' >&2
        printf 'info: the image may be unformatted, blank, or use an unsupported scheme\n' >&2
        exit 1
    fi

    LABEL="none"
    SECTOR_SIZE=512
    IMAGE_SIZE_BYTES=$(disk_image_size_bytes)
    IMAGE_SIZE_HUMAN=$(bytes_human "${IMAGE_SIZE_BYTES}")
    PARTITIONS_JSON=$(whole_disk_partition_json \
        "${SECTOR_SIZE}" "${IMAGE_SIZE_BYTES}" "${IMAGE_SIZE_HUMAN}" "${DISK_FSTYPE}")
fi

FULL_JSON=$(jq -n \
    --arg     image   "/disk.img" \
    --argjson size_b  "${IMAGE_SIZE_BYTES}" \
    --arg     size_h  "${IMAGE_SIZE_HUMAN}" \
    --arg     label   "${LABEL}" \
    --argjson parts   "${PARTITIONS_JSON}" \
    '{
        image:       $image,
        size_bytes:  $size_b,
        size_human:  $size_h,
        label:       $label,
        partitions:  $parts
    }')

# DISK_FSTYPE was already set before the partition loop (see above).
if [[ -n "${DISK_FSTYPE}" ]]; then
    FULL_JSON=$(echo "${FULL_JSON}" \
        | jq --arg df "${DISK_FSTYPE}" '. + {disk_filesystem: $df}')
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [[ "${JSON_MODE}" == "--json" ]]; then
    echo "${FULL_JSON}"
    exit 0
fi

MOUNTABLE_COUNT=$(echo "${FULL_JSON}" \
    | jq '[.partitions[] | select(.mountable == true)] | length')

if [[ -n "${DISK_FSTYPE}" ]]; then
    printf "Image:  /disk.img  (%s)  [disk-level: %s]\n" \
        "${IMAGE_SIZE_HUMAN}" "${DISK_FSTYPE}"
else
    printf "Image:  /disk.img  (%s)\n" "${IMAGE_SIZE_HUMAN}"
fi
printf "Scheme: %s\n\n" "${LABEL^^}"
printf "  %-3s  %-10s  %-10s  %-22s  %-10s  %s\n" \
    "#" "Filesystem" "Size" "Label" "UUID" "Notes"

while IFS= read -r p; do
    num=$(echo "${p}"       | jq -r '.number')
    fstype=$(echo "${p}"    | jq -r '.fstype')
    size=$(echo "${p}"      | jq -r '.size_human')
    lbl=$(echo "${p}"       | jq -r '.label')
    uuid=$(echo "${p}"      | jq -r '.uuid_short')
    mount=$(echo "${p}"     | jq -r '.mountable')
    reason=$(echo "${p}"    | jq -r '.mountable_reason // ""')
    raw_hint=$(echo "${p}"  | jq -r '.raw_hint // ""')
    slayer=$(echo "${p}"    | jq -r '.storage_layer // ""')

    if [[ "${mount}" == "true" && -n "${slayer}" ]]; then
        note="[mountable via ${slayer}]"
    elif [[ "${mount}" == "true" ]]; then
        note="[mountable]"
    elif [[ -n "${raw_hint}" ]]; then
        note="[raw: ${raw_hint}]"
    else
        note="[${reason}]"
    fi

    printf "  %-3s  %-10s  %-10s  %-22s  %-10s  %s\n" \
        "${num}" "${fstype}" "${size}" "${lbl:0:22}" "${uuid}" "${note}"
done < <(echo "${FULL_JSON}" | jq -c '.partitions[]')

echo ""
case "${MOUNTABLE_COUNT}" in
    0) echo "No mountable partitions found." ;;
    1)
        P=$(echo "${FULL_JSON}" \
            | jq -r '[.partitions[] | select(.mountable==true)][0].number')
        printf "1 mountable partition (partition %s). Omit -p to auto-select.\n" "${P}" ;;
    *)
        printf "%s mountable partitions found. Pass -p N to select one.\n" \
            "${MOUNTABLE_COUNT}" ;;
esac
