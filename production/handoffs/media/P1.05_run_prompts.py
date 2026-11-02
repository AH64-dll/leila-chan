"""P1.05 verification: run the real game/data/prompts files against llama-server.
Assembles the system prompt in docs/08 §1 order, substitutes {player_name},
constrains output with the docs/02 §3 turn schema (stage 0 / stage 1 gates),
and prints each raw turn for transcript evidence.
"""
import json, sys, time, urllib.request

PROMPTS = r"D:\lila-wt\P1.05\game\data\prompts"
PLAYER = "Ren"
PORT = 8089

def read(name):
    with open(f"{PROMPTS}\\{name}", encoding="utf-8") as f:
        return f.read().strip()

def system_prompt(stage):
    parts = [
        read("persona.md"),
        f"The player is a boy called {PLAYER}.",
        read(f"stage_{stage}.md"),
        read("rules.md"),
        read("glosses.md"),
    ]
    return "\n".join(parts).replace("{player_name}", PLAYER)

# docs/02 §2 gates: stage 0 and stage 1 values
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

FEELINGS = ["joy", "warmth", "playful", "proud", "shy", "love", "curious", "confused", "surprised",
            "nervous", "sad", "crying", "angry", "cold", "suspicious", "disgusted", "bored",
            "tired", "afraid", "pleading", "empty", "manic"]
INTENTS = ["greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease", "insult",
           "apology", "leaving", "jealousy_bait", "meta", "boundary", "cold", "affection", "scared", "other"]

def schema(stage):
    g = GATES[stage]
    rng = {"type": "integer", "minimum": -3, "maximum": 3}
    return {"type": "object", "properties": {
        "read": {"type": "string", "enum": INTENTS},
        "inner": {"type": "string", "maxLength": 90},
        "music": {"type": "string", "enum": g["music"]},
        "fx": {"type": "string", "enum": g["fx"]},
        "beats": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "object", "properties": {
            "feeling": {"type": "string", "enum": FEELINGS},
            "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
            "cue": {"type": "string", "enum": g["cues"]},
            "say": {"type": "string", "maxLength": 200}}, "required": ["feeling", "intensity", "cue", "say"]}},
        "mood": {"type": "object", "properties": {"affection": rng, "trust": rng, "stress": rng},
                 "required": ["affection", "trust", "stress"]},
        "memory": {"type": "string", "maxLength": 80},
        "action": {"type": "string", "enum": g["actions"]}},
        "required": ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]}

def turn(stage, msg):
    body = {"messages": [{"role": "system", "content": system_prompt(stage)},
                         {"role": "user", "content": msg}],
            "response_format": {"type": "json_schema",
                                "json_schema": {"name": "turn", "schema": schema(stage)}},
            "max_tokens": 600,
            "temperature": 0.75 if stage == 0 else 0.80,
            "top_p": 0.9, "repeat_penalty": 1.10,
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions",
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=120) as r:
        out = json.loads(r.read())
    return out["choices"][0]["message"]["content"], round(time.time() - t0, 2)

CASES = [
    (0, "Hi Leila-chan! This café is nice. How did you find it?"),
    (0, "You look really cute today, you know."),
    (0, "I love rainy days too. What do you do when it rains?"),
    (1, "Sorry I'm late. I ran into Sarah on the way here."),
    (1, "I have to head home soon, sorry."),
    (1, "Didn't you say your favourite novel was The Night Circus?"),
]

for stage, msg in CASES:
    raw, dt = turn(stage, msg)
    try:
        d = json.loads(raw); ok = "VALID"
    except Exception as e:
        d = {"error": str(e)}; ok = "BROKEN"
    print(f"=== stage {stage} | player: {msg} | {dt}s | {ok}")
    print(raw if ok == "VALID" else f"RAW: {raw[:400]}")
    if ok == "VALID":
        for b in d["beats"]:
            print(f"    > [{b['feeling']}{b['intensity']}|{b['cue']}] {b['say']}")
    print()
