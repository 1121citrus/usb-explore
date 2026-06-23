#!/usr/bin/env bash
# Layer driver: LUKS (Linux Unified Key Setup)
#
# Detects LUKS-encrypted partitions and opens them using a passphrase
# from the environment or a key file. Uses LUKS_RO_FLAG from dispatch.sh
# to control read-only vs read-write access.

# dm mapping name for this invocation scope.
# Reads USB_EXPLORE_DM_SCOPE_PREFIX from dispatch.sh.
luks_dm_name() {
    local scope="${USB_EXPLORE_DM_SCOPE_PREFIX:-usb-explore}"
    echo "${scope}-luks"
}

# Detect whether the device contains a LUKS header.
# Args:   $1 = block device node
# Returns: 0 if crypto_LUKS, 1 otherwise
luks_detect() {
    local node="${1}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ "${fstype}" == "crypto_LUKS" ]]
}

# Open the LUKS volume and return the mapper device path.
# Credential sources (checked in order):
#   1. USB_EXPLORE_LUKS_KEY_FILE — binary key file (--luks-key-file)
#   2. USB_EXPLORE_LUKS_PASSPHRASE_FILE — text passphrase file
#      (--luks-passphrase-file; not exposed in env vars or process args)
#   3. USB_EXPLORE_LUKS_PASSPHRASE — passphrase string
#      (--luks-passphrase; visible in docker inspect)
#   4. stdin prompt (only when stdin is a TTY)
# Args:   $1 = block device node
# Stdout: /dev/mapper/<name>
# Returns: 0 on success; exits 5 on error
luks_activate() {
    local node="${1}"
    local dm_name
    dm_name="$(luks_dm_name)"

    if [[ -n "${USB_EXPLORE_LUKS_KEY_FILE:-}" ]]; then
        if [[ ! -f "${USB_EXPLORE_LUKS_KEY_FILE}" ]]; then
            echo "error: LUKS key file not found:" \
                 "${USB_EXPLORE_LUKS_KEY_FILE}" >&2
            exit 5
        fi
        # shellcheck disable=SC2086
        cryptsetup open ${LUKS_RO_FLAG} \
            --key-file "${USB_EXPLORE_LUKS_KEY_FILE}" \
            "${node}" "${dm_name}" || {
            echo "error: failed to open LUKS volume with key file" >&2
            exit 5
        }
    elif [[ -n "${USB_EXPLORE_LUKS_PASSPHRASE_FILE:-}" ]]; then
        if [[ ! -f "${USB_EXPLORE_LUKS_PASSPHRASE_FILE}" ]]; then
            echo "error: LUKS passphrase file not found:" \
                 "${USB_EXPLORE_LUKS_PASSPHRASE_FILE}" >&2
            exit 5
        fi
        # shellcheck disable=SC2086
        cryptsetup open ${LUKS_RO_FLAG} \
            "${node}" "${dm_name}" \
            < "${USB_EXPLORE_LUKS_PASSPHRASE_FILE}" || {
            echo "error: failed to open LUKS volume (wrong passphrase?)" >&2
            exit 5
        }
    elif [[ -n "${USB_EXPLORE_LUKS_PASSPHRASE:-}" ]]; then
        # shellcheck disable=SC2086
        printf '%s' "${USB_EXPLORE_LUKS_PASSPHRASE}" \
            | cryptsetup open ${LUKS_RO_FLAG} \
                "${node}" "${dm_name}" || {
            echo "error: failed to open LUKS volume (wrong passphrase?)" >&2
            exit 5
        }
    elif [[ -t 0 ]]; then
        echo "LUKS encrypted volume detected." >&2
        echo "Enter passphrase:" >&2
        # shellcheck disable=SC2086
        cryptsetup open ${LUKS_RO_FLAG} "${node}" "${dm_name}" || {
            echo "error: failed to open LUKS volume" >&2
            exit 5
        }
    else
        echo "error: LUKS encrypted volume detected but no credentials" \
             "provided" >&2
        echo "       Pass --luks-passphrase-file, --luks-passphrase," \
             "or --luks-key-file to decrypt" >&2
        exit 5
    fi

    echo "/dev/mapper/${dm_name}"
}

# Close the LUKS mapping.
# Args: none
# Returns: 0 (best-effort)
luks_deactivate() {
    cryptsetup close "$(luks_dm_name)" 2>/dev/null || true
}
