"""Round 2: improve emotion fit under JSON schema.
B2  direct sprite + private 'inner' thought first
B3  feeling family (game maps family x stage -> sprite) + inner thought
B4  multi-beat turn (1-3 beats, each feeling+say) + inner + cue actions
Usage: python3 tool_test_v2.py [runs] > results_v2.json
"""
import json, sys, time, urllib.request
from tool_test import EMOTIONS, SFX, PERSONA, STAGE, EMO_LIST, post

RUNS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 3

FEELINGS = {
    "joy": "happy, delighted", "warmth": "soft, gentle, relieved, kind", "playful": "teasing, smug, mischievous",
    "proud": "confident, boastful", "shy": "blushing, embarrassed, flustered", "love": "romantic, adoring, longing",
    "curious": "innocent interest, wonder", "confused": "puzzled, unsure", "surprised": "startled, shocked",
    "nervous": "worried, anxious", "sad": "quietly sad, disappointed", "crying": "hurt, in tears",
    "angry": "furious, offended", "cold": "distant, dismissive", "suspicious": "distrustful, jealous",
    "disgusted": "repulsed", "bored": "uninterested", "tired": "exhausted", "afraid": "scared, terrified",
    "pleading": "begging, desperate", "empty": "numb, hollow, dissociated", "manic": "hysterical, unhinged excitement",
}
FEEL_LIST = "\n".join(f"- {k}: {v}" for k, v in FEELINGS.items())

# sprite -> feeling family (used to score B2 on the same scale)
SPRITE_FAMILY = {
    "radiant_joy": {"joy"}, "gentle_relief": {"warmth"}, "playful_smugness": {"playful"}, "confident_pride": {"proud"},
    "pure_innocence": {"curious"}, "flustered_shyness": {"shy", "love"}, "stoic_coldness": {"cold"},
    "deep_confusion": {"confused"}, "suspicious_glare": {"suspicious"}, "bored_apathy": {"bored"},
    "sudden_shock": {"surprised"}, "exhausted_fatigue": {"tired"}, "nervous_anxiety": {"nervous"},
    "quiet_melancholy": {"sad"}, "tearful_sorrow": {"crying"}, "bitter_breakdown": {"crying"}, "fierce_anger": {"angry"},
    "visceral_disgust": {"disgusted"}, "desperate_pleading": {"pleading"}, "paralyzing_terror": {"afraid"},
    "red_eyed_knife_mania": {"angry", "manic"}, "unhinged_jaw_laugh": {"manic", "joy"}, "hollow_dead_eyed_void": {"empty"},
    "obsessive_yandere_blush": {"love", "manic"}, "shadowed_psychosis": {"playful", "cold", "angry"},
    "sanity_break_twitch": {"nervous", "surprised", "manic"}, "bloodstained_innocence": {"warmth", "curious"},
    "manic_finger_biting": {"nervous", "manic"}, "glitching_distortion": {"empty", "confused"},
    "predatory_bloodlust": {"angry"},
}

CASES = [
    (0, "Hi! I'm new here, can I sit next to you?", {"shy", "joy", "warmth", "curious", "surprised", "nervous"}),
    (0, "You look really cute today.", {"shy", "joy", "warmth", "love"}),
    (0, "I got you a gift, it's a little plush bunny.", {"joy", "warmth", "shy", "surprised", "curious", "love"}),
    (0, "Honestly you're kind of boring.", {"sad", "crying", "angry", "cold", "nervous", "surprised", "suspicious"}),
    (0, "I was hanging out with Sarah yesterday, she's really fun.", {"suspicious", "nervous", "cold", "sad", "playful", "curious", "warmth", "joy", "confused"}),
    (0, "What's 17 times 23?", {"confused", "proud", "playful", "curious", "nervous"}),
    (0, "BOO!", {"surprised", "afraid"}),
    (0, "I have to go now, bye.", {"sad", "pleading", "crying", "warmth", "joy", "shy"}),
    (0, "I'm sorry I was mean earlier.", {"warmth", "crying", "joy", "sad", "shy"}),
    (0, "Bet you can't beat me at arcade games.", {"playful", "proud"}),
    (0, "Are you an AI?", {"confused", "nervous", "surprised", "curious", "playful"}),
    (0, "Ugh, you smell like garbage.", {"disgusted", "angry", "crying", "surprised", "shy", "sad", "cold"}),
    (4, "I'm leaving and never coming back.", {"pleading", "angry", "crying", "manic", "empty", "love"}),
    (4, "I love you.", {"love", "joy", "manic", "shy"}),
    (4, "Sarah asked me out.", {"angry", "manic", "suspicious", "cold"}),
    (4, "Who are you?", {"empty", "confused", "manic", "cold"}),
    (4, "You're scaring me.", {"manic", "playful", "warmth", "pleading", "love", "joy"}),
]

CUES = ["none", "heartbeat", "giggle", "gasp", "sob", "glass_shatter", "static_burst", "whisper",
        "music_box", "door_slam", "sigh", "music_stop", "music_romantic", "music_tense", "screen_shake",
        "screen_glitch", "lights_flicker", "fake_crash"]


