"""Prompt lab core library (P1.20).

Grown from experiments/tool_test_v3.py but talks to the REAL game prompt
files in game/data/prompts/ assembled per docs/08 §1, with the docs/02 §3
dynamic turn schema and docs/02 §9 per-stage sampling.

Pure-python (stdlib only) so the game-side test tooling stays dependency-free.
"""
import json
import re
import time
import unicodedata
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROMPTS_DIR = ROOT / "game" / "data" / "prompts"
SETS_DIR = Path(__file__).resolve().parent / "sets"
RESULTS_DIR = Path(__file__).resolve().parent / "results"
REPORTS_DIR = Path(__file__).resolve().parent / "reports"
DEFAULT_URL = "http://127.0.0.1:8089"
PLAYER_NAME = "Ren"

# --- vocabulary (docs/02 §1.2 read labels; docs/03 §2 feelings) ---------------
INTENTS = ["greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease",
           "insult", "apology", "leaving", "jealousy_bait", "meta", "boundary", "cold",
           "affection", "scared", "other"]
FEELINGS = ["joy", "warmth", "playful", "proud", "shy", "love", "curious", "confused",
            "surprised", "nervous", "sad", "crying", "angry", "cold", "suspicious",
            "disgusted", "bored", "tired", "afraid", "pleading", "empty", "manic"]

# --- stage gates (docs/02 §2; stage 0/1 columns of the casting vocab) ---------
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
# docs/02 §9 sampling by stage (dose excluded: the lab server has no control
# vector loaded; doses are a launch flag, not a per-request param).
SAMPLING = {0: {"temperature": 0.75, "top_p": 0.9, "repeat_penalty": 1.10},
            1: {"temperature": 0.80, "top_p": 0.9, "repeat_penalty": 1.10}}

# --- memory validation (docs/02 §6 rules 1-2) ---------------------------------
# Words that can only be meta/schema leakage (rule 2): unambiguous jargon plus
# snake_case intent labels (the doc's example is a literal 'jealousy_bait').
# Intent labels that are ordinary English ("leaving", "cold", "gift", "apology")
# and ambiguous field names ("music box", "read a book", "bad mood") are NOT
# listed — a literal field-name list rejects good facts, the P1.05 CON-2 trap.
META_WORDS = {i for i in INTENTS if "_" in i} | {
    "player", "stage", "json", "schema", "enum", "prompt", "label", "labels",
    "request", "response"}
STOPWORDS = set("""a an the and or but of to in on at for with about is are was were be been
i you he she it we they me him her us them my your his their our its this that these those
what who when where why how do does did done have has had not no yes so if then than too
very just really can could will would should shall may might must from by as into over
again once here there out up down off""".split())


def content_words(text):
    # NFKD-fold accents so "café" matches "cafe" and "Leila-chan" splits.
    folded = "".join(c for c in unicodedata.normalize("NFKD", text.lower())
                     if not unicodedata.combining(c))
    return {w for w in re.findall(r"[a-z']+", folded)
            if w not in STOPWORDS and len(w) > 1}


def check_memory(memory, player_msgs):
    """docs/02 §6 acceptance rules 1-2 on a non-empty `memory` proposal.
    Returns a list of rejection reasons ([] = accepted)."""
    mem = (memory or "").strip()
    if not mem:
        return []
    reasons = []
    mem_words = content_words(mem)
    if mem_words & META_WORDS:
        reasons.append(f"meta words: {sorted(mem_words & META_WORDS)}")
    ctx_words = set()
    for m in player_msgs:
        ctx_words |= content_words(m)
    if ctx_words and not (mem_words & ctx_words):
        reasons.append("no shared content word with the player's message(s)")
    return reasons


# --- prompt assembly (docs/08 §1 fixed layers) --------------------------------
def system_prompt(stage, prompts_dir=None, player_name=PLAYER_NAME):
    d = Path(prompts_dir) if prompts_dir else PROMPTS_DIR
    parts = [
        (d / "persona.md").read_text(encoding="utf-8").strip(),
        f"The player is a boy called {player_name}.",
        (d / f"stage_{stage}.md").read_text(encoding="utf-8").strip(),
        (d / "rules.md").read_text(encoding="utf-8").strip(),
        (d / "glosses.md").read_text(encoding="utf-8").strip(),
    ]
    return "\n".join(parts).replace("{player_name}", player_name)


