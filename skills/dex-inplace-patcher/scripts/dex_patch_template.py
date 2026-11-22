#!/usr/bin/env python3
"""Reusable skeleton for alignment-preserving in-place DEX & ZIP CRC patching."""

from __future__ import annotations

import hashlib
import struct
import zipfile
import zlib
from pathlib import Path
from typing import Callable


def read_uleb128(buf: bytes | bytearray, pos: int) -> tuple[int, int]:
    val = shift = 0
    while True:
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            return val, pos
        shift += 7


def parse_dex_tables(dex: bytes | bytearray) -> dict:
    str_cnt, str_off = struct.unpack_from("<II", dex, 56)
    type_cnt, type_off = struct.unpack_from("<II", dex, 64)
    field_cnt, field_off = struct.unpack_from("<II", dex, 80)
    meth_cnt, meth_off = struct.unpack_from("<II", dex, 88)
    cls_cnt, cls_off = struct.unpack_from("<II", dex, 96)

    strings: list[str] = []
    for i in range(str_cnt):
        off = struct.unpack_from("<I", dex, str_off + i * 4)[0]
        _, p = read_uleb128(dex, off)
        strings.append(dex[p : dex.index(b"\x00", p)].decode("utf-8", "replace"))

    types = [strings[struct.unpack_from("<I", dex, type_off + i * 4)[0]] for i in range(type_cnt)]

    def field_sig(fid: int) -> str:
        cid, tid, nid = struct.unpack_from("<HHI", dex, field_off + fid * 8)
        return f"{types[cid]}->{strings[nid]}:{types[tid]}"

    def method_sig(mid: int) -> str:
        cid, _, nid = struct.unpack_from("<HHI", dex, meth_off + mid * 8)
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


def fix_dex_checksums(dex: bytearray) -> bytes:
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    struct.pack_into("<I", dex, 8, zlib.adler32(dex[12:]) & 0xFFFFFFFF)
    return bytes(dex)


def patch_archive_dex_inplace(
    src_zip: Path,
    dst_zip: Path,
    dex_patch_fn: Callable[[str, bytes], bytes | None],
) -> list[str]:
    """Apply `dex_patch_fn(entry_name, dex_bytes) -> new_bytes | None` in-place."""
    raw = bytearray(src_zip.read_bytes())
    crc_updates: dict[str, int] = {}

    with zipfile.ZipFile(src_zip, "r") as z:
        for ci in sorted((c for c in z.infolist() if c.filename.startswith("classes") and c.filename.endswith(".dex")), key=lambda c: c.filename):
            lhoff = ci.header_offset
            fnlen, exlen = struct.unpack_from("<HH", raw, lhoff + 26)
            dex_off = lhoff + 30 + fnlen + exlen
            dex_len = ci.file_size
            orig = bytes(raw[dex_off : dex_off + dex_len])

            patched = dex_patch_fn(ci.filename, orig)
            if patched is None or patched == orig:
                continue
            if ci.compress_type != zipfile.ZIP_STORED:
                raise RuntimeError(f"{ci.filename} is compressed; in-place patch requires ZIP_STORED")
            if len(patched) != len(orig):
                raise RuntimeError(f"{ci.filename} size changed ({len(orig)} -> {len(patched)})")

            new_crc = zlib.crc32(patched) & 0xFFFFFFFF
            raw[dex_off : dex_off + dex_len] = patched
            if struct.unpack_from("<I", raw, lhoff + 14)[0] != ci.CRC:
                raise RuntimeError(f"Local header CRC mismatch for {ci.filename}")
            struct.pack_into("<I", raw, lhoff + 14, new_crc)
            crc_updates[ci.filename] = new_crc

    if crc_updates:
        eocd = raw.rfind(b"PK\x05\x06")
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
            raise RuntimeError(f"CD CRC update missed: {sorted(remaining)}")

    dst_zip.write_bytes(raw)
    with zipfile.ZipFile(dst_zip, "r") as z:
        if z.testzip() is not None:
            raise RuntimeError("Resulting ZIP failed integrity check")
    return sorted(crc_updates)
