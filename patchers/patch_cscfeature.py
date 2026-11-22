#!/usr/bin/env python3
"""Dynamic OMC CSC decoder & enhancer for Samsung OneUI 9 (TGY / OnePlus 13).

Extracts the per-device 256-byte `salts` and `shifts` obfuscation tables from
`Lcom/samsung/android/feature/SemCscFeature;` in `framework.jar`, decodes
OMC-encoded `cscfeature.xml` (bit-rotate-left + XOR + gzip), injects daily
enhancements (Call Recording, 50Hz anti-flicker, Camera Shutter menu, Real-time
network speed, Recent App Lock, eSIM disable), and outputs clean UTF-8 XML
starting with `<?xml` (accepted natively by `SemCscFeature.isXmlEncoded()`).
"""

from __future__ import annotations

import argparse
import gzip
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

_HERE = str(Path(__file__).resolve().parent)
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from patch_telephony_sms import _parse_dex_tables, _uleb128

CSC_ENHANCEMENTS: dict[str, str] = {
    "CscFeature_VoiceCall_ConfigRecording": "RecordingAllowed",
    "CscFeature_RIL_SupportEsim": "FALSE",
    "CscFeature_Camera_CameraFlicker": "50hz",
    "CscFeature_Camera_ShutterSoundMenu": "TRUE",
    "CscFeature_Setting_SupportRealTimeNetworkSpeed": "TRUE",
    "CscFeature_SystemUI_SupportRecentAppProtection": "TRUE",
}

# Dalvik instruction widths in 16-bit code units indexed by low opcode byte.
_SINGLE_UNIT_OPS = frozenset(
    {0x00, 0x01, 0x04, 0x07, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x1D, 0x1E, 0x21, 0x27, 0x28}
    | set(range(0x3E, 0x44))
    | {0x73, 0x79, 0x7A}
    | set(range(0x7B, 0x90))
    | set(range(0xB0, 0xD0))
    | set(range(0xE3, 0xFA))
)
_THREE_UNIT_OPS = frozenset(
    {0x03, 0x06, 0x09, 0x14, 0x17, 0x1B, 0x24, 0x25, 0x26, 0x2A, 0x2B, 0x2C, 0xFC, 0xFD}
    | set(range(0x6E, 0x73))
    | set(range(0x74, 0x79))
)
_FOUR_UNIT_OPS = frozenset({0xFA, 0xFB})


def _dalvik_insn_width(w0: int) -> int:
    op = w0 & 0xFF
    if op == 0x00 and w0 != 0x0000:
        # Data payload pseudo-instructions live after bytecode
        return 1
    if op in _SINGLE_UNIT_OPS:
        return 1
    if op == 0x18:
        return 5
    if op in _FOUR_UNIT_OPS:
        return 4
    if op in _THREE_UNIT_OPS:
        return 3
    return 2


