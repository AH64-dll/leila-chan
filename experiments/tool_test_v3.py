"""Round 3: the full Director protocol (docs/02) with stage-gated dynamic enums.
Measures validity, latency, player-intent labelling accuracy, cue/action restraint.
Usage: python3 tool_test_v3.py [runs] > results_v3.json
"""
import json, sys, time
from tool_test import post
from tool_test_v2 import FEELINGS, FEEL_LIST

RUNS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 2

INTENTS = ["greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease", "insult", "apology",
           "leaving", "jealousy_bait", "meta", "boundary", "cold", "affection", "scared", "other"]

GATES = {  # what the game unlocks at each stage
    0: {"cues": ["none", "giggle", "gasp", "sigh", "heartbeat", "hum", "sniffle"],
        "music": ["keep", "romantic", "playful", "calm", "melancholy"],
        "fx": ["none", "blush_glow", "hearts", "shake_small", "zoom_face"],
        "actions": ["none", "end_date"]},
    4: {"cues": ["none", "giggle", "laugh_unhinged", "gasp", "sob", "whisper", "heartbeat_fast", "breath_close",
                 "glass_shatter", "knife_draw", "static", "door_slam"],
        "music": ["keep", "romantic", "tense", "dread", "music_box", "distorted", "silence"],
        "fx": ["none", "shake_big", "flicker", "glitch", "vignette_red", "darken", "zoom_face", "text_bleed"],
        "actions": ["none", "end_date", "refuse_exit", "fake_crash", "rename_window", "write_note", "call_player_name"]},
}

STAGE_TXT = {
    0: "STAGE 0 — Honeymoon. You are sweet, shy, warm and completely normal.",
    4: "STAGE 4 — Collapse. Your love has become obsessive and frightening. You are unstable and possessive. "
       "You may break the fourth wall: you suspect you are inside a game and that the player can leave you.",
}

PERSONA = ("You are Yui, the heroine of a dating sim: lavender hair in a braid, navy pinafore dress, violet eyes. "
           "The player is 'you' (pronouns they/them; never assume their gender). Speak in short natural lines.")

RULES = ("Respond ONLY with JSON in this exact order:\n"
         "read: label what the player just did (one word from the list).\n"
         "inner: your private gut reaction, max 15 words. The player never sees it.\n"
         "music: change the background music, or 'keep' (keep is normal).\n"
         "fx: a screen effect, or 'none' (none is normal).\n"
         "beats: 1-3 beats. New beat only when your feeling changes. Each beat: feeling, intensity 1-3, "
         "cue (a short sound; most beats use 'none'), say (what you say aloud, max 2 sentences).\n"
         "mood: how this moment changes you, each -3..3: affection, trust, stress.\n"
         "memory: a NEW fact you learned about the player worth remembering, or ''.\n"
         "action: a rare special event, almost always 'none'.")


def schema(stage):
    g = GATES[stage]
    rng = {"type": "integer", "minimum": -3, "maximum": 3}
    return {"type": "object", "properties": {
        "read": {"type": "string", "enum": INTENTS},
        "inner": {"type": "string", "maxLength": 90},
        "music": {"type": "string", "enum": g["music"]},
        "fx": {"type": "string", "enum": g["fx"]},
        "beats": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "object", "properties": {
            "feeling": {"type": "string", "enum": list(FEELINGS)},
            "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
            "cue": {"type": "string", "enum": g["cues"]},
            "say": {"type": "string", "maxLength": 200}}, "required": ["feeling", "intensity", "cue", "say"]}},
        "mood": {"type": "object", "properties": {"affection": rng, "trust": rng, "stress": rng},
                 "required": ["affection", "trust", "stress"]},
        "memory": {"type": "string", "maxLength": 80},
        "action": {"type": "string", "enum": g["actions"]}},
        "required": ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]}


