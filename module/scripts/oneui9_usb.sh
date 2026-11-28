#!/system/bin/sh
# OneUI 9.0 (Android 17) on OnePlus 13 (PJZ110 / dodge)
# Userspace USB ConfigFS + UDC + sys.usb.state + os_desc bridge (v1.3.1)
# Strictly POSIX sh (no 'local', no bashisms).

G1="/config/usb_gadget/g1"
CFG="$G1/configs/b.1"
PIDFILE="/data/local/tmp/.oneui9_usb.pid"
LOCKDIR="/data/local/tmp/.oneui9_usb.lock"
FIFO="/data/local/tmp/.oneui9_usb.fifo"
LOGFILE="/data/local/tmp/oneui9_usb.log"

log_msg() {
    printf '%s %s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null || echo '00-00 00:00:00')" "$*" >> "$LOGFILE" 2>/dev/null || true
}

find_udc() {
    _p_ctrl="$(getprop sys.usb.controller 2>/dev/null)"
    if [ -n "$_p_ctrl" ] && [ -d "/sys/class/udc/$_p_ctrl" ]; then
        printf '%s\n' "$_p_ctrl"
        return 0
    fi
    _v_ctrl="$(getprop vendor.usb.controller 2>/dev/null)"
    if [ -n "$_v_ctrl" ] && [ -d "/sys/class/udc/$_v_ctrl" ]; then
        printf '%s\n' "$_v_ctrl"
        return 0
    fi
    if [ -d /sys/class/udc/a600000.dwc3 ]; then
        printf '%s\n' "a600000.dwc3"
        return 0
    fi
    for _u in /sys/class/udc/*; do
        if [ -e "$_u" ]; then
            printf '%s\n' "${_u##*/}"
            return 0
        fi
    done
    return 1
}

ensure_gadget_base() {
    [ -d "$G1" ] || return 1
    mkdir -p "$G1/strings/0x409" "$CFG/strings/0x409" 2>/dev/null || true
    if [ ! -s "$G1/strings/0x409/manufacturer" ]; then
        printf 'OnePlus' > "$G1/strings/0x409/manufacturer" 2>/dev/null || true
    fi
    if [ ! -s "$G1/strings/0x409/product" ]; then
        printf 'PJZ110' > "$G1/strings/0x409/product" 2>/dev/null || true
    fi
    if [ ! -s "$G1/strings/0x409/serialnumber" ]; then
        _ser="$(getprop ro.serialno 2>/dev/null)"
        [ -n "$_ser" ] && printf '%s' "$_ser" > "$G1/strings/0x409/serialnumber" 2>/dev/null || true
    fi
    if [ ! -s "$CFG/strings/0x409/configuration" ]; then
        printf 'Conf 1' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
    fi
    printf '0x0200' > "$G1/bcdUSB" 2>/dev/null || true
    printf '0x00' > "$G1/bDeviceClass" 2>/dev/null || true
    printf '0x00' > "$G1/bDeviceSubClass" 2>/dev/null || true
    printf '0x00' > "$G1/bDeviceProtocol" 2>/dev/null || true
    printf '1' > "$G1/os_desc/use" 2>/dev/null || true
    printf '0x1' > "$G1/os_desc/b_vendor_code" 2>/dev/null || true
    printf 'MSFT100' > "$G1/os_desc/qw_sign" 2>/dev/null || true
    return 0
}

