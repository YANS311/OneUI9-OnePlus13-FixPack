#!/system/bin/sh
# OneUI 9.0 (Android 17) on OnePlus 13 (PJZ110 / dodge)
# Userspace USB ConfigFS + UDC + sys.usb.state bridge
# Bridges Samsung UsbDeviceManager <-> Qualcomm DWC3 ConfigFS gadget (g1),
# enabling MTP, PTP, RNDIS, MIDI, and ADB without overwriting sys.usb.config.
# Strictly POSIX sh (no 'local', no bashisms).

G1="/config/usb_gadget/g1"
CFG="$G1/configs/b.1"
PIDFILE="/data/local/tmp/.oneui9_usb.pid"
LOCKDIR="/data/local/tmp/.oneui9_usb.lock"
FIFO="/data/local/tmp/.oneui9_usb.fifo"

find_udc() {
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
        printf 'OnePlus 13' > "$G1/strings/0x409/product" 2>/dev/null || true
    fi
    if [ ! -s "$G1/strings/0x409/serialnumber" ]; then
        _ser="$(getprop ro.serialno)"
        [ -n "$_ser" ] && printf '%s' "$_ser" > "$G1/strings/0x409/serialnumber" 2>/dev/null || true
    fi
    if [ ! -s "$CFG/strings/0x409/configuration" ]; then
        printf 'Conf 1' > "$CFG/strings/0x409/configuration" 2>/dev/null || true
    fi
    printf '0x0200' > "$G1/bcdUSB" 2>/dev/null || true
    printf '0xEF' > "$G1/bDeviceClass" 2>/dev/null || true
    printf '0x02' > "$G1/bDeviceSubClass" 2>/dev/null || true
    printf '0x01' > "$G1/bDeviceProtocol" 2>/dev/null || true
    return 0
}

clear_config_links() {
    for _lnk in "$CFG"/*; do
        if [ -L "$_lnk" ]; then
            rm -f "$_lnk" 2>/dev/null || true
        fi
    done
}

link_func() {
    _fn="$1"
    if [ ! -d "$G1/functions/$_fn" ]; then
        mkdir -p "$G1/functions/$_fn" 2>/dev/null || true
    fi
    if [ -d "$G1/functions/$_fn" ]; then
        ln -sf "$G1/functions/$_fn" "$CFG/$_fn" 2>/dev/null || return 1
        return 0
    fi
    return 1
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

apply_usb_config() {
    _cfg="$1"
    ensure_gadget_base || return 1
    _udc="$(find_udc)" || return 1

    acquire_lock || return 1

    case "$_cfg" in
        ""|none|charging)
            printf '' > "$G1/UDC" 2>/dev/null || true
            clear_config_links
            if [ -z "$_cfg" ]; then
                setprop sys.usb.state none
            else
                setprop sys.usb.state "$_cfg"
            fi
            release_lock
            return 0
            ;;
    esac

    # Unbind before mutating gadget links and PID/VID
    printf '' > "$G1/UDC" 2>/dev/null || true
    clear_config_links

    _need_ffs=0
    case "$_cfg" in
        adb)
            write_ids 0x22D9 0x2769
            link_func ffs.adb
            _need_ffs=1
            ;;
        mtp)
            write_ids 0x22D9 0x2764
            link_func ffs.mtp || link_func mtp.gs0 || true
            _need_ffs=1
            ;;
        mtp,adb|adb,mtp)
            write_ids 0x22D9 0x2765
            link_func ffs.mtp || link_func mtp.gs0 || true
            link_func ffs.adb
            _need_ffs=1
            ;;
        ptp)
            write_ids 0x22D9 0x2766
            link_func ffs.ptp || link_func ptp.gs1 || true
            _need_ffs=1
            ;;
        ptp,adb|adb,ptp)
            write_ids 0x22D9 0x2767
            link_func ffs.ptp || link_func ptp.gs1 || true
            link_func ffs.adb
            _need_ffs=1
            ;;
        rndis)
            write_ids 0x22D9 0x276A
            link_func rndis.gs4 || link_func ncm.gs6 || true
            ;;
        rndis,adb|adb,rndis)
            write_ids 0x22D9 0x276B
            link_func rndis.gs4 || link_func ncm.gs6 || true
            link_func ffs.adb
            _need_ffs=1
            ;;
        midi)
            write_ids 0x22D9 0x2773
            link_func midi.gs5 || true
            ;;
        midi,adb|adb,midi)
            write_ids 0x22D9 0x2774
            link_func midi.gs5 || true
            link_func ffs.adb
            _need_ffs=1
            ;;
        *)
            release_lock
            return 1
            ;;
    esac

    if [ "$_need_ffs" -eq 1 ]; then
        setprop sys.usb.ffs.ready 1
    fi

    # Retry UDC write briefly while adbd/MtpService finishes opening FunctionFS ep0
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
    fi

    release_lock
    [ "$_bound" -eq 1 ]
}

sync_usb_state() {
    _cfg="$(getprop sys.usb.config)"
    if [ -z "$_cfg" ]; then
        _pcfg="$(getprop persist.sys.usb.config)"
        if [ -n "$_pcfg" ]; then
            setprop sys.usb.config "$_pcfg"
            _cfg="$_pcfg"
        fi
    fi

    _state="$(getprop sys.usb.state)"
    _cur_udc="$(cat "$G1/UDC" 2>/dev/null)"

    case "$_cfg" in
        ""|none|charging)
            if [ -n "$_cur_udc" ] || { [ -n "$_cfg" ] && [ "$_state" != "$_cfg" ]; } || { [ -z "$_cfg" ] && [ "$_state" != "none" ]; }; then
                apply_usb_config "$_cfg"
            fi
            return 0
            ;;
    esac

    # Re-apply whenever sys.usb.state lags sys.usb.config OR UDC dropped unexpectedly
    if [ "$_state" != "$_cfg" ] || [ -z "$_cur_udc" ]; then
        apply_usb_config "$_cfg"
        return 0
    fi

    # Also verify expected function symlink wasn't stripped by an external service
    case "$_cfg" in
        *mtp*)
            if [ ! -L "$CFG/ffs.mtp" ] && [ ! -L "$CFG/mtp.gs0" ]; then
                apply_usb_config "$_cfg"
            fi
            ;;
        *ptp*)
            if [ ! -L "$CFG/ffs.ptp" ] && [ ! -L "$CFG/ptp.gs1" ]; then
                apply_usb_config "$_cfg"
            fi
            ;;
        *adb*)
            if [ ! -L "$CFG/ffs.adb" ]; then
                apply_usb_config "$_cfg"
            fi
            ;;
    esac
}

# Synchronous CLI mode: oneui9_usb.sh --apply [config]
if [ "${1:-}" = "--apply" ]; then
    if [ -n "${2:-}" ]; then
        _target="$2"
        setprop sys.usb.config "$_target"
    else
        _target="$(getprop sys.usb.config)"
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

# Clear any stale lock on fresh daemon start and perform initial sync
rmdir "$LOCKDIR" 2>/dev/null || true
sync_usb_state

rm -f "$FIFO" 2>/dev/null || true
if mkfifo "$FIFO" 2>/dev/null; then
    # Open read-write on FD 3 so pipe never sends premature EOF when a writer restarts
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
            sleep 3
            printf 'tick\n' >&3
        done
    ) &
    TICK_PID="$!"

    while IFS= read -r _trig <&3; do
        [ -n "$_trig" ] && sync_usb_state
    done
else
    # Fallback polling loop if FIFO creation fails
    while true; do
        sync_usb_state
        sleep 1
    done
fi
