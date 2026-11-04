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

# docs/03 §4: every sprite change is a crossfade plus a motion preset "chosen by intensity and family", with no
# extra art per intensity. The doc fixes each preset's displacement (6 px hop, +-4 px shake, ...) but gives no
# amplitude ladder, so this is the art direction for P2.14: the doc's numbers are the i2 baseline and i1/i3 are
# quieter/louder versions of the same preset. The resolver ships it as packet.motion_scale; Character multiplies.
MOTION_INTENSITY = {"1": 0.6, "2": 1.0, "3": 1.4}

# docs/03 §1 "Tier" column: the corruption tiers each sprite is documented for. The resolver's step-3 gate
# ("sprite.min_tier <= tier") reads tiers[0]; a path override that names a T3-only face therefore cannot leak
# into T2 (YANDERE angry at stage 3 stays on 17, the knife waits for T3). The upper bound is descriptive — the
# base table itself casts 16 at T0 i3 (docs/03 §3.1) — so only the minimum is enforced.
SPRITE_TIERS = {
    "00": ["T0", "T1", "T2", "T3"], "01": ["T0", "T1", "T2", "T3"], "02": ["T0", "T1", "T2", "T3"],
    "03": ["T0", "T1", "T2"], "04": ["T0", "T1"], "05": ["T0", "T1", "T2", "T3"],
    "06": ["T0", "T1", "T2"], "07": ["T0", "T1", "T2", "T3"], "08": ["T0", "T1", "T2"],
    "09": ["T0", "T1", "T2", "T3"], "10": ["T0", "T1", "T2", "T3"], "11": ["T0", "T1", "T2", "T3"],
    "12": ["T0", "T1", "T2", "T3"], "13": ["T0", "T1", "T2"], "14": ["T0", "T1", "T2", "T3"],
    "15": ["T0", "T1", "T2", "T3"], "16": ["T1", "T2", "T3"], "17": ["T0", "T1", "T2", "T3"],
    "18": ["T0", "T1", "T2", "T3"], "19": ["T1", "T2", "T3"], "20": ["T0", "T1", "T2", "T3"],
    "21": ["T3"], "22": ["T2", "T3"], "23": ["T2", "T3"], "24": ["T2", "T3"], "25": ["T3"],
    "26": ["T2", "T3"], "27": ["T3"], "28": ["T2", "T3"], "29": ["T3"], "30": ["T3"],
}

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

# docs/02 §2.3 + §5, generated into casting.fx so the game reads its effect
# gates/cooldowns from data instead of code (role playbook: tables live in
# casting.json, never forked). "gate" is the minimum stage; "cooldown_turns"
# is how many turns after a firing stay locked (earliest refire = gap + 1);
# "max_per" is the extra per-window cap the doc gives the two heavy effects.
# Implemented names in v1 are the five stage-0 effects; the rest ship their
# gate data now so the schema builder (P1.07 follow-up) and FX.gd drop them
# before they are coded.
FX = {name: {"gate": gate, "cooldown_turns": 3} for name, gate in FX_GATE.items()}
FX["none"] = {"gate": 0, "cooldown_turns": 0}
for _heavy in ("shake_big", "glitch"):
    FX[_heavy]["max_per"] = {"count": 1, "turns": 2}

# Stage baseline screen effects (P2.15). These are not model picks: no effect
# gate and no cooldown — the world drifts with the stage itself. Onset comes
# from docs/01 §3 ("backgrounds desaturate" at stage 3); the rate comes from
# docs/03 §4's desaturate preset, saturation x (1 - 0.15*stage), so stage 5
# leaves 25% saturation. Kept in data so FX.gd reads a table, never a formula.
STAGE_FX = {
    str(stage): {"desaturation": 0.0 if stage < 3 else round(0.15 * stage, 2)}
    for stage in range(6)
}

# docs/03 §3 step 4 (anti-repeat): when one sprite would show on a third beat in a row, the
# resolver swaps to the feeling's sibling face for that beat. The doc gives only the example
# 06 -> 01; the rest keeps the same mood family (positive<->positive, hostile<->hostile,
# low<->low) and only uses healthy faces (id <= 20), so a T0-T1 swap can never escalate or
# read as corruption. Every sibling differs from the feeling's own T0-T1 sprite set.
# T2+ path-aware siblings are P2.14's job (docs/03 §3.2).
SIBLINGS = {
    "joy": "06", "warmth": "05", "playful": "05", "proud": "01",
    "shy": "01",  # the doc's own example: repeated 06 -> 01
    "love": "02", "curious": "01", "confused": "09", "surprised": "08", "nervous": "06",
    "sad": "12", "crying": "14", "angry": "18", "cold": "10", "suspicious": "07",
    "disgusted": "17", "bored": "12", "tired": "10", "afraid": "13", "pleading": "15",
    "empty": "14", "manic": "11",
}

