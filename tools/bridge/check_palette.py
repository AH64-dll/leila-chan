#!/usr/bin/env python3
"""Palette compliance: every opaque pixel of every exported Leila sprite
must be a colour from art/leila/palette.json (role checklist item).

    python tools/bridge/check_palette.py            # check exported sprites
    python tools/bridge/check_palette.py --source   # check art/leila/x2 instead

Exit 0 = compliant. Needs opencv-python-headless + numpy (requirements.txt).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def palette_rgb() -> np.ndarray:
    groups = json.loads((ROOT / "art" / "leila" / "palette.json").read_text())
    hexes = [c for ramp in groups.values() for c in ramp]
    rgb = np.array(
        [[int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)] for c in hexes],
        dtype=np.uint8,
    )
    return np.unique(rgb, axis=0)


def main() -> int:
    src = ROOT / "art" / "leila" / "x2" if "--source" in sys.argv else (
        ROOT / "game" / "assets" / "sprites" / "leila")
    allowed = palette_rgb()
    lut = np.zeros((256, 256, 256), dtype=bool)
    lut[allowed[:, 0], allowed[:, 1], allowed[:, 2]] = True

    bad = 0
    for png in sorted(src.glob("*.png")):
        img = cv2.imread(str(png), cv2.IMREAD_UNCHANGED)
        rgb = img[..., [2, 1, 0]]
        if img.shape[2] == 4:
            rgb = rgb[img[..., 3] > 0]
        else:
            rgb = rgb.reshape(-1, 3)
        off = int((~lut[rgb[:, 0], rgb[:, 1], rgb[:, 2]]).sum())
        print(f"{png.name}: {off} off-palette px")
        bad += off

    if bad:
        print(f"check_palette: FAILED ({bad} off-palette px, {len(allowed)} palette colours)")
        return 1
    print(f"check_palette: all sprites inside the {len(allowed)}-colour palette")
    return 0


if __name__ == "__main__":
    sys.exit(main())
