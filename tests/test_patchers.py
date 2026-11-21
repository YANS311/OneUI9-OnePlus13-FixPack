#!/usr/bin/env python3
"""Automated unit tests for OneUI 9.0 FixPack patchers."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "patchers"))

from patch_imsservice import patch_imsprofile_json, patch_imsservice_apk
from patch_xmls import (
    patch_camera_feature_xml,
    patch_euicc_permissions_xml,
    patch_floating_feature_xml,
)


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
        # Non-mobile RCS profile untouched
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


if __name__ == "__main__":
    unittest.main()
