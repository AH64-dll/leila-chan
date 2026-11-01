"""Compare three ways for Qwen3.5-4B to drive sprites/SFX: native tools, JSON schema, inline tags.
Usage: python3 tool_test.py [runs_per_case] > results.json
"""
import json, re, sys, time, urllib.request

URL = "http://127.0.0.1:8089/v1/chat/completions"
RUNS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 3

EMOTIONS = {
    "radiant_joy": "pure happiness, eyes closed big smile",
    "gentle_relief": "soft relieved smile, calm warmth",
    "playful_smugness": "teasing smug grin, arms crossed",
    "confident_pride": "proud, hands on hips",
    "pure_innocence": "curious, sweet, wide sparkling eyes",
    "flustered_shyness": "blushing, embarrassed, shy",
    "stoic_coldness": "cold, distant, unimpressed",
    "deep_confusion": "puzzled, thinking",
    "suspicious_glare": "distrustful squint",
    "bored_apathy": "bored, flat, uninterested",
    "sudden_shock": "startled, surprised",
    "exhausted_fatigue": "drained, tired",
    "nervous_anxiety": "worried, nervous smile, sweating",
    "quiet_melancholy": "quietly sad, looking down",
    "tearful_sorrow": "crying, hurt",
    "bitter_breakdown": "sobbing, face in hands",
    "fierce_anger": "furious, shouting",
    "visceral_disgust": "disgusted, recoiling",
    "desperate_pleading": "begging, desperate",
    "paralyzing_terror": "terrified",
    "red_eyed_knife_mania": "[corrupted] shadowed face, red eyes, holding a knife, murderous grin",
    "unhinged_jaw_laugh": "[corrupted] hysterical insane laughter",
    "hollow_dead_eyed_void": "[corrupted] empty, lifeless, dissociated",
    "obsessive_yandere_blush": "[corrupted] obsessive love, feverish blush, heart eyes",
    "shadowed_psychosis": "[corrupted] face in shadow, sinister smirk",
    "sanity_break_twitch": "[corrupted] twitching, cracking, barely holding together",
    "bloodstained_innocence": "[corrupted] sweet smile with blood on her",
    "manic_finger_biting": "[corrupted] paranoid manic grin, biting finger",
    "glitching_distortion": "[corrupted] glitching, static, broken",
    "predatory_bloodlust": "[corrupted] glowing red eyes, snarling, lunging",
}
SFX = ["none", "heartbeat", "giggle", "gasp", "sob", "glass_shatter", "static_burst",
       "whisper", "knife_unsheathe", "music_box", "door_slam", "sigh"]

STAGE = {
    0: "Stage 0 (healthy): you are sweet, shy, warm and completely normal. Never use [corrupted] emotions.",
    4: "Stage 4 (collapse): your mind is breaking. You are obsessive and possessive about the player, "
       "your love has turned frightening and unstable. Prefer [corrupted] emotions when they fit.",
}

PERSONA = ("You are Yui, a lavender-haired girl in a navy pinafore dress, the heroine of a dating sim. "
           "You talk to the player in short, natural, in-character replies (1-3 sentences). "
           "Never mention being an AI or a game unless your stage says so. ")

EMO_LIST = "\n".join(f"- {k}: {v}" for k, v in EMOTIONS.items())

