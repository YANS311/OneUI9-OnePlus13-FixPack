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
    stealth_bind_mount "$MODS_DIR/imsservice.apk" /system/priv-app/imsservice/imsservice.apk 0644
    rm -f /data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_0.xml /data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_1.xml
    killall com.sec.imsservice 2>/dev/null || true
fi

# 7. Ensure TGY cscfeature.xml mount (fallback if /optics mounted after post-fs-data)
if [ -f "$MODS_DIR/cscfeature.xml" ] && [ -f /optics/configs/carriers/TGY/conf/system/cscfeature.xml ]; then
    if ! grep -q '/optics/configs/carriers/TGY/conf/system/cscfeature.xml' /proc/mounts 2>/dev/null; then
        stealth_bind_mount "$MODS_DIR/cscfeature.xml" /optics/configs/carriers/TGY/conf/system/cscfeature.xml 0644
    else
        mount -o remount,ro,bind /optics/configs/carriers/TGY/conf/system/cscfeature.xml 2>/dev/null || true
        susfs_hide_mount /optics/configs/carriers/TGY/conf/system/cscfeature.xml
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