# docs/10 §3.1 delegates the T2+ siblings to the resolver's path rules. A corrupt face repeating three beats
# in a row has no healthy face it may swap to without lying about the state (a corrupted face can never quietly
# turn healthy), so the corrupt band gets its own table: one sibling per sprite, same path signature or mood
# family (docs/03 §1 "Feeling family"), never crossing into 01-20. "Love and violence share a face"
# (docs/03 §3.2): 21 -> 24 -> 28 is the YANDERE loop, 22 -> 26 -> 28 the manic/nervous one.
SIBLINGS_CORRUPT = {
    "21": "24", "22": "26", "23": "29", "24": "28", "25": "29",
    "26": "28", "27": "24", "28": "26", "29": "23", "30": "21",
}

# docs/01 §4 "Sprites:" lines, transcribed by hand and checked against the doc by tests/test_casting_paths.py.
# These are the path *pools*: every face a path's own rules may put on screen, so the design bible stays the
# authority on each path's look and the resolver never invents a signature.
PATH_POOLS = {
    # §4.1 "Sprites: 01, 06, 24, 21, 30, 27."
    "YANDERE": ["01", "06", "24", "21", "30", "27"],
    # §4.2 "Sprites: 01 <-> 17 rapid swaps, 19, 15, 16, 13."
    "SPLIT": ["01", "17", "19", "15", "16", "13"],
    # §4.3 "Sprites: 03, 07, 09, 17, 10, 26."
    "TSUN": ["03", "07", "09", "17", "10", "26"],
    # §4.4 "Sprites: 14, 12, 10, 23, 25."
    "HOLLOW": ["14", "12", "10", "23", "25"],
    # §4.5 "Sprites: 08, 29, 11, 22, 25."
    "AWAKE": ["08", "29", "11", "22", "25"],
    # §4.6 "Sprites: 02, 05, 06, 13, 14, then sudden spikes of 26 / 21 she recovers from."
    "ANCHOR": ["02", "05", "06", "13", "14", "26", "21"],
}

# docs/03 §3.2's per-path spot fixes that name a face outside the path's docs/01 §4 pool. They are the resolver
# spec's explicit overrides (P2.14 shipped them), so they stay; the pool column keeps docs/01 §4 honest and this
# list keeps the divergence countable instead of silent. tests/test_casting_paths.py compares both against the docs.
DOC03_EXTRAS = {
    "YANDERE": ["22", "28"],     # §3.2 "joy→22", "suspicious→28" (docs/01 §4.1 omits both)
    "SPLIT": [],                 # 01↔17, 16, 19 are all in the §4.2 pool
    "TSUN": ["16", "18", "20"],  # §3.2 "disgusted→18"; break "afraid→20, crying→16"
    "HOLLOW": [],                # drift 23/10/12/14 sits inside the §4.4 pool
    "AWAKE": ["26"],             # §3.2 "surprised→26" (docs/01 §4.5 lists 11 instead)
    "ANCHOR": ["22"],            # §3.2 relapse "26/22"; docs/01 §4.6 gives the spikes as "26 / 21"
}

