#!/usr/bin/env python3
"""Automated unit tests for OneUI 9.0 FixPack patchers."""

from __future__ import annotations

import hashlib
import json
import struct
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "patchers"))

from patch_cscfeature import (
    CSC_ENHANCEMENTS,
    _dalvik_insn_width,
    decode_cscfeature_bytes,
    omc_decode,
    omc_encode,
    patch_csc_xml,
    patch_cscfeature_file,
)
from patch_imsservice import patch_imsprofile_json, patch_imsservice_apk
from patch_systemui_seconds import patch_systemui_apk_inplace, patch_systemui_dex_bytes
from patch_xmls import (
    patch_camera_feature_xml,
    patch_euicc_permissions_xml,
    patch_floating_feature_xml,
)


def _encode_uleb128(val: int) -> bytes:
    out = bytearray()
    while True:
        b = val & 0x7F
        val >>= 7
        if val:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _build_synthetic_systemui_dex() -> bytes:
    """Build a minimal valid DEX containing the 3 Clock Seconds patch target methods."""
    strings = [
        "()V",
        "()Z",
        "<init>",
        "Lcom/android/systemui/slimindicator/SlimIndicatorPluginMediator;",
        "Lcom/android/systemui/statusbar/policy/QSClockBellSound;",
        "Lcom/android/systemui/statusbar/policy/QSClockIndicatorView;",
        "Lcom/android/systemui/statusbar/policy/QSClockQuickStarHelper;",
        "Ljava/lang/String;",
        "TimeText",
        "TimeTextWithSeconds",
        "V",
        "Z",
        "mIsSPluginConnected",
        "notifyTimeChanged",
        "shouldShowSecondsClock",
    ]
    s_idx = {s: i for i, s in enumerate(strings)}

    # Types aligned 1:1 with type descriptors needed
    type_names = [
        "Lcom/android/systemui/slimindicator/SlimIndicatorPluginMediator;",
        "Lcom/android/systemui/statusbar/policy/QSClockBellSound;",
        "Lcom/android/systemui/statusbar/policy/QSClockIndicatorView;",
        "Lcom/android/systemui/statusbar/policy/QSClockQuickStarHelper;",
        "Ljava/lang/String;",
        "V",
        "Z",
    ]
    t_idx = {t: i for i, t in enumerate(type_names)}

    protos = [
        (s_idx["()V"], t_idx["V"], 0),
        (s_idx["()Z"], t_idx["Z"], 0),
    ]
    fields = [
        (t_idx["Lcom/android/systemui/slimindicator/SlimIndicatorPluginMediator;"], t_idx["Z"], s_idx["mIsSPluginConnected"]),
        (t_idx["Lcom/android/systemui/statusbar/policy/QSClockBellSound;"], t_idx["Ljava/lang/String;"], s_idx["TimeText"]),
        (t_idx["Lcom/android/systemui/statusbar/policy/QSClockBellSound;"], t_idx["Ljava/lang/String;"], s_idx["TimeTextWithSeconds"]),
    ]
    methods = [
        (t_idx["Lcom/android/systemui/slimindicator/SlimIndicatorPluginMediator;"], 0, s_idx["<init>"]),
        (t_idx["Lcom/android/systemui/statusbar/policy/QSClockQuickStarHelper;"], 1, s_idx["shouldShowSecondsClock"]),
        (t_idx["Lcom/android/systemui/statusbar/policy/QSClockIndicatorView;"], 0, s_idx["notifyTimeChanged"]),
    ]

    # Code items (16-byte header + insns)
    # 0: const/4 v1, 0 (0x0112); iput-boolean v1, v0, field@0 (0x015c, 0x0000); return-void (0x000e)
    insns_med = struct.pack("<HHHH", 0x0112, 0x015C, 0x0000, 0x000E)
    code_med = struct.pack("<HHHHII", 2, 1, 0, 0, 0, len(insns_med) // 2) + insns_med

    # 1: const/4 v0, 0 (0x0012); return v0 (0x000f)
    insns_help = struct.pack("<HH", 0x0012, 0x000F)
    code_help = struct.pack("<HHHHII", 2, 1, 0, 0, 0, len(insns_help) // 2) + insns_help

    # 2: nop; nop; iget-object v0, v7, field@1 (0x7054, 0x0001); return-void
    insns_not = struct.pack("<HHHHH", 0x0000, 0x0000, 0x7054, 0x0001, 0x000E)
    code_not = struct.pack("<HHHHII", 8, 2, 0, 0, 0, len(insns_not) // 2) + insns_not

    # Lay out fixed tables from offset 112
    str_off = 112
    type_off = str_off + 4 * len(strings)
    proto_off = type_off + 4 * len(type_names)
    field_off = proto_off + 12 * len(protos)
    meth_off = field_off + 8 * len(fields)
    cls_off = meth_off + 8 * len(methods)
    cls_cnt = 3
    data_off = cls_off + 32 * cls_cnt

    buf = bytearray(data_off)

    # Write string data
    str_ptrs = []
    for s in strings:
        str_ptrs.append(len(buf))
        b = s.encode("utf-8")
        buf.extend(_encode_uleb128(len(s)))
        buf.extend(b + b"\x00")
    for i, ptr in enumerate(str_ptrs):
        struct.pack_into("<I", buf, str_off + i * 4, ptr)
    for i, tn in enumerate(type_names):
        struct.pack_into("<I", buf, type_off + i * 4, s_idx[tn])
    for i, p in enumerate(protos):
        struct.pack_into("<III", buf, proto_off + i * 12, *p)
    for i, f in enumerate(fields):
        struct.pack_into("<HHI", buf, field_off + i * 8, *f)
    for i, m in enumerate(methods):
        struct.pack_into("<HHI", buf, meth_off + i * 8, *m)

    def append_aligned4(blob: bytes) -> int:
        while len(buf) % 4:
            buf.append(0)
        off = len(buf)
        buf.extend(blob)
        return off

    coff_med = append_aligned4(code_med)
    coff_help = append_aligned4(code_help)
    coff_not = append_aligned4(code_not)

    class_specs = [
        (t_idx["Lcom/android/systemui/slimindicator/SlimIndicatorPluginMediator;"], 0, coff_med),
        (t_idx["Lcom/android/systemui/statusbar/policy/QSClockQuickStarHelper;"], 1, coff_help),
        (t_idx["Lcom/android/systemui/statusbar/policy/QSClockIndicatorView;"], 2, coff_not),
    ]
    for i, (cid, midx, coff) in enumerate(class_specs):
        cdata = (
            _encode_uleb128(0)
            + _encode_uleb128(0)
            + _encode_uleb128(1)
            + _encode_uleb128(0)
            + _encode_uleb128(midx)
            + _encode_uleb128(1)
            + _encode_uleb128(coff)
        )
        cdoff = len(buf)
        buf.extend(cdata)
        struct.pack_into("<IIIIIIII", buf, cls_off + i * 32, cid, 1, 0, 0, 0, 0, cdoff, 0)

    # Header
    buf[0:8] = b"dex\n035\x00"
    struct.pack_into("<II", buf, 32, len(buf), 112)
    struct.pack_into("<I", buf, 40, 0x12345678)
    struct.pack_into("<II", buf, 56, len(strings), str_off)
    struct.pack_into("<II", buf, 64, len(type_names), type_off)
    struct.pack_into("<II", buf, 72, len(protos), proto_off)
    struct.pack_into("<II", buf, 80, len(fields), field_off)
    struct.pack_into("<II", buf, 88, len(methods), meth_off)
    struct.pack_into("<II", buf, 96, cls_cnt, cls_off)
    struct.pack_into("<II", buf, 104, len(buf) - data_off, data_off)
    buf[12:32] = hashlib.sha1(buf[32:]).digest()
    struct.pack_into("<I", buf, 8, zlib.adler32(buf[12:]) & 0xFFFFFFFF)
    return bytes(buf)


class TestXMLPatchers(unittest.TestCase):
    def test_camera_feature_patch(self):
        sample = """
        <local name="BACK_CAMERA_RESOLUTION_16BY9_LARGE" value="4000x2252" />
        <local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_60FPS" value="false" />
        <local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_60FPS" value="false" />
        <local name="FRONT_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_60FPS" value="false" />
        """
        out, fps_n, ratio_n = patch_camera_feature_xml(sample)
        self.assertEqual(fps_n, 3)
        self.assertEqual(ratio_n, 1)
        self.assertIn('value="3840x2160"', out)
        self.assertNotIn('value="4000x2252"', out)
        self.assertNotIn('value="false"', out)

    def test_floating_feature_patch(self):
        sample = """<SecFloatingFeatureSet>
    <SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH>tsds2</SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH>
    <SEC_FLOATING_FEATURE_AUDIO_SUPPORT_DUAL_SPEAKER>TRUE</SEC_FLOATING_FEATURE_AUDIO_SUPPORT_DUAL_SPEAKER>
</SecFloatingFeatureSet>"""
        out, n = patch_floating_feature_xml(sample)
        self.assertEqual(n, 1)
        self.assertNotIn("EMBEDDED_SIM_SLOTSWITCH", out)
        self.assertIn("DUAL_SPEAKER", out)

    def test_euicc_permissions_patch(self):
        sample = """<permissions>
    <feature name="android.hardware.telephony.euicc" />
    <feature name="android.hardware.telephony.euicc.mep" />
    <privapp-permissions package="com.samsung.euicc" />
</permissions>"""
        out, n = patch_euicc_permissions_xml(sample)
        self.assertEqual(n, 2)
        self.assertNotIn("android.hardware.telephony.euicc", out)
        self.assertIn("com.samsung.euicc", out)


class TestImsServicePatcher(unittest.TestCase):
    def test_imsprofile_json_patch(self):
        sample = json.dumps({
            "profile": [
                {"name": "CMCC Mobile VoLTE", "mnoname": "CMCC_CN", "dbr_timer": 0, "use_precondition": False},
                {"name": "CTC Mobile", "mnoname": "CTC_CN", "dbr_timer": 6000, "use_precondition": True},
                {"name": "CU Mobile VoLTE", "mnoname": "CU_CN", "dbr_timer": 6000, "use_precondition": True},
                {"name": "CTC Internet RCS", "mnoname": "CTC_CN", "dbr_timer": 6000, "use_precondition": True},
            ]
        })
        new_json, patched = patch_imsprofile_json(sample)
        self.assertEqual(patched, ["CTC Mobile (CTC_CN)", "CU Mobile VoLTE (CU_CN)"])
        parsed = json.loads(new_json)
        by_name = {p["name"]: p for p in parsed["profile"]}
        self.assertEqual(by_name["CTC Mobile"]["dbr_timer"], 0)
        self.assertFalse(by_name["CTC Mobile"]["use_precondition"])
        self.assertEqual(by_name["CU Mobile VoLTE"]["dbr_timer"], 0)
        self.assertFalse(by_name["CU Mobile VoLTE"]["use_precondition"])
        self.assertEqual(by_name["CTC Internet RCS"]["dbr_timer"], 6000)

    def test_imsservice_apk_roundtrip(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "ims_in.apk"
            dst = Path(td) / "ims_out.apk"
            with zipfile.ZipFile(src, "w") as z:
                z.writestr("res/raw/imsprofile.json", json.dumps({
                    "profile": [{"name": "CTC Mobile", "mnoname": "CTC_CN", "dbr_timer": 6000, "use_precondition": True}]
                }))
                z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n")
            patched = patch_imsservice_apk(src, dst)
            self.assertEqual(patched, ["CTC Mobile (CTC_CN)"])
            with zipfile.ZipFile(dst, "r") as z:
                self.assertIsNone(z.testzip())
                d = json.loads(z.read("res/raw/imsprofile.json"))
                self.assertEqual(d["profile"][0]["dbr_timer"], 0)


class TestCscFeaturePatcher(unittest.TestCase):
    def test_omc_roundtrip_and_xml_injection(self):
        salts = bytes((i * 73 + 19) & 0xFF for i in range(256))
        shifts = bytes((i % 8) for i in range(256))
        sample_xml = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<SamsungMobileFeature>\n"
            "  <FeatureSet>\n"
            "    <CscFeature_RIL_SupportEsim>TRUE</CscFeature_RIL_SupportEsim>\n"
            "    <CscFeature_Common_KeepMe>KEEP</CscFeature_Common_KeepMe>\n"
            "  </FeatureSet>\n"
            "</SamsungMobileFeature>\n"
        )
        encoded = omc_encode(sample_xml.encode("utf-8"), salts, shifts)
        self.assertFalse(encoded.lstrip().startswith(b"<"))
        decoded = omc_decode(encoded, salts, shifts).decode("utf-8")
        self.assertEqual(decoded, sample_xml)

        patched_xml, changes = patch_csc_xml(decoded)
        self.assertTrue(patched_xml.startswith('<?xml version="1.0" encoding="utf-8"?>'))
        self.assertIn("updated:CscFeature_RIL_SupportEsim:TRUE->FALSE", changes)
        root = ET.fromstring(patched_xml)
        fset = root.find("FeatureSet")
        self.assertIsNotNone(fset)
        self.assertEqual(fset.findtext("CscFeature_Common_KeepMe"), "KEEP")
        for key, expected in CSC_ENHANCEMENTS.items():
            self.assertEqual(fset.findtext(key), expected)

    def test_plaintext_file_passthrough(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "csc.xml"
            dst = Path(td) / "csc_out.xml"
            src.write_text("<SamsungMobileFeature><FeatureSet /></SamsungMobileFeature>", encoding="utf-8")
            changes, was_encoded = patch_cscfeature_file(src, dst)
            self.assertFalse(was_encoded)
            self.assertEqual(len(changes), len(CSC_ENHANCEMENTS))
            xml_out, enc2 = decode_cscfeature_bytes(dst.read_bytes())
            self.assertFalse(enc2)
            self.assertIn("RecordingAllowed", xml_out)


class TestSystemUiSecondsPatcher(unittest.TestCase):
    def test_dalvik_insn_widths(self):
        self.assertEqual(_dalvik_insn_width(0x0012), 1)  # const/4
        self.assertEqual(_dalvik_insn_width(0x7054), 2)  # iget-object
        self.assertEqual(_dalvik_insn_width(0x0026), 3)  # fill-array-data
        self.assertEqual(_dalvik_insn_width(0x00FA), 4)  # invoke-polymorphic
        self.assertEqual(_dalvik_insn_width(0x0018), 5)  # const-wide

    def test_patch_and_idempotency(self):
        raw_dex = _build_synthetic_systemui_dex()
        patched_dex, st1 = patch_systemui_dex_bytes(raw_dex)
        self.assertEqual(st1["mediator_patched"], 1)
        self.assertEqual(st1["helper_patched"], 1)
        self.assertEqual(st1["notify_patched"], 1)

        # Verify recomputed DEX SHA-1 & Adler32
        self.assertEqual(patched_dex[12:32], hashlib.sha1(patched_dex[32:]).digest())
        self.assertEqual(
            struct.unpack_from("<I", patched_dex, 8)[0],
            zlib.adler32(patched_dex[12:]) & 0xFFFFFFFF,
        )

        # Second pass must be completely idempotent
        patched2, st2 = patch_systemui_dex_bytes(patched_dex)
        self.assertEqual(patched2, patched_dex)
        self.assertEqual(st2["mediator_already"], 1)
        self.assertEqual(st2["helper_already"], 1)
        self.assertEqual(st2["notify_already"], 1)

    def test_apk_inplace_roundtrip(self):
        raw_dex = _build_synthetic_systemui_dex()
        with tempfile.TemporaryDirectory() as td:
            src = Path(td) / "SystemUI.apk"
            dst = Path(td) / "SystemUI_out.apk"
            with zipfile.ZipFile(src, "w", compression=zipfile.ZIP_STORED) as z:
                z.writestr("AndroidManifest.xml", b"manifest")
                z.writestr("classes3.dex", raw_dex)
            stats = patch_systemui_apk_inplace(src, dst)
            self.assertEqual(stats["mediator_patched"], 1)
            self.assertEqual(stats["helper_patched"], 1)
            self.assertEqual(stats["notify_patched"], 1)
            with zipfile.ZipFile(dst, "r") as z:
                self.assertIsNone(z.testzip())
                out_dex = z.read("classes3.dex")
            # Re-running on output APK is idempotent
            dst2 = Path(td) / "SystemUI_out2.apk"
            stats2 = patch_systemui_apk_inplace(dst, dst2)
            self.assertEqual(stats2["mediator_already"], 1)
            self.assertEqual(stats2["helper_already"], 1)
            self.assertEqual(stats2["notify_already"], 1)
            with zipfile.ZipFile(dst2, "r") as z:
                self.assertEqual(z.read("classes3.dex"), out_dex)


class TestModuleAndSkillHygiene(unittest.TestCase):
    def test_module_prop_version_and_stealth_mounts(self):
        prop_text = (ROOT / "module" / "module.prop").read_text(encoding="utf-8")
        self.assertIn("version=v1.2.0", prop_text)
        self.assertIn("versionCode=120", prop_text)

        pfd = (ROOT / "module" / "post-fs-data.sh").read_text(encoding="utf-8")
        srv = (ROOT / "module" / "service.sh").read_text(encoding="utf-8")
        for script_text in (pfd, srv):
            self.assertIn("stealth_bind_mount", script_text)
            self.assertNotIn('mount -o bind "$MODS_DIR/', script_text)

    def test_lf_line_endings(self):
        exts = {".sh", ".html", ".prop", ".py"}
        for base in (ROOT / "module", ROOT / "patchers"):
            for p in base.rglob("*"):
                if p.is_file() and p.suffix.lower() in exts:
                    self.assertNotIn(b"\r\n", p.read_bytes(), f"CRLF found in {p}")

    def test_skills_frontmatter(self):
        expected_skills = (
            "android-rom-port-debugger",
            "dex-inplace-patcher",
            "oneplus-arb-safe-flasher",
            "android-root-bl-stealth",
        )
        for name in expected_skills:
            skill_md = ROOT / "skills" / name / "SKILL.md"
            self.assertTrue(skill_md.is_file(), f"Missing {skill_md}")
            text = skill_md.read_text(encoding="utf-8")
            self.assertTrue(text.startswith("---\n"), f"Missing YAML frontmatter in {skill_md}")
            self.assertIn(f"name: {name}", text)
            self.assertIn("description:", text)


if __name__ == "__main__":
    unittest.main()
