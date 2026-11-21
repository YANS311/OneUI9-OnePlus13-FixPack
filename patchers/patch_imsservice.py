#!/usr/bin/env python3
"""Patches res/raw/imsprofile.json inside Samsung imsservice.apk for CTC_CN & CU_CN VoLTE calls.

Sets dbr_timer=0 (prevents 6-second auto-hangup) and use_precondition=false
(prevents 183 Session Progress QoS stall where remote never rings) on
China Telecom (CTC_CN), China Unicom (CU_CN), and China Mobile (CMCC_CN).
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path


def patch_imsprofile_json(raw_json: str) -> tuple[str, list[str]]:
    data = json.loads(raw_json)
    patched: list[str] = []
    for p in data.get("profile", []):
        name = p.get("name", "")
        mno = p.get("mnoname", "")
        if mno in ("CTC_CN", "CU_CN", "CMCC_CN") and "Mobile" in name:
            if p.get("dbr_timer") != 0 or p.get("use_precondition") is not False:
                p["dbr_timer"] = 0
                p["use_precondition"] = False
                patched.append(f"{name} ({mno})")
    return json.dumps(data, ensure_ascii=False, indent=2), patched


def patch_imsservice_apk(src_path: Path, dst_path: Path) -> list[str]:
    with zipfile.ZipFile(src_path, "r") as zin:
        raw_json = zin.read("res/raw/imsprofile.json").decode("utf-8")
        new_json, patched = patch_imsprofile_json(raw_json)
        new_bytes = new_json.encode("utf-8")
        with zipfile.ZipFile(dst_path, "w") as zout:
            for info in zin.infolist():
                buf = new_bytes if info.filename == "res/raw/imsprofile.json" else zin.read(info.filename)
                zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                zi.compress_type = info.compress_type
                zi.external_attr = info.external_attr
                zout.writestr(zi, buf)
    with zipfile.ZipFile(dst_path, "r") as z:
        if z.testzip() is not None:
            raise RuntimeError("Patched imsservice.apk failed ZIP integrity check")
    return patched


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input imsservice.apk> <output imsservice.apk>")
        return 2
    patched = patch_imsservice_apk(Path(sys.argv[1]), Path(sys.argv[2]))
    print(f"Patched imsservice.apk profiles: {patched}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