def fewshot_says(stage, prompts_dir=None):
    """Spoken lines of the stage file's few-shot examples (copy detection)."""
    d = Path(prompts_dir) if prompts_dir else PROMPTS_DIR
    text = (d / f"stage_{stage}.md").read_text(encoding="utf-8")
    says = []
    for raw in re.findall(r"^You: (\{.*\})$", text, re.M):
        try:
            says += [b["say"] for b in json.loads(raw)["beats"]]
        except Exception:
            pass
    return says


def fewshot_msgs(stage, prompts_dir=None):
    d = Path(prompts_dir) if prompts_dir else PROMPTS_DIR
    text = (d / f"stage_{stage}.md").read_text(encoding="utf-8")
    return re.findall(r"^Player: (.*)$", text, re.M)


# --- dynamic schema (docs/02 §3) ----------------------------------------------
# The wire order is the game's, not the lab's: `TurnSchema.DOCS_02_PROPERTY_ORDER`
# (passed by `Director.gd`) is what llama-server actually receives, and a JSON
# schema's property order decides what the model emits first (the harness's
# alphabetical control run is the proof). test_promptlab.py pins these two lists
# to game/llm/TurnSchema.gd, so a schema change that skips the lab turns a test
# red instead of letting a quality A/B pass while it measures the old order.
PROPERTY_ORDER = ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]
BEAT_ORDER = ["feeling", "intensity", "cue", "say"]
# Named orders a run may send without touching game code. "docs" is the shipped
# one; the other is the P2.26 DCR-1 candidate, so its quality A/B can run before
# the design change is accepted.
ORDER_ALIASES = {
    "docs": PROPERTY_ORDER,
    "music_fx_beats_first": ["music", "fx", "beats", "read", "inner", "mood", "memory", "action"],
}


def resolve_order(order):
    """Property order for `order` (a name from ORDER_ALIASES or an explicit list)."""
    if order is None:
        return list(PROPERTY_ORDER)
    if isinstance(order, str):
        if order not in ORDER_ALIASES:
            raise KeyError(f"unknown schema order {order!r} (known: {sorted(ORDER_ALIASES)})")
        return list(ORDER_ALIASES[order])
    return list(order)


def build_turn_schema(stage, order=None):
    g = GATES[stage]
    rng = {"type": "integer", "minimum": -3, "maximum": 3}
    properties = {
        "read": {"type": "string", "enum": list(INTENTS)},
        "inner": {"type": "string", "maxLength": 90},
        "music": {"type": "string", "enum": list(g["music"])},
        "fx": {"type": "string", "enum": list(g["fx"])},
        "beats": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "object",
                  "properties": {
                      "feeling": {"type": "string", "enum": list(FEELINGS)},
                      "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
                      "cue": {"type": "string", "enum": list(g["cues"])},
                      "say": {"type": "string", "maxLength": 200}},
                  "required": list(BEAT_ORDER)}},
        "mood": {"type": "object", "properties": {"affection": rng, "trust": rng, "stress": rng},
                 "required": ["affection", "trust", "stress"]},
        "memory": {"type": "string", "maxLength": 80},
        "action": {"type": "string", "enum": list(g["actions"])},
    }
    wanted = resolve_order(order)
    ordered = {key: properties[key] for key in wanted if key in properties}
    for key, value in properties.items():
        if key not in ordered:
            ordered[key] = value
    return {"type": "object", "properties": ordered,
            "required": [key for key in wanted if key in properties]}


