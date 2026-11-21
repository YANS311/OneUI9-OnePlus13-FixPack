#!/usr/bin/env python3
"""XML patchers for OneUI 9.0 on OnePlus 13 (PJZ110 / dodge)."""

from __future__ import annotations

import re


def patch_camera_feature_xml(xml_text: str) -> tuple[str, int, int]:
    """Unlock all _60FPS entries and fix 9:16 photo size (4000x2252 -> 3840x2160)."""
    fps_count = 0

    def _enable_60fps(match: re.Match[str]) -> str:
        nonlocal fps_count
        line = match.group(0)
        if 'value="false"' in line:
            fps_count += 1
            return line.replace('value="false"', 'value="true"')
        return line

    out = re.sub(r"^.*_60FPS.*$", _enable_60fps, xml_text, flags=re.MULTILINE)
    out, ratio_count = re.subn(r'value="4000x2252"', 'value="3840x2160"', out)
    return out, fps_count, ratio_count


def patch_floating_feature_xml(xml_text: str) -> tuple[str, int]:
    """Remove S26 Ultra tsds2 eSIM slot-switch declaration."""
    return re.subn(
        r"\s*<SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH>.*?</SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH>",
        "",
        xml_text,
    )


def patch_euicc_permissions_xml(xml_text: str) -> tuple[str, int]:
    """Strip android.hardware.telephony.euicc* feature declarations."""
    return re.subn(r"\s*<feature\s+name=\"android\.hardware\.telephony\.euicc[^\"]*\"\s*/>", "", xml_text)
