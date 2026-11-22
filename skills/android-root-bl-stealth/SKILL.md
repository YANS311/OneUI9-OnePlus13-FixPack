---
name: android-root-bl-stealth
description: Systematic auditor and hardening guide for Android Root, Bootloader, and environment detection bypass. Use when diagnosing mountinfo leaks, Verified Boot/AVB/debuggable property anomalies, Zygisk/LSPosed traces, Hide My Applist (HMA) isolation, TrickyStore Key Attestation, Play Integrity, or SUSFS vs kernel ABI trade-offs on KernelSU/Magisk and cross-OEM ROM ports.
---

# Android Root & Bootloader Stealth Auditor

Diagnose and fix environment detection leaks from the **non-root app perspective (`uid=2000` / unprivileged app sandbox)** rather than blindly piling up overlapping hide modules that conflict with each other.

## Six-Layer Stealth Architecture

### Layer 1: Bootloader, AVB & Debuggable Properties
- Detectors read `ro.boot.*` and build properties via libc `__system_property_get` (bypassing Binder) as well as Java `SystemProperties`.
- Use KernelSU `resetprop -n` (direct property area mmap mutation) early in `post-fs-data.sh` and re-verify in `service.sh` for late overrides (e.g., `persist.service.debuggable`):
  - `ro.boot.verifiedbootstate=green`
  - `ro.boot.flash.locked=1`
  - `ro.boot.vbmeta.device_state=locked`
  - `ro.boot.veritymode=enforcing`
  - `ro.boot.warranty_bit=0`, `ro.warranty_bit=0`
  - `ro.secure=1`, `ro.debuggable=0`, `persist.service.debuggable=0`
  - `ro.build.tags=release-keys`, `ro.build.type=user`
- **Hard Red Line on DFE ROMs**: On Decrypted/DFE ports where `ro.crypto.state=unsupported`, **never globally spoof `ro.crypto.state=encrypted`** via `resetprop` — doing so can desync `vold`/Keyguard/lockscreen credential flows and cause PIN unlock loops.

### Layer 2: `/proc/self/mountinfo` Hygiene
- Even with KernelSU Umount enabled, **manual `mount -o bind` commands executed inside custom `post-fs-data.sh` / `service.sh` scripts are visible in every app's `/proc/self/mountinfo`**.
- **Rule 1 — Never bind-mount directly from `/data/adb/*`**: Any line in `/proc/self/mountinfo` showing `/adb/oneui9_mods/...` or `/adb/modules/...` immediately flags root to basic native scanners. Stage runtime copies into a neutral directory (e.g., `/data/misc/oneui_rt/`) with `0644` / `u:object_r:system_file:s0`.
- **Rule 2 — Always lock system bind-mounts read-only**: Immediately after `mount -o bind`, run `mount -o remount,ro,bind <target>` so read-only partitions (`/system`, `/vendor`, `/system_ext`, `/optics`) do not appear as `rw` mounts.
- **Rule 3 — Avoid stacked double-mounts**: Never keep legacy standalone `.d` scripts mounting the same target twice.
- **Rule 4 — SUSFS Hook**: When `/data/adb/ksu/bin/ksu_susfs` exists, automatically register `add_sus_mount <target>`.

### Layer 3: Kernel SUSFS vs `vendor_dlkm` / HAL Stability Trade-off
- Kernel-level SUSFS removes almost all `/proc/self/mountinfo` and `stat()` overlay fingerprints across namespaces.
- **Critical Port Warning (OnePlus / SM8750)**: Never blindly flash a random GKI/SUSFS kernel build over an older vendor baseline (e.g., `15.0.0.860` + `6.6.66-android15-8` `vendor_dlkm`) without rebuilt matching `vendor_dlkm` modules — ABI drift frequently triggers `CAM-ICP` 60fps camera crashes or PMIC resets. Only adopt SUSFS kernels compiled cleanly for the exact `vendor_dlkm` ABI.

### Layer 4: Zygisk & LSPosed / hosts Footprint
- Classic `zygisk_lsposed` mounts `/adb/modules/zygisk_lsposed/bin/dex2oat` globally across ART, exposing an obvious `/adb/modules/zygisk_lsposed` string in every app's `/proc/self/mountinfo`.
  - **Mitigation**: Migrate to modern Zygisk implementations (`ReZygisk` or `Zygisk Next` with proper unmount policy) and newer LSPosed builds (`JingMatrix LSPosed`) that avoid global `dex2oat` bind-mount leakage.
- Module `bindhosts` leaves `/adb/modules/bindhosts/system/etc/hosts` in `mountinfo`; switch to Private DNS (DoT) / VPN-less DNS or SUSFS-hidden mounts when facing strict detectors.

### Layer 5: App Package Visibility Isolation
- Standard APIs (`pm list packages` / `PackageManager.getInstalledPackages`) reveal `me.weishu.kernelsu`, `org.frknkrc44.hma_oss`, etc.
- Configure **Hide My Applist (HMA OSS)** whitelist/blacklist templates strictly against banking, gov, payment, and detector apps (never enable global system-wide hooks that destabilize `system_server`).

### Layer 6: Hardware Key Attestation & Play Integrity
- Bootloader lock (`KEY_VERIFIED_BOOT_STATE`) inside hardware TEE Keystore certificates cannot be fixed by `resetprop` alone.
- Pair **TrickyStore** (`target.txt` scoped to sensitive apps & GMS) + **PlayIntegrityFork** (`PIF`).
- Never bundle, commit, or redistribute proprietary TEE keybox XML files; keep user keyboxes strictly on-device.

See [references/detection-audit-checklist.md](references/detection-audit-checklist.md) for the non-root ADB live audit one-liner and detector-by-detector triage table.
