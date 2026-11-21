#!/usr/bin/env python3
"""In-place surgical DEX patcher for Samsung OneUI 9 telephony-common.jar.

Fixes outgoing SMS on non-Samsung (Qualcomm QTI RIL) hardware:
1. GsmSMSDispatcher.sendSms():
   - Replaces SMSDispatcher->mSemCi with SMSDispatcher->mCi
   - Replaces SemCommandsInterface->secSendSMS* with CommandsInterface->sendSMS*
   (Eliminates RADIO_NOT_AVAILABLE from missing ISehRadioMessaging HAL.)
2. ImsSmsDispatcher.isAvailable(String):
   - Replaces ImsSmsDispatcher->mIsSmsOverImsOnly with ImsSmsDispatcher->mIsRegistered
   (Enables IMS SMS over VoLTE for China Telecom / VoLTE-only carriers.)

Preserves exact ZIP alignment (in-place patch on STORED classes.dex) for ART mmap.
"""

from __future__ import annotations

import hashlib
import struct
import sys
import zipfile
import zlib
from pathlib import Path


def _uleb128(buf: bytes, pos: int) -> tuple[int, int]:
    val, shift = 0, 0
    while True:
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            return val, pos
        shift += 7


def _parse_dex_tables(dex: bytes):
    str_cnt, str_off = struct.unpack_from("<II", dex, 56)
    type_cnt, type_off = struct.unpack_from("<II", dex, 64)
    proto_cnt, proto_off = struct.unpack_from("<II", dex, 72)
    field_cnt, field_off = struct.unpack_from("<II", dex, 80)
    meth_cnt, meth_off = struct.unpack_from("<II", dex, 88)
    cls_cnt, cls_off = struct.unpack_from("<II", dex, 96)

    strings: list[str] = []
    for i in range(str_cnt):
        off = struct.unpack_from("<I", dex, str_off + i * 4)[0]
        _, p = _uleb128(dex, off)
        end = dex.index(b"\x00", p)
        strings.append(dex[p:end].decode("utf-8", "replace"))

    types = [strings[struct.unpack_from("<I", dex, type_off + i * 4)[0]] for i in range(type_cnt)]

    def field_sig(fid: int) -> str:
        cid, tid, nid = struct.unpack_from("<HHI", dex, field_off + fid * 8)
        return f"{types[cid]}->{strings[nid]}:{types[tid]}"

    def method_sig(mid: int) -> str:
        cid, pid, nid = struct.unpack_from("<HHI", dex, meth_off + mid * 8)
        return f"{types[cid]}->{strings[nid]}"

    return {
        "strings": strings,
        "types": types,
        "field_cnt": field_cnt,
        "meth_cnt": meth_cnt,
        "cls_cnt": cls_cnt,
        "cls_off": cls_off,
        "field_sig": field_sig,
        "method_sig": method_sig,
    }