def extract_csc_keys_from_dex(dex: bytes) -> tuple[bytes, bytes] | None:
    """Extract 256-byte (salts, shifts) from SemCscFeature inside a single DEX."""
    if b"SemCscFeature" not in dex:
        return None
    t = _parse_dex_tables(dex)

    for i in range(t["cls_cnt"]):
        cidx, _, _, _, _, _, cdoff, _ = struct.unpack_from("<IIIIIIII", dex, t["cls_off"] + i * 32)
        if not cdoff or t["types"][cidx] != "Lcom/samsung/android/feature/SemCscFeature;":
            continue

        p = cdoff
        sf, p = _uleb128(dex, p)
        inf, p = _uleb128(dex, p)
        dm, p = _uleb128(dex, p)
        _, p = _uleb128(dex, p)
        for _ in range(sf + inf):
            _, p = _uleb128(dex, p)
            _, p = _uleb128(dex, p)

        salts: bytes | None = None
        shifts: bytes | None = None
        for _ in range(dm):
            diff, p = _uleb128(dex, p)
            _, p = _uleb128(dex, p)
            coff, p = _uleb128(dex, p)
            if not coff:
                continue

            insns_size = struct.unpack_from("<I", dex, coff + 12)[0]
            base = coff + 16
            arrays: dict[int, bytes] = {}
            pc = 0
            while pc < insns_size:
                w0 = struct.unpack_from("<H", dex, base + pc * 2)[0]
                op = w0 & 0xFF
                if op == 0x00 and w0 in (0x0100, 0x0200, 0x0300):
                    break

                if op == 0x26 and pc + 2 < insns_size:  # fill-array-data vAA, +BBBBBBBB
                    reg = (w0 >> 8) & 0xFF
                    rel = struct.unpack_from("<i", dex, base + (pc + 1) * 2)[0]
                    pay_off = base + (pc + rel) * 2
                    if 0 <= pc + rel < insns_size and pay_off + 8 <= len(dex):
                        ident, width, count = struct.unpack_from("<HHI", dex, pay_off)
                        if ident == 0x0300 and width == 1 and count == 256:
                            arrays[reg] = bytes(dex[pay_off + 8 : pay_off + 8 + 256])
                elif op == 0x07:  # move-object vA, vB
                    dst_r = (w0 >> 8) & 0xF
                    src_r = (w0 >> 12) & 0xF
                    if src_r in arrays:
                        arrays[dst_r] = arrays[src_r]
                elif op == 0x08 and pc + 1 < insns_size:  # move-object/from16 vAA, vBBBB
                    dst_r = (w0 >> 8) & 0xFF
                    src_r = struct.unpack_from("<H", dex, base + (pc + 1) * 2)[0]
                    if src_r in arrays:
                        arrays[dst_r] = arrays[src_r]
                elif op == 0x5B and pc + 1 < insns_size:  # iput-object vA, vB, field@CCCC
                    src_r = (w0 >> 8) & 0xF
                    fid = struct.unpack_from("<H", dex, base + (pc + 1) * 2)[0]
                    fs = t["field_sig"](fid)
                    if src_r in arrays:
                        if fs == "Lcom/samsung/android/feature/SemCscFeature;->salts:[B":
                            salts = arrays[src_r]
                        elif fs == "Lcom/samsung/android/feature/SemCscFeature;->shifts:[B":
                            shifts = arrays[src_r]
                elif op == 0x69 and pc + 1 < insns_size:  # sput-object vAA, field@BBBB
                    src_r = (w0 >> 8) & 0xFF
                    fid = struct.unpack_from("<H", dex, base + (pc + 1) * 2)[0]
                    fs = t["field_sig"](fid)
                    if src_r in arrays:
                        if fs == "Lcom/samsung/android/feature/SemCscFeature;->salts:[B":
                            salts = arrays[src_r]
                        elif fs == "Lcom/samsung/android/feature/SemCscFeature;->shifts:[B":
                            shifts = arrays[src_r]

                pc += _dalvik_insn_width(w0)

        if salts and shifts:
            return salts, shifts
    return None


def extract_csc_keys(framework_jar: Path) -> tuple[bytes, bytes]:
    """Scan classes*.dex inside framework.jar for SemCscFeature salts & shifts."""
    with zipfile.ZipFile(framework_jar, "r") as z:
        dex_names = sorted(n for n in z.namelist() if n.startswith("classes") and n.endswith(".dex"))
        for name in dex_names:
            keys = extract_csc_keys_from_dex(z.read(name))
            if keys is not None:
                return keys
    raise RuntimeError(f"SemCscFeature salts/shifts not found in {framework_jar}")


def omc_decode(encoded: bytes, salts: bytes, shifts: bytes) -> bytes:
    """Decode Samsung OMC obfuscated gzip payload using 256-byte salts & shifts."""
    if len(salts) != 256 or len(shifts) != 256:
        raise ValueError("salts and shifts must each be 256 bytes")
    plain = bytearray(len(encoded))
    for i, b in enumerate(encoded):
        rot = shifts[i & 0xFF] & 7
        rot_b = ((b << rot) | (b >> (8 - rot))) & 0xFF
        plain[i] = rot_b ^ salts[i & 0xFF]
    return gzip.decompress(bytes(plain))


