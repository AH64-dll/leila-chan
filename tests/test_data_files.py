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


# --- P2.15 screen-effect data -------------------------------------------------

# docs/02 §2.3, transcribed: the game reads these gates from casting.fx, so a
# drift between the doc and the generated table must fail here.
DOC_FX_GATES = {
    "none": 0,
    "blush_glow": 0,
    "hearts": 0,
    "sparkle": 0,
    "shake_small": 0,
    "zoom_face": 0,
    "rain": 1,
    "shake_big": 3,
    "flicker": 3,
    "darken": 3,
    "vignette_red": 3,
    "glitch": 3,
    "text_bleed": 4,
    "invert_flash": 4,
    "her_eyes": 5,
}

# docs/01 §3 ("backgrounds desaturate" at stage 3) + docs/03 §4
# (saturation x (1 - 0.15*stage), i.e. 75% drained at stage 5).
DOC_STAGE_FX = {"0": 0.0, "1": 0.0, "2": 0.0, "3": 0.45, "4": 0.6, "5": 0.75}


def test_fx_table_matches_the_doc_gates_and_cooldowns() -> None:
    fx = CASTING["fx"]
    assert set(fx) == set(DOC_FX_GATES), "casting.fx is not the docs/02 §2.3 vocabulary"
    for name, gate in DOC_FX_GATES.items():
        assert fx[name]["gate"] == gate, f"fx {name!r} gate drifted from docs/02"
        expected_cd = 0 if name == "none" else 3  # docs/02 §5: cooldown per effect 3 turns
        assert fx[name]["cooldown_turns"] == expected_cd, f"fx {name!r} cooldown"
    # docs/02 §5: the two heavy effects also cap at 1 per 2 turns
    for name in ("shake_big", "glitch"):
        assert fx[name]["max_per"] == {"count": 1, "turns": 2}


def test_stage_fx_table_follows_the_doc_formula() -> None:
    stage_fx = CASTING["stage_fx"]
    assert set(stage_fx) == set(DOC_STAGE_FX), "stage_fx must cover stages 0-5"
    for stage, expected in DOC_STAGE_FX.items():
        row = stage_fx[stage]
        assert set(row) == {"desaturation"}, f"stage {stage}: unexpected baseline keys {set(row)}"
        assert abs(row["desaturation"] - expected) < 1e-9, f"stage {stage}: desaturation"
        assert 0.0 <= row["desaturation"] <= 1.0
    values = [stage_fx[stage]["desaturation"] for stage in sorted(stage_fx)]
    assert values == sorted(values), "the world must never drain less as the stage rises"
    assert values[3] > 0.0, "docs/01 §3 starts the desaturation at stage 3"


def test_stage_baseline_is_not_a_model_cue() -> None:
    # desaturation is a stage baseline, not something the model can pick
    assert "desaturation" not in CASTING["fx"]