def patch_dex_bytes(dex_in: bytes) -> tuple[bytes, dict[str, int]]:
    dex = bytearray(dex_in)
    t = _parse_dex_tables(dex)

    # Resolve dynamic field & method IDs
    fid_mSemCi = fid_mCi = fid_imsOnly = fid_isReg = None
    for fid in range(t["field_cnt"]):
        fs = t["field_sig"](fid)
        if fs == "Lcom/android/internal/telephony/SMSDispatcher;->mSemCi:Lcom/android/internal/telephony/SemCommandsInterface;":
            fid_mSemCi = fid
        elif fs == "Lcom/android/internal/telephony/SMSDispatcher;->mCi:Lcom/android/internal/telephony/CommandsInterface;":
            fid_mCi = fid
        elif fs == "Lcom/android/internal/telephony/ImsSmsDispatcher;->mIsSmsOverImsOnly:Z":
            fid_imsOnly = fid
        elif fs == "Lcom/android/internal/telephony/ImsSmsDispatcher;->mIsRegistered:Z":
            fid_isReg = fid

    mid_secSend = mid_secSendMore = mid_send = mid_sendMore = None
    for mid in range(t["meth_cnt"]):
        ms = t["method_sig"](mid)
        if ms == "Lcom/android/internal/telephony/SemCommandsInterface;->secSendSMS":
            mid_secSend = mid
        elif ms == "Lcom/android/internal/telephony/SemCommandsInterface;->secSendSMSExpectMore":
            mid_secSendMore = mid
        elif ms == "Lcom/android/internal/telephony/CommandsInterface;->sendSMS":
            mid_send = mid
        elif ms == "Lcom/android/internal/telephony/CommandsInterface;->sendSMSExpectMore":
            mid_sendMore = mid

    if None in (fid_mSemCi, fid_mCi, fid_imsOnly, fid_isReg, mid_secSend, mid_secSendMore, mid_send, mid_sendMore):
        raise RuntimeError("Required telephony-common.jar symbols not found in DEX")

    stats = {"mSemCi_patched": 0, "secSendSMS_patched": 0, "imsSmsOnly_patched": 0}

    for i in range(t["cls_cnt"]):
        cidx, _, _, _, _, _, cdoff, _ = struct.unpack_from("<IIIIIIII", dex, t["cls_off"] + i * 32)
        if cdoff == 0:
            continue
        cname = t["types"][cidx]
        if cname not in (
            "Lcom/android/internal/telephony/gsm/GsmSMSDispatcher;",
            "Lcom/android/internal/telephony/ImsSmsDispatcher;",
        ):
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
                insns_size = struct.unpack_from("<I", dex, coff + 12)[0]
                base = coff + 16

                if msig == "Lcom/android/internal/telephony/gsm/GsmSMSDispatcher;->sendSms":
                    for k in range(insns_size - 2):
                        w0, w1 = struct.unpack_from("<HH", dex, base + k * 2)
                        op = w0 & 0xFF
                        if op == 0x54 and w1 == fid_mSemCi:
                            # Verify next instruction invokes secSendSMS or secSendSMSExpectMore
                            if k + 3 < insns_size:
                                nw0, nw1 = struct.unpack_from("<HH", dex, base + (k + 2) * 2)
                                if (nw0 & 0xFF) == 0x72 and nw1 in (mid_secSend, mid_secSendMore):
                                    struct.pack_into("<H", dex, base + k * 2 + 2, fid_mCi)
                                    stats["mSemCi_patched"] += 1
                                    new_mid = mid_send if nw1 == mid_secSend else mid_sendMore
                                    struct.pack_into("<H", dex, base + (k + 2) * 2 + 2, new_mid)
                                    stats["secSendSMS_patched"] += 1

                elif msig == "Lcom/android/internal/telephony/ImsSmsDispatcher;->isAvailable" and insns_size > 20:
                    # Patch the final `return mIsImsServiceUp && mIsSmsOverImsOnly` check near method tail
                    for k in range(max(0, insns_size - 25), insns_size - 1):
                        w0, w1 = struct.unpack_from("<HH", dex, base + k * 2)
                        if (w0 & 0xFF) == 0x55 and w1 == fid_imsOnly:
                            struct.pack_into("<H", dex, base + k * 2 + 2, fid_isReg)
                            stats["imsSmsOnly_patched"] += 1

    if stats["mSemCi_patched"] == 0 or stats["secSendSMS_patched"] == 0 or stats["imsSmsOnly_patched"] == 0:
        raise RuntimeError(f"Expected patch sites not all matched: {stats}")

    # Recompute DEX SHA-1 [12:32] and Adler32 [8:12]
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    struct.pack_into("<I", dex, 8, zlib.adler32(dex[12:]) & 0xFFFFFFFF)
    return bytes(dex), stats


def patch_jar_inplace(src_path: Path, dst_path: Path) -> dict[str, int]:
    raw = bytearray(src_path.read_bytes())
    with zipfile.ZipFile(src_path, "r") as z:
        ci = z.getinfo("classes.dex")
        if ci.compress_type != zipfile.ZIP_STORED:
            raise RuntimeError("Expected uncompressed (STORED) classes.dex in telephony-common.jar")
        old_crc = ci.CRC
        lhoff = ci.header_offset
        fnlen, exlen = struct.unpack_from("<HH", raw, lhoff + 26)
        dex_off = lhoff + 30 + fnlen + exlen
        dex_len = ci.file_size

    patched_dex, stats = patch_dex_bytes(bytes(raw[dex_off : dex_off + dex_len]))
    new_crc = zlib.crc32(patched_dex) & 0xFFFFFFFF
    raw[dex_off : dex_off + dex_len] = patched_dex

    # Update local file header CRC
    if struct.unpack_from("<I", raw, lhoff + 14)[0] != old_crc:
        raise RuntimeError("Local header CRC mismatch")
    struct.pack_into("<I", raw, lhoff + 14, new_crc)

    # Update central directory CRC
    eocd = raw.rfind(b"PK\x05\x06")
    pos = struct.unpack_from("<I", raw, eocd + 16)[0]
    updated_cd = False
    while pos < eocd and raw[pos : pos + 4] == b"PK\x01\x02":
        fl, el, cl = struct.unpack_from("<HHH", raw, pos + 28)
        name = raw[pos + 46 : pos + 46 + fl].decode("utf-8", "replace")
        if name == "classes.dex":
            struct.pack_into("<I", raw, pos + 16, new_crc)
            updated_cd = True
            break
        pos += 46 + fl + el + cl
    if not updated_cd:
        raise RuntimeError("Failed to locate classes.dex in ZIP Central Directory")

    dst_path.write_bytes(raw)
    with zipfile.ZipFile(dst_path, "r") as z:
        if z.testzip() is not None:
            raise RuntimeError("Patched JAR failed ZIP integrity check")
    return stats


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input telephony-common.jar> <output telephony-common.jar>")
        return 2
    stats = patch_jar_inplace(Path(sys.argv[1]), Path(sys.argv[2]))
    print(f"Patched telephony-common.jar successfully: {stats}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
