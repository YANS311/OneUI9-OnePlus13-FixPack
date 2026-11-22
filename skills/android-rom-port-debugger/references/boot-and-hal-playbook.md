# Boot, RIL, Camera HAL & Mount-Timing Playbook

## 1. KernelSU / Magisk Bind-Mount Timing Matrix

| Stage | Timing | What Runs Here | Required Mounts |
| :--- | :--- | :--- | :--- |
| `post-fs-data.sh` | Before Zygote & `system_server` | Blocking; SELinux & `/data` ready | Classpath jars (`sec_camerax_impl.jar`), `telephony-common.jar`, `privapp-permissions-*.xml`, `SystemUI.apk`, `cscfeature.xml` |
| `service.sh` | After `sys.boot_completed=1` | Non-blocking background | `setprop ril.ICC_TYPE*`, `content update` IMS DB, `imsservice.apk` remount + `killall com.sec.imsservice`, `camera-feature.xml`, hardware daemons (`alert_slider.sh`, `power_guard.sh`) |

> **Pitfall**: Never write `adb` push helpers assuming `/vendor/etc/oneui9/` mounts haven't overlaid `/system/framework/` — always verify both `/vendor/etc/oneui9/` and `/system/framework/` paths, and clean up legacy `/data/adb/post-fs-data.d/` or `service.d/` hotfix scripts inside `customize.sh` to avoid duplicate execution.

## 2. Diagnostic One-Liners

```sh
# Radio & IMS SMS / VoLTE debugging
adb logcat -b radio -b main -v time | grep -E "SmsDispatcher|ImsSms|SemCi|imsprofile|SIP"

# Camera HAL stream / ICP crashes
adb logcat -b main -d | grep -E "CameraService|CamX|CHIUSECASE|ICP"
adb shell dmesg | grep -E "CAM-ICP|DMI_STATUS|cam_sync"

# Find input event device by name without hardcoding eventX
awk '/^N: Name=/{m=($0~/oplus,hall_tri_state_key/)} m && /^H: Handlers=/{print $0; exit}' /proc/bus/input/devices

# Verify live bind-mounts inside KernelSU
grep -E "camerax|telephony-common|imsservice|SystemUI|cscfeature|camera-feature" /proc/mounts
```

## 3. Samsung OMC `cscfeature.xml` Dynamic Decoding
1. Pull `/system/framework/framework.jar` and locate `Lcom/samsung/android/feature/SemCscFeature;` (search `classes*.dex`).
2. Decode `fill-array-data` payloads in `<init>` assigned to `salts:[B` and `shifts:[B` (each 256 bytes).
3. For byte `b` at index `i`:
   - `rot = shifts[i & 0xff] & 7`
   - `decrypted = (((b << rot) | (b >> (8 - rot))) & 0xff) ^ salts[i & 0xff]`
4. Decompress result with `gzip`.
5. `SemCscFeature.isXmlEncoded()` accepts plaintext XML starting with `<?xml`, so clean UTF-8 `<?xml version="1.0" encoding="utf-8"?>` output works directly on bind-mount without re-encrypting.
