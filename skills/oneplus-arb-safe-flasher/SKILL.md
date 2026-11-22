---
name: oneplus-arb-safe-flasher
description: Pre-flight safety checker for flashing firmware, kernels, or ROM ports onto Qualcomm Anti-Rollback (ARB) enforced OnePlus devices (especially Snapdragon 8 Elite / SM8750 / OnePlus 13 PJZ110). Use before recommending or executing any fastboot flash, EDL payload, firmware update, or bootloader/baseband downgrade.
---

# OnePlus Qualcomm ARB Safe Flasher

Protect devices from **irreversible Qualcomm Anti-Rollback (ARB) fuse blow** and hard-bricks (`QPST/9008` lockout) when flashing stock firmware, ColorOS upgrades, or cross-OEM ROM ports (such as OneUI).

## Hard Safety Rules (Zero Exceptions)

1. **Know the Partition Risk Matrix**:
   - **CRITICAL / ARB-FUSED (NEVER flash blindly or upgrade across major OS generations unless intentionally committing to that ARB floor)**:
     - `abl`, `xbl`, `xbl_config`, `xbl_ramdump`, `shrm`, `tz`, `hyp`, `aop`, `aop_config`, `devcfg`, `keymaster`, `qupfw`, `uefisecapp`, `cpucp`, `modem`, `dsp`, `featenabler`
   - **PORT / RUNTIME SAFE (typically safe to re-flash/swap without blowing XBL/TZ fuses)**:
     - `boot`, `init_boot`, `vendor_boot`, `dtbo`, `recovery`, `vbmeta`, `vbmeta_system`, `vbmeta_vendor`, and logical partitions inside `super` (`system`, `system_ext`, `product`, `vendor`, `vendor_dlkm`, `odm`).

2. **OnePlus 13 (`PJZ110` / `dodge`) Known ARB Boundary**:
   - **ARB 0 Safe Baseline**: ColorOS `15.0.0.860` and earlier ColorOS 15 builds carry `ARB = 0`.
   - **Danger Zone**: ColorOS 16+ / newer Android 16+ full firmware zips increment the XBL/TZ/modem ARB index (`>= 1`). Flashing those critical firmware images even once blows eFuses inside the SoC, making any future downgrade to `15.0.0.860`-based ROM ports/kernels/EDL packages **permanently unbootable (EDL 9008 Sahara reject without authorized firehose)**.

3. **Kernel vs `vendor_dlkm` / Firmware ABI Matching**:
   - Do not flash a random newer GKI/AnyKernel build (e.g., `6.6.104`) on top of older `vendor_dlkm` + `15.0.0.860` firmware unless `vendor_dlkm` modules were built together with that exact kernel.
   - Symptoms of kernel/firmware mismatch: random `CAM-ICP DMI_STATUS` hangs during 60fps video, Wi-Fi/BT drops, or sudden black-screen PMIC resets.
   - If using `15.0.0.860` baseline firmware + `6.6.66-android15-8` stock-matched kernel + matching `vendor_dlkm`, leave working critical partitions untouched.

## Pre-Flash Verification Checklist

Before flashing any zip or `.img`:
- Inspect archive contents (`unzip -l` / payload dumper) to verify **whether critical `xbl`/`tz`/`abl`/`modem` images are included**.
- If a ROM port installer (`update-binary` / `super_flash.sh`) includes firmware images, **strip or comment out** critical ARB-fused partitions if your current firmware baseline already meets boot requirements.
- Verify slot alignment (`fastboot getvar current-slot`) and check vbmeta disable flags (`--disable-verity --disable-verification`) when swapping `boot`/`vendor_boot`/`dtbo`.
- Ensure `/vendor/etc/fstab.qcom` removes non-existent OEM partitions (`my_*`) and handles userdata encryption cleanly before rebooting from recovery.
