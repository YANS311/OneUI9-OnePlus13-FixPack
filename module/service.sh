#!/system/bin/sh
# Runs after boot_completed=1 so vendor init & settings provider are fully ready
MODDIR=${0%/*}
MODS_DIR="/data/adb/oneui9_mods"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done
sleep 5

if [ -f "$MODDIR/scripts/stealth_lib.sh" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$MODDIR/scripts/stealth_lib.sh"
elif [ -f "$MODS_DIR/stealth_lib.sh" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$MODS_DIR/stealth_lib.sh"
fi

# 0. Re-enforce Bootloader / Debuggable stealth properties (catches late boot overrides)
apply_stealth_props

# 1. Ensure CameraX Kotlin fix & read-only lock
if [ -f /system/framework/sec_camerax_impl.jar ] && [ -f /odm/framework/androidx.camera.extensions.impl.fake.jar ]; then
    if ! grep -q '/odm/framework/androidx.camera.extensions.impl.fake.jar' /proc/mounts 2>/dev/null; then
        mount -o bind /system/framework/sec_camerax_impl.jar /odm/framework/androidx.camera.extensions.impl.fake.jar
    fi
    mount -o remount,ro,bind /odm/framework/androidx.camera.extensions.impl.fake.jar 2>/dev/null || true
    susfs_hide_mount /odm/framework/androidx.camera.extensions.impl.fake.jar
fi

# Harden inherited /system/framework/telephony-common.jar bind mount as read-only
if [ -f "$MODS_DIR/telephony-common.jar" ] && [ -f /system/framework/telephony-common.jar ]; then
    mount -o remount,ro,bind /system/framework/telephony-common.jar 2>/dev/null || true
    susfs_hide_mount /system/framework/telephony-common.jar
fi

# 2. Ensure clean floating_feature.xml (no tsds2 eSIM slot switch) & Samsung RIL ICC_TYPE props
if [ -f "$MODS_DIR/floating_feature.xml" ]; then
    stealth_bind_mount "$MODS_DIR/floating_feature.xml" /system/etc/floating_feature.xml 0644
fi

SIM_STATES=$(getprop gsm.sim.state)
S0=$(echo "$SIM_STATES" | cut -d, -f1)
S1=$(echo "$SIM_STATES" | cut -d, -f2)
if [ "$S0" != "ABSENT" ]; then
    setprop ril.ICC_TYPE0 2
else
    setprop ril.ICC_TYPE0 0
fi
if [ "$S1" != "ABSENT" ]; then
    setprop ril.ICC_TYPE1 2
else
    setprop ril.ICC_TYPE1 0
fi
am force-stop com.samsung.android.app.telephonyui 2>/dev/null || true

# 3. Samsung Camera 60fps unlock + 9:16 3840x2160 fix (stealth read-only mount)
if [ -f "$MODS_DIR/camera-feature.xml" ]; then
    stealth_bind_mount "$MODS_DIR/camera-feature.xml" /system/cameradata/camera-feature.xml 0644
fi

# 4. Ensure permanent clock seconds setting (when patched SystemUI.apk is present)
if [ -f "$MODS_DIR/SystemUI.apk" ]; then
    settings put secure icon_blacklist "rotate,headset,slimindicator_show_seconds" 2>/dev/null || true
fi

# 5. Enable SMS over IP (IMS SMS) on both SIM slots
content update --uri 'content://com.sec.ims.settings/global#simslot0' --bind sms_over_ip_indication:i:1 --bind enable_default_sms_fallback:i:1 >/dev/null 2>&1 || true
content update --uri 'content://com.sec.ims.settings/global#simslot1' --bind sms_over_ip_indication:i:1 --bind enable_default_sms_fallback:i:1 >/dev/null 2>&1 || true

# 6. Late-mount patched imsservice.apk (CMCC + CTC + CU dbr_timer=0 & use_precondition=false)
if [ -f "$MODS_DIR/imsservice.apk" ] && [ -f /system/priv-app/imsservice/imsservice.apk ]; then
    for ims_pid in $(pidof com.sec.imsservice 2>/dev/null); do
        kill -9 "$ims_pid" 2>/dev/null || true
    done
    umount -l /vendor/etc/oneui9/imsservice.apk 2>/dev/null || true
    umount -l /system/priv-app/imsservice/imsservice.apk 2>/dev/null || true
    stealth_bind_mount "$MODS_DIR/imsservice.apk" /system/priv-app/imsservice/imsservice.apk 0644
    rm -f /data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_0.xml /data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_1.xml
    for ims_pid in $(pidof com.sec.imsservice 2>/dev/null); do
        kill -9 "$ims_pid" 2>/dev/null || true
    done
fi

# 7. Ensure TGY cscfeature.xml mount & shared peer lock (fallback if /optics mounted after post-fs-data)
if [ -f "$MODS_DIR/cscfeature.xml" ] && [ -f /optics/configs/carriers/TGY/conf/system/cscfeature.xml ]; then
    if ! grep -q '/optics/configs/carriers/TGY/conf/system/cscfeature.xml' /proc/mounts 2>/dev/null; then
        stealth_bind_mount "$MODS_DIR/cscfeature.xml" /optics/configs/carriers/TGY/conf/system/cscfeature.xml 0644
    else
        mount -o remount,ro,bind /optics/configs/carriers/TGY/conf/system/cscfeature.xml 2>/dev/null || true
        susfs_hide_mount /optics/configs/carriers/TGY/conf/system/cscfeature.xml
    fi
    if [ -e /vendor/etc/oneui9/optics/configs/carriers/TGY/conf/system/cscfeature.xml ]; then
        mount -o remount,ro,bind /vendor/etc/oneui9/optics/configs/carriers/TGY/conf/system/cscfeature.xml 2>/dev/null || true
        susfs_hide_mount /vendor/etc/oneui9/optics/configs/carriers/TGY/conf/system/cscfeature.xml
    fi
fi

# 8. Start OnePlus 13 hardware daemons (0% idle CPU Alert Slider + Bypass Charging Power Guard)
if [ -x "$MODDIR/scripts/alert_slider.sh" ]; then
    nohup "$MODDIR/scripts/alert_slider.sh" >/dev/null 2>&1 &
elif [ -x "$MODS_DIR/alert_slider.sh" ]; then
    nohup "$MODS_DIR/alert_slider.sh" >/dev/null 2>&1 &
fi

if [ -x "$MODDIR/scripts/power_guard.sh" ]; then
    nohup "$MODDIR/scripts/power_guard.sh" >/dev/null 2>&1 &
elif [ -x "$MODS_DIR/power_guard.sh" ]; then
    nohup "$MODS_DIR/power_guard.sh" >/dev/null 2>&1 &
fi

# 9. Replace broken stock USB watchdog with ConfigFS MTP/PTP/RNDIS + ADB bridge
if [ -f "$MODS_DIR/oneui9_usb.sh" ] && [ -f /vendor/bin/oneui9_usb.sh ]; then
    stealth_bind_mount "$MODS_DIR/oneui9_usb.sh" /vendor/bin/oneui9_usb.sh 0755
fi
pkill -f 'oneui9_usb\.sh' 2>/dev/null || true
rm -f /data/local/tmp/.oneui9_usb.pid 2>/dev/null || true
rmdir /data/local/tmp/.oneui9_usb.lock 2>/dev/null || true
if [ -x "$MODS_DIR/oneui9_usb.sh" ]; then
    nohup "$MODS_DIR/oneui9_usb.sh" >/dev/null 2>&1 &
elif [ -x "$MODDIR/scripts/oneui9_usb.sh" ]; then
    nohup "$MODDIR/scripts/oneui9_usb.sh" >/dev/null 2>&1 &
fi

# 10. Dual-SIM ringtone null fallback (re-hydrate MediaStore URIs only if null/empty)
(
    _cur_r1="$(settings get system ringtone 2>/dev/null)"
    if [ -z "$_cur_r1" ] || [ "$_cur_r1" = "null" ]; then
        _rt_try=0
        _ring_id=""
        while [ "$_rt_try" -lt 6 ]; do
            _ring_id="$(content query --uri content://media/internal/audio/media --projection _id --where "_data='/system/media/audio/ringtones/SoundTheme/Galaxy/ACH_Over_the_Horizon_2026.ogg'" 2>/dev/null | sed -n 's/.*_id=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
            [ -n "$_ring_id" ] && break
            _rt_try=$((_rt_try + 1))
            sleep 5
        done
        if [ -n "$_ring_id" ]; then
            settings put system ringtone "content://media/internal/audio/media/$_ring_id?title=Over%20the%20Horizon%202026&canonical=1" 2>/dev/null || true
            _cur_r2="$(settings get system ringtone_2 2>/dev/null)"
            if [ -z "$_cur_r2" ] || [ "$_cur_r2" = "null" ]; then
                _ring2_id="$(content query --uri content://media/internal/audio/media --projection _id --where "_data='/system/media/audio/ringtones/SoundTheme/Galaxy/ACH_Signal.ogg'" 2>/dev/null | sed -n 's/.*_id=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
                [ -n "$_ring2_id" ] && settings put system ringtone_2 "content://media/internal/audio/media/$_ring2_id?title=Signal&canonical=1" 2>/dev/null || true
            fi
            _cur_n1="$(settings get system notification_sound 2>/dev/null)"
            if [ -z "$_cur_n1" ] || [ "$_cur_n1" = "null" ]; then
                _not_id="$(content query --uri content://media/internal/audio/media --projection _id --where "_data='/system/media/audio/notifications/SoundTheme/Galaxy/Galaxy_Bells.ogg'" 2>/dev/null | sed -n 's/.*_id=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
                if [ -n "$_not_id" ]; then
                    _not_uri="content://media/internal/audio/media/$_not_id?title=Galaxy%20Bells&canonical=1"
                    settings put system notification_sound "$_not_uri" 2>/dev/null || true
                    _cur_n2="$(settings get system notification_sound_2 2>/dev/null)"
                    if [ -z "$_cur_n2" ] || [ "$_cur_n2" = "null" ]; then
                        settings put system notification_sound_2 "$_not_uri" 2>/dev/null || true
                    fi
                fi
            fi
        fi
    fi
) >/dev/null 2>&1 &
