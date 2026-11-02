#!/usr/bin/env python3
"""Python-side tests for the asset/data bridge. The GDScript test
(game/tests/test_bridge.gd) exercises the outputs; these exercise the
generator itself.

    python -m pytest tools/bridge/test_export_to_godot.py
"""

from __future__ import annotations

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import export_to_godot as bridge  # noqa: E402


def test_build_outputs_is_deterministic():
    a = bridge.build_outputs()
    b = bridge.build_outputs()
    assert a.keys() == b.keys()
    assert all(a[p] == b[p] for p in a)


def test_every_sprite_has_a_matching_import():
    out = bridge.build_outputs()
    pngs = {p for p in out if p.suffix == ".png" and p.parent == bridge.DST_SPRITE_DIR}
    imports = {p for p in out if p.name.endswith(".png.import")}
    assert len(pngs) == len(imports) == 31
    assert imports == {p.with_name(p.name + ".import") for p in pngs}


def test_import_template_is_pixel_art_lossless():
    out = bridge.build_outputs()
    imp = next(p for p in out if p.name.endswith(".png.import"))
    text = out[imp].decode("utf-8")
    assert 'importer="texture"' in text
    assert 'uid="uid://' in text
    assert "mipmaps/generate=false" in text
    assert "compress/mode=0" in text  # lossless, no VRAM smearing


def test_uid_port_known_values():
    # Anchors the DJB2 x PCG32 x base-34 port against silent regressions.
    assert bridge._id_to_text(
        bridge._create_id_for_path("res://x.png", "0" * 32, "proj")
    ) == "uid://dlc3hw73nmxl2"


@pytest.mark.parametrize("pin,ok", [
    ("4.7.2-stable", True),
    ("4.7.0-stable", True),
    ("4.7", True),
    ("4.8.0-stable", False),
    ("5.0.0-stable", False),
    ("3.6-stable", False),
    ("latest", False),
    ("", False),
])
def test_godot_version_guard(pin, ok):
    assert bridge._pin_supported(pin) is ok


def test_version_guard_refuses_wrong_pin(monkeypatch, tmp_path):
    (tmp_path / "game").mkdir()
    (tmp_path / "game" / ".godot-version").write_text("4.8.0-stable\n")
    monkeypatch.setattr(bridge, "ROOT", tmp_path)
    with pytest.raises(SystemExit, match="verified only for Godot 4.7"):
        bridge._check_godot_version()


def test_stale_detection_covers_data_files(monkeypatch, tmp_path):
    # A file that used to be managed (in the old manifest) but is not in the
    # new outputs is stale even though it owns no glob like the sprite dir.
    gone = tmp_path / "gone.txt"
    gone.write_text("x")
    monkeypatch.setattr(bridge, "ROOT", tmp_path)
    manifest = tmp_path / ".bridge_manifest.json"
    manifest.write_text(json.dumps({"files": ["gone.txt", "kept.txt"]}))
    monkeypatch.setattr(bridge, "DST_MANIFEST", manifest)
    monkeypatch.setattr(bridge, "DST_SPRITE_DIR", tmp_path / "none")
    outputs = {tmp_path / "kept.txt": b"x"}
    assert bridge._collect_stale(outputs) == [gone]


def test_manifest_lists_every_output():
    out = bridge.build_outputs()
    listed = json.loads(out[bridge.DST_MANIFEST])["files"]
    assert listed == sorted(
        p.relative_to(bridge.ROOT).as_posix() for p in out
    )
    assert "game/data/.bridge_manifest.json" in listed


def test_crlf_source_is_refused(monkeypatch, tmp_path):
    bad = tmp_path / "cue_map.json"
    bad.write_bytes(b'{"a": 1}\r\n')
    monkeypatch.setattr(bridge, "ROOT", tmp_path)
    monkeypatch.setattr(bridge, "SRC_CUE_MAP", bad)
    with pytest.raises(SystemExit, match="CRLF"):
        bridge._check_text_sources()