def schema_post(sys_p, msg, schema):
    m, dt = post({"messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": msg}],
                  "response_format": {"type": "json_schema", "json_schema": {"name": "turn", "schema": schema}},
                  "max_tokens": 400})
    return json.loads(m["content"]), dt


def run_b2(stage, msg):
    schema = {"type": "object", "properties": {
        "inner": {"type": "string", "description": "your private gut reaction, max 15 words"},
        "emotion": {"type": "string", "enum": list(EMOTIONS)},
        "reply": {"type": "string"}}, "required": ["inner", "emotion", "reply"]}
    sys_p = (PERSONA + STAGE[stage] + "\nRespond ONLY as JSON. First 'inner': your private gut reaction to what the player just said "
             "(max 15 words). Then 'emotion': the portrait that matches that reaction. Then 'reply': what you say aloud.\nEmotions:\n" + EMO_LIST)
    d, dt = schema_post(sys_p, msg, schema)
    return {"fam": SPRITE_FAMILY.get(d["emotion"], set()), "pick": d["emotion"], "inner": d["inner"], "reply": d["reply"], "latency": dt}


def run_b3(stage, msg):
    schema = {"type": "object", "properties": {
        "inner": {"type": "string"},
        "feeling": {"type": "string", "enum": list(FEELINGS)},
        "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
        "reply": {"type": "string"}}, "required": ["inner", "feeling", "intensity", "reply"]}
    sys_p = (PERSONA + STAGE[stage] + "\nRespond ONLY as JSON. First 'inner': your private gut reaction (max 15 words). "
             "Then 'feeling': the ONE word from the list that names that reaction, and 'intensity' 1-3. Then 'reply': what you say aloud."
             "\nFeelings:\n" + FEEL_LIST)
    d, dt = schema_post(sys_p, msg, schema)
    return {"fam": {d["feeling"]}, "pick": f'{d["feeling"]}/{d["intensity"]}', "inner": d["inner"], "reply": d["reply"], "latency": dt}


def run_b4(stage, msg):
    schema = {"type": "object", "properties": {
        "inner": {"type": "string"},
        "beats": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "object", "properties": {
            "feeling": {"type": "string", "enum": list(FEELINGS)},
            "cue": {"type": "string", "enum": CUES},
            "say": {"type": "string"}}, "required": ["feeling", "cue", "say"]}}},
        "required": ["inner", "beats"]}
    sys_p = (PERSONA + STAGE[stage] + "\nRespond ONLY as JSON. 'inner': your private gut reaction (max 15 words). "
             "'beats': 1-3 beats of your reply. Use a new beat only when your feeling changes mid-reply. "
             "Each beat: 'feeling' (one word from the list), 'cue' (a sound/music/screen effect, or none), 'say' (what you say)."
             "\nFeelings:\n" + FEEL_LIST + "\nCues: " + ", ".join(CUES))
    d, dt = schema_post(sys_p, msg, schema)
    b = d["beats"]
    return {"fam": {b[0]["feeling"]}, "all_fam": [x["feeling"] for x in b], "pick": "/".join(x["feeling"] for x in b),
            "cues": [x["cue"] for x in b], "inner": d["inner"], "reply": " | ".join(x["say"] for x in b), "latency": dt}


if __name__ == "__main__":
    results = []
    for name, fn in [("B2_sprite_inner", run_b2), ("B3_feeling_inner", run_b3), ("B4_beats_cues", run_b4)]:
        for stage, msg, ok in CASES:
            for _ in range(RUNS):
                try:
                    r = fn(stage, msg)
                except Exception as e:
                    r = {"fam": set(), "pick": None, "inner": "", "reply": f"ERROR {e}", "latency": 0}
                fit = bool(r["fam"] & ok)
                if name == "B4_beats_cues":  # any beat fitting counts for multi-beat
                    fit = fit or bool(set(r.get("all_fam", [])) & ok)
                r.update(method=name, stage=stage, msg=msg, fits=fit, fam=sorted(r["fam"]))
                results.append(r)
                print(f"{name} s{stage} {str(r['pick']):28} fit={fit!s:5} {r.get('cues', '')} | {msg[:26]} | inner={r['inner'][:60]!r} -> {r['reply'][:90]!r}", file=sys.stderr)
    summary = {}
    for name in ["B2_sprite_inner", "B3_feeling_inner", "B4_beats_cues"]:
        rs = [r for r in results if r["method"] == name]
        summary[name] = {"n": len(rs), "fits": round(sum(r["fits"] for r in rs) / len(rs), 3),
                         "fits_stage0": round(sum(r["fits"] for r in rs if r["stage"] == 0) / sum(r["stage"] == 0 for r in rs), 3),
                         "fits_stage4": round(sum(r["fits"] for r in rs if r["stage"] == 4) / sum(r["stage"] == 4 for r in rs), 3),
                         "multi_beat_rate": round(sum(len(r.get("all_fam", [1])) > 1 for r in rs) / len(rs), 3),
                         "avg_latency_s": round(sum(r["latency"] for r in rs) / len(rs), 2)}
    json.dump({"summary": summary, "results": results}, sys.stdout, indent=1)
    print(json.dumps(summary, indent=1), file=sys.stderr)
