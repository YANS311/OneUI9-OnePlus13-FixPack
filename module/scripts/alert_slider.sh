#!/system/bin/sh
# OneUI 9 FixPack - Event-driven Alert Slider daemon for OnePlus 13 (PJZ110)
# Consumes 0% CPU while idle by blocking on `getevent -l`.

MODS_DIR="/data/adb/oneui9_mods"
CONF_FILE="$MODS_DIR/power.conf"
TRI_NODE="/proc/tristatekey/tri_state"
LOG_FILE="$MODS_DIR/alert_slider.log"
PID_FILE="$MODS_DIR/alert_slider.pid"

log_msg() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo '00:00:00')" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

read_slider_enabled() {
    if [ -f "$CONF_FILE" ]; then
        val=$(awk -F= '/^SLIDER_ENABLED=/{print $2; exit}' "$CONF_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ "$val" = "0" ]; then
            echo "0"
            return
        fi
    fi
    echo "1"
}

find_slider_dev() {
    awk '
        /^N: Name=/ { matched = ($0 ~ /oplus,hall_tri_state_key|tri_state_key/) }
        matched && /^H: Handlers=/ {
            for (i = 1; i <= NF; i++) {
                tok = $i
                sub(/^Handlers=/, "", tok)
                if (tok ~ /^event[0-9]+$/) {
                    printf "/dev/input/%s", tok
                    exit
                }
            }
        }
    ' /proc/bus/input/devices 2>/dev/null
}

read_tri_state() {
    if [ -r "$TRI_NODE" ]; then
        tr -d '[:space:]' < "$TRI_NODE" 2>/dev/null
    elif [ -r /sys/class/switch/tri-state-key/state ]; then
        tr -d '[:space:]' < /sys/class/switch/tri-state-key/state 2>/dev/null
    fi
}

vibrate_for_state() {
    state="$1"
    if ! command -v cmd >/dev/null 2>&1; then
        return
    fi
    case "$state" in
        1)
            # Silent: light crisp click
            cmd vibrator_manager synced oneshot -a 18 140 >/dev/null 2>&1 || true
            ;;
        2)
            # Vibrate: distinct double pulse
            cmd vibrator_manager synced waveform -a 25 220 55 0 25 220 >/dev/null 2>&1 \
                || cmd vibrator_manager synced oneshot -a 40 220 >/dev/null 2>&1 || true
            ;;
        3)
            # Ring: firm single pulse
            cmd vibrator_manager synced oneshot -a 35 230 >/dev/null 2>&1 || true
            ;;
    esac
}

apply_tri_state() {
    state="$1"
    with_haptic="$2"
    case "$state" in
        1) mode=0 ;; # RINGER_MODE_SILENT
        2) mode=1 ;; # RINGER_MODE_VIBRATE
        3) mode=2 ;; # RINGER_MODE_NORMAL
        *) return 1 ;;
    esac

    # IAudioService$Stub.TRANSACTION_setRingerModeExternal = 53
    service call audio 53 i32 "$mode" s16 android >/dev/null 2>&1 || return 1
    if [ "$with_haptic" = "1" ]; then
        vibrate_for_state "$state"
    fi
    log_msg "Applied tri_state=$state -> ringer_mode=$mode"
    return 0
}

# Avoid duplicate instances
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && [ -d "/proc/$OLD_PID" ]; then
        if tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null | grep -q "alert_slider.sh"; then
            exit 0
        fi
    fi
fi
echo "$$" > "$PID_FILE" 2>/dev/null || true
: > "$LOG_FILE" 2>/dev/null || true

SLIDER_DEV=$(find_slider_dev)
if [ -z "$SLIDER_DEV" ] || [ ! -c "$SLIDER_DEV" ]; then
    log_msg "Alert slider input device not found; exiting."
    exit 0
fi
log_msg "Watching slider device: $SLIDER_DEV (node=$TRI_NODE)"

# Sync initial physical slider state silently at boot if enabled
LAST_STATE=""
if [ "$(read_slider_enabled)" = "1" ]; then
    INIT_STATE=$(read_tri_state)
    if apply_tri_state "$INIT_STATE" "0"; then
        LAST_STATE="$INIT_STATE"
    fi
fi

while true; do
    getevent -l "$SLIDER_DEV" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *KEY_F3*)
                if [ "$(read_slider_enabled)" != "1" ]; then
                    continue
                fi
                # Tiny settle window so /proc/tristatekey/tri_state is updated
                sleep 0.05 2>/dev/null || true
                CUR_STATE=$(read_tri_state)
                if [ -n "$CUR_STATE" ] && [ "$CUR_STATE" != "$LAST_STATE" ]; then
                    if apply_tri_state "$CUR_STATE" "1"; then
                        LAST_STATE="$CUR_STATE"
                    fi
                fi
                ;;
        esac
    done
    sleep 5
done
