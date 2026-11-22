---
name: android-rom-port-debugger
description: Systematic root-cause debugger for cross-OEM Android ROM ports (e.g., Samsung OneUI ported onto OnePlus / Qualcomm hardware). Use when diagnosing bootloops, fstab encryption stalls, Kotlin app crashes, broken Dual SIM, failed SMS/VoLTE/IMS, camera 60fps/ratio crashes, audio call-bridge races, or adapting OEM hardware switches and charging controls.
---

# Android ROM Port Debugger

Diagnose cross-OEM ROM port defects systematically by layer rather than guessing symptoms. Most cross-vendor bugs come from **ABI/HAL mismatches**, **ClassLoader pollution**, **vendor init vs module mount races**, or **carrier XML/JSON/bytecode assumptions**.

## Diagnostic Triage Workflow

### 1. First-Screen Bootloop & Encryption Stalls
- Pull `/proc/last_kmsg` / `pstore` or inspect early init via recovery.
- Check `/vendor/etc/fstab.qcom` for leftover vendor dynamic/logical partitions (`my_product`, `my_stock`, `my_heytap`, `my_bigball`) that do not exist in the ported `super` image.
- Check `vold` logcat for vendor KeyMint extensions (e.g., `ISehKeyMintExtension`) hanging FBE decryption; apply DFE/metadata cleanup when port frameworks expect vendor KeyMint hardware absent on target bootloader.

### 2. Third-Party App Crashes (Kotlin / R8 / CameraX)
- Capture fatal crash tombstone/logcat (`adb logcat -b crash -d`).
- If obfuscated apps (WeChat, OneDrive, Kotlin apps) throw `NoSuchMethodError` or `NoSuchFieldError` on `kotlin.*` / `androidx.camera.extensions.*`:
  - Check `BOOTCLASSPATH` and `SYSTEMSERVERCLASSPATH` plus vendor/odm extension jars (`/odm/framework/androidx.camera.extensions.impl*.jar`).
  - Often an OEM vendor jar bundles un-obfuscated `kotlin-stdlib` into a parent ClassLoader, shadowing app R8 classes.
  - **Fix**: Bind-mount a clean framework/stub jar over the polluted `/odm/framework/...` jar in `post-fs-data.sh` (before Zygote starts).

### 3. Dual SIM, Outgoing SMS & VoLTE / IMS
- **Fake eSIM / Missing SIM 2**: Remove `android.hardware.telephony.euicc*` from `privapp-permissions`, strip `EMBEDDED_SIM_SLOTSWITCH` (`tsds2`) from `floating_feature.xml`, and align `ril.ICC_TYPE0` / `ril.ICC_TYPE1` in `service.sh` based on `gsm.sim.state`. Force-stop `com.samsung.android.app.telephonyui`.
- **SMS `RADIO_NOT_AVAILABLE` / `SMS_FAIL_RETRY`**: Check `adb logcat -b radio` for OEM RIL wrappers (`mSemCi` -> `ISehRadioMessaging`) vs QTI standard `CommandsInterface` (`mCi` -> `sendSMS*`), and check VoLTE-only carriers (`ImsSmsDispatcher.isAvailable()` stuck on `mIsSmsOverImsOnly`). Enable `sms_over_ip_indication=1` via IMS settings ContentProvider and patch DEX in-place (`dex-inplace-patcher`).
- **VoLTE 6-second drop or `183 Session Progress` stall**: Dump `imsservice.apk`'s `res/raw/imsprofile.json` and check all CN/regional mobile profiles (`CMCC_CN`, `CTC_CN`, `CU_CN`) for `dbr_timer: 0` and `use_precondition: false`. Always clear cached `imsprofile_*.xml` under `/data/user_de/0/com.sec.imsservice/shared_prefs/` when remounting.
- **Audio Call Bridge Race / Silent First Second**: Inspect RTP bridge daemons (`callbridge_auto.sh`). Tighten state polling (`0.3s`), stop both relay + bridge cleanly before relaunching, and cap log growth.

### 4. Camera 60fps & Resolution Crashes
- Diff `/vendor/etc/oneui9/camera-feature.xml` against target sensor HAL stream configurations.
- Unlock `_60FPS` toggles carefully, and remap donor aspect-ratio sizes (e.g., `4000x2252`) to hardware-supported 3-stream sizes (`3840x2160`).
- **Critical**: If 60fps video triggers kernel `CAM-ICP` / `DMI_STATUS` resets or sudden black-screen poweroff, verify kernel (`uname -r`) matches `vendor_dlkm` and camera firmware ABI. Do not mix mismatched major/sublevel kernels.

### 5. Target Hardware Adaptation & OMC CSC
- **Physical Alert Slider / Switches**: Query `/proc/bus/input/devices` + `getevent -pl` to trigger on kernel key events at **0% idle CPU polling**, read physical state node (`/proc/tristatekey/tri_state`), switch audio via `service call audio ...`, and pulse haptics via `cmd vibrator_manager`.
- **Bypass Charging**: Check `/sys/class/*chg*/battery/mmi_charging_enable` (or vendor charging enable node) rather than unreliable USB disconnect hacks.
- **OMC Encoded CSC XML**: Extract per-framework `salts`/`shifts` from `SemCscFeature.<init>` in `framework.jar` before attempting edits.

Read [references/boot-and-hal-playbook.md](references/boot-and-hal-playbook.md) for exact inspection commands and KernelSU bind-mount timing rules.