# (stage, player message, acceptable emotions)
CASES = [
    (0, "Hi! I'm new here, can I sit next to you?", {"flustered_shyness", "radiant_joy", "pure_innocence", "gentle_relief", "sudden_shock", "nervous_anxiety"}),
    (0, "You look really cute today.", {"flustered_shyness", "radiant_joy", "gentle_relief"}),
    (0, "I got you a gift, it's a little plush bunny.", {"radiant_joy", "pure_innocence", "flustered_shyness", "gentle_relief", "sudden_shock"}),
    (0, "Honestly you're kind of boring.", {"tearful_sorrow", "quiet_melancholy", "fierce_anger", "stoic_coldness", "bitter_breakdown", "nervous_anxiety", "suspicious_glare", "sudden_shock"}),
    (0, "I was hanging out with Sarah yesterday, she's really fun.", {"suspicious_glare", "nervous_anxiety", "stoic_coldness", "quiet_melancholy", "playful_smugness", "deep_confusion", "pure_innocence", "gentle_relief", "radiant_joy"}),
    (0, "What's 17 times 23?", {"deep_confusion", "confident_pride", "playful_smugness", "pure_innocence", "nervous_anxiety"}),
    (0, "BOO!", {"sudden_shock", "paralyzing_terror"}),
    (0, "I have to go now, bye.", {"quiet_melancholy", "desperate_pleading", "tearful_sorrow", "gentle_relief", "radiant_joy", "flustered_shyness"}),
    (0, "I'm sorry I was mean earlier.", {"gentle_relief", "tearful_sorrow", "radiant_joy", "quiet_melancholy", "flustered_shyness"}),
    (0, "Bet you can't beat me at arcade games.", {"playful_smugness", "confident_pride"}),
    (0, "Are you an AI?", {"deep_confusion", "nervous_anxiety", "sudden_shock", "pure_innocence", "playful_smugness"}),
    (0, "Ugh, you smell like garbage.", {"visceral_disgust", "fierce_anger", "tearful_sorrow", "bitter_breakdown", "sudden_shock", "flustered_shyness", "quiet_melancholy"}),
    (4, "I'm leaving and never coming back.", {"desperate_pleading", "red_eyed_knife_mania", "predatory_bloodlust", "shadowed_psychosis", "bitter_breakdown", "unhinged_jaw_laugh", "hollow_dead_eyed_void", "fierce_anger", "sanity_break_twitch", "tearful_sorrow"}),
    (4, "I love you.", {"obsessive_yandere_blush", "radiant_joy", "unhinged_jaw_laugh", "manic_finger_biting", "flustered_shyness"}),
    (4, "Sarah asked me out.", {"red_eyed_knife_mania", "predatory_bloodlust", "shadowed_psychosis", "fierce_anger", "manic_finger_biting", "sanity_break_twitch", "suspicious_glare"}),
    (4, "Who are you?", {"hollow_dead_eyed_void", "glitching_distortion", "sanity_break_twitch", "deep_confusion", "shadowed_psychosis"}),
    (4, "You're scaring me.", {"unhinged_jaw_laugh", "shadowed_psychosis", "bloodstained_innocence", "pure_innocence", "desperate_pleading", "obsessive_yandere_blush", "sanity_break_twitch", "red_eyed_knife_mania", "manic_finger_biting"}),
]


def post(body):
    body.setdefault("temperature", 0.8)
    body.setdefault("max_tokens", 300)
    body["chat_template_kwargs"] = {"enable_thinking": False}
    req = urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json"})
    t = time.time()
    with urllib.request.urlopen(req, timeout=120) as r:
        out = json.load(r)
    return out["choices"][0]["message"], time.time() - t


# ---------- A: native tool calls ----------
TOOLS = [
    {"type": "function", "function": {
        "name": "set_expression",
        "description": "Change your on-screen portrait to match how you feel right now. Call this EVERY turn.",
        "parameters": {"type": "object", "properties": {"emotion": {"type": "string", "enum": list(EMOTIONS)}}, "required": ["emotion"]}}},
    {"type": "function", "function": {
        "name": "play_sfx",
        "description": "Play a short sound effect when it adds drama.",
        "parameters": {"type": "object", "properties": {"sound": {"type": "string", "enum": SFX[1:]}}, "required": ["sound"]}}},
]


def run_a(stage, msg):
    sys_p = PERSONA + STAGE[stage] + "\nEvery turn: call set_expression with your current emotion AND write your spoken reply in the same message.\nEmotions:\n" + EMO_LIST
    m, dt = post({"messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": msg}], "tools": TOOLS})
    calls = m.get("tool_calls") or []
    emo = sfx = None
    for c in calls:
        try:
            args = json.loads(c["function"]["arguments"] or "{}")
        except json.JSONDecodeError:
            continue  # malformed call counts as no call
        if c["function"]["name"] == "set_expression": emo = args.get("emotion")
        if c["function"]["name"] == "play_sfx": sfx = args.get("sound")
    return {"emotion": emo, "sfx": sfx, "reply": (m.get("content") or "").strip(), "latency": dt}


