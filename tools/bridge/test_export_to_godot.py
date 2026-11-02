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


def _fake_roots(monkeypatch, tmp_path):
    """Point the bridge's destinations at a scratch tree."""
    monkeypatch.setattr(bridge, "ROOT", tmp_path)
    monkeypatch.setattr(bridge, "DST_DATA_DIR", tmp_path / "game" / "data")
    monkeypatch.setattr(bridge, "DST_SPRITE_DIR", tmp_path / "none")
    monkeypatch.setattr(
        bridge, "DST_MANIFEST", tmp_path / "tools" / "bridge" / ".bridge_manifest.json"
    )


def test_stale_detection_covers_data_files(monkeypatch, tmp_path):
    # A file that used to be managed (in the old manifest) but is not in the
    # new outputs is stale even though it owns no glob like the sprite dir.
    _fake_roots(monkeypatch, tmp_path)
    data = bridge.DST_DATA_DIR
    data.mkdir(parents=True)
    gone = data / "gone.txt"
    gone.write_text("x")
    (data / "kept.txt").write_text("x")
    bridge.DST_MANIFEST.parent.mkdir(parents=True)
    bridge.DST_MANIFEST.write_text(
        json.dumps({"files": ["game/data/gone.txt", "game/data/kept.txt"]})
    )
    outputs = {data / "kept.txt": b"x"}
    assert bridge._collect_stale(outputs) == [gone.resolve()]


@pytest.mark.parametrize("entry", [
    "../victim.txt",                       # escapes ROOT entirely
    "tools/bridge/export_to_godot.py",     # real repo file, not a destination
    "game/casting.json",                   # inside game/ but outside game/data
    42,                                    # non-string
    "",                                    # empty
])
def test_manifest_rejects_bad_entries(monkeypatch, tmp_path, entry):
    # A generated manifest never contains these, so one means it was edited or
    # badly merged: refuse rather than let stale pruning unlink them.
    _fake_roots(monkeypatch, tmp_path)
    bridge.DST_MANIFEST.parent.mkdir(parents=True)
    bridge.DST_MANIFEST.write_text(json.dumps({"files": [entry]}))
    with pytest.raises(SystemExit, match="not a bridge destination"):
        bridge._prev_managed()


def test_manifest_rejects_absolute_path(monkeypatch, tmp_path):
    _fake_roots(monkeypatch, tmp_path)
    bridge.DST_MANIFEST.parent.mkdir(parents=True)
    bridge.DST_MANIFEST.write_text(
        json.dumps({"files": [str(tmp_path.resolve() / "game" / "data" / "x.json")]})
    )
    with pytest.raises(SystemExit, match="not a bridge destination"):
        bridge._prev_managed()


def test_manifest_lives_outside_the_godot_project():
    # tools/bridge/, not game/: Godot must never scan bridge bookkeeping.
    assert bridge.DST_MANIFEST.relative_to(bridge.ROOT).parts[0] == "tools"


def test_manifest_lists_every_output():
    out = bridge.build_outputs()
    listed = json.loads(out[bridge.DST_MANIFEST])["files"]
    assert listed == sorted(
        p.relative_to(bridge.ROOT).as_posix() for p in out
    )
    assert "tools/bridge/.bridge_manifest.json" in listed


def test_crlf_source_is_refused(monkeypatch, tmp_path):
    bad = tmp_path / "cue_map.json"
    bad.write_bytes(b'{"a": 1}\r\n')
    monkeypatch.setattr(bridge, "ROOT", tmp_path)
    monkeypatch.setattr(bridge, "SRC_CUE_MAP", bad)
    with pytest.raises(SystemExit, match="CRLF"):
        bridge._check_text_sources()
