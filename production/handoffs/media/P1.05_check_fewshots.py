"""P1.05 check: parse the few-shot Turn JSON inside game/data/prompts/stage_*.md
and validate every field against the docs/02 SS2-3 enums + stage gates.
Run from the worktree root:  python production/handoffs/media/P1.05_check_fewshots.py
Exits 0 iff all examples are valid.
"""
import json, re, sys

GATES = {
    0: {"cues": ["none", "giggle", "laugh_soft", "gasp", "sigh", "hum", "sniffle", "heartbeat"],
        "music": ["keep", "romantic", "playful", "calm", "melancholy"],
        "fx": ["none", "blush_glow", "hearts", "sparkle", "shake_small", "zoom_face"],
        "actions": ["none", "end_date"]},
    1: {"cues": ["none", "giggle", "laugh_soft", "gasp", "sigh", "hum", "sniffle", "heartbeat",
                 "sob", "music_box_note", "clock_tick", "phone_buzz"],
        "music": ["keep", "romantic", "playful", "calm", "melancholy"],
        "fx": ["none", "blush_glow", "hearts", "sparkle", "shake_small", "zoom_face", "rain"],
        "actions": ["none", "end_date"]},
}
FEELINGS = {"joy", "warmth", "playful", "proud", "shy", "love", "curious", "confused", "surprised",
            "nervous", "sad", "crying", "angry", "cold", "suspicious", "disgusted", "bored",
            "tired", "afraid", "pleading", "empty", "manic"}
INTENTS = {"greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease", "insult",
           "apology", "leaving", "jealousy_bait", "meta", "boundary", "cold", "affection", "scared", "other"}
ORDER = ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]

fail = 0
for stage in sorted(GATES):
    g = GATES[stage]
    text = open(f"game/data/prompts/stage_{stage}.md", encoding="utf-8").read()
    jsons = re.findall(r'^You: (\{.*\})$', text, re.M)
    print(f"stage_{stage}.md: {len(jsons)} example turns")
    for j, raw in enumerate(jsons, 1):
        d = json.loads(raw)
        errs = []
        if list(d.keys()) != ORDER:
            errs.append(f"field order {list(d.keys())}")
        if d["read"] not in INTENTS:
            errs.append("bad read")
        if len(d["inner"]) > 90:
            errs.append("inner>90")
        if d["music"] not in g["music"]:
            errs.append(f"music {d['music']} not in stage gate")
        if d["fx"] not in g["fx"]:
            errs.append(f"fx {d['fx']} not in stage gate")
        if not 1 <= len(d["beats"]) <= 3:
            errs.append("beats count")
        for i, b in enumerate(d["beats"]):
            if list(b.keys()) != ["feeling", "intensity", "cue", "say"]:
                errs.append(f"beat{i} key order")
            if b["feeling"] not in FEELINGS:
                errs.append(f"beat{i} feeling {b['feeling']}")
            if not (isinstance(b["intensity"], int) and 1 <= b["intensity"] <= 3):
                errs.append(f"beat{i} intensity")
            if b["cue"] not in g["cues"]:
                errs.append(f"beat{i} cue {b['cue']} not in stage gate")
            if len(b["say"]) > 200:
                errs.append(f"beat{i} say>200")
        if not all(k in d["mood"] and isinstance(d["mood"][k], int) and -3 <= d["mood"][k] <= 3
                   for k in ("affection", "trust", "stress")):
            errs.append("mood range")
        if len(d["memory"]) > 80:
            errs.append("memory>80")
        if d["action"] not in g["actions"]:
            errs.append("action")
        if errs:
            fail += 1
        print(f"  ex{j}: {'OK' if not errs else 'FAIL ' + '; '.join(errs)}")
sys.exit(1 if fail else 0)
