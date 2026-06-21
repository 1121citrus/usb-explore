#!/usr/bin/env bash
# Layer driver: LVM (Logical Volume Manager)
#
# Detects LVM2 physical volumes, activates the volume group read-only,
# and returns the path to the selected logical volume.

# Detect whether the device contains an LVM2 physical volume.
# Args:   $1 = block device node
# Returns: 0 if LVM2_member, 1 otherwise
lvm_detect() {
    local node="${1}"
    local fstype
    fstype=$(blkid -o value -s TYPE "${node}" 2>/dev/null || true)
    [[ "${fstype}" == "LVM2_member" ]]
}

# Activate the volume group and return the LV device path.
# When USB_EXPLORE_LV is set, selects that LV by name. Otherwise
# auto-selects when exactly one LV exists; exits with an error listing
# available LVs when multiple exist.
#
# The VG is activated with --sysinit (not --readonly) because
# --readonly prevents dm node creation in Docker containers without
# udev. Read-only access is enforced at the mount level instead.
# Args:   $1 = block device node (the PV)
# Stdout: device path of the selected LV
# Returns: 0 on success; exits 5 on error
lvm_activate() {
    local node="${1}"
    local vg_name=""
    local vg_activated=false

    # lvm_fail — best-effort deactivate the activated VG before exiting.
    # Args: none
    # Returns: exits 5
    lvm_fail() {
        if [[ "${vg_activated}" == true && -n "${vg_name}" ]]; then
            vgchange --activate n "${vg_name}" >/dev/null 2>&1 || true
        fi
        exit 5
    }

    # Disable udev sync — containers have no udevd running
    mkdir -p /run/lvm
    printf 'activation { udev_sync = 0\nudev_rules = 0\n}\n' \
        > /etc/lvm/lvmlocal.conf

    pvscan --cache "${node}" >/dev/null 2>&1
    vgscan --mknodes >/dev/null 2>&1

    vg_name=$(pvs --noheadings -o vg_name "${node}" 2>/dev/null \
              | tr -d ' ')

    if [[ -z "${vg_name}" ]]; then
        echo "error: no volume group found on ${node}" >&2
        lvm_fail
    fi

    if ! vgchange --activate ay --sysinit "${vg_name}" >/dev/null 2>&1; then
        echo "error: failed to activate volume group '${vg_name}'" >&2
        lvm_fail
    fi
    vg_activated=true

    local lv_paths=()
    while IFS= read -r lv_path; do
        [[ -n "${lv_path}" ]] && lv_paths+=("${lv_path}")
    done < <(lvs --noheadings -o lv_path "${vg_name}" 2>/dev/null \
             | tr -d ' ')

    if [[ ${#lv_paths[@]} -eq 0 ]]; then
        echo "error: volume group '${vg_name}' contains no logical volumes" >&2
        lvm_fail
    fi

    local selected=""
    if [[ -n "${USB_EXPLORE_LV:-}" ]]; then
        for lv in "${lv_paths[@]}"; do
            local lv_name
            lv_name=$(basename "${lv}")
            if [[ "${lv_name}" == "${USB_EXPLORE_LV}" ]]; then
                selected="${lv}"
                break
            fi
        done
        if [[ -z "${selected}" ]]; then
            echo "error: logical volume '${USB_EXPLORE_LV}' not found" \
                 "in volume group '${vg_name}'" >&2
            echo "       Available LVs:" >&2
            for lv in "${lv_paths[@]}"; do
                echo "         $(basename "${lv}")" >&2
            done
            lvm_fail
        fi
    elif [[ ${#lv_paths[@]} -eq 1 ]]; then
        selected="${lv_paths[0]}"
    else
        echo "error: volume group '${vg_name}' contains" \
             "${#lv_paths[@]} logical volumes" >&2
        echo "       Pass --lv <name> to select one:" >&2
        for lv in "${lv_paths[@]}"; do
            local lv_name lv_size
            lv_name=$(basename "${lv}")
            lv_size=$(lvs --noheadings -o lv_size --units m --nosuffix \
                      "${lv}" 2>/dev/null | tr -d ' ')
            echo "         ${lv_name}  (${lv_size} MB)" >&2
        done
        lvm_fail
    fi

    # Store VG name for deactivate
    USB_EXPLORE_LVM_VG="${vg_name}"
    echo "${selected}"
}

# Deactivate the volume group.
# Args: none (reads USB_EXPLORE_LVM_VG)
# Returns: 0 (best-effort)
lvm_deactivate() {
    if [[ -n "${USB_EXPLORE_LVM_VG:-}" ]]; then
        vgchange --activate n "${USB_EXPLORE_LVM_VG}" >/dev/null 2>&1 || true
    fi
}
