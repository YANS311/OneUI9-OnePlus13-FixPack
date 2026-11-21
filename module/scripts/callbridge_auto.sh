#!/system/bin/sh
# Hardened callbridge_auto.sh for OneUI 9 on OnePlus 13:
# - 0.3s fast pickup polling (3x faster than stock 1.0s)
# - Synchronous cleanup prevents port 19001 collision on rapid back-to-back calls
# - Bounded rtprelay.out log per call

LOCK=/data/local/tmp/.oneui9_callbridge.pid
if [ -f "$LOCK" ]; then
    O=$(tr -dc '0-9' < "$LOCK" 2>/dev/null)
    if [ -n "$O" ] && [ -d "/proc/$O" ] && tr '\0' ' ' < "/proc/$O/cmdline" 2>/dev/null | grep -q callbridge_auto; then
        exit 0
    fi
    rm -f "$LOCK"
fi
echo $$ > "$LOCK"

LOG=/data/local/tmp/callbridge_auto.log
log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }

kill_relay() {
    for p in $(pidof app_process); do
        if timeout 2 tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "RtpRelay"; then
            kill -9 "$p" 2>/dev/null || true
        fi
    done
}

idle=0
active=0
tact=0
while :; do
    cs=$(dumpsys telephony.registry 2>/dev/null | grep -o 'mCallState=[0-9]' | cut -d= -f2 | sort -n | tail -1)
    [ -z "$cs" ] && cs=0
    if [ "$cs" = "2" ]; then
        idle=0
        if [ "$active" = "0" ]; then
            active=1
            tact=$(date +%s)
            log "OFFHOOK -> rebuild relay + bridge (fast)"
            kill_relay
            am force-stop com.aric.rtpbridge >/dev/null 2>&1 || true
            setsid sh -c 'CLASSPATH=/system/framework/framework.jar:/vendor/etc/oneui9/rtprelay.jar app_process /system/bin RtpRelay 19001 3600' >/data/local/tmp/rtprelay.out 2>&1 </dev/null &
            sleep 0.1
            am start-foreground-service -n com.aric.rtpbridge/.BridgeService >/dev/null 2>&1 || true
            touch /data/local/tmp/.bridge.on
            log "bridge restarted (fast)"
        fi
    else
        if [ "$active" = "1" ]; then
            active=0
            dur=$(( $(date +%s) - tact ))
            tact=0
            if [ "$dur" -ge 2 ]; then
                log "call end (offhook ${dur}s)"
                (
                    sleep 0.1
                    printf '\000\000\000\034\073\000\000\000\000\000\000\000\015\000\000\000\017\001\000\015\000\000\000\000\026\003\003\002\000\000\000\000' | nc -U /dev/socket/Multiclient
                ) >/dev/null 2>&1 &
            fi
        fi
        # Debounce: ~2.1s (7 * 0.3s) idle before stopping bridge
        idle=$((idle + 1))
        if [ -f /data/local/tmp/.bridge.on ] && [ "$idle" -ge 7 ]; then
            rm -f /data/local/tmp/.bridge.on
            log "IDLE -> stop bridge"
            am force-stop com.aric.rtpbridge >/dev/null 2>&1 || true
            kill_relay
        fi
    fi
    sleep 0.3
done
