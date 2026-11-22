#!/system/bin/sh
# OneUI 9 FixPack - Root/BL stealth property hardening & read-only mount library

MODS_DIR="/data/adb/oneui9_mods"
RT_DIR="/data/misc/oneui_rt"
CONF_FILE="$MODS_DIR/power.conf"

do_resetprop() {
    prop_k="$1"
    prop_v="$2"
    if [ -x /data/adb/ksu/bin/resetprop ]; then
        /data/adb/ksu/bin/resetprop -n "$prop_k" "$prop_v" >/dev/null 2>&1
    elif [ -x /data/adb/ksud ]; then
        /data/adb/ksud resetprop -n "$prop_k" "$prop_v" >/dev/null 2>&1
    elif [ -x /vendor/bin/resetprop ]; then
        /vendor/bin/resetprop -n "$prop_k" "$prop_v" >/dev/null 2>&1
    elif [ -x /data/local/tmp/ksud ]; then
        /data/local/tmp/ksud resetprop -n "$prop_k" "$prop_v" >/dev/null 2>&1
    elif command -v resetprop >/dev/null 2>&1; then
        resetprop -n "$prop_k" "$prop_v" >/dev/null 2>&1
    else
        return 1
    fi
}

set_prop_if_diff() {
    prop_k="$1"
    prop_v="$2"
    cur_v=$(getprop "$prop_k" 2>/dev/null)
    if [ "$cur_v" != "$prop_v" ]; then
        do_resetprop "$prop_k" "$prop_v" || true
    fi
}

read_stealth_enabled() {
    if [ -f "$CONF_FILE" ]; then
        val=$(awk -F= '/^STEALTH_PROPS=/{print $2; exit}' "$CONF_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ "$val" = "0" ]; then
            printf '%s' "0"
            return 0
        fi
    fi
    printf '%s' "1"
}

apply_stealth_props() {
    [ "$(read_stealth_enabled)" = "1" ] || return 0
    # Never spoof ro.crypto.state globally on DFE ROMs (can break vold / lockscreen)
    set_prop_if_diff "ro.boot.verifiedbootstate" "green"
    set_prop_if_diff "ro.boot.flash.locked" "1"
    set_prop_if_diff "ro.boot.vbmeta.device_state" "locked"
    set_prop_if_diff "ro.boot.veritymode" "enforcing"
    set_prop_if_diff "ro.boot.warranty_bit" "0"
    set_prop_if_diff "ro.warranty_bit" "0"
    set_prop_if_diff "ro.secure" "1"
    set_prop_if_diff "ro.debuggable" "0"
    set_prop_if_diff "persist.service.debuggable" "0"
    set_prop_if_diff "ro.build.tags" "release-keys"
    set_prop_if_diff "ro.build.type" "user"
}

find_susfs() {
    if [ -x /data/adb/ksu/bin/ksu_susfs ]; then
        printf '%s' "/data/adb/ksu/bin/ksu_susfs"
    elif [ -x /data/adb/ksu/bin/susfs4ksu ]; then
        printf '%s' "/data/adb/ksu/bin/susfs4ksu"
    elif command -v ksu_susfs >/dev/null 2>&1; then
        command -v ksu_susfs
    fi
}

susfs_hide_mount() {
    susfs_target="$1"
    susfs_bin=$(find_susfs)
    if [ -n "$susfs_bin" ] && [ -n "$susfs_target" ]; then
        "$susfs_bin" add_sus_mount "$susfs_target" >/dev/null 2>&1 || true
    fi
}

stealth_bind_mount() {
    src_file="$1"
    target_path="$2"
    file_mode="${3:-0644}"
    [ -f "$src_file" ] && [ -e "$target_path" ] || return 1

    if [ ! -d "$RT_DIR" ]; then
        mkdir -p "$RT_DIR" 2>/dev/null || return 1
    fi
    chmod 0755 "$RT_DIR" 2>/dev/null || true
    chcon u:object_r:system_file:s0 "$RT_DIR" 2>/dev/null || true

    rt_file="$RT_DIR/${src_file##*/}"
    if [ ! -f "$rt_file" ] || ! cmp -s "$src_file" "$rt_file" 2>/dev/null; then
        cp -f "$src_file" "$rt_file" || return 1
    fi
    chmod "$file_mode" "$rt_file" 2>/dev/null || true
    chcon u:object_r:system_file:s0 "$rt_file" 2>/dev/null || true

    real_target=$(realpath "$target_path" 2>/dev/null || printf '%s' "$target_path")
    umount -l "$real_target" 2>/dev/null || umount "$real_target" 2>/dev/null || true
    mount -o bind "$rt_file" "$real_target" || return 1
    mount -o remount,ro,bind "$real_target" 2>/dev/null || true
    susfs_hide_mount "$real_target"
}

count_mount_pat() {
    pat="$1"
    cnt=$(grep -c "$pat" /proc/self/mountinfo 2>/dev/null)
    printf '%s' "${cnt:-0}"
}

audit_stealth() {
    vbs=$(getprop ro.boot.verifiedbootstate 2>/dev/null)
    locked=$(getprop ro.boot.flash.locked 2>/dev/null)
    vbmeta=$(getprop ro.boot.vbmeta.device_state 2>/dev/null)
    verity=$(getprop ro.boot.veritymode 2>/dev/null)
    wbit=$(getprop ro.boot.warranty_bit 2>/dev/null)
    dbg=$(getprop ro.debuggable 2>/dev/null)
    p_dbg=$(getprop persist.service.debuggable 2>/dev/null)
    crypto=$(getprop ro.crypto.state 2>/dev/null)
    adb_mounts=$(count_mount_pat '/adb/')
    fixpack_adb_mounts=$(count_mount_pat '/adb/oneui9_mods')
    fixpack_rt_mounts=$(count_mount_pat '/misc/oneui_rt')
    rw_sys_mounts=$(awk '$5 ~ /^\/(system|vendor|system_ext|optics)\// && $6 ~ /(^|,)rw(,|$)/ {c++} END{print c+0}' /proc/self/mountinfo 2>/dev/null)
    [ -z "$rw_sys_mounts" ] && rw_sys_mounts="0"
    if [ -n "$(find_susfs)" ]; then
        susfs="1"
    else
        susfs="0"
    fi
    zygisk_leak=$(count_mount_pat 'zygisk_lsposed')
    bindhosts_leak=$(count_mount_pat '/adb/modules/bindhosts')
    stealth_props=$(read_stealth_enabled)

    printf 'vbs=%s\nlocked=%s\nvbmeta=%s\nverity=%s\nwbit=%s\ndbg=%s\np_dbg=%s\ncrypto=%s\nadb_mounts=%s\nfixpack_adb_mounts=%s\nfixpack_rt_mounts=%s\nrw_sys_mounts=%s\nsusfs=%s\nzygisk_leak=%s\nbindhosts_leak=%s\nstealth_props=%s\n' \
        "$vbs" "$locked" "$vbmeta" "$verity" "$wbit" "$dbg" "$p_dbg" "$crypto" \
        "$adb_mounts" "$fixpack_adb_mounts" "$fixpack_rt_mounts" "$rw_sys_mounts" \
        "$susfs" "$zygisk_leak" "$bindhosts_leak" "$stealth_props"
}

case "${1:-}" in
    apply-props) apply_stealth_props ;;
    audit) audit_stealth ;;
esac
