#!/system/bin/sh
# OneUI 9.0 FixPack for OnePlus 13 (PJZ110 / dodge) - Installer
SKIPUNZIP=0

MODS_DIR="/data/adb/oneui9_mods"
mkdir -p "$MODS_DIR"

ui_print "************************************************"
ui_print "  OneUI 9.0 FixPack for OnePlus 13 (PJZ110)"
ui_print "************************************************"

# 1. Generate clean eUICC permission XMLs (removes fake eSIM on Dual Physical SIM)
if [ -f /system/etc/permissions/privapp-permissions-com.samsung.euicc.xml ]; then
    sed '/android.hardware.telephony.euicc/d' /system/etc/permissions/privapp-permissions-com.samsung.euicc.xml > "$MODS_DIR/privapp-permissions-com.samsung.euicc.xml"
    ui_print "- Patched privapp-permissions-com.samsung.euicc.xml"
fi
if [ -f /system/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml ]; then
    sed '/android.hardware.telephony.euicc/d' /system/etc/permissions/privapp-permissions-com.samsung.euicc.mep.xml > "$MODS_DIR/privapp-permissions-com.samsung.euicc.mep.xml"
    ui_print "- Patched privapp-permissions-com.samsung.euicc.mep.xml"
fi

# 2. Generate clean floating_feature.xml (removes tsds2 eSIM slot-switch)
FF_SRC="/vendor/etc/oneui9/floating_feature.xml"
[ ! -f "$FF_SRC" ] && FF_SRC="/system/etc/floating_feature.xml"
if [ -f "$FF_SRC" ]; then
    sed '/SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH/d' "$FF_SRC" > "$MODS_DIR/floating_feature.xml"
    ui_print "- Patched floating_feature.xml (removed tsds2 eSIM slot switch)"
fi

# 3. Generate patched camera-feature.xml (unlock 60fps + fix 9:16 4000x2252 -> 3840x2160)
CF_SRC="/vendor/etc/oneui9/camera-feature.xml"
[ ! -f "$CF_SRC" ] && CF_SRC="/system/cameradata/camera-feature.xml"
if [ -f "$CF_SRC" ]; then
    sed -e '/_60FPS/s/value="false"/value="true"/g' \
        -e 's/value="4000x2252"/value="3840x2160"/g' \
        "$CF_SRC" > "$MODS_DIR/camera-feature.xml"
    ui_print "- Patched camera-feature.xml (60fps unlocked + 9:16 3840x2160)"
fi

# 4. Install hardened callbridge_auto.sh (0.3s fast pickup + race-free relay)
if [ -f "$MODPATH/scripts/callbridge_auto.sh" ]; then
    cp -f "$MODPATH/scripts/callbridge_auto.sh" "$MODS_DIR/callbridge_auto.sh"
    chmod 0755 "$MODS_DIR/callbridge_auto.sh"
    ui_print "- Installed hardened callbridge_auto.sh"
fi

# Fix permissions & SELinux labels
chmod 0644 "$MODS_DIR"/*.xml 2>/dev/null || true
chcon -R u:object_r:system_file:s0 "$MODS_DIR" 2>/dev/null || true
chmod 0755 "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" "$MODPATH/uninstall.sh" 2>/dev/null || true

ui_print "- Note: For DEX binary patches (SMS v3, CTC/CU VoLTE, Clock Seconds),"
ui_print "  run 'python patchers/apply_via_adb.py' from PC once, then reboot."
ui_print "- Done! Reboot to apply all changes."