def omc_encode(xml_bytes: bytes, salts: bytes, shifts: bytes) -> bytes:
    """Inverse OMC obfuscation (used for round-trip testing and verification)."""
    if len(salts) != 256 or len(shifts) != 256:
        raise ValueError("salts and shifts must each be 256 bytes")
    gz = gzip.compress(xml_bytes)
    out = bytearray(len(gz))
    for i, b in enumerate(gz):
        x = b ^ salts[i & 0xFF]
        rot = shifts[i & 0xFF] & 7
        out[i] = ((x >> rot) | (x << (8 - rot))) & 0xFF
    return bytes(out)


def decode_cscfeature_bytes(raw: bytes, framework_jar: Path | None = None) -> tuple[str, bool]:
    """Return `(xml_text, was_encoded)` from either OMC binary or plaintext XML."""
    stripped = raw.lstrip(b"\xef\xbb\xbf \t\r\n")
    if stripped.startswith(b"<"):
        return raw.decode("utf-8-sig"), False
    if framework_jar is None:
        raise ValueError("framework.jar path is required to decode OMC-encoded cscfeature.xml")
    salts, shifts = extract_csc_keys(framework_jar)
    decoded_bytes = omc_decode(raw, salts, shifts)
    return decoded_bytes.decode("utf-8-sig"), True


def patch_csc_xml(xml_text: str, enhancements: dict[str, str] | None = None) -> tuple[str, list[str]]:
    """Inject or update `<FeatureSet>` keys cleanly and return plaintext XML."""
    target_map = enhancements if enhancements is not None else CSC_ENHANCEMENTS
    root = ET.fromstring(xml_text.lstrip("\ufeff"))
    feature_set = root.find("FeatureSet")
    if feature_set is None:
        feature_set = ET.SubElement(root, "FeatureSet")

    changes: list[str] = []
    for key, val in target_map.items():
        node = feature_set.find(key)
        if node is None:
            elem = ET.SubElement(feature_set, key)
            elem.text = val
            changes.append(f"added:{key}={val}")
        elif (node.text or "").strip() != val:
            old = (node.text or "").strip()
            node.text = val
            changes.append(f"updated:{key}:{old}->{val}")
        else:
            changes.append(f"kept:{key}={val}")

    if hasattr(ET, "indent"):
        ET.indent(root, space="  ")
    body = ET.tostring(root, encoding="unicode")
    return '<?xml version="1.0" encoding="utf-8"?>\n' + body + "\n", changes


def patch_cscfeature_file(
    src_csc: Path,
    dst_xml: Path,
    framework_jar: Path | None = None,
) -> tuple[list[str], bool]:
    """Decode `src_csc` if needed, inject enhancements, and write UTF-8 plaintext XML."""
    raw = src_csc.read_bytes()
    xml_text, was_encoded = decode_cscfeature_bytes(raw, framework_jar)
    patched_xml, changes = patch_csc_xml(xml_text)
    dst_xml.write_bytes(patched_xml.encode("utf-8"))
    return changes, was_encoded


def main() -> int:
    ap = argparse.ArgumentParser(description="Decode & patch Samsung OneUI 9 cscfeature.xml")
    ap.add_argument("src", type=Path, help="Input cscfeature.xml (OMC-encoded or plaintext)")
    ap.add_argument("dst", type=Path, help="Output plaintext patched cscfeature.xml")
    ap.add_argument("--framework-jar", type=Path, default=None, help="framework.jar for OMC key extraction")
    args = ap.parse_args()

    changes, was_encoded = patch_cscfeature_file(args.src, args.dst, args.framework_jar)
    print(f"Decoded OMC={was_encoded}; wrote {args.dst} ({args.dst.stat().st_size} bytes)")
    for c in changes:
        print(f"  - {c}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
