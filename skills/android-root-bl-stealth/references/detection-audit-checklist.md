# Root & Bootloader Detection Audit Checklist

## 1. Non-Root App-Perspective ADB Audit (`uid=2000`)

Run this script from `adb shell` (unprivileged `uid=2000`, matching what regular apps can inspect except where explicitly noted):

```sh
echo "=== Boot / AVB / Debug Props ==="
for p in ro.boot.verifiedbootstate ro.boot.vbmeta.device_state ro.boot.flash.locked \
         ro.boot.veritymode ro.boot.warranty_bit ro.warranty_bit \
         ro.secure ro.debuggable persist.service.debuggable \
         ro.build.tags ro.build.type ro.crypto.state; do
  echo "$p=$(getprop "$p")"
done

echo "=== Boot cmdline (serial redacted) ==="
sed 's/serialno=[^ ]*/serialno=REDACTED/g' /proc/cmdline 2>/dev/null \
  | tr ' ' '\n' | grep -iE "verified|vbmeta|lock|verity|selinux|ksu|warranty"

echo "=== Mountinfo /adb or rw system leaks ==="
grep -E '/adb/|zygisk|magisk|kernelsu|lsposed|/local/tmp/' /proc/self/mountinfo
awk '$5 ~ /^\/(system|vendor|system_ext|odm|optics)\// && $6 ~ /(^|,)rw(,|$)/ {print "RW_MOUNT:", $5, $6}' /proc/self/mountinfo

echo "=== Visible Root/Hide Packages ==="
pm list packages | grep -iE "ksu|kernelsu|sukisu|magisk|lsposed|zygisk|shamiko|tricky|hma|applist|momo|native|detector|integrity" | sort
```

## 2. Detector Symptom -> Root Cause -> Fix Matrix

| Symptom / Detector Signal | Root Cause | Safe Remediation |
| :--- | :--- | :--- |
| **`/adb/...` or `zygisk_lsposed` in `mountinfo`** | Custom `mount -o bind` from `/data/adb/...` or legacy `zygisk_lsposed` `dex2oat` mount | Move custom module sources to `/data/misc/<neutral>/` with `remount,ro,bind`; replace `zygisk_lsposed` with `ReZygisk` + `JingMatrix LSPosed`; enable KernelSU `umount` + SUSFS if kernel supports it |
| **`rw` flag on `/system/...`, `/vendor/...`, `/optics/...` mount** | Manual `mount -o bind` without `-o remount,ro,bind` | Always run `mount -o remount,ro,bind <target>` after binding |
| **`persist.service.debuggable=1` or empty `vbmeta.device_state`** | Debug prop set late by vendor/port scripts or omitted by unlocked bootloader | `resetprop -n` in both `post-fs-data.sh` & `service.sh` |
| **App fails TEE / Hardware Key Attestation** | TEE returns `deviceLocked=false` / `verifiedBootState=Orange` despite spoofed props | Configure **TrickyStore** (`target.txt`) with valid on-device keybox + **PlayIntegrityFork** (`PIF`) |
| **App detects `me.weishu.kernelsu` / HMA via `PackageManager`** | Visible package query across user apps | Configure **Hide My Applist (HMA OSS)** filter per banking/detector app; test with KernelSU manager hidden/stub if supported |
| **CN Banking app flags DFE `ro.crypto.state=unsupported`** | ROM runs unencrypted (`DFE`) | Treat carefully: never use global `resetprop ro.crypto.state encrypted` (can break `vold` / lockscreen). Only target specific app hooks if ever needed |
| **Ported ROM artifacts (`/vendor/etc/oneui9`, `/local/tmp/sales_code.dat`)** | Baked into vendor image / early `init.rc` scripts | Cannot be hidden purely in userspace without kernel SUSFS `add_sus_mount` + path hiding; balance SUSFS kernel need against `vendor_dlkm`/camera HAL stability |
