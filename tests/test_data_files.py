"""Smoke tests for the committed data files the game loads (P0.07).

Guards the JSON contract, not the content: broken JSON or dangling sprite
references are exactly the merge breakage CI exists to catch.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASTING = json.loads((ROOT / "data" / "casting.json").read_text(encoding="utf-8"))
CUE_MAP = json.loads((ROOT / "assets" / "audio" / "cue_map.json").read_text(encoding="utf-8"))


def test_casting_schema() -> None:
    for key in ("version", "tiers", "art", "feelings", "paths", "sprites", "fallback"):
        assert key in CASTING, f"casting.json missing top-level key {key!r}"
    assert CASTING["feelings"], "casting.json has no feelings"
    assert CASTING["sprites"], "casting.json has no sprites"


def test_casting_sprite_refs_resolve() -> None:
    sprites = set(CASTING["sprites"])
    for feeling, spec in CASTING["feelings"].items():
        for tier, tier_spec in spec["tiers"].items():
            for intensity, sprite in tier_spec["sprite"].items():
                assert sprite in sprites, (
                    f"feeling {feeling!r} tier {tier} intensity {intensity} "
                    f"-> missing sprite {sprite!r}"
                )
    for tier, sprite in CASTING["fallback"].items():
        assert sprite in sprites, f"fallback[{tier}] -> missing sprite {sprite!r}"


def test_cue_map_schema() -> None:
    for key in ("cues", "system", "music"):
        assert key in CUE_MAP, f"cue_map.json missing top-level key {key!r}"
    assert CUE_MAP["cues"], "cue_map.json has no cues"
