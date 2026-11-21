#!/usr/bin/env python3
"""One-click PC ADB installer for OneUI 9.0 FixPack (OnePlus 13 PJZ110).

Pulls your device's own telephony-common.jar and imsservice.apk via ADB,
applies surgical patches locally, verifies ZIP/DEX integrity, and pushes
them to /data/adb/oneui9_mods/ for KernelSU module mounting.
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

from patch_imsservice import patch_imsservice_apk
from patch_telephony_sms import patch_jar_inplace


def run(cmd: list[str]) -> str:
    res = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return res.stdout.strip()


def main() -> int:
    ap = argparse.ArgumentParser(description="Apply OneUI 9.0 FixPack binary patches via ADB")
    ap.add_argument("--adb", default="adb", help="Path to adb executable")
    ap.add_argument("--reboot", action="store_true", help="Reboot device after pushing patches")
    args = ap.parse_args()

    adb = args.adb
    print("[1/5] Checking ADB device...")
    out = run([adb, "devices"])
    if "\tdevice" not in out:
        raise RuntimeError(f"No authorized ADB device found:\n{out}")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        tc_in, tc_out = tmp / "telephony-common.jar", tmp / "telephony-common-patched.jar"
        ims_in, ims_out = tmp / "imsservice.apk", tmp / "imsservice-patched.apk"

        print("[2/5] Pulling ROM telephony-common.jar & imsservice.apk...")
        run([adb, "pull", "/vendor/etc/oneui9/telephony-common.jar", str(tc_in)])
        run([adb, "pull", "/vendor/etc/oneui9/imsservice.apk", str(ims_in)])

        print("[3/5] Patching telephony-common.jar (SMS v3: CS/NAS + IMS SMS)...")
        stats = patch_jar_inplace(tc_in, tc_out)
        print(f"      -> {stats}")

        print("[4/5] Patching imsservice.apk (CTC_CN + CU_CN VoLTE dbr_timer=0, use_precondition=false)...")
        patched_profiles = patch_imsservice_apk(ims_in, ims_out)
        print(f"      -> {patched_profiles}")

        print("[5/5] Pushing patched files to /data/adb/oneui9_mods/...")
        run([adb, "shell", "mkdir -p /data/adb/oneui9_mods"])
        run([adb, "push", str(tc_out), "/data/adb/oneui9_mods/telephony-common.jar"])
        run([adb, "push", str(ims_out), "/data/adb/oneui9_mods/imsservice.apk"])
        run([
            adb, "shell",
            "chmod 644 /data/adb/oneui9_mods/telephony-common.jar /data/adb/oneui9_mods/imsservice.apk && "
            "chcon u:object_r:system_file:s0 /data/adb/oneui9_mods/telephony-common.jar /data/adb/oneui9_mods/imsservice.apk",
        ])

    if args.reboot:
        print("Rebooting device...")
        run([adb, "reboot"])
    else:
        print("Done! Reboot your phone to activate all patches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