PATHS = {
    "YANDERE": {"pool": PATH_POOLS["YANDERE"], "tiers": ["T2", "T3"],
                "override": {"love": "24", "angry": "21", "suspicious": "28", "joy": "22"},
                "flagged": {"warmth": ["27", "rival_gone"]}, "rule": "love and violence share a face",
                "music_bias": "music_box", "cue_bias": ["heartbeat_fast", "breath_close"]},
    # docs/01 §4.2: "01 ↔ 17 rapid swaps". docs/03 §3.2's broader "positive → 01/02/24, negative → 17/18/07"
    # lists are the feelings' own base-table faces (02, 24, 18, 07 all resolve there anyway), so the *rule*
    # uses the two whiplash faces the design bible names; see the P3.06 handoff DCR.
    "SPLIT": {"pool": PATH_POOLS["SPLIT"], "tiers": ["T2", "T3"], "override": {"crying": "16", "pleading": "19"},
              "idealize": "01", "devalue": "17", "rule": "alternate when beat valence flips",
              "music_bias": "tense", "cue_bias": ["sob", "door_slam"]},
    "TSUN": {"pool": PATH_POOLS["TSUN"], "tiers": ["T2", "T3"],
             "override": {"playful": "03", "cold": "07", "disgusted": "18", "angry": "17"},
             "break": {"flag": "tsun_break", "sprite": {"afraid": "20", "crying": "16"}},
             "rule": "the act cracks into a scared child",
             "music_bias": "keep", "cue_bias": ["sigh", "door_slam"]},
    # docs/03 §3.2: "most feelings drift to 23/10/12/14; sprite changes only on intensity 3" — the face stops
    # responding. Sad/tired/bored keep their own numb face, every other feeling (cold included) drifts to 23.
    # Cold has no entry of its own: 25's first tier is T3 and cold's T3 base cell is already 25, so a `cold: 25`
    # entry could never change a face (DES-2); 25 stays a docs/01 §4.4 pool signature via the base table.
    "HOLLOW": {"pool": PATH_POOLS["HOLLOW"], "tiers": ["T2", "T3"], "change_intensity": 3,
               "drift": {"default": "23", "sad": "14", "tired": "12", "bored": "10"},
               "rule": "sprite changes only on intensity 3", "voice": "no blips at i1",
               "music_bias": "silence", "cue_bias": ["clock_tick", "music_box_note"]},
    "AWAKE": {"pool": PATH_POOLS["AWAKE"], "tiers": ["T2", "T3"],
              "override": {"confused": "29", "surprised": "26", "cold": "25", "manic": "22"},
              "rule": "glitch shader on every sprite change", "shader": "glitch", "voice": "voice_blip.awake",
              "music_bias": "distorted", "cue_bias": ["static"]},
    # docs/03 §3.2: "keeps healthy sprites; relapse beats use 26/22 for one beat, then 02". healthy_tier is the
    # pre-fracture column the beat resolves from, so ANCHOR never shows a corrupt face (docs/01 §4.6). The
    # relapse spike is data: distress for a negative beat, elation for a positive one, and — docs/01 §4.6's
    # "sudden spikes of 26 / 21" — the knife at stage 5 intensity 3 on a distress beat (docs/03 §1 gives 21
    # valence -3, and it stays under its 1-per-scene reveal budget).
    "ANCHOR": {"pool": PATH_POOLS["ANCHOR"], "tiers": ["T2", "T3"], "healthy_tier": "T1",
               "relapse": {"flag": "anchor_relapse", "spike": {"distress": "26", "elation": "22"},
                           "crisis": {"sprite": "21", "tier": "T3", "intensity": 3}, "then": "02"},
               "rule": "keeps healthy sprites; relapse beat uses 26/22 once, then 02",
               "music_bias": "calm", "cue_bias": ["hum", "sigh"]},
}
for _path, _spec in PATHS.items():
    _spec["docs_03_extras"] = DOC03_EXTRAS[_path]


