#!/usr/bin/env python3
"""Tests for the palette generator (write_palette) in leila_finish.py:
the fx_derived derivation guard and the px-scan input checks.

    python -m pytest tools/art/test_leila_finish.py
"""

from __future__ import annotations

import json
import os
import sys

import cv2
import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import leila_finish as LF  # noqa: E402


def _png(path, hex_rgb):
    r, g, b = (int(hex_rgb[i:i + 2], 16) for i in (0, 2, 4))
    cv2.imwrite(str(path), np.array([[[b, g, r, 255]]], dtype=np.uint8))


def test_write_palette_requires_px_dir(tmp_path):
    with pytest.raises(SystemExit, match="px missing"):
        LF.write_palette(str(tmp_path))


def test_fx_derived_admits_scaled_shade(tmp_path):
    # a8d8ff (fx group) x0.55 -> 5c768c: a documented derivation of a listed
    # colour is admitted into fx_derived.
    px = tmp_path / "px"
    px.mkdir()
    _png(px / "tiny.png", "5c768c")
    LF.write_palette(str(tmp_path))
    pal = json.loads((tmp_path / "palette.json").read_text(encoding="utf-8"))
    assert pal["fx_derived"] == ["5c768c"]


def test_fx_derived_rejects_underived_colour(tmp_path):
    # int(c*0.55) <= 140 for any c <= 255, so ff0000 can never be derived:
    # the build must fail instead of silently legitimising a new colour.
    px = tmp_path / "px"
    px.mkdir()
    _png(px / "tiny.png", "ff0000")
    with pytest.raises(SystemExit, match="ff0000"):
        LF.write_palette(str(tmp_path))


def test_write_palette_rejects_unreadable_png(tmp_path):
    px = tmp_path / "px"
    px.mkdir()
    (px / "bad.png").write_bytes(b"not a png")
    with pytest.raises(SystemExit, match="bad.png"):
        LF.write_palette(str(tmp_path))
