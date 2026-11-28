#!/system/bin/sh
# OneUI 9.0 FixPack for OnePlus 13 (PJZ110 / dodge) - Installer
SKIPUNZIP=0

MODS_DIR="/data/adb/oneui9_mods"
mkdir -p "$MODS_DIR"

ui_print "************************************************"
ui_print "  OneUI 9.0 FixPack for OnePlus 13 (PJZ110)"
ui_print "************************************************"

# 1. Generate clean eUICC permission XMLs atomically (avoids truncating live bind-mounted inodes)
if [ -f /system/etc/permissions/privapp-permissions-com.samsung.euicc.xml ]; then
    sed '/android.hardware.telephony.euicc/d' /system/etc/permissions/privapp-permissions-com.samsung.euicc.xml > "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml.tmp"
    if [ -s "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml.tmp" ]; then
        mv -f "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml.tmp" "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml"
        ui_print "- Patched privapp-permissions-com.samsung.euicc.xml"
    else
        rm -f "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml.tmp"
        ui_print "! Skipped empty privapp-permissions-com.samsung.euicc.xml"
    fi
fi
if [ -f /system/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml ]; then
    sed '/android.hardware.telephony.euicc/d' /system/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml > "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml.tmp"
    if [ -s "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml.tmp" ]; then
        mv -f "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml.tmp" "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml"
        ui_print "- Patched privapp-permissions-com.samsung.euicc.mep.xml"
    else
        rm -f "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml.tmp"
        ui_print "! Skipped empty privapp-permissions-com.samsung.euicc.mep.xml"
    fi
fi

# 2. Generate clean floating_feature.xml atomically (removes tsds2 eSIM slot-switch)
FF_SRC="/vendor/etc/oneui9/floating_feature.xml"
[ ! -f "$FF_SRC" ] && FF_SRC="/system/etc/floating_feature.xml"
if [ -f "$FF_SRC" ]; then
    sed '/SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH/d' "$FF_SRC" > "$MODS_DIR/floating_feature.xml.tmp"
    if [ -s "$MODS_DIR/floating_feature.xml.tmp" ]; then
        mv -f "$MODS_DIR/floating_feature.xml.tmp" "$MODS_DIR/floating_feature.xml"
        ui_print "- Patched floating_feature.xml (removed tsds2 eSIM slot switch)"
    else
        rm -f "$MODS_DIR/floating_feature.xml.tmp"
        ui_print "! Skipped empty floating_feature.xml"
    fi
fi

# 3. Generate patched camera-feature.xml atomically (unlock 60fps + fix 9:16 4000x2252 -> 3840x2160)
CF_SRC="/vendor/etc/oneui9/camera-feature.xml"
[ ! -f "$CF_SRC" ] && CF_SRC="/system/cameradata/camera-feature.xml"
if [ -f "$CF_SRC" ]; then
    sed -e '/_60FPS/s/value="false"/value="true"/g' \
        -e 's/value="4000x2252"/value="3840x2160"/g' \
        "$CF_SRC" > "$MODS_DIR/camera-feature.xml.tmp"
    if [ -s "$MODS_DIR/camera-feature.xml.tmp" ]; then
        mv -f "$MODS_DIR/camera-feature.xml.tmp" "$MODS_DIR/camera-feature.xml"
        ui_print "- Patched camera-feature.xml (60fps unlocked + 9:16 3840x2160)"
    else
        rm -f "$MODS_DIR/camera-feature.xml.tmp"
        ui_print "! Skipped empty camera-feature.xml"
    fi
fi

# 4. Install hardened callbridge_auto.sh + hardware daemons + stealth library + USB bridge
for s in callbridge_auto.sh alert_slider.sh power_guard.sh stealth_lib.sh oneui9_usb.sh; do
    if [ -f "$MODPATH/scripts/$s" ]; then
        cp -f "$MODPATH/scripts/$s" "$MODS_DIR/$s"
        chmod 0755 "$MODS_DIR/$s"
        ui_print "- Installed $s"
    fi
