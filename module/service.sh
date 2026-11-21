#!/system/bin/sh
# Runs after boot_completed=1 so vendor init & settings provider are fully ready
MODS_DIR="/data/adb/oneui9_mods"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done
sleep 5

# 1. Ensure CameraX Kotlin fix
if [ -f /system/framework/sec_camerax_impl.jar ] && [ -f /odm/framework/androidx.camera.extensions.impl.fake.jar ]; then
    umount /odm/framework/androidx.camera.extensions.impl.fake.jar 2>/dev/null || true
    mount -o bind /system/framework/sec_camerax_impl.jar /odm/framework/androidx.camera.extensions.impl.fake.jar
fi

# 2. Ensure clean floating_feature.xml (no tsds2 eSIM slot switch) & Samsung RIL ICC_TYPE props
if [ -f "$MODS_DIR/floating_feature.xml" ]; then
    umount /system/etc/floating_feature.xml 2>/dev/null || true
    mount -o bind "$MODS_DIR/floating_feature.xml" /system/etc/floating_feature.xml
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

# 3. Samsung Camera 60fps unlock + 9:16 3840x2160 fix
if [ -f "$MODS_DIR/camera-feature.xml" ]; then
    umount /system/cameradata/camera-feature.xml 2>/dev/null || true
    mount -o bind "$MODS_DIR/camera-feature.xml" /system/cameradata/camera-feature.xml
fi

# 4. Ensure permanent clock seconds setting (when patched SystemUI.apk is present)
if [ -f "$MODS_DIR/SystemUI.apk" ]; then
    settings put secure icon_blacklist "rotate,headset,slimindicator_show_seconds" 2>/dev/null || true
fi

# 5. Enable SMS over IP (IMS SMS) on both SIM slots
content update --uri 'content://com.sec.ims.settings/global#simslot0' --bind sms_over_ip_indication:i:1 --bind enable_default_sms_fallback:i:1 >/dev/null 2>&1 || true
content update --uri 'content://com.sec.ims.settings/global#simslot1' --bind sms_over_ip_indication:i:1 --bind enable_default_sms_fallback:i:1 >/dev/null 2>&1 || true

# 6. Mount patched imsservice.apk (CMCC + CTC + CU dbr_timer=0 & use_precondition=false)
if [ -f "$MODS_DIR/imsservice.apk" ] && [ -f /system/priv-app/imsservice/imsservice.apk ]; then
    umount /system/priv-app/imsservice/imsservice.apk 2>/dev/null || true
    mount -o bind "$MODS_DIR/imsservice.apk" /system/priv-app/imsservice/imsservice.apk
    rm -f /data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_0.xml /data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_1.xml
    killall com.sec.imsservice 2>/dev/null || true
fi