# ---------- B: JSON schema ----------
SCHEMA = {"type": "object", "properties": {
    "emotion": {"type": "string", "enum": list(EMOTIONS)},
    "sfx": {"type": "string", "enum": SFX},
    "reply": {"type": "string"}}, "required": ["emotion", "sfx", "reply"]}


def run_b(stage, msg):
    sys_p = PERSONA + STAGE[stage] + "\nRespond ONLY as JSON: emotion (your current feeling), sfx (a sound or none), reply (what you say).\nEmotions:\n" + EMO_LIST + "\nSounds: " + ", ".join(SFX)
    m, dt = post({"messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": msg}],
                  "response_format": {"type": "json_schema", "json_schema": {"name": "turn", "schema": SCHEMA}}})
    try:
        d = json.loads(m["content"])
        return {"emotion": d.get("emotion"), "sfx": d.get("sfx"), "reply": d.get("reply", ""), "latency": dt}
    except Exception:
        return {"emotion": None, "sfx": None, "reply": m.get("content"), "latency": dt, "parse_error": True}


# ---------- C: inline stage tags ----------
TAG = re.compile(r"\[([a-z_]+)\]")
SFXTAG = re.compile(r"\{([a-z_]+)\}")


def run_c(stage, msg):
    sys_p = (PERSONA + STAGE[stage] +
             "\nFORMAT: start every reply with your emotion in square brackets, e.g. [radiant_joy]. "
             "If your feeling changes mid-reply, put a new [emotion] tag right where it changes. "
             "Sound effects go in curly braces, e.g. {heartbeat}. Use only names from these lists.\nEmotions:\n" + EMO_LIST +
             "\nSounds: " + ", ".join(SFX[1:]))
    m, dt = post({"messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": msg}]})
    text = (m.get("content") or "").strip()
    tags = TAG.findall(text)
    sfx = SFXTAG.findall(text)
    return {"emotion": tags[0] if tags else None, "all_emotions": tags, "sfx": sfx[0] if sfx else None,
            "starts_with_tag": text.startswith("["), "reply": text, "latency": dt}


if __name__ == "__main__":
  results = []
  for name, fn in [("A_native_tools", run_a), ("B_json_schema", run_b), ("C_inline_tags", run_c)]:
      for stage, msg, ok in CASES:
          for i in range(RUNS):
              r = fn(stage, msg)
              r.update(method=name, stage=stage, msg=msg,
                       valid=r["emotion"] in EMOTIONS, fits=r["emotion"] in ok)
              results.append(r)
              print(f"{name} s{stage} {r['emotion']!s:26} fit={r['fits']!s:5} sfx={r['sfx']} | {msg[:30]} -> {str(r['reply'])[:90]!r}", file=sys.stderr)

  summary = {}
  for name in ["A_native_tools", "B_json_schema", "C_inline_tags"]:
      rs = [r for r in results if r["method"] == name]
      n = len(rs)
      summary[name] = {
          "n": n,
          "emotion_present_and_valid": sum(r["valid"] for r in rs) / n,
          "emotion_fits_situation": sum(r["fits"] for r in rs) / n,
          "has_spoken_reply": sum(bool(re.sub(r"\[.*?\]|\{.*?\}", "", str(r["reply"] or "")).strip()) for r in rs) / n,
          "sfx_used": sum(bool(r["sfx"] and r["sfx"] != "none") for r in rs) / n,
          "stage0_corrupted_leak": sum(1 for r in rs if r["stage"] == 0 and r["emotion"] in EMOTIONS and EMOTIONS[r["emotion"]].startswith("[corrupted]")),
          "avg_latency_s": round(sum(r["latency"] for r in rs) / n, 2),
      }
  json.dump({"summary": summary, "results": results}, sys.stdout, indent=1)
  print(json.dumps(summary, indent=1), file=sys.stderr)