done

# 5. Initialize power.conf (preserve user preferences across upgrades)
if [ ! -f "$MODS_DIR/power.conf" ]; then
    cat <<'EOF' > "$MODS_DIR/power.conf"
BYPASS_MODE=0
CHARGE_LIMIT=0
RESUME_DELTA=5
SLIDER_ENABLED=1
STEALTH_PROPS=1
EOF
    chmod 0644 "$MODS_DIR/power.conf"
    ui_print "- Initialized default power.conf"
elif ! grep -q '^STEALTH_PROPS=' "$MODS_DIR/power.conf" 2>/dev/null; then
    printf '\nSTEALTH_PROPS=1\n' >> "$MODS_DIR/power.conf"
    ui_print "- Enabled STEALTH_PROPS=1 in existing power.conf"
fi

# 6. Install staged binary/CSC patches atomically from /sdcard/Download/OneUI9_v1.1.0 .. v1.3.0
for STAGE_DIR in /sdcard/Download/OneUI9_v1.1.0 /sdcard/Download/OneUI9_v1.2.0 /sdcard/Download/OneUI9_v1.2.1 /sdcard/Download/OneUI9_v1.2.2 /sdcard/Download/OneUI9_v1.3.0; do
    for f in cscfeature.xml telephony-common.jar imsservice.apk SystemUI.apk; do
        if [ -s "$STAGE_DIR/$f" ]; then
            cp -f "$STAGE_DIR/$f" "$MODS_DIR/$f.tmp" && mv -f "$MODS_DIR/$f.tmp" "$MODS_DIR/$f"
            chmod 0644 "$MODS_DIR/$f"
            ui_print "- Installed staged patch from ${STAGE_DIR##*/}: $f"
        fi
    done
done

# 7. Clean up legacy standalone boot scripts from early hotfixes to prevent double execution
rm -f /data/adb/post-fs-data.d/oneui9_camerax_fix.sh /data/adb/service.d/oneui9_cam60.sh

# Fix permissions & SELinux labels
chmod 0644 "$MODS_DIR"/*.xml "$MODS_DIR"/*.conf 2>/dev/null || true
chmod 0755 "$MODS_DIR"/*.sh 2>/dev/null || true
chcon -R u:object_r:system_file:s0 "$MODS_DIR" 2>/dev/null || true
chmod 0755 "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" "$MODPATH/uninstall.sh" "$MODPATH/scripts"/*.sh 2>/dev/null || true

# 8. Live-activate USB ConfigFS MTP/PTP/ADB bridge immediately on flash (no reboot needed)
if [ -x "$MODS_DIR/oneui9_usb.sh" ]; then
    if [ -f "$MODS_DIR/stealth_lib.sh" ] && [ -f /vendor/bin/oneui9_usb.sh ]; then
        # shellcheck disable=SC1090,SC1091
        . "$MODS_DIR/stealth_lib.sh"
        stealth_bind_mount "$MODS_DIR/oneui9_usb.sh" /vendor/bin/oneui9_usb.sh 0755
    fi
    pkill -f 'oneui9_usb\.sh' 2>/dev/null || true
    rm -f /data/local/tmp/.oneui9_usb.pid 2>/dev/null || true
    rmdir /data/local/tmp/.oneui9_usb.lock 2>/dev/null || true
    nohup "$MODS_DIR/oneui9_usb.sh" >/dev/null 2>&1 &
    ui_print "- Activated USB ConfigFS MTP/PTP/ADB bridge live!"
fi

ui_print "- KernelSU WebUI dashboard is ready: tap 'Open' on the module card!"
ui_print "- Note: For DEX binary patches (SMS v3, CTC/CU VoLTE, Clock Seconds),"
ui_print "  run 'python patchers/apply_via_adb.py' from PC once, then reboot."
ui_print "- Done! Reboot to apply all changes."
