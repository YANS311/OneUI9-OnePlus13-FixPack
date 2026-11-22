#!/usr/bin/env python3
"""In-place surgical DEX patcher for Samsung OneUI 9 SystemUI.apk (Clock Seconds).

Idempotently patches 3 sites in SystemUI's uncompressed `classes*.dex`:
1. `SlimIndicatorPluginMediator.<init>()`: sets `mIsSPluginConnected = true`
   (`const/4 vR, 0` -> `const/4 vR, 1` before `iput-boolean -> mIsSPluginConnected:Z`).
2. `QSClockQuickStarHelper.shouldShowSecondsClock()`: replaces method prologue
   with `const/4 v0, 1; return v0` (`0x1012, 0x000f`).
3. `QSClockIndicatorView.notifyTimeChanged(QSClockBellSound)`: swaps `iget-object`
   from `QSClockBellSound->TimeText:Ljava/lang/String;` to `->TimeTextWithSeconds`.

Preserves exact ZIP offsets/alignment for ART mmap and updates DEX + ZIP checksums.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
import zipfile
import zlib
from pathlib import Path

_HERE = str(Path(__file__).resolve().parent)
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from patch_cscfeature import _dalvik_insn_width
from patch_telephony_sms import _parse_dex_tables, _uleb128

TARGET_CLASSES = (
    "Lcom/android/systemui/slimindicator/SlimIndicatorPluginMediator;",
    "Lcom/android/systemui/statusbar/policy/QSClockQuickStarHelper;",
    "Lcom/android/systemui/statusbar/policy/QSClockIndicatorView;",
)


def patch_systemui_dex_bytes(dex_in: bytes) -> tuple[bytes, dict[str, int]]:
    """Patch Clock Seconds sites inside a single SystemUI DEX buffer idempotently."""
    stats = {
        "mediator_patched": 0,
        "mediator_already": 0,
        "helper_patched": 0,
        "helper_already": 0,
        "notify_patched": 0,
        "notify_already": 0,
    }
    if not any(tag in dex_in for tag in (b"SlimIndicatorPluginMediator", b"QSClockQuickStarHelper", b"QSClockIndicatorView")):
        return dex_in, stats

    dex = bytearray(dex_in)
    t = _parse_dex_tables(dex)

    fid_conn = fid_time_text = fid_time_sec = None
    for fid in range(t["field_cnt"]):
        fs = t["field_sig"](fid)
        if fs == "Lcom/android/systemui/slimindicator/SlimIndicatorPluginMediator;->mIsSPluginConnected:Z":
            fid_conn = fid
        elif fs == "Lcom/android/systemui/statusbar/policy/QSClockBellSound;->TimeText:Ljava/lang/String;":
            fid_time_text = fid
        elif fs == "Lcom/android/systemui/statusbar/policy/QSClockBellSound;->TimeTextWithSeconds:Ljava/lang/String;":
            fid_time_sec = fid

    changed = False
    for i in range(t["cls_cnt"]):
        cidx, _, _, _, _, _, cdoff, _ = struct.unpack_from("<IIIIIIII", dex, t["cls_off"] + i * 32)
        if not cdoff or t["types"][cidx] not in TARGET_CLASSES:
            continue

        p = cdoff
        sf, p = _uleb128(dex, p)
        inf, p = _uleb128(dex, p)
        dm, p = _uleb128(dex, p)
        vm, p = _uleb128(dex, p)
        for _ in range(sf + inf):
            _, p = _uleb128(dex, p)
            _, p = _uleb128(dex, p)

        for cnt in (dm, vm):
            mid = 0
            for _ in range(cnt):
                diff, p = _uleb128(dex, p)
                mid += diff
                _, p = _uleb128(dex, p)
                coff, p = _uleb128(dex, p)
                if not coff:
                    continue

                msig = t["method_sig"](mid)
                regs_size = struct.unpack_from("<H", dex, coff)[0]
                insns_size = struct.unpack_from("<I", dex, coff + 12)[0]
                base = coff + 16

                if (
                    msig == "Lcom/android/systemui/slimindicator/SlimIndicatorPluginMediator;-><init>"
                    and fid_conn is not None
                ):
                    pc = 0
                    prev_pc = -1
                    while pc < insns_size:
                        w0 = struct.unpack_from("<H", dex, base + pc * 2)[0]
                        op = w0 & 0xFF
                        if op == 0x5C and pc + 1 < insns_size:  # iput-boolean vA, vB, field@CCCC
                            fid = struct.unpack_from("<H", dex, base + (pc + 1) * 2)[0]
                            if fid == fid_conn and prev_pc >= 0 and pc - prev_pc == 1:
                                pw0 = struct.unpack_from("<H", dex, base + prev_pc * 2)[0]
                                if (pw0 & 0xFF) == 0x12 and ((pw0 >> 8) & 0xF) == ((w0 >> 8) & 0xF):
                                    lit = (pw0 >> 12) & 0xF
                                    if lit == 0:
                                        struct.pack_into("<H", dex, base + prev_pc * 2, (pw0 & 0x0FFF) | 0x1000)
                                        stats["mediator_patched"] += 1
                                        changed = True
                                    elif lit == 1:
                                        stats["mediator_already"] += 1
                        prev_pc = pc
                        pc += _dalvik_insn_width(w0)

                elif (
                    msig == "Lcom/android/systemui/statusbar/policy/QSClockQuickStarHelper;->shouldShowSecondsClock"
                    and insns_size >= 2
                    and regs_size >= 1
                ):
                    w0, w1 = struct.unpack_from("<HH", dex, base)
                    if w0 == 0x1012 and w1 == 0x000F:
                        stats["helper_already"] += 1
                    else:
                        struct.pack_into("<HH", dex, base, 0x1012, 0x000F)
                        stats["helper_patched"] += 1
                        changed = True

                elif (
                    msig == "Lcom/android/systemui/statusbar/policy/QSClockIndicatorView;->notifyTimeChanged"
                    and fid_time_text is not None
                    and fid_time_sec is not None
                ):
                    pc = 0
                    while pc < insns_size:
                        w0 = struct.unpack_from("<H", dex, base + pc * 2)[0]
                        if (w0 & 0xFF) == 0x54 and pc + 1 < insns_size:  # iget-object
                            fid = struct.unpack_from("<H", dex, base + (pc + 1) * 2)[0]
                            if fid == fid_time_text:
                                struct.pack_into("<H", dex, base + (pc + 1) * 2, fid_time_sec)
                                stats["notify_patched"] += 1
                                changed = True
                            elif fid == fid_time_sec:
                                stats["notify_already"] += 1
                        pc += _dalvik_insn_width(w0)

    if changed:
        dex[12:32] = hashlib.sha1(dex[32:]).digest()
        struct.pack_into("<I", dex, 8, zlib.adler32(dex[12:]) & 0xFFFFFFFF)
    return bytes(dex), stats


def patch_systemui_apk_inplace(src_apk: Path, dst_apk: Path) -> dict[str, int]:
    """Patch SystemUI.apk DEX entry/entries in-place while preserving ZIP layout."""
    raw = bytearray(src_apk.read_bytes())
    totals = {
        "mediator_patched": 0,
        "mediator_already": 0,
        "helper_patched": 0,
        "helper_already": 0,
        "notify_patched": 0,
        "notify_already": 0,
    }
    crc_updates: dict[str, int] = {}

    with zipfile.ZipFile(src_apk, "r") as z:
        dex_infos = sorted(
            (ci for ci in z.infolist() if ci.filename.startswith("classes") and ci.filename.endswith(".dex")),
            key=lambda ci: ci.filename,
        )
        if not dex_infos:
            raise RuntimeError(f"No classes*.dex found in {src_apk}")

        for ci in dex_infos:
            lhoff = ci.header_offset
            fnlen, exlen = struct.unpack_from("<HH", raw, lhoff + 26)
            dex_off = lhoff + 30 + fnlen + exlen
            dex_len = ci.file_size
            orig_bytes = bytes(raw[dex_off : dex_off + dex_len])

            patched_bytes, st = patch_systemui_dex_bytes(orig_bytes)
            for k, v in st.items():
                totals[k] += v

            if any(st.values()):
                if ci.compress_type != zipfile.ZIP_STORED:
                    raise RuntimeError(f"Expected uncompressed (STORED) {ci.filename} in SystemUI.apk")
                if patched_bytes != orig_bytes:
                    new_crc = zlib.crc32(patched_bytes) & 0xFFFFFFFF
                    raw[dex_off : dex_off + dex_len] = patched_bytes
                    if struct.unpack_from("<I", raw, lhoff + 14)[0] != ci.CRC:
                        raise RuntimeError(f"Local header CRC mismatch on {ci.filename}")
                    struct.pack_into("<I", raw, lhoff + 14, new_crc)
                    crc_updates[ci.filename] = new_crc

    if (
        totals["mediator_patched"] + totals["mediator_already"] == 0
        or totals["helper_patched"] + totals["helper_already"] == 0
        or totals["notify_patched"] + totals["notify_already"] == 0
    ):
        raise RuntimeError(f"Required Clock Seconds symbols/sites missing in {src_apk}: {totals}")

    if crc_updates:
        eocd = raw.rfind(b"PK\x05\x06")
        if eocd < 0:
            raise RuntimeError("ZIP End-of-Central-Directory signature not found")
        pos = struct.unpack_from("<I", raw, eocd + 16)[0]
        remaining = set(crc_updates)
        while pos < eocd and raw[pos : pos + 4] == b"PK\x01\x02":
            fl, el, cl = struct.unpack_from("<HHH", raw, pos + 28)
            name = raw[pos + 46 : pos + 46 + fl].decode("utf-8", "replace")
            if name in crc_updates:
                struct.pack_into("<I", raw, pos + 16, crc_updates[name])
                remaining.discard(name)
            pos += 46 + fl + el + cl
        if remaining:
            raise RuntimeError(f"Failed to update Central Directory CRC for: {sorted(remaining)}")

    dst_apk.write_bytes(raw)
    with zipfile.ZipFile(dst_apk, "r") as z:
        bad = z.testzip()
        if bad is not None:
            raise RuntimeError(f"Corrupt ZIP entry after in-place patch: {bad}")
    return totals


def main() -> int:
    ap = argparse.ArgumentParser(description="Patch Samsung OneUI 9 SystemUI.apk for permanent clock seconds")
    ap.add_argument("src", type=Path, help="Input SystemUI.apk")
    ap.add_argument("dst", type=Path, help="Output patched SystemUI.apk")
    args = ap.parse_args()

    stats = patch_systemui_apk_inplace(args.src, args.dst)
    print(f"Patched {args.dst}: {stats}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