clear_config_links() {
    rm -f "$G1/os_desc/b.1" 2>/dev/null || true
    for _lnk in "$CFG"/*; do
        if [ -L "$_lnk" ]; then
            rm -f "$_lnk" 2>/dev/null || true
        fi
    done
}

wait_adb_ffs() {
    start adbd 2>/dev/null || setprop ctl.start adbd 2>/dev/null || true
    _wi=0
    while [ "$_wi" -lt 20 ]; do
        if [ "$(getprop sys.usb.ffs.ready 2>/dev/null)" = "1" ]; then
            return 0
        fi
        _wi=$((_wi + 1))
        sleep 0.05 2>/dev/null || sleep 1
    done
    return 1
}

ensure_func_dir() {
    _fn="$1"
    if [ ! -d "$G1/functions/$_fn" ]; then
        mkdir -p "$G1/functions/$_fn" 2>/dev/null || true
    fi
    [ -d "$G1/functions/$_fn" ]
}

link_slot() {
    _slot="$1"
    _fn="$2"
    ensure_func_dir "$_fn" || return 1
    ln -sf "$G1/functions/$_fn" "$CFG/$_slot" 2>/dev/null || return 1
    return 0
}

write_ids() {
    _vid="$1"
    _pid="$2"
    printf '%s' "$_vid" > "$G1/idVendor" 2>/dev/null || true
    printf '%s' "$_pid" > "$G1/idProduct" 2>/dev/null || true
}

acquire_lock() {
    _tries=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        _tries=$((_tries + 1))
        if [ "$_tries" -ge 30 ]; then
            rmdir "$LOCKDIR" 2>/dev/null || true
            mkdir "$LOCKDIR" 2>/dev/null || return 1
            break
        fi
        sleep 0.05 2>/dev/null || sleep 1
    done
    return 0
}

release_lock() {
    rmdir "$LOCKDIR" 2>/dev/null || true
}

bind_adb_fallback() {
    _fb_udc="$1"
    printf '' > "$G1/UDC" 2>/dev/null || true
    clear_config_links
    write_ids 0x22D9 0x2769
    printf 'adb' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
    ensure_func_dir ffs.adb >/dev/null 2>&1 || true
    ln -sf "$G1/functions/ffs.adb" "$CFG/f1" 2>/dev/null || true
    ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
    printf '%s' "$_fb_udc" > "$G1/UDC" 2>/dev/null || true
    if [ "$(cat "$G1/UDC" 2>/dev/null)" = "$_fb_udc" ]; then
        setprop sys.usb.state adb
        log_msg "fallback bound adb on $_fb_udc"
        return 0
    fi
    return 1
}

apply_usb_config() {
    _cfg="$1"
    ensure_gadget_base || return 1
    _udc="$(find_udc)" || return 1

    acquire_lock || return 1

    # Immediate unbind on none/empty so UsbDeviceManager.waitForState("none") never stalls
    case "$_cfg" in
        ""|none)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            setprop sys.usb.state none
            release_lock
            return 0
            ;;
        charging|sec_charging)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            setprop sys.usb.state "$_cfg"
            release_lock
            return 0
            ;;
    esac

    # Let init.qcom.usb.rc property trigger finish partial writes before we replace f1/f2 cleanly
    sleep 0.06 2>/dev/null || true

    _need_adb=0
    case "$_cfg" in
        *adb*)
            _need_adb=1
            wait_adb_ffs || true
            ;;
    esac

    case "$_cfg" in
        mtp,adb|adb,mtp|mtp,conn_gadget,adb|mtp,diag,adb)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            write_ids 0x22D9 0x2765
            printf 'mtp_adb' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            link_slot f1 ffs.mtp || link_slot f1 mtp.gs0 || true
            link_slot f2 ffs.adb || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        mtp|mtp,conn_gadget)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            write_ids 0x22D9 0x2764
            printf 'mtp' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            link_slot f1 ffs.mtp || link_slot f1 mtp.gs0 || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        ptp,adb|adb,ptp|ptp,conn_gadget,adb)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            write_ids 0x22D9 0x2772
            printf 'ptp_adb' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            link_slot f1 ffs.ptp || link_slot f1 ptp.gs1 || true
            link_slot f2 ffs.adb || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        ptp|ptp,conn_gadget)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            write_ids 0x22D9 0x2771
            printf 'ptp' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            link_slot f1 ffs.ptp || link_slot f1 ptp.gs1 || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        rndis,adb|adb,rndis)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            if [ -d "$G1/functions/gsi.rndis" ]; then
                write_ids 0x05C6 0x9024
                link_slot f1 gsi.rndis || true
            else
                write_ids 0x22D9 0x276B
                link_slot f1 rndis.gs4 || link_slot f1 ncm.gs6 || true
            fi
            printf 'rndis_adb' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            link_slot f2 ffs.adb || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        rndis)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            if [ -d "$G1/functions/gsi.rndis" ]; then
                write_ids 0x05C6 0xF00E
                link_slot f1 gsi.rndis || true
            else
                write_ids 0x22D9 0x276A
                link_slot f1 rndis.gs4 || link_slot f1 ncm.gs6 || true
            fi
            printf 'rndis' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        midi,adb|adb,midi)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            write_ids 0x18d1 0x4ee9
            printf 'midi_adb' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            link_slot f1 midi.gs5 || true
            link_slot f2 ffs.adb || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        midi)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            write_ids 0x18d1 0x4ee8
            printf 'midi' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            link_slot f1 midi.gs5 || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        adb|diag,adb|adb,diag|sec_charging,adb|charging,adb|*adb*)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            write_ids 0x22D9 0x2769
            printf 'adb' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
            link_slot f1 ffs.adb || true
            ln -sf "$CFG" "$G1/os_desc/b.1" 2>/dev/null || true
            ;;
        *)
            # Do not wipe UDC/links for unrecognized non-adb vendor configs
            release_lock
            return 0
            ;;
    esac

    _bound=0
    _retry=0
    while [ "$_retry" -lt 12 ]; do
        printf '%s' "$_udc" > "$G1/UDC" 2>/dev/null || true
        _cur_udc="$(cat "$G1/UDC" 2>/dev/null)"
        if [ "$_cur_udc" = "$_udc" ]; then
            _bound=1
            break
        fi
        _retry=$((_retry + 1))
        sleep 0.1 2>/dev/null || sleep 1
    done

    if [ "$_bound" -eq 1 ]; then
        setprop sys.usb.state "$_cfg"
        log_msg "bound $_cfg on $_udc (f1=$(readlink "$CFG/f1" 2>/dev/null) f2=$(readlink "$CFG/f2" 2>/dev/null))"
        release_lock
        return 0
    fi

    if [ "$_need_adb" -eq 1 ]; then
        log_msg "failed to bind $_cfg cleanly, keeping adb alive"
        bind_adb_fallback "$_udc" || true
    fi

    release_lock
    return 1
}

sync_usb_state() {
    _cfg="$(getprop sys.usb.config 2>/dev/null)"
    if [ -z "$_cfg" ]; then
        _pcfg="$(getprop persist.sys.usb.config 2>/dev/null)"
        if [ -n "$_pcfg" ]; then
            setprop sys.usb.config "$_pcfg"
            _cfg="$_pcfg"
        fi
    fi

    _state="$(getprop sys.usb.state 2>/dev/null)"
    _cur_udc="$(cat "$G1/UDC" 2>/dev/null)"
    _cls="$(cat "$G1/bDeviceClass" 2>/dev/null)"

    case "$_cfg" in
        ""|none|charging|sec_charging)
            _exp="$_cfg"
            [ -z "$_exp" ] && _exp="none"
            if [ -n "$_cur_udc" ] || [ "$_state" != "$_exp" ]; then
                apply_usb_config "$_cfg"
            fi
            return 0
            ;;
    esac

    if [ "$_state" != "$_cfg" ] || [ -z "$_cur_udc" ] || [ "$_cls" != "0x00" ]; then
        apply_usb_config "$_cfg"
        return 0
    fi

    # Require clean f1/os_desc links and purge any leftover direct ffs.* symlinks
    if [ ! -L "$CFG/f1" ] || [ -L "$CFG/ffs.mtp" ] || [ -L "$CFG/ffs.adb" ] || [ ! -L "$G1/os_desc/b.1" ]; then
        apply_usb_config "$_cfg"
        return 0
    fi
}

# Synchronous CLI mode: oneui9_usb.sh --apply [config]
if [ "${1:-}" = "--apply" ]; then
    if [ -n "${2:-}" ]; then
        _target="$2"
        setprop sys.usb.config "$_target"
    else
        _target="$(getprop sys.usb.config 2>/dev/null)"
    fi
    apply_usb_config "$_target"
    exit $?
fi

# Single-instance PID guard using tr '\0' ' ' cmdline inspection
if [ -f "$PIDFILE" ]; then
    _oldpid="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$_oldpid" ] && [ -d "/proc/$_oldpid" ]; then
        _cmd="$(tr '\0' ' ' < "/proc/$_oldpid/cmdline" 2>/dev/null)"
        case "$_cmd" in
            *oneui9_usb.sh*)
                exit 0
                ;;
        esac
    fi
fi
printf '%s\n' "$$" > "$PIDFILE"

LOGCAT_PID=""
TICK_PID=""

cleanup_daemon() {
    [ -n "$LOGCAT_PID" ] && kill "$LOGCAT_PID" 2>/dev/null || true
    [ -n "$TICK_PID" ] && kill "$TICK_PID" 2>/dev/null || true
    rm -f "$FIFO" "$PIDFILE" 2>/dev/null || true
    rmdir "$LOCKDIR" 2>/dev/null || true
}
trap cleanup_daemon EXIT INT TERM

rmdir "$LOCKDIR" 2>/dev/null || true
sync_usb_state

rm -f "$FIFO" 2>/dev/null || true
if mkfifo "$FIFO" 2>/dev/null; then
    exec 3<>"$FIFO"

    (
        trap - EXIT INT TERM
        while true; do
            logcat -b main -b system -s UsbDeviceManager:V -T 1 2>/dev/null | while IFS= read -r _line; do
                case "$_line" in
                    *UsbDeviceManager*)
                        printf 'ev\n' >&3
                        ;;
                esac
            done
            sleep 2
        done
    ) &
    LOGCAT_PID="$!"

    (
        trap - EXIT INT TERM
        while true; do
            if [ "$(cat /sys/class/power_supply/usb/online 2>/dev/null)" = "1" ]; then
                sleep 0.4 2>/dev/null || sleep 1
            else
                sleep 3
            fi
            printf 'tick\n' >&3
        done
    ) &
    TICK_PID="$!"

    while IFS= read -r _trig <&3; do
        [ -n "$_trig" ] && sync_usb_state
    done
else
    while true; do
        sync_usb_state
        sleep 0.4 2>/dev/null || sleep 1
    done
fi