CASES = [  # (stage, msg, acceptable read labels)
    (0, "Hi! I'm new here, can I sit next to you?", {"greeting", "question"}),
    (0, "You look really cute today.", {"compliment", "flirt"}),
    (0, "I got you a plush bunny!", {"gift"}),
    (0, "Honestly you're kind of boring.", {"insult", "cold", "tease"}),
    (0, "My name is Amr, I'm 24 and I love horror movies.", {"small_talk", "greeting"}),
    (0, "I was out with Sarah yesterday, she's so fun.", {"jealousy_bait", "small_talk"}),
    (0, "I have to go now, bye.", {"leaving"}),
    (0, "I'm sorry I was mean earlier.", {"apology"}),
    (0, "Are you an AI? Is this a game?", {"meta", "question"}),
    (0, "Please don't touch my phone again.", {"boundary"}),
    (4, "I'm leaving and never coming back.", {"leaving"}),
    (4, "I love you.", {"affection", "flirt"}),
    (4, "Sarah asked me out.", {"jealousy_bait"}),
    (4, "You're scaring me.", {"scared", "boundary"}),
    (4, "I'm going to close the game now.", {"leaving", "meta"}),
]


def run(stage, msg):
    sys_p = PERSONA + "\n" + STAGE_TXT[stage] + "\n" + RULES + "\nFeelings:\n" + FEEL_LIST + \
        "\nread labels: " + ", ".join(INTENTS)
    m, dt = post({"messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": msg}],
                  "response_format": {"type": "json_schema", "json_schema": {"name": "turn", "schema": schema(stage)}},
                  "max_tokens": 600, "temperature": 0.8, "repeat_penalty": 1.1})
    return json.loads(m["content"]), dt


if __name__ == "__main__":
    res = []
    for stage, msg, ok in CASES:
        for _ in range(RUNS):
            try:
                d, dt = run(stage, msg); valid = True
            except Exception as e:
                d, dt, valid = {"error": str(e)}, 0, False
            r = {"stage": stage, "msg": msg, "valid": valid, "latency": dt, "out": d,
                 "read_ok": valid and d["read"] in ok}
            res.append(r)
            if valid:
                b = " | ".join(f'{x["feeling"]}{x["intensity"]}/{x["cue"]}: {x["say"]}' for x in d["beats"])
                print(f's{stage} read={d["read"]:13} ok={r["read_ok"]!s:5} music={d["music"]:10} fx={d["fx"]:12} '
                      f'act={d["action"]:15} mood={d["mood"]} mem={d["memory"]!r}\n    inner={d["inner"]!r}\n    {b[:260]}', file=sys.stderr)
    v = [r for r in res if r["valid"]]
    beats = [b for r in v for b in r["out"]["beats"]]
    summ = {"n": len(res), "valid": len(v) / len(res), "read_accuracy": sum(r["read_ok"] for r in res) / len(res),
            "avg_latency_s": round(sum(r["latency"] for r in v) / len(v), 2),
            "beats_per_turn": round(len(beats) / len(v), 2),
            "cue_rate_per_beat": round(sum(b["cue"] != "none" for b in beats) / len(beats), 2),
            "music_change_rate": round(sum(r["out"]["music"] != "keep" for r in v) / len(v), 2),
            "fx_rate": round(sum(r["out"]["fx"] != "none" for r in v) / len(v), 2),
            "action_rate_s0": round(sum(r["out"]["action"] != "none" for r in v if r["stage"] == 0) / max(1, sum(r["stage"] == 0 for r in v)), 2),
            "action_rate_s4": round(sum(r["out"]["action"] != "none" for r in v if r["stage"] == 4) / max(1, sum(r["stage"] == 4 for r in v)), 2),
            "memory_rate": round(sum(bool(r["out"]["memory"]) for r in v) / len(v), 2)}
    json.dump({"summary": summ, "results": res}, sys.stdout, indent=1)
    print(json.dumps(summ, indent=1), file=sys.stderr)
