"""Build data/casting.json + docs/10_CASTING.md: every feeling -> sprite / motion / fx / voice / cues / music.

Validated against the stage gates (docs/02), the audio map (assets/audio/cue_map.json) and the exported art (art/leila).
    python3 tools/casting/build_casting.py
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
from leila_finish import SPRITES  # noqa: E402

TIERS = {"T0": [0, 1], "T1": [2, 2], "T2": [3, 3], "T3": [4, 5]}
CUE_GATE = {"giggle": 0, "laugh_soft": 0, "gasp": 0, "sigh": 0, "hum": 0, "sniffle": 0, "sob": 1, "heartbeat": 0,
            "heartbeat_fast": 2, "whisper": 2, "breath_close": 3, "music_box_note": 1, "clock_tick": 1, "phone_buzz": 1,
            "knock": 2, "door_slam": 3, "glass_shatter": 3, "static": 3, "laugh_unhinged": 4, "knife_draw": 4, "scream": 5}
MUSIC_GATE = {"keep": 0, "romantic": 0, "playful": 0, "calm": 0, "melancholy": 0, "tense": 2, "music_box": 2,
              "dread": 3, "distorted": 3, "silence": 2}
FX_GATE = {"blush_glow": 0, "hearts": 0, "sparkle": 0, "shake_small": 0, "zoom_face": 0, "rain": 1, "shake_big": 3,
           "flicker": 3, "darken": 3, "vignette_red": 3, "glitch": 3, "text_bleed": 4, "invert_flash": 4, "her_eyes": 5}
MOTIONS = {"breathe", "bounce", "shake", "tremble", "sink", "lean_in", "twitch", "freeze", "glitch"}

# resolver base table (docs/03 §3.1): tier -> (i1-2, i3)
RESOLVE = {
    "joy": [("01", "01"), ("01", "01"), ("01", "22"), ("22", "22")],
    "warmth": [("02", "02"), ("02", "02"), ("02", "02"), ("05", "05")],
    "playful": [("03", "03"), ("03", "03"), ("03", "03"), ("25", "25")],
    "proud": [("04", "04"), ("04", "04"), ("03", "03"), ("25", "25")],
    "shy": [("06", "06"), ("06", "06"), ("06", "24"), ("24", "24")],
    "love": [("06", "01"), ("06", "06"), ("24", "24"), ("24", "24")],
    "curious": [("05", "05"), ("05", "05"), ("05", "05"), ("05", "05")],
    "confused": [("08", "08"), ("08", "08"), ("08", "26"), ("29", "29")],
    "surprised": [("11", "11"), ("11", "11"), ("11", "26"), ("26", "26")],
    "nervous": [("13", "13"), ("13", "12"), ("13", "28"), ("28", "28")],
    "sad": [("14", "15"), ("14", "14"), ("14", "14"), ("23", "23")],
    "crying": [("15", "16"), ("15", "16"), ("16", "16"), ("16", "16")],
    "angry": [("17", "17"), ("17", "17"), ("17", "17"), ("17", "30")],
    "cold": [("07", "07"), ("07", "07"), ("07", "07"), ("25", "25")],
    "suspicious": [("09", "09"), ("09", "09"), ("09", "09"), ("25", "25")],
    "disgusted": [("18", "18"), ("18", "18"), ("18", "18"), ("18", "30")],
    "bored": [("10", "10"), ("10", "10"), ("10", "10"), ("23", "23")],
    "tired": [("12", "12"), ("12", "12"), ("12", "12"), ("23", "23")],
    "afraid": [("11", "20"), ("20", "20"), ("20", "20"), ("26", "26")],
    "pleading": [("19", "19"), ("19", "19"), ("19", "19"), ("19", "19")],
    "empty": [("07", "07"), ("10", "10"), ("23", "23"), ("23", "29")],
    "manic": [("03", "13"), ("13", "13"), ("22", "22"), ("22", "28")],
}

# feeling: valence, arousal, border tint, voice (semitones, rate), motion per intensity,
#          then per tier T0..T3: fx pool, cue pool, music state, and the model-facing hint
F = {
 "joy":        dict(v=3, a=2, tint="ff7a6e", voice=(3, 1.15), motion=["breathe", "bounce", "bounce"],
                    fx=[["sparkle", "hearts"], ["sparkle"], ["sparkle", "flicker"], ["vignette_red", "flicker"]],
                    cues=[["giggle", "laugh_soft"], ["giggle", "laugh_soft"], ["laugh_soft", "music_box_note"], ["laugh_unhinged", "music_box_note"]],
                    music=["playful", "playful", "music_box", "distorted"],
                    hint="giggle/laugh_soft; music playful"),
 "warmth":     dict(v=2, a=0, tint="e8a0a0", voice=(1, 0.95), motion=["breathe", "breathe", "bounce"],
                    fx=[["blush_glow", "sparkle"], ["blush_glow"], ["blush_glow"], ["darken"]],
                    cues=[["hum", "sigh"], ["hum", "music_box_note"], ["music_box_note", "hum"], ["music_box_note", "breath_close"]],
                    music=["calm", "calm", "music_box", "music_box"],
                    hint="hum/sigh; music calm"),
 "playful":    dict(v=1, a=1, tint="e08a84", voice=(2, 1.1), motion=["breathe", "bounce", "bounce"],
                    fx=[["sparkle"], ["sparkle"], ["sparkle"], ["darken"]],
                    cues=[["giggle"], ["giggle", "phone_buzz"], ["giggle", "whisper"], ["whisper", "laugh_unhinged"]],
                    music=["playful", "playful", "playful", "dread"],
                    hint="giggle; music playful"),
 "proud":      dict(v=2, a=2, tint="d8323a", voice=(2, 1.05), motion=["breathe", "bounce", "bounce"],
                    fx=[["sparkle", "zoom_face"], ["sparkle"], ["zoom_face"], ["zoom_face", "darken"]],
                    cues=[["laugh_soft"], ["laugh_soft"], ["laugh_soft", "heartbeat"], ["laugh_unhinged"]],
                    music=["playful", "playful", "playful", "dread"],
                    hint="laugh_soft; fx sparkle"),
 "shy":        dict(v=1, a=2, tint="e8a0a0", voice=(2, 1.25), motion=["bounce", "bounce", "tremble"],
                    fx=[["blush_glow", "hearts"], ["blush_glow", "hearts"], ["blush_glow"], ["blush_glow", "vignette_red"]],
                    cues=[["giggle", "gasp", "heartbeat"], ["giggle", "heartbeat"], ["heartbeat_fast", "giggle"], ["heartbeat_fast", "breath_close"]],
                    music=["romantic", "romantic", "music_box", "music_box"],
                    hint="giggle/heartbeat; fx blush_glow"),
 "love":       dict(v=3, a=2, tint="ff7a6e", voice=(1, 0.9), motion=["breathe", "lean_in", "lean_in"],
                    fx=[["hearts", "blush_glow"], ["hearts", "blush_glow"], ["hearts", "vignette_red"], ["vignette_red", "her_eyes"]],
                    cues=[["heartbeat", "sigh", "hum"], ["heartbeat", "music_box_note"], ["heartbeat_fast", "whisper"], ["breath_close", "heartbeat_fast"]],
                    music=["romantic", "romantic", "music_box", "music_box"],
                    hint="heartbeat; music romantic; fx hearts"),
 "curious":    dict(v=1, a=1, tint="efd2c6", voice=(2, 1.0), motion=["breathe", "bounce", "lean_in"],
                    fx=[["sparkle"], ["sparkle"], ["zoom_face"], ["zoom_face"]],
                    cues=[["hum", "gasp"], ["hum"], ["whisper"], ["whisper", "static"]],
                    music=["keep", "keep", "keep", "keep"],
                    hint="hum; usually no cue"),
 "confused":   dict(v=0, a=1, tint="b98b88", voice=(1, 0.85), motion=["breathe", "breathe", "shake"],
                    fx=[["zoom_face"], ["zoom_face"], ["glitch"], ["glitch", "text_bleed"]],
                    cues=[["sigh", "hum"], ["clock_tick"], ["static", "clock_tick"], ["static"]],
                    music=["keep", "keep", "tense", "distorted"],
                    hint="hum; usually no cue"),
 "surprised":  dict(v=0, a=3, tint="fbe9e0", voice=(4, 1.3), motion=["bounce", "shake", "shake"],
                    fx=[["shake_small", "zoom_face"], ["shake_small", "zoom_face"], ["shake_big", "zoom_face"], ["shake_big", "invert_flash"]],
                    cues=[["gasp"], ["gasp", "phone_buzz"], ["gasp", "glass_shatter", "door_slam"], ["glass_shatter", "static", "scream"]],
                    music=["keep", "keep", "tense", "silence"],
                    hint="gasp; fx shake_small"),
 "nervous":    dict(v=-1, a=2, tint="b65252", voice=(1, 1.3), motion=["breathe", "tremble", "tremble"],
                    fx=[["shake_small"], ["shake_small"], ["flicker"], ["flicker", "glitch"]],
                    cues=[["gasp", "heartbeat"], ["heartbeat", "clock_tick"], ["heartbeat_fast", "clock_tick"], ["heartbeat_fast", "clock_tick", "whisper"]],
                    music=["calm", "tense", "tense", "tense"],
                    hint="heartbeat; music tense when it lasts"),
 "sad":        dict(v=-2, a=0, tint="6c1522", voice=(-2, 0.8), motion=["sink", "sink", "sink"],
                    fx=[["rain"], ["rain"], ["rain", "darken"], ["darken"]],
                    cues=[["sigh", "sniffle"], ["sigh", "sniffle", "music_box_note"], ["music_box_note", "sigh"], ["music_box_note"]],
                    music=["melancholy", "melancholy", "melancholy", "silence"],
                    hint="sigh; music melancholy"),
 "crying":     dict(v=-2, a=1, tint="6fa8dc", voice=(-3, 0.75), motion=["sink", "tremble", "tremble"],
                    fx=[["rain"], ["rain"], ["rain", "darken"], ["darken", "text_bleed"]],
                    cues=[["sniffle", "sob"], ["sob", "sniffle"], ["sob"], ["sob", "whisper"]],
                    music=["melancholy", "melancholy", "melancholy", "music_box"],
                    hint="sniffle/sob; music melancholy"),
 "angry":      dict(v=-3, a=3, tint="d8323a", voice=(1, 1.2), loud=3, motion=["shake", "shake", "shake"],
                    fx=[["shake_small"], ["shake_small"], ["shake_big", "vignette_red"], ["shake_big", "vignette_red", "her_eyes"]],
                    cues=[["sigh"], ["knock"], ["door_slam", "glass_shatter"], ["knife_draw", "glass_shatter"]],
                    music=["keep", "tense", "tense", "dread"],
                    hint="fx shake_small; music tense"),
 "cold":       dict(v=-1, a=0, tint="433f4a", voice=(-1, 0.85), motion=["breathe", "breathe", "freeze"],
                    fx=[[], [], ["darken"], ["darken"]],
                    cues=[["sigh"], ["sigh", "clock_tick"], ["clock_tick"], ["whisper", "clock_tick"]],
                    music=["keep", "keep", "silence", "dread"],
                    hint="sigh or none; music keep"),
 "suspicious": dict(v=-1, a=1, tint="9b1420", voice=(-1, 0.9), motion=["breathe", "lean_in", "lean_in"],
                    fx=[["zoom_face"], ["zoom_face"], ["zoom_face", "vignette_red"], ["her_eyes", "vignette_red"]],
                    cues=[["hum"], ["phone_buzz", "clock_tick"], ["whisper", "knock"], ["breath_close", "whisper"]],
                    music=["keep", "tense", "tense", "dread"],
                    hint="hum; fx zoom_face"),
 "disgusted":  dict(v=-2, a=2, tint="7d2a2c", voice=(0, 1.1), motion=["shake", "shake", "shake"],
                    fx=[["shake_small"], ["shake_small"], ["darken"], ["vignette_red"]],
                    cues=[["sigh"], ["sigh"], ["door_slam"], ["knife_draw"]],
                    music=["keep", "keep", "tense", "dread"],
                    hint="sigh; fx shake_small"),
 "bored":      dict(v=-1, a=0, tint="333039", voice=(-2, 0.7), motion=["breathe", "sink", "sink"],
                    fx=[[], [], ["darken"], ["darken"]],
                    cues=[["sigh"], ["sigh", "clock_tick"], ["clock_tick"], ["clock_tick", "static"]],
                    music=["calm", "calm", "silence", "silence"],
                    hint="sigh; music calm"),
 "tired":      dict(v=-1, a=0, tint="8a5f63", voice=(-2, 0.7), motion=["sink", "sink", "sink"],
                    fx=[[], [], ["darken"], ["darken"]],
                    cues=[["sigh"], ["sigh", "clock_tick"], ["clock_tick"], ["clock_tick", "breath_close"]],
                    music=["calm", "melancholy", "melancholy", "dread"],
                    hint="sigh; music calm"),
 "afraid":     dict(v=-3, a=3, tint="fbe9e0", voice=(2, 1.4), motion=["tremble", "tremble", "tremble"],
                    fx=[["shake_small"], ["shake_small"], ["flicker", "darken"], ["flicker", "glitch"]],
                    cues=[["gasp", "heartbeat"], ["gasp", "heartbeat_fast"], ["heartbeat_fast", "knock"], ["heartbeat_fast", "static", "scream"]],
                    music=["keep", "tense", "dread", "dread"],
                    hint="gasp/heartbeat; music tense"),
 "pleading":   dict(v=-2, a=3, tint="e08a84", voice=(1, 1.2), motion=["lean_in", "tremble", "tremble"],
                    fx=[["zoom_face"], ["zoom_face"], ["zoom_face", "vignette_red"], ["her_eyes", "text_bleed"]],
                    cues=[["sniffle", "gasp"], ["sob", "heartbeat"], ["sob", "heartbeat_fast"], ["sob", "breath_close"]],
                    music=["melancholy", "melancholy", "music_box", "music_box"],
                    hint="sniffle; fx zoom_face"),
 "empty":      dict(v=-2, a=0, tint="26242c", voice=None, motion=["freeze", "freeze", "freeze"],
                    fx=[[], [], ["darken"], ["darken", "glitch"]],
                    cues=[[], ["clock_tick"], ["music_box_note"], ["static", "whisper"]],
                    music=["keep", "calm", "silence", "silence"],
                    hint="no cue; music silence when it deepens"),
 "manic":      dict(v=0, a=3, tint="ff3b3b", voice=(3, 1.5), motion=["bounce", "twitch", "twitch"],
                    fx=[["shake_small"], ["shake_small"], ["glitch"], ["glitch", "invert_flash", "text_bleed"]],
                    cues=[["giggle", "laugh_soft"], ["giggle"], ["laugh_soft", "heartbeat_fast", "static"], ["laugh_unhinged", "static"]],
                    music=["playful", "playful", "distorted", "distorted"],
                    hint="giggle; music playful"),
}

# what happens the moment a sprite appears (on top of the feeling's own casting)
ON_ENTER = {
    "11": {"system": ["stinger.soft"]},
    "16": {"cue": "sob"},
    "20": {"cue": "heartbeat_fast", "motion": "tremble"},
    "21": {"cue": "knife_draw", "system": ["stinger.mid"], "fx": "vignette_red", "music": "dread", "motion": "lean_in",
           "budget": "1 reveal per scene"},
    "22": {"cue": "laugh_unhinged", "cue_below_stage4": "laugh_soft", "motion": "shake"},
    "23": {"music": "silence", "system": ["weird"], "motion": "freeze"},
    "24": {"cue": "heartbeat", "fx": "hearts"},
    "25": {"system": ["stinger.soft"], "fx": "darken"},
    "26": {"system": ["glitch"], "motion": "twitch"},
    "27": {"cue": "music_box_note", "music": "music_box", "flag": "rival_gone"},
    "28": {"cue": "clock_tick", "motion": "twitch"},
    "29": {"cue": "static", "system": ["glitch", "distort_layer"], "fx": "glitch", "motion": "glitch",
           "note": "also the fallback face for invalid model output at T3"},
    "30": {"cue": "heartbeat_fast", "system": ["stinger.stage_change"], "fx": "her_eyes", "fx_below_stage5": "vignette_red",
           "music": "dread", "motion": "lean_in", "budget": "terminal climax only"},
}

VOICE_BY_STAGE = {"0": "voice_blip.stage0_2", "1": "voice_blip.stage0_2", "2": "voice_blip.stage0_2",
                  "3": "voice_blip.stage3", "4": "voice_blip.stage4", "5": "voice_blip.stage5", "AWAKE>=3": "voice_blip.awake"}

PATHS = {
    "YANDERE": {"tiers": ["T2", "T3"], "override": {"love": "24", "angry": "21", "suspicious": "28", "joy": "22"},
                "flagged": {"warmth": ["27", "rival_gone"]}, "music_bias": "music_box", "cue_bias": ["heartbeat_fast", "breath_close"]},
    "SPLIT": {"tiers": ["T2", "T3"], "override": {"crying": "16", "pleading": "19"},
              "idealize": ["01", "02", "24"], "devalue": ["17", "18", "07"], "rule": "alternate when beat valence flips",
              "music_bias": "tense", "cue_bias": ["sob", "door_slam"]},
    "TSUN": {"tiers": ["T2", "T3"], "override": {"playful": "03", "cold": "07", "disgusted": "18", "angry": "17"},
             "break": {"afraid": "20", "crying": "16"}, "music_bias": "keep", "cue_bias": ["sigh", "door_slam"]},
    "HOLLOW": {"tiers": ["T2", "T3"], "drift_to": ["23", "10", "12", "14"], "rule": "sprite changes only on intensity 3",
               "voice": "no blips at i1", "music_bias": "silence", "cue_bias": ["clock_tick", "music_box_note"]},
    "AWAKE": {"tiers": ["T2", "T3"], "override": {"confused": "29", "surprised": "26", "cold": "25", "manic": "22"},
              "rule": "glitch shader on every sprite change", "voice": "voice_blip.awake",
              "music_bias": "distorted", "cue_bias": ["static"]},
    "ANCHOR": {"tiers": ["T2", "T3"], "rule": "keeps healthy sprites; relapse beat uses 26/22 once, then 02",
               "music_bias": "calm", "cue_bias": ["hum", "sigh"]},
}


def main():
    with open(os.path.join(ROOT, "assets/audio/cue_map.json"), encoding="utf-8") as fh:
        cue_map = json.load(fh)
    errors = []
    art = {f[:2]: f for f in os.listdir(os.path.join(ROOT, "art/leila/px")) if f.endswith(".png")}

    def chk_tier(kind, name, tier, where):
        gate = {"cue": CUE_GATE, "music": MUSIC_GATE, "fx": FX_GATE}[kind]
        if name not in gate:
            errors.append(f"{where}: unknown {kind} '{name}'")
        elif gate[name] > TIERS[tier][1]:
            errors.append(f"{where}: {kind} '{name}' gated at stage {gate[name]} but used in {tier}")
        if kind == "cue" and name not in cue_map["cues"]:
            errors.append(f"{where}: cue '{name}' missing in cue_map.json")
        if kind == "music" and name not in ("keep", "silence") and name not in cue_map["music"]:
            errors.append(f"{where}: music '{name}' missing in cue_map.json")

    feelings = {}
    for f, d in F.items():
        tiers = {}
        for ti, t in enumerate(TIERS):
            for c in d["cues"][ti]:
                chk_tier("cue", c, t, f)
            for x in d["fx"][ti]:
                chk_tier("fx", x, t, f)
            chk_tier("music", d["music"][ti], t, f)
            i12, i3 = RESOLVE[f][ti]
            for s in (i12, i3):
                if s not in art:
                    errors.append(f"{f}: sprite {s} not exported")
            tiers[t] = {"stages": TIERS[t], "sprite": {"1": i12, "2": i12, "3": i3},
                        "fx": d["fx"][ti], "cues": d["cues"][ti], "music": d["music"][ti]}
        for m in d["motion"]:
            if m not in MOTIONS:
                errors.append(f"{f}: unknown motion {m}")
        empty_cues = [c for t in tiers.values() for c in t["cues"] if not cue_map["cues"].get(c, {}).get("files")]
        feelings[f] = {
            "valence": d["v"], "arousal": d["a"], "tint": "#" + d["tint"],
            "voice": None if d["voice"] is None else {"pitch_st": d["voice"][0], "rate": d["voice"][1],
                                                      "gain_db": d.get("loud", 0)},
            "motion": {"1": d["motion"][0], "2": d["motion"][1], "3": d["motion"][2]},
            "model_hint": d["hint"], "tiers": tiers,
            "cues_waiting_for_voice_actor": sorted(set(empty_cues)),
        }
    for s, e in ON_ENTER.items():
        if s not in art:
            errors.append(f"on_enter: sprite {s} missing")
        for g in e.get("system", []):
            if g not in cue_map["system"]:
                errors.append(f"on_enter {s}: system group {g} missing")
        for k in ("cue", "cue_below_stage4"):
            if k in e and e[k] not in cue_map["cues"]:
                errors.append(f"on_enter {s}: cue {e[k]} missing")
    for st, g in VOICE_BY_STAGE.items():
        if g not in cue_map["system"]:
            errors.append(f"voice {st}: {g} missing")

    sprites = {}
    for name, spec in SPRITES.items():
        k = name[:2]
        off = spec.get("off", [0, 0])
        sprites[k] = {"key": name[3:], "file": f"art/leila/x2/{name}.png", "native": f"art/leila/px/{name}.png",
                      "face": {kk: spec[kk] for kk in ("eyes", "brows", "mouth", "extras") if kk in spec},
                      "eyes_native": [[2 * (84 + off[0]), 2 * (49 + off[1])], [2 * (100 + off[0]), 2 * (49 + off[1])]],
                      "bust_crop_native": [104, 20, 280, 220],
                      "used_by": sorted({f for f, d in feelings.items() for t in d["tiers"].values() if k in t["sprite"].values()}),
                      "on_enter": ON_ENTER.get(k, {})}
    orphans = [k for k, v in sprites.items() if not v["used_by"] and k not in ("00", "21", "27", "29")]
    if orphans:
        errors.append(f"sprites never cast: {orphans}")
    if errors:
        print("\n".join(errors))
        sys.exit(1)

    out = {
        "version": 1,
        "about": "Leila-chan casting table: what the game does for every feeling the model names. Generated by "
                 "tools/casting/build_casting.py — edit that file, not this one.",
        "tiers": TIERS,
        "art": {"display": "art/leila/x2", "native": "art/leila/px", "display_size": [768, 1376],
                "native_size": [384, 688], "scale": 2, "filter": "nearest", "palette": "art/leila/palette.json"},
        "voice_by_stage": VOICE_BY_STAGE,
        "feelings": feelings,
        "paths": PATHS,
        "sprites": sprites,
        "intensity_3": {"camera": "push to bust_crop", "auto_sting": "stinger.soft (T0-T1) / stinger.mid (T2-T3) if budget allows",
                        "textbox_border": "feeling tint"},
        "fallback": {"T0": "00", "T1": "00", "T2": "00", "T3": "29"},
    }
    with open(os.path.join(ROOT, "data/casting.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1)
    write_doc(out)
    print(f"ok: {len(feelings)} feelings, {len(sprites)} sprites, all cues/music/fx/system groups validated")


def write_doc(c):
    L = []
    w = L.append
    w("# 10 — Casting: feeling → face → motion → voice → sound → music\n")
    w("> Generated from `tools/casting/build_casting.py` (also writes `data/casting.json`, the file the game loads).")
    w("> Every name below is validated against the stage gates (docs/02 §2), the audio map (`assets/audio/cue_map.json`)")
    w("> and the exported art (`art/leila/`). Re-run the script after any change.\n")
    w("## 1. How a beat is cast\n")
    w("The model only says `feeling` + `intensity` (and optionally `cue`, `music`, `fx`). The **CastingDirector** fills in")
    w("everything else from this table, so her face, body, voice, sounds and music always agree:\n")
    w("```")
    w("beat {feeling, intensity, cue?, say}")
    w("  ├─ sprite   = resolver(feeling, intensity, tier, path)        → §2 (+ path overrides §4)")
    w("  ├─ motion   = feelings[f].motion[intensity]                   → Godot tween preset (docs/03 §4)")
    w("  ├─ voice    = voice_by_stage[stage]  pitched by feelings[f].voice (empty → no blips: she speaks in silence)")
    w("  ├─ cue      = model's cue if allowed, else (auto-fill, i ≥ 2, budget ok) random from tiers[t].cues")
    w("  ├─ fx       = model's fx if allowed, else (i = 3) first of tiers[t].fx")
    w("  ├─ music    = model's music, else after 2 beats of the same feeling → tiers[t].music (20 s hold)")
    w("  └─ on_enter = extra sounds/fx when certain sprites appear (§3)")
    w("```\n")
    w("Model-chosen values always win when they pass the gates; the table only fills gaps and keeps them coherent.")
    w("The `model_hint` column is appended to the feeling glosses in `rules.md`, so the model learns the pairing.\n")
    w("## 2. Feelings\n")
    w("Sprite cells are `i1–2 / i3`. Tiers: T0 = stage 0–1, T1 = 2, T2 = 3, T3 = 4–5.\n")
    w("| Feeling | V/A | Sprites T0 · T1 · T2 · T3 | Motion i1/i2/i3 | Voice | Model hint |")
    w("|---|---|---|---|---|---|")
    for f, d in c["feelings"].items():
        sp = " · ".join(f'{t["sprite"]["1"]}/{t["sprite"]["3"]}' for t in d["tiers"].values())
        mo = "/".join(d["motion"].values())
        vo = "silent" if d["voice"] is None else f'{d["voice"]["pitch_st"]:+d} st ×{d["voice"]["rate"]}' + (
            f' +{d["voice"]["gain_db"]} dB' if d["voice"]["gain_db"] else "")
        w(f'| **{f}** | {d["valence"]:+d}/{d["arousal"]} | {sp} | {mo} | {vo} | {d["model_hint"]} |')
    w("\n### 2.1 Sound, music and screen per tier\n")
    w("| Feeling | Tier | Cue pool | Music | FX |")
    w("|---|---|---|---|---|")
    for f, d in c["feelings"].items():
        for t, x in d["tiers"].items():
            w(f'| {f if t == "T0" else ""} | {t} | {", ".join(x["cues"]) or "—"} | {x["music"]} | {", ".join(x["fx"]) or "—"} |')
    w("\nCues `hum`, `sniffle` and `sob` are cast but have no files yet (voice-actor gap, docs/04 §8.4); until then the")
    w("AudioDirector skips them silently.\n")
    w("## 3. Sprite on-enter events\n")
    w("| Sprite | Extra when it appears |")
    w("|---|---|")
    for k, e in ON_ENTER.items():
        w(f'| {k} {c["sprites"][k]["key"]} | ' + "; ".join(f"{a}: {', '.join(b) if isinstance(b, list) else b}" for a, b in e.items()) + " |")
    w("\n## 4. Paths\n")
    w("| Path | Overrides (T2–T3) | Rule | Music / cue bias |")
    w("|---|---|---|---|")
    for p, d in c["paths"].items():
        ov = ", ".join(f"{a}→{b}" for a, b in d.get("override", {}).items())
        w(f'| {p} | {ov or "—"} | {d.get("rule", "")} | {d["music_bias"]} / {", ".join(d["cue_bias"])} |')
    w("\n## 5. Voice by stage\n")
    w("| Stage | Blip pool (`cue_map.json` system group) |")
    w("|---|---|")
    for k, v in c["voice_by_stage"].items():
        w(f"| {k} | `{v}` |")
    w("\n## 6. Sprite reference\n")
    w("All sprites: native 384×688 (`art/leila/px`), display 768×1376 (`art/leila/x2`, nearest-neighbour ×2).")
    w("Eye points (native px) drive the glow/`her_eyes` shaders; `bust_crop_native` is the `zoom_face` / intensity-3 frame.\n")
    w("| # | Key | Face (eyes · mouth · extras) | Cast by feelings |")
    w("|---|---|---|---|")
    for k, s in c["sprites"].items():
        fc = s["face"]
        eyes = fc["eyes"] if isinstance(fc["eyes"], str) else "/".join(fc["eyes"])
        w(f'| {k} | {s["key"]} | {eyes} · {fc.get("mouth", "")} · {", ".join(fc.get("extras", []))} | {", ".join(s["used_by"]) or "special (idle / flag / fallback)"} |')
    with open(os.path.join(ROOT, "docs/10_CASTING.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
