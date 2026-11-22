#!/system/bin/sh
# Runs early in post-fs-data BEFORE Zygote & PackageManager scan permissions/jars
MODDIR=${0%/*}
MODS_DIR="/data/adb/oneui9_mods"

if [ -f "$MODDIR/scripts/stealth_lib.sh" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$MODDIR/scripts/stealth_lib.sh"
elif [ -f "$MODS_DIR/stealth_lib.sh" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$MODS_DIR/stealth_lib.sh"
fi

# 0. Harden Bootloader / Debuggable properties before Zygote reads Build props
apply_stealth_props

# 1. Fix WeChat / OneDrive / Kotlin App crash caused by /odm/framework/androidx.camera.extensions.impl.fake.jar
if [ -f /system/framework/sec_camerax_impl.jar ] && [ -f /odm/framework/androidx.camera.extensions.impl.fake.jar ]; then
    umount /odm/framework/androidx.camera.extensions.impl.fake.jar 2>/dev/null || true
    mount -o bind /system/framework/sec_camerax_impl.jar /odm/framework/androidx.camera.extensions.impl.fake.jar
    mount -o remount,ro,bind /odm/framework/androidx.camera.extensions.impl.fake.jar 2>/dev/null || true
    susfs_hide_mount /odm/framework/androidx.camera.extensions.impl.fake.jar
fi

# 2. Remove eUICC/eSIM system features before PackageManager scans /system/etc/permissions
if [ -f "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml" ]; then
    stealth_bind_mount "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml" /system/etc/permissions/privapp-permissions-com.samsung.euicc.xml 0644
fi
if [ -f "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml" ]; then
    stealth_bind_mount "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml" /system/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml 0644
fi

# 3. Stealth-mount SMS-fixed telephony-common.jar before vendor init bind-mounts it onto /system/framework/
if [ -f "$MODS_DIR/telephony-common.jar" ] && [ -f /vendor/etc/oneui9/telephony-common.jar ]; then
    stealth_bind_mount "$MODS_DIR/telephony-common.jar" /vendor/etc/oneui9/telephony-common.jar 0644
fi

# 4. Stealth-mount patched SystemUI.apk (permanent status bar & QS clock seconds) before SystemUI starts
if [ -f "$MODS_DIR/SystemUI.apk" ] && [ -f /system/system_ext/priv-app/SystemUI/SystemUI.apk ]; then
    stealth_bind_mount "$MODS_DIR/SystemUI.apk" /system/system_ext/priv-app/SystemUI/SystemUI.apk 0644
fi

# 5. Stealth-mount hardened callbridge_auto.sh (0.3s fast pickup + race-free RTP relay)
if [ -f "$MODS_DIR/callbridge_auto.sh" ] && [ -f /vendor/etc/oneui9/callbridge_auto.sh ]; then
    stealth_bind_mount "$MODS_DIR/callbridge_auto.sh" /vendor/etc/oneui9/callbridge_auto.sh 0755
fi

# 6. Stealth-mount enhanced plaintext TGY cscfeature.xml (Call Recording, 50Hz, Network Speed, App Lock)
if [ -f "$MODS_DIR/cscfeature.xml" ] && [ -f /optics/configs/carriers/TGY/conf/system/cscfeature.xml ]; then
    stealth_bind_mount "$MODS_DIR/cscfeature.xml" /optics/configs/carriers/TGY/conf/system/cscfeature.xml 0644
fi
