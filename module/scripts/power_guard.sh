#!/system/bin/sh
# OneUI 9 FixPack - Hardware Bypass Charging & Charge-Limit daemon for OnePlus 13
# Controls /sys/class/oplus_chg/battery/mmi_charging_enable via power.conf.

MODS_DIR="/data/adb/oneui9_mods"
CONF_FILE="$MODS_DIR/power.conf"
MMI_NODE="/sys/class/oplus_chg/battery/mmi_charging_enable"
CAP_NODE="/sys/class/power_supply/battery/capacity"
LOG_FILE="$MODS_DIR/power_guard.log"
PID_FILE="$MODS_DIR/power_guard.pid"

log_msg() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo '00:00:00')" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

ensure_conf() {
    if [ ! -f "$CONF_FILE" ]; then
        cat <<'EOF' > "$CONF_FILE"
BYPASS_MODE=0
CHARGE_LIMIT=0
RESUME_DELTA=5
SLIDER_ENABLED=1
EOF
        chmod 0644 "$CONF_FILE" 2>/dev/null || true
    fi
}

read_conf_int() {
    key="$1"
    def="$2"
    val=$(awk -F= -v k="$key" '$1 == k { print $2; exit }' "$CONF_FILE" 2>/dev/null | tr -d '[:space:]')
    case "$val" in
        ''|*[!0-9]*) echo "$def" ;;
        *) echo "$val" ;;
    esac
}

set_mmi_charging() {
    want="$1"
    reason="$2"
    cur=$(tr -d '[:space:]' < "$MMI_NODE" 2>/dev/null)
    if [ "$cur" != "$want" ]; then
        if printf '%s\n' "$want" > "$MMI_NODE" 2>/dev/null; then
            log_msg "mmi_charging_enable: $cur -> $want ($reason)"
        fi
    fi
}

if [ -f "$PID_FILE" ]; then
    OLD_PID=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && [ -d "/proc/$OLD_PID" ]; then
        if tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null | grep -q "power_guard.sh"; then
            exit 0
        fi
    fi
fi
echo "$$" > "$PID_FILE" 2>/dev/null || true
: > "$LOG_FILE" 2>/dev/null || true

if [ ! -e "$MMI_NODE" ]; then
    log_msg "mmi_charging_enable node missing; exiting."
    exit 0
fi

ensure_conf
log_msg "Started power_guard daemon (node=$MMI_NODE)"

while true; do
    ensure_conf
    BYPASS=$(read_conf_int "BYPASS_MODE" 0)
    LIMIT=$(read_conf_int "CHARGE_LIMIT" 0)
    DELTA=$(read_conf_int "RESUME_DELTA" 5)

    if [ "$BYPASS" = "1" ]; then
        set_mmi_charging 0 "bypass_mode=1"
    elif [ "$LIMIT" -gt 0 ] && [ "$LIMIT" -lt 100 ]; then
        CAP=$(tr -d '[:space:]' < "$CAP_NODE" 2>/dev/null)
        case "$CAP" in
            ''|*[!0-9]*) ;;
            *)
                RESUME_AT=$((LIMIT - DELTA))
                [ "$RESUME_AT" -lt 10 ] && RESUME_AT=10
                if [ "$CAP" -ge "$LIMIT" ]; then
                    set_mmi_charging 0 "cap=${CAP}% >= limit=${LIMIT}%"
                elif [ "$CAP" -le "$RESUME_AT" ]; then
                    set_mmi_charging 1 "cap=${CAP}% <= resume=${RESUME_AT}%"
                fi
                ;;
        esac
    else
        set_mmi_charging 1 "limit_off"
    fi

    sleep 15
done
