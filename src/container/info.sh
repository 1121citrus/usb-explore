#!/usr/bin/env bash
# Partition discovery: read the disk image via sfdisk + blkid and emit
# either a human-readable table or JSON, depending on the first argument.
set -euo pipefail

LOOP="${1}"
JSON_MODE="${2:-}"

SECTOR_SIZE=512

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Format a byte count as a human-readable string (e.g. 31138512896 → 29.0 GB).
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

# Look up the human name for a known GPT partition type GUID.
# Args: $1 = GUID (upper-case)
# Returns: 0; writes name to stdout (falls back to "Unknown type")
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

# Determine whether a partition is mountable and, if not, why.
# Args: $1 = GPT type GUID or MBR hex type; $2 = blkid TYPE value
# Sets globals: MOUNTABLE (true/false), MOUNTABLE_REASON (string or "null")
classify_partition() {
    local type_id="${1^^}" fstype="${2}"
    MOUNTABLE=true
    MOUNTABLE_REASON="null"

    # Exclude by GPT type GUID
    case "${type_id}" in
        C12A7328-*)
            MOUNTABLE=false
            MOUNTABLE_REASON="EFI System Partition excluded"
            return ;;
        21686148-*)
            MOUNTABLE=false
            MOUNTABLE_REASON="BIOS Boot Partition excluded"
            return ;;
        0657FD6D-*)
            MOUNTABLE=false
            MOUNTABLE_REASON="Linux swap excluded"
            return ;;
        E6D6D379-*)
            MOUNTABLE=false
            MOUNTABLE_REASON="LVM physical volume excluded"
            return ;;
        # MBR type bytes
        00|82|8E|EE)
            MOUNTABLE=false
            MOUNTABLE_REASON="partition type excluded (${type_id})"
            return ;;
    esac

    # Exclude by filesystem type
    case "${fstype}" in
        squashfs)
            MOUNTABLE=false
            MOUNTABLE_REASON="squashfs not supported in this version"
            return ;;
        btrfs)
            MOUNTABLE=false
            MOUNTABLE_REASON="btrfs not supported in this version"
            return ;;
        swap|"")
            MOUNTABLE=false
            MOUNTABLE_REASON="no recognised filesystem"
            return ;;
    esac
}

# ---------------------------------------------------------------------------
# Build partition records
# ---------------------------------------------------------------------------

SFDISK_JSON=$(sfdisk --json "${LOOP}")
LABEL=$(echo "${SFDISK_JSON}" | jq -r '.partitiontable.label')
SECTOR_SIZE=$(echo "${SFDISK_JSON}" \
    | jq -r '.partitiontable.sectorsize // 512')

IMAGE_SIZE_SECTORS=$(echo "${SFDISK_JSON}" \
    | jq -r '.partitiontable.lastlba + 1')
IMAGE_SIZE_BYTES=$(( IMAGE_SIZE_SECTORS * SECTOR_SIZE ))
IMAGE_SIZE_HUMAN=$(bytes_human "${IMAGE_SIZE_BYTES}")

# Build a JSON array of partition records
PARTITIONS_JSON="[]"
PART_NUM=0

while IFS= read -r part_json; do
    PART_NUM=$(( PART_NUM + 1 ))
    NODE=$(echo "${part_json}"   | jq -r '.node')
    START=$(echo "${part_json}"  | jq -r '.start')
    SIZE_S=$(echo "${part_json}" | jq -r '.size')
    TYPE=$(echo "${part_json}"   | jq -r '.type // "00"')
    NAME=$(echo "${part_json}"   | jq -r '.name // ""')

    SIZE_BYTES=$(( SIZE_S * SECTOR_SIZE ))
    SIZE_HUMAN=$(bytes_human "${SIZE_BYTES}")

    # Enrich with filesystem data from blkid
    FSTYPE=$(blkid -o value -s TYPE  "${NODE}" 2>/dev/null || echo "")
    FS_LABEL=$(blkid -o value -s LABEL "${NODE}" 2>/dev/null || echo "")
    UUID=$(blkid -o value -s UUID   "${NODE}" 2>/dev/null || echo "")
    UUID_SHORT="${UUID:0:8}"

    # Determine type name for display
    if [[ "${LABEL}" == "gpt" ]]; then
        TYPE_NAME=$(gpt_type_name "${TYPE}")
    else
        TYPE_NAME="MBR type 0x${TYPE}"
    fi

    # Classify mountability
    MOUNTABLE=true
    MOUNTABLE_REASON="null"
    classify_partition "${TYPE}" "${FSTYPE}"

    # Append record to JSON array
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
            mountable_reason: (if $mreason == "null" then null
                               else $mreason end)
        }')

    PARTITIONS_JSON=$(echo "${PARTITIONS_JSON}" \
        | jq --argjson r "${RECORD}" '. + [$r]')

done < <(echo "${SFDISK_JSON}" \
    | jq -c '.partitiontable.partitions[]')

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

# Human-readable table
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
    0)
        echo "No mountable partitions found." ;;
    1)
        P=$(echo "${FULL_JSON}" \
            | jq -r '[.partitions[] | select(.mountable==true)][0].number')
        echo "1 mountable partition (partition ${P})." \
             "Omit -p to auto-select." ;;
    *)
        echo "${MOUNTABLE_COUNT} mountable partitions found." \
             "Pass -p N to select one." ;;
esac