def path_rule_sprites(spec):
    """(sprite, where) for every face a path's own rule tables can select (docs/03 §3.2)."""
    out = []
    for feeling, sprite in spec.get("override", {}).items():
        out.append((sprite, f"override {feeling}"))
    for feeling, pair in spec.get("flagged", {}).items():
        out.append((pair[0], f"flagged {feeling}"))
    for feeling, sprite in spec.get("break", {}).get("sprite", {}).items():
        out.append((sprite, f"break {feeling}"))
    for key in ("idealize", "devalue"):
        if spec.get(key):
            out.append((spec[key], key))
    for feeling, sprite in spec.get("drift", {}).items():
        out.append((sprite, f"drift {feeling}"))
    relapse = spec.get("relapse", {})
    for key, sprite in relapse.get("spike", {}).items():
        out.append((sprite, f"relapse {key}"))
    if relapse.get("crisis", {}).get("sprite"):
        out.append((relapse["crisis"]["sprite"], "relapse crisis"))
    if relapse.get("then"):
        out.append((relapse["then"], "relapse recovery"))
    return out


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
    for f, s in SIBLINGS.items():
        if f not in F:
            errors.append(f"siblings: unknown feeling '{f}'")
            continue
        if s not in art:
            errors.append(f"siblings {f}: sprite {s} not exported")
        own = {feelings[f]["tiers"][t]["sprite"][i] for t in ("T0", "T1") for i in ("1", "2", "3")}
        if s in own:
            errors.append(f"siblings {f}: {s} is the feeling's own T0-T1 face (anti-repeat would be a no-op)")
        if int(s) > 20:
            errors.append(f"siblings {f}: {s} is a corruption face (docs/03 §1) — siblings stay healthy")
    if sorted(SPRITE_TIERS) != sorted(art):
        errors.append(f"sprite tiers: declared {sorted(SPRITE_TIERS)} != exported {sorted(art)}")
    for k, ts in SPRITE_TIERS.items():
        if not ts or any(t not in TIERS for t in ts):
            errors.append(f"sprite tiers {k}: unknown tier list {ts}")
        elif ts != [t for t in TIERS if t in ts]:
            errors.append(f"sprite tiers {k}: {ts} is not in T0..T3 order")
    for s, e in SIBLINGS_CORRUPT.items():
        if s not in art or e not in art:
            errors.append(f"siblings_corrupt {s}: sprite {e} not exported")
            continue
        if s == e:
            errors.append(f"siblings_corrupt {s}: points at itself (anti-repeat would be a no-op)")
        if int(s) < 21 or int(e) < 21:
            errors.append(f"siblings_corrupt {s}->{e}: both faces must be in the corruption band 21-30")
        if TIERS[SPRITE_TIERS[e][0]][0] > TIERS[SPRITE_TIERS[s][-1]][1]:
            errors.append(f"siblings_corrupt {s}->{e}: {e} starts above the tier {s} ends at")
    for k, v in MOTION_INTENSITY.items():
        if k not in ("1", "2", "3") or not 0.0 < v <= 3.0:
            errors.append(f"motion intensity {k}: {v} is not a plausible amplitude scale")
    if sorted(PATHS) != sorted(PATH_POOLS):
        errors.append(f"paths {sorted(PATHS)} != pools {sorted(PATH_POOLS)}")
    for name, spec in PATHS.items():
        pool = spec.get("pool", [])
        if not pool:
            errors.append(f"paths {name}: empty docs/01 §4 pool")
        if len(set(pool)) != len(pool):
            errors.append(f"paths {name}: pool repeats a sprite")
        for s in pool:
            if s not in art:
                errors.append(f"paths {name}: pool sprite {s} not exported")
        if spec.get("healthy_tier", "T1") not in ("T0", "T1"):
            errors.append(f"paths {name}: healthy_tier {spec['healthy_tier']} is not pre-fracture")
        if "break" in spec and not str(spec["break"].get("flag", "")).strip():
            errors.append(f"paths {name}: break rule needs the beat flag that fires it")
        if "relapse" in spec and not str(spec["relapse"].get("flag", "")).strip():
            errors.append(f"paths {name}: relapse rule needs the beat flag that fires it")
        rules = path_rule_sprites(spec)
        for s, where in rules:
            if s not in art:
                errors.append(f"paths {name}: {where} names sprite {s}, which is not exported")
        extras = sorted({s for s, _ in rules if s not in pool})
        if extras != sorted(DOC03_EXTRAS[name]):
            errors.append(f"paths {name}: docs/03 extras {extras} != DOC03_EXTRAS {sorted(DOC03_EXTRAS[name])}")
    for s, e in ON_ENTER.items():
        if s not in art:
            errors.append(f"on_enter: sprite {s} missing")
        for g in e.get("system", []):
            if g not in cue_map["system"]:
                errors.append(f"on_enter {s}: system group {g} missing")
        for k in ("cue", "cue_below_stage4"):
            if k in e and e[k] not in cue_map["cues"]:
                errors.append(f"on_enter {s}: cue {e[k]} missing")
        budget = e.get("budget", "")
        if budget and not (budget == "terminal climax only" or (budget.split(" ")[0].isdigit()
                                                              and budget.endswith(" reveal per scene"))):
            errors.append(f"on_enter {s}: unknown budget form '{budget}'")
    for st, g in VOICE_BY_STAGE.items():
        if g not in cue_map["system"]:
            errors.append(f"voice {st}: {g} missing")

    sprites = {}
    for name, spec in SPRITES.items():
        k = name[:2]
        off = spec.get("off", [0, 0])
        sprites[k] = {"key": name[3:], "file": f"art/leila/x2/{name}.png", "native": f"art/leila/px/{name}.png",
                      "tiers": SPRITE_TIERS[k],
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
        "motion_intensity": MOTION_INTENSITY,
        "fx": FX,
        "stage_fx": STAGE_FX,
        "feelings": feelings,
        "siblings": SIBLINGS,
        "siblings_corrupt": SIBLINGS_CORRUPT,
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
    w("  ├─ sprite   = resolver(feeling, intensity, tier, path)        → §2 (+ path overrides §4;")
    w("  │              same sprite 3 beats in a row → siblings[f], docs/03 §3 step 4)")
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
    ladder = " · ".join(f"i{k} ×{v:g}" for k, v in c["motion_intensity"].items())
    w(f"\nMotion presets have no extra art per intensity (docs/03 §4): the displacement is scaled by")
    w(f"`casting.motion_intensity` ({ladder}), with i2 = the doc's baseline. A beat's `motion_scale` travels in the")
    w("resolver packet, so bounce/shake/tremble/sink/lean-in/twitch all breathe more or less with the intensity.")
    w("\n### 2.1 Sound, music and screen per tier\n")
    w("| Feeling | Tier | Cue pool | Music | FX |")
    w("|---|---|---|---|---|")
    for f, d in c["feelings"].items():
        for t, x in d["tiers"].items():
            w(f'| {f if t == "T0" else ""} | {t} | {", ".join(x["cues"]) or "—"} | {x["music"]} | {", ".join(x["fx"]) or "—"} |')
    w("\nCues `hum`, `sniffle` and `sob` are cast but have no files yet (voice-actor gap, docs/04 §8.4); until then the")
    w("AudioDirector skips them silently.\n")
    w("### 2.2 Screen-effect rules (docs/02 §2.3 + §5)\n")
    w("`fx.none` is the default (no effect). `gate` is the minimum stage; `cooldown_turns` is how many turns")
    w("after a firing stay locked (earliest refire = gap + 1); `max_per` is the doc's extra per-window cap.")
    w("FX.gd reads this table and drops over-gate/over-budget picks silently; the debug menu (F6) can force")
    w("any implemented effect.\n")
    w("Photosensitive mode changes the look, never the rule: `flicker` becomes a single dim instead of a flicker")
    w("(no luminance change faster than 3 Hz, docs/02 §2.3) and `invert_flash` is suppressed. Reduced motion")
    w("still cuts `shake_big` and `shake_small` — shakes are skipped, not softened.\n")
    w("| Effect | Gate stage | Cooldown (turns) | Extra cap |")
    w("|---|---|---|---|")
    for name, spec in c["fx"].items():
        cap = spec.get("max_per")
        cap_s = f'max {cap["count"]} per {cap["turns"]} turns' if cap else "—"
        cd = spec.get("cooldown_turns", 0)
        w(f'| {name} | {spec["gate"]} | {cd or "—"} | {cap_s} |')
    w("")
    w("### 2.3 Stage baseline effects (docs/01 §3 + docs/03 §4)\n")
    w("The world itself drifts as the stage rises. These rows are not model picks, so they carry no gate and no")
    w("cooldown; FX.gd applies the row on every stage change and names it to the host. `desaturation` is the")
    w("screen's 0–1 drain: docs/01 §3 starts it at stage 3 (\"backgrounds desaturate\") and docs/03 §4 gives the")
    w("rate (`saturation × (1 − 0.15·stage)`, so stage 5 keeps 25%). The host ramps the value, so a transition")
    w("reads as a drain rather than a snap.\n")
    w("| Stage | Desaturation |")
    w("|---|---|")
    for stage, spec in c["stage_fx"].items():
        w(f'| {stage} | {spec["desaturation"]:.2f} |')
    w("")
    w("## 3. Sprite on-enter events\n")
    w("Extra sound, music, fx or motion the instant a sprite appears, on top of the beat's own casting. `cue_below_stage4`")
    w("and `fx_below_stage5` swap in the quieter variant under that stage; `budget` caps how often the effect may fire")
    w("(`1 reveal per scene` gates the sprite itself, `terminal climax only` withholds the `system` sting until stage 5).\n")
    w("| Sprite | Extra when it appears |")
    w("|---|---|")
    for k, e in ON_ENTER.items():
        w(f'| {k} {c["sprites"][k]["key"]} | ' + "; ".join(f"{a}: {', '.join(b) if isinstance(b, list) else b}" for a, b in e.items()) + " |")
    w("\n### 3.1 Anti-repeat siblings\n")
    w("docs/03 §3 step 4: when one sprite would show on a third beat in a row, the resolver shows the feeling's sibling")
    w("instead. Siblings are healthy faces (ids 01–20, so a T0–T1 swap can never read as corruption) in the same mood")
    w("family; a swap never crosses the healthy/corrupt band.\n")
    w("| Feeling | Sibling |")
    w("|---|---|")
    for f, s in c["siblings"].items():
        w(f'| {f} | {s} {c["sprites"][s]["key"]} |')
    w("\n### 3.2 Corrupt-band siblings (T2+)\n")
    w("A corrupted sprite cannot swap to a healthy one (that would lie about the state), so the corruption band has its")
    w("own table: one sibling per sprite, same path signature or mood family, addressed by sprite id. A sibling whose")
    w("own `tiers` start above the current tier is skipped, so the beat simply repeats rather than jump forward.\n")
    w("| Sprite | Tiers | Sibling |")
    w("|---|---|---|")
    for s, e in c["siblings_corrupt"].items():
        w(f'| {s} {c["sprites"][s]["key"]} | {"–".join(c["sprites"][s]["tiers"])} | {e} {c["sprites"][e]["key"]} |')
    w("\n## 4. Paths\n")
    w("Each path owns a sprite pool — docs/01 §4's own `Sprites:` line — and docs/03 §3.2's beat rules, live from")
    w("the path's tiers up (T2–T3; below them every path is inert, docs/03 §3 step 2). A face a path's rules name")
    w("must be either in its pool or one of the **docs/03 extras** counted below, and every pool face is exported")
    w("art: a docs/03 §3.2 override the design bible's pool omits still ships (the resolver spec is explicit per")
    w("feeling), but the divergence stays visible here instead of hiding in code.\n")
    w("| Path | Pool (docs/01 §4) | Overrides (docs/03 §3.2) | Rule | Music / cue bias |")
    w("|---|---|---|---|---|")
    for p, d in c["paths"].items():
        parts = [", ".join(f"{a}→{b}" for a, b in d.get("override", {}).items()),
                 ", ".join(f"{a}→{b[0]} if {b[1]}" for a, b in d.get("flagged", {}).items()),
                 ", ".join(f"{a}→{b}" for a, b in d.get("break", {}).get("sprite", {}).items())]
        ov = "; ".join(x for x in parts if x) or "—"
        w(f'| {p} | {" ".join(d["pool"])} | {ov} | {d.get("rule", "")} | {d["music_bias"]} / {", ".join(d["cue_bias"])} |')
    w("")
    w("### 4.1 Beat rules\n")
    w("| Path | What the resolver does | Data |")
    w("|---|---|---|")
    for p, d in c["paths"].items():
        bits = []
        if "idealize" in d:
            bits.append(f'valence flip → {d["idealize"]} (idealize) / {d["devalue"]} (devalue)')
        if "break" in d:
            made = ", ".join(f"{f}→{s}" for f, s in d["break"]["sprite"].items())
            bits.append(f'flag `{d["break"]["flag"]}`: {made}')
        if "drift" in d:
            drift = ", ".join(f"{f}→{s}" for f, s in d["drift"].items())
            bits.append(f'freezes below i{d["change_intensity"]}; drift {drift}')
        if "healthy_tier" in d:
            bits.append(f'keeps healthy sprites: resolves from the {d["healthy_tier"]} (pre-fracture) column')
        if "relapse" in d:
            r = d["relapse"]
            spikes = ", ".join(f"{k}→{s}" for k, s in r["spike"].items())
            bits.append(f'flag `{r["flag"]}`: {spikes}; crisis→{r["crisis"]["sprite"]} at '
                        f'{r["crisis"]["tier"]} i{r["crisis"]["intensity"]} on a distress '
                        f'(negative-valence) beat; then {r["then"]}')
        if bits:
            w(f'| {p} | {d.get("rule", "")} | {" · ".join(bits)} |')
    w("")
    w("A pool face is a docs/01 §4 signature. Faces docs/03 §3.2 names outside the pool (kept, see above):")
    for p, d in c["paths"].items():
        w(f'- {p}: {", ".join(d.get("docs_03_extras", [])) or "—"}')
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
