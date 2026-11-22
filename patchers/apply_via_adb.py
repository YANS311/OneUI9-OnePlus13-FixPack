#!/usr/bin/env python3
"""One-click PC ADB installer for OneUI 9.0 FixPack (OnePlus 13 PJZ110).

Pulls your device's own framework/telephony/SystemUI/CSC files via ADB, applies
all surgical binary & OMC CSC patches locally, verifies ZIP/DEX integrity, and
either pushes directly to /data/adb/oneui9_mods/ (if ADB shell has root) or
stages them to /sdcard/Download/OneUI9_v1.2.1/ for KernelSU module installation.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

_HERE = str(Path(__file__).resolve().parent)
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from patch_cscfeature import patch_cscfeature_file
from patch_imsservice import patch_imsservice_apk
from patch_systemui_seconds import patch_systemui_apk_inplace
from patch_telephony_sms import patch_jar_inplace

STAGE_SDCARD_DIR = "/sdcard/Download/OneUI9_v1.2.1"
MODS_DIR = "/data/adb/oneui9_mods"


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def pull_first_available(adb: str, candidates: list[str], dst: Path) -> str:
    for remote in candidates:
        res = run([adb, "pull", remote, str(dst)], check=False)
        if res.returncode == 0 and dst.exists():
            return remote
    raise RuntimeError(f"Failed to pull any of {candidates}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Apply OneUI 9.0 FixPack v1.2.1 binary & CSC patches via ADB")
    ap.add_argument("--adb", default="adb", help="Path to adb executable")
    ap.add_argument("--reboot", action="store_true", help="Reboot device if pushed directly as root")
    args = ap.parse_args()

    adb = args.adb
    print("[1/7] Checking ADB device...")
    out = run([adb, "devices"]).stdout.strip()
    if "\tdevice" not in out:
        raise RuntimeError(f"No authorized ADB device found:\n{out}")

    uid = run([adb, "shell", "id -u"]).stdout.strip()
    has_root = uid == "0"

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        tc_in, tc_out = tmp / "telephony-common.jar", tmp / "telephony-common-patched.jar"
        ims_in, ims_out = tmp / "imsservice.apk", tmp / "imsservice-patched.apk"
        ui_in, ui_out = tmp / "SystemUI.apk", tmp / "SystemUI-patched.apk"
        fw_in = tmp / "framework.jar"
        csc_in, csc_out = tmp / "cscfeature.bin", tmp / "cscfeature.xml"

        print("[2/7] Pulling device ROM binaries & CSC config...")
        tc_src = pull_first_available(
            adb,
            ["/vendor/etc/oneui9/telephony-common.jar", "/system/framework/telephony-common.jar"],
            tc_in,
        )
        ims_src = pull_first_available(
            adb,
            ["/vendor/etc/oneui9/imsservice.apk", "/system/priv-app/imsservice/imsservice.apk"],
            ims_in,
        )
        run([adb, "pull", "/system/system_ext/priv-app/SystemUI/SystemUI.apk", str(ui_in)])
        run([adb, "pull", "/system/framework/framework.jar", str(fw_in)])
        csc_src = pull_first_available(
            adb,
            [
                "/optics/configs/carriers/TGY/conf/system/cscfeature.xml",
                "/optics/configs/carriers/single/TGY/conf/system/cscfeature.xml",
            ],
            csc_in,
        )
        print(f"      -> Pulled from {tc_src}, {ims_src}, {csc_src}")

        outputs: list[tuple[Path, str]] = []

        print("[3/7] Patching telephony-common.jar (SMS v3: CS/NAS + IMS SMS)...")
        try:
            stats = patch_jar_inplace(tc_in, tc_out)
            print(f"      -> {stats}")
            outputs.append((tc_out, "telephony-common.jar"))
        except RuntimeError as exc:
            print(f"      -> skipped ({exc}; already patched on device?)")

        print("[4/7] Patching imsservice.apk (CTC_CN + CU_CN VoLTE dbr_timer=0, use_precondition=false)...")
        patched_profiles = patch_imsservice_apk(ims_in, ims_out)
        print(f"      -> {patched_profiles}")
        outputs.append((ims_out, "imsservice.apk"))

        print("[5/7] Patching SystemUI.apk (permanent status bar & QS clock seconds)...")
        ui_stats = patch_systemui_apk_inplace(ui_in, ui_out)
        print(f"      -> {ui_stats}")
        outputs.append((ui_out, "SystemUI.apk"))

        print("[6/7] Decoding & enhancing TGY cscfeature.xml...")
        csc_changes, was_encoded = patch_cscfeature_file(csc_in, csc_out, framework_jar=fw_in)
        print(f"      -> decoded_omc={was_encoded}, changes={csc_changes}")
        outputs.append((csc_out, "cscfeature.xml"))

        if has_root:
            print(f"[7/7] Pushing {len(outputs)} patched files to {MODS_DIR}/ (adb uid=0)...")
            run([adb, "shell", f"mkdir -p {MODS_DIR}"])
            pushed = []
            for local_f, remote_name in outputs:
                remote_path = f"{MODS_DIR}/{remote_name}"
                run([adb, "push", str(local_f), remote_path])
                pushed.append(remote_path)
            joined = " ".join(pushed)
            run([adb, "shell", f"chmod 644 {joined} && chcon u:object_r:system_file:s0 {joined}"])
            if args.reboot:
                print("Rebooting device...")
                run([adb, "reboot"])
            else:
                print("Done! Reboot your phone to activate all patches.")
        else:
            print(f"[7/7] ADB shell is non-root (uid={uid}); staging outputs to {STAGE_SDCARD_DIR}/...")
            run([adb, "shell", f"mkdir -p {STAGE_SDCARD_DIR}"])
            for local_f, remote_name in outputs:
                run([adb, "push", str(local_f), f"{STAGE_SDCARD_DIR}/{remote_name}"])
            print(
                f"Done! Flash OneUI9-OnePlus13-FixPack-v1.2.1.zip in KernelSU Manager;\n"
                f"customize.sh will automatically import all staged files from {STAGE_SDCARD_DIR}/."
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
