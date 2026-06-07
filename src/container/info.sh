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
        *) echo "Unknown type" ;;
    esac
}

# classify_partition — set MOUNTABLE and MOUNTABLE_REASON globals.
# Args: $1 = GPT type GUID or MBR hex type; $2 = blkid TYPE value
classify_partition() {
    local type_id="${1^^}" fstype="${2}"
    MOUNTABLE=true
    MOUNTABLE_REASON="null"

    case "${type_id}" in
        C12A7328-*) MOUNTABLE=false; MOUNTABLE_REASON="EFI System Partition excluded"; return ;;
        21686148-*) MOUNTABLE=false; MOUNTABLE_REASON="BIOS Boot Partition excluded"; return ;;
        0657FD6D-*) MOUNTABLE=false; MOUNTABLE_REASON="Linux swap excluded"; return ;;
        E6D6D379-*) MOUNTABLE=false; MOUNTABLE_REASON="LVM physical volume excluded"; return ;;
        00|82|8E|EE) MOUNTABLE=false; MOUNTABLE_REASON="partition type excluded (${type_id})"; return ;;
    esac

    case "${fstype}" in
        squashfs) MOUNTABLE=false; MOUNTABLE_REASON="squashfs not supported in this version"; return ;;
        btrfs)    MOUNTABLE=false; MOUNTABLE_REASON="btrfs not supported in this version"; return ;;
        swap|"")  MOUNTABLE=false; MOUNTABLE_REASON="no recognised filesystem"; return ;;
    esac
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

# ---------------------------------------------------------------------------
# Read partition table
# ---------------------------------------------------------------------------

SFDISK_JSON=$(sfdisk --json /disk.img 2>/dev/null)
LABEL=$(echo "${SFDISK_JSON}" | jq -r '.partitiontable.label')
SECTOR_SIZE=$(echo "${SFDISK_JSON}" | jq -r '.partitiontable.sectorsize // 512')

IMAGE_SIZE_SECTORS=$(echo "${SFDISK_JSON}" | jq -r '.partitiontable.lastlba + 1')
IMAGE_SIZE_BYTES=$(( IMAGE_SIZE_SECTORS * SECTOR_SIZE ))
IMAGE_SIZE_HUMAN=$(bytes_human "${IMAGE_SIZE_BYTES}")

# ---------------------------------------------------------------------------
# Build partition records
# ---------------------------------------------------------------------------

PARTITIONS_JSON="[]"
PART_COUNT=$(echo "${SFDISK_JSON}" | jq '.partitiontable.partitions | length')

for (( idx=0; idx<PART_COUNT; idx++ )); do
    PART_NUM=$(( idx + 1 ))
    PART_JSON=$(echo "${SFDISK_JSON}" | jq -c ".partitiontable.partitions[${idx}]")

    NODE=$(echo "${PART_JSON}"  | jq -r '.node')
    START=$(echo "${PART_JSON}" | jq -r '.start')
    SIZE_S=$(echo "${PART_JSON}"| jq -r '.size')
    TYPE=$(echo "${PART_JSON}"  | jq -r '.type // "00"')

    SIZE_BYTES=$(( SIZE_S * SECTOR_SIZE ))
    SIZE_HUMAN=$(bytes_human "${SIZE_BYTES}")
    OFFSET=$(( START * SECTOR_SIZE ))

    # Probe filesystem metadata directly from the image file at the
    # partition's byte offset — no loop device required.
    FSTYPE=$(probe_partition "${OFFSET}" "${SIZE_BYTES}" "TYPE")
    FS_LABEL=$(probe_partition "${OFFSET}" "${SIZE_BYTES}" "LABEL")
    UUID=$(probe_partition "${OFFSET}" "${SIZE_BYTES}" "UUID")
    UUID_SHORT="${UUID:0:8}"

    if [[ "${LABEL}" == "gpt" ]]; then
        TYPE_NAME=$(gpt_type_name "${TYPE}")
    else
        TYPE_NAME="MBR type 0x${TYPE}"
    fi

    MOUNTABLE=true
    MOUNTABLE_REASON="null"
    classify_partition "${TYPE}" "${FSTYPE}"

    RECORD=$(jq -n \
        --argjson num    "${PART_NUM}" \
        --arg     node   "${NODE}" \
        --argjson start  "${START}" \
        --argjson size_s "${SIZE_S}" \
        --argjson size_b "${SIZE_BYTES}" \
        --arg     size_h "${SIZE_HUMAN}" \
        --arg     type   "${TYPE}" \
        --arg     tname  "${TYPE_NAME}" \
        --arg     fstype "${FSTYPE}" \
        --arg     label  "${FS_LABEL}" \
        --arg     uuid   "${UUID}" \
        --arg     uuid_s "${UUID_SHORT}" \
        --argjson mount  "${MOUNTABLE}" \
        --arg     mreason "${MOUNTABLE_REASON}" \
        '{
            number:           $num,
            node:             $node,
            start_sector:     $start,
            size_sectors:     $size_s,
            size_bytes:       $size_b,
            size_human:       $size_h,
            type_id:          $type,
            type_name:        $tname,
            fstype:           (if $fstype == "" then "unknown" else $fstype end),
            label:            $label,
            uuid:             $uuid,
            uuid_short:       $uuid_s,
            mountable:        $mount,
            mountable_reason: (if $mreason == "null" then null else $mreason end)
        }')

    PARTITIONS_JSON=$(echo "${PARTITIONS_JSON}" \
        | jq --argjson r "${RECORD}" '. + [$r]')
done

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

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [[ "${JSON_MODE}" == "--json" ]]; then
    echo "${FULL_JSON}"
    exit 0
fi

MOUNTABLE_COUNT=$(echo "${FULL_JSON}" \
    | jq '[.partitions[] | select(.mountable == true)] | length')

printf "Image:  /disk.img  (%s)\n" "${IMAGE_SIZE_HUMAN}"
printf "Scheme: %s\n\n" "${LABEL^^}"
printf "  %-3s  %-10s  %-10s  %-22s  %-10s  %s\n" \
    "#" "Filesystem" "Size" "Label" "UUID" "Notes"

while IFS= read -r p; do
    num=$(echo "${p}"    | jq -r '.number')
    fstype=$(echo "${p}" | jq -r '.fstype')
    size=$(echo "${p}"   | jq -r '.size_human')
    lbl=$(echo "${p}"    | jq -r '.label')
    uuid=$(echo "${p}"   | jq -r '.uuid_short')
    mount=$(echo "${p}"  | jq -r '.mountable')
    reason=$(echo "${p}" | jq -r '.mountable_reason // ""')

    if [[ "${mount}" == "true" ]]; then
        note="[mountable]"
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
