#!/system/bin/sh
# Runs early in post-fs-data BEFORE Zygote & PackageManager scan permissions/jars
MODS_DIR="/data/adb/oneui9_mods"

# 1. Fix WeChat / OneDrive / Kotlin App crash caused by /odm/framework/androidx.camera.extensions.impl.fake.jar
if [ -f /system/framework/sec_camerax_impl.jar ] && [ -f /odm/framework/androidx.camera.extensions.impl.fake.jar ]; then
    umount /odm/framework/androidx.camera.extensions.impl.fake.jar 2>/dev/null || true
    mount -o bind /system/framework/sec_camerax_impl.jar /odm/framework/androidx.camera.extensions.impl.fake.jar
fi

# 2. Remove eUICC/eSIM system features before PackageManager scans /system/etc/permissions
if [ -f "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml" ]; then
    umount /system/etc/permissions/privapp-permissions-com.samsung.euicc.xml 2>/dev/null || true
    mount -o bind "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml" /system/etc/permissions/privapp-permissions-com.samsung.euicc.xml
fi
if [ -f "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml" ]; then
    umount /system/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml 2>/dev/null || true
    mount -o bind "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml" /system/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml
fi

# 3. Mount SMS-fixed telephony-common.jar before vendor init bind-mounts it onto /system/framework/
if [ -f "$MODS_DIR/telephony-common.jar" ] && [ -f /vendor/etc/oneui9/telephony-common.jar ]; then
    mount -o bind "$MODS_DIR/telephony-common.jar" /vendor/etc/oneui9/telephony-common.jar
fi

# 4. Mount patched SystemUI.apk (permanent status bar & QS clock seconds) before SystemUI starts
if [ -f "$MODS_DIR/SystemUI.apk" ] && [ -f /system/system_ext/priv-app/SystemUI/SystemUI.apk ]; then
    umount /system/system_ext/priv-app/SystemUI/SystemUI.apk 2>/dev/null || true
    mount -o bind "$MODS_DIR/SystemUI.apk" /system/system_ext/priv-app/SystemUI/SystemUI.apk
fi

# 5. Mount hardened callbridge_auto.sh (0.3s fast pickup + race-free RTP relay)
if [ -f "$MODS_DIR/callbridge_auto.sh" ] && [ -f /vendor/etc/oneui9/callbridge_auto.sh ]; then
    mount -o bind "$MODS_DIR/callbridge_auto.sh" /vendor/etc/oneui9/callbridge_auto.sh
fi