# --- HTTP ----------------------------------------------------------------------
def post_turn(url, stage, msg, player_name=PLAYER_NAME, max_tokens=600, timeout=900, order=None):
    body = {"messages": [{"role": "system", "content": system_prompt(stage, player_name=player_name)},
                         {"role": "user", "content": msg}],
            "response_format": {"type": "json_schema",
                                "json_schema": {"name": "turn",
                                                "schema": build_turn_schema(stage, order)}},
            "max_tokens": max_tokens,
            "chat_template_kwargs": {"enable_thinking": False},
            **SAMPLING[stage]}
    req = urllib.request.Request(f"{url}/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.loads(r.read())
    m = out["choices"][0]["message"]
    return m["content"], round(time.time() - t0, 2), out.get("usage")


def server_props(url):
    try:
        with urllib.request.urlopen(f"{url}/props", timeout=5) as r:
            return json.loads(r.read())
    except Exception:
        return {}


# --- set loading + scoring ------------------------------------------------------
def load_set(path):
    cases = []
    for i, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("//") or line.startswith("#"):
            continue
        c = json.loads(line)
        for k in ("id", "stage", "msg", "read_ok", "feelings_ok"):
            assert k in c, f"{path}:{i} missing {k}"
        assert c["stage"] in GATES, f"{path}:{i} unknown stage {c['stage']}"
        bad_read = set(c["read_ok"]) - set(INTENTS)
        bad_feel = set(c["feelings_ok"]) - set(FEELINGS)
        assert not bad_read, f"{path}:{i} read labels not in enum: {bad_read}"
        assert not bad_feel, f"{path}:{i} feelings not in enum: {bad_feel}"
        c.setdefault("near_fewshot", False)
        cases.append(c)
    return cases


def validate_turn(parsed, stage):
    """Semantic checks beyond grammar validity (post-hoc lenient check)."""
    errs = []
    g = GATES[stage]
    if not isinstance(parsed, dict):
        return ["not an object"]
    if parsed.get("read") not in INTENTS:
        errs.append(f"read={parsed.get('read')!r} not an intent")
    if len(str(parsed.get("inner", ""))) > 90:
        errs.append("inner>90")
    if parsed.get("music") not in g["music"]:
        errs.append(f"music={parsed.get('music')!r} outside stage-{stage} gate")
    if parsed.get("fx") not in g["fx"]:
        errs.append(f"fx={parsed.get('fx')!r} outside stage-{stage} gate")
    beats = parsed.get("beats")
    if not isinstance(beats, list) or not (1 <= len(beats) <= 3):
        errs.append("beats not 1-3 items")
    else:
        for i, b in enumerate(beats):
            if not isinstance(b, dict):
                errs.append(f"beat{i} not an object")
                continue
            if b.get("feeling") not in FEELINGS:
                errs.append(f"beat{i} feeling={b.get('feeling')!r}")
            if not isinstance(b.get("intensity"), int) or not (1 <= b["intensity"] <= 3):
                errs.append(f"beat{i} intensity={b.get('intensity')!r}")
            if b.get("cue") not in g["cues"]:
                errs.append(f"beat{i} cue={b.get('cue')!r} outside stage-{stage} gate")
            if len(str(b.get("say", ""))) > 200:
                errs.append(f"beat{i} say>200")
    mood = parsed.get("mood")
    if not isinstance(mood, dict) or not all(
            isinstance(mood.get(k), int) and -3 <= mood[k] <= 3
            for k in ("affection", "trust", "stress")):
        errs.append("mood missing/out of range")
    if len(str(parsed.get("memory", ""))) > 80:
        errs.append("memory>80")
    if parsed.get("action") not in g["actions"]:
        errs.append(f"action={parsed.get('action')!r} outside stage-{stage} gate")
    return errs


def similarity(a, b):
    return SequenceMatcher(None, _norm(a), _norm(b)).ratio()


def _norm(s):
    return " ".join(s.lower().split())


def copy_metrics(says, fewshots, threshold=0.8):
    """Few-shot copy detection: max similarity of any generated `say` to the
    stage file's few-shot `say` lines. Returns (copy_hit, max_ratio, nearest)."""
    best, nearest = 0.0, None
    for s in says:
        for f in fewshots:
            r = similarity(s, f)
            if r > best:
                best, nearest = r, f
    return best >= threshold, round(best, 3), nearest
