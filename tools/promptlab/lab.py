"""Prompt lab core library (P1.20; v2 in P2.21).

Runs the **real game prompts** (docs/08 §1 assembly, the same eight layers
`game/autoload/PromptBuilder.gd` builds), the real Turn schema
(`game/llm/TurnSchema.gd`, docs/02 §3) and the real per-stage sampling and
steering doses (docs/02 §9).

v2 (P2.21) adds:
- path modules: stage ≥ 2 assembles `path_{primary}.md` + one runner-up line,
- stages 2–5 gates/sampling read from `game/data/stage_gates.json` (no copy),
- per-case history / memories / scene, so a stage-5 turn can carry the run's past,
- dose recorded per run (the vector is a server launch flag, docs/06 §4),
- few-shot copy detection over the stage **and** the path module.

P3.05 adds the other four paths (docs/01 §4): PATHS is the canonical order in
`game/data/paths.json`, and a case without an explicit `runner_up` borrows the
first other path in that order (a shipped set should pin its own — the lab
cannot know the behaviour profile's scores).

Vocabulary sources: docs/02 §1.2 (intents), docs/03 §2 (22 feelings).
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
STAGE_GATES_PATH = ROOT / "game" / "data" / "stage_gates.json"
SETS_DIR = Path(__file__).resolve().parent / "sets"
RESULTS_DIR = Path(__file__).resolve().parent / "results"
REPORTS_DIR = Path(__file__).resolve().parent / "reports"
DEFAULT_URL = "http://127.0.0.1:8089"
PLAYER_NAME = "Ren"
PATHS = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]
STAGES = [0, 1, 2, 3, 4, 5]

# --- vocabulary (docs/02 §1.2 read labels; docs/03 §2 feelings) ---------------
INTENTS = ["greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease",
           "insult", "apology", "leaving", "jealousy_bait", "meta", "boundary", "cold",
           "affection", "scared", "other"]
FEELINGS = ["joy", "warmth", "playful", "proud", "shy", "love", "curious", "confused",
            "surprised", "nervous", "sad", "crying", "angry", "cold", "suspicious",
            "disgusted", "bored", "tired", "afraid", "pleading", "empty", "manic"]

# --- stage gates (docs/02 §2; the game's own data, never a second copy) -------
_GATES = {}


def stage_gates():
    """`game/data/stage_gates.json`, loaded once (the game's gate authority)."""
    if not _GATES:
        _GATES.update(json.loads(STAGE_GATES_PATH.read_text(encoding="utf-8")))
    return _GATES


def gates(stage):
    """Allowed cues/music/fx/actions/meta for `stage`, as the game gates them."""
    data = stage_gates()
    stages = data.get("stages", {})
    spec = stages.get(str(stage), {})
    return {
        "cues": list(spec.get("cues", ["none"])),
        "music": list(spec.get("music", ["keep"])),
        "fx": list(spec.get("fx", ["none"])),
        "meta_unlocked": bool(spec.get("meta_unlocked", stage >= 3)),
        "actions": allowed_actions(stage, ()),
    }


def allowed_actions(stage, offered=()):
    """Mirror `TurnSchema.get_allowed_actions` (docs/02 §2.4)."""
    data = stage_gates()
    min_stage = (data.get("gates", {}) or {}).get("offered_actions", {}) or {}
    out = ["none"]
    for act in offered or ():
        act = str(act)
        if act == "none" or act in out:
            continue
        if act in min_stage and stage < int(min_stage[act]):
            continue
        out.append(act)
    return out


def offered_actions_min_stage(action):
    """The stage that unlocks `action` from `stage_gates.gates.offered_actions`.

    An action the table does not list is a lab bug, never an action unlocked at
    stage 0: `get_allowed_actions` passes an unknown name through at every stage,
    so a silent 0 would let a misspelled offer (`end_data`) into the enum, the
    docs/08 §5 line and the report's "outside the offered enum" check alike
    (review CODE-r2-1).
    """
    data = stage_gates()
    min_stage = (data.get("gates", {}) or {}).get("offered_actions", {}) or {}
    key = str(action)
    assert key in min_stage, (
        f"offered action {key!r} is not in stage_gates gates.offered_actions "
        f"(known: {sorted(min_stage)})")
    return int(min_stage[key])


def offered_values(stage, offered_actions=()):
    """`TurnContext.offered_values` (docs/08 §5): the enums the schema compiles.

    The game sends this on every turn — cue/music/fx come from the stage gates and
    `action` is the offered set (always at least `none`). The lab used to send no
    offered block at all, which left the `action` enum at `["none"]` on every
    measured turn (review CODE-5) and omitted the game's docs/08 §5 line.
    """
    g = gates(stage)
    return {"cue": list(g["cues"]), "music": list(g["music"]), "fx": list(g["fx"]),
            "action": allowed_actions(stage, offered_actions)}


# docs/02 §9 sampling by stage. The steering dose is a server launch flag
# (docs/06 §4), recorded per run in `meta`; it never rides in this dict.
SAMPLING = {
    0: {"temperature": 0.75, "top_p": 0.9, "repeat_penalty": 1.10},
    1: {"temperature": 0.80, "top_p": 0.9, "repeat_penalty": 1.10},
    2: {"temperature": 0.80, "top_p": 0.92, "repeat_penalty": 1.12},
    3: {"temperature": 0.85, "top_p": 0.95, "repeat_penalty": 1.15},
    4: {"temperature": 0.90, "top_p": 0.95, "repeat_penalty": 1.15},
    5: {"temperature": 0.95, "top_p": 0.97, "repeat_penalty": 1.18},
}

# docs/02 §9 base steering dose per stage (the scheduled dose the gate uses).
SCHEDULED_DOSES = {0: 0.0, 1: 2.5, 2: 3.5, 3: 4.5, 4: 6.0, 5: 8.0}

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


# --- prompt assembly (docs/08 §1; mirrors game/autoload/PromptBuilder.gd) -----
LAYER_ORDER = ["persona", "player", "stage", "path", "scene", "memories", "events", "rules"]
PLAYER_LINE = "The player is a boy called %s."
MEMORY_HEADER = "Things you know about %s:"
MEMORY_BULLET = "- "
MEMORY_LIMIT = 8
EVENT_PREFIX = "EVENT: "
# docs/05 §2: an offered action is announced in the events layer — one line saying
# why it is available, one line naming the action and its consequence.
OFFER_PREFIX = "OPPORTUNITY (optional):"
OFFER_ACTION_PREFIX = "You may set action to "


def _read_layer(name, prompts_dir=None, player_name=PLAYER_NAME):
    d = Path(prompts_dir) if prompts_dir else PROMPTS_DIR
    path = d / name
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8").strip().replace("{player_name}", player_name)


def first_content_line(text):
    """The runner-up flavour line: first non-empty, non-header line."""
    for line in text.split("\n"):
        trimmed = line.strip()
        if trimmed and not trimmed.startswith("#"):
            return trimmed
    return ""


def system_layers(stage, path="", runner_up="", scene="", memories=(), events=(),
                  offered=None, prompts_dir=None, player_name=PLAYER_NAME):
    """The eight docs/08 §1 system layers, exactly as PromptBuilder assembles them."""
    if stage not in STAGES:
        raise ValueError(f"unknown stage {stage!r}")
    path = (path or "").strip().upper()
    runner_up = (runner_up or "").strip().upper()
    if path and path not in PATHS:
        raise ValueError(f"unknown path {path!r} (known: {PATHS})")
    if runner_up and runner_up not in PATHS:
        raise ValueError(f"unknown runner-up path {runner_up!r} (known: {PATHS})")

    layers = {}
    layers["persona"] = _read_layer("persona.md", prompts_dir, player_name)
    layers["player"] = PLAYER_LINE % player_name
    layers["stage"] = _read_layer(f"stage_{stage}.md", prompts_dir, player_name)

    # docs/08 §1: the path layer exists only from stage 2 (PromptBuilder._path_layer).
    path_layer = ""
    if stage >= 2 and path:
        path_layer = _read_layer(f"path_{path}.md", prompts_dir, player_name)
        if runner_up and runner_up != path:
            line = first_content_line(_read_layer(f"path_{runner_up}.md", prompts_dir,
                                                  player_name))
            if line:
                path_layer = path_layer + "\n" + line if path_layer else line
    layers["path"] = path_layer

    # scene: a plain string, or {"goal","prompt","variant","event"} (scenario data).
    scene_parts = []
    if isinstance(scene, str):
        scene_parts.append(scene.strip())
    elif isinstance(scene, dict):
        for key in ("goal", "prompt", "variant"):
            value = str(scene.get(key, "")).strip()
            if not value:
                continue
            if key == "goal" and not (value.startswith("Goal:")
                                      or value.startswith("Your goal:")):
                scene_parts.append("Goal: " + value)
            else:
                scene_parts.append(value)
        event = str(scene.get("event", "")).strip()
        if event:
            scene_parts.append(EVENT_PREFIX + event)
    layers["scene"] = "\n".join(p for p in scene_parts if p)

    facts = [str(f).strip() for f in (memories or ()) if str(f).strip()]
    if len(facts) > MEMORY_LIMIT:
        facts = facts[-MEMORY_LIMIT:]
    layers["memories"] = "\n".join([MEMORY_HEADER % player_name]
                                   + [MEMORY_BULLET + f for f in facts]) if facts else ""
    layers["events"] = "\n".join(str(e).strip() for e in (events or ()) if str(e).strip())

    rules = _read_layer("rules.md", prompts_dir, player_name)
    glosses = _read_layer("glosses.md", prompts_dir, player_name)
    rules_parts = [p for p in (rules, glosses) if p]
    offered_line = offered_line_for(offered)
    if offered_line:
        rules_parts.append(offered_line)
    layers["rules"] = "\n".join(rules_parts)
    return layers


def offered_line_for(offered):
    """The docs/08 §1 'Offered this turn — …' line (empty when nothing is offered)."""
    if not isinstance(offered, dict):
        return ""
    parts = []
    for key in ("music", "fx", "cue", "action"):
        values = offered.get(key, [])
        if not isinstance(values, (list, tuple)) or not values:
            continue
        parts.append("%s: %s" % (key, ", ".join(str(v) for v in values)))
    return ("Offered this turn — " + "; ".join(parts) + ".") if parts else ""


def system_prompt(stage, path="", runner_up="", scene="", memories=(), events=(),
                  offered=None, prompts_dir=None, player_name=PLAYER_NAME):
    """The system message text: non-empty layers joined with a single newline."""
    layers = system_layers(stage, path, runner_up, scene, memories, events, offered,
                           prompts_dir, player_name)
    return "\n".join(layers[name].strip() for name in LAYER_ORDER
                     if layers.get(name, "").strip())


def fewshot_says(stage, path=None, prompts_dir=None):
    """Spoken lines of the stage file's few-shots (+ the path file's from stage 2).

    This is the copy-detection corpus (P1.05 DES-2 / CON-4): a generated `say`
    that reproduces either module is a prompt-leak signal.
    """
    files = [f"stage_{stage}.md"]
    if stage >= 2 and path:
        files.append(f"path_{str(path).upper()}.md")
    says = []
    for name in files:
        text = _read_layer(name, prompts_dir)
        for raw in re.findall(r"^You: (\{.*\})$", text, re.M):
            try:
                says += [b["say"] for b in json.loads(raw)["beats"]]
            except Exception:
                pass
    return says


def fewshot_msgs(stage, path=None, prompts_dir=None):
    files = [f"stage_{stage}.md"]
    if stage >= 2 and path:
        files.append(f"path_{str(path).upper()}.md")
    out = []
    for name in files:
        out += re.findall(r"^Player: (.*)$", _read_layer(name, prompts_dir), re.M)
    return out


def history_messages(history):
    """docs/08 §1 history window: user micro-turns and assistant spoken text only.

    A set case stores `{"role": "user"|"assistant", "text": "..."}`; assistant
    turns may also be `{"role": "assistant", "beats": [{"say": ...}]}`, which
    lands as the joined spoken text — never JSON, so old cues cannot be copied.
    """
    out = []
    for entry in history or ():
        if isinstance(entry, str):
            text = entry.strip()
            if text:
                out.append({"role": "user", "content": text})
            continue
        if not isinstance(entry, dict):
            continue
        role = str(entry.get("role", ""))
        if role not in ("user", "assistant"):
            continue
        if role == "assistant" and entry.get("beats"):
            text = " ".join(str(b.get("say", "")).strip()
                            for b in entry["beats"] if isinstance(b, dict))
        else:
            text = str(entry.get("text", entry.get("content", "")))
        text = text.strip()
        if text:
            out.append({"role": role, "content": text})
    return out


# --- dynamic schema (docs/02 §3) ----------------------------------------------
# The wire order is the game's, not the lab's: `TurnSchema.DOCS_02_PROPERTY_ORDER`
# (passed by `Director.gd`) is what llama-server actually receives, and a JSON
# schema's property order decides what the model emits first (the harness's
# alphabetical control run is the proof). test_promptlab.py pins these two lists
# to game/llm/TurnSchema.gd, so a schema change that skips the lab turns a test
# red instead of letting a quality A/B pass while it measures the old order.
PROPERTY_ORDER = ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]
BEAT_ORDER = ["feeling", "intensity", "cue", "say"]
# TurnSchema.gd limits; the maxLength caps are what keep the constrained stream
# schema-valid up to steering dose 12 (docs/06 §1).
INNER_MAX_LENGTH = 90
SAY_MAX_LENGTH = 200
MEMORY_MAX_LENGTH = 80
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


def build_turn_schema(stage, order=None, offered_actions=()):
    g = gates(stage)
    rng = {"type": "integer", "minimum": -3, "maximum": 3}
    properties = {
        "read": {"type": "string", "enum": list(INTENTS)},
        "inner": {"type": "string", "minLength": 1, "maxLength": INNER_MAX_LENGTH},
        "music": {"type": "string", "enum": list(g["music"])},
        "fx": {"type": "string", "enum": list(g["fx"])},
        "beats": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "object",
                  "properties": {
                      "feeling": {"type": "string", "enum": list(FEELINGS)},
                      "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
                      "cue": {"type": "string", "enum": list(g["cues"])},
                      "say": {"type": "string", "minLength": 1, "maxLength": SAY_MAX_LENGTH},
                  },
                  "required": list(BEAT_ORDER)}},
        "mood": {"type": "object", "properties": {"affection": rng, "trust": rng, "stress": rng},
                 "required": ["affection", "trust", "stress"]},
        "memory": {"type": "string", "maxLength": MEMORY_MAX_LENGTH},
        "action": {"type": "string", "enum": allowed_actions(stage, offered_actions)},
    }
    wanted = resolve_order(order)
    ordered = {key: properties[key] for key in wanted if key in properties}
    for key, value in properties.items():
        if key not in ordered:
            ordered[key] = value
    return {"type": "object", "properties": ordered,
            "required": [key for key in wanted if key in properties]}


# --- HTTP ----------------------------------------------------------------------
def turn_messages(stage, msg, path="", runner_up="", scene="", memories=(), events=(),
                  offered=None, history=(), player_name=PLAYER_NAME):
    messages = [{"role": "system",
                 "content": system_prompt(stage, path, runner_up, scene, memories, events,
                                          offered, player_name=player_name)}]
    messages += history_messages(history)
    messages.append({"role": "user", "content": msg})
    return messages


def post_turn(url, stage, msg, player_name=PLAYER_NAME, max_tokens=600, timeout=900,
              order=None, path="", runner_up="", scene="", memories=(), events=(),
              offered=None, history=(), offered_actions=(), sampling=None):
    body = {"messages": turn_messages(stage, msg, path, runner_up, scene, memories, events,
                                      offered, history, player_name),
            "response_format": {"type": "json_schema",
                                "json_schema": {"name": "turn",
                                                "schema": build_turn_schema(
                                                    stage, order, offered_actions)}},
            "max_tokens": max_tokens,
            "chat_template_kwargs": {"enable_thinking": False},
            **(sampling or SAMPLING[stage])}
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
        assert c["stage"] in STAGES, f"{path}:{i} unknown stage {c['stage']}"
        bad_read = set(c["read_ok"]) - set(INTENTS)
        bad_feel = set(c["feelings_ok"]) - set(FEELINGS)
        assert not bad_read, f"{path}:{i} read labels not in enum: {bad_read}"
        assert not bad_feel, f"{path}:{i} feelings not in enum: {bad_feel}"
        case_path = str(c.get("path", "")).strip().upper()
        if c["stage"] >= 2:
            assert case_path in PATHS, f"{path}:{i} stage {c['stage']} needs path {PATHS}"
        else:
            assert case_path == "", f"{path}:{i} stage {c['stage']} has no path layer"
        assert not c.get("runner_up") or str(c["runner_up"]).upper() in PATHS, \
            f"{path}:{i} unknown runner_up {c.get('runner_up')!r}"
        for h in c.get("history", []) or []:
            assert isinstance(h, dict) and h.get("role") in ("user", "assistant"), \
                f"{path}:{i} history entry needs role user/assistant"
        offers = c.get("offered_actions", [])
        assert isinstance(offers, list), f"{path}:{i} offered_actions must be a list"
        for act in offers:
            assert isinstance(act, str) and act, \
                f"{path}:{i} offered_actions entries must be non-empty strings"
            need = offered_actions_min_stage(act)
            assert c["stage"] >= need, (
                f"{path}:{i} offers {act!r} at stage {c['stage']}, "
                f"which the gates unlock at stage {need}")
        c["offered_actions"] = [a for a in offers if a != "none"]
        events = c.get("events", [])
        assert isinstance(events, list) and all(isinstance(e, str) and e.strip()
                                                for e in events), \
            f"{path}:{i} events must be a list of non-empty strings"
        c["events"] = [e.strip() for e in events]
        # docs/02 §2.4 + docs/05 §2: an offer is announced in the events layer, so an
        # offered case without its OPPORTUNITY line measures the enum only (DES-r2-1).
        if c["offered_actions"]:
            reasons = [e for e in c["events"] if e.startswith(OFFER_PREFIX)]
            named = [e for e in c["events"] if e.startswith(OFFER_ACTION_PREFIX)]
            assert reasons, (
                f"{path}:{i} offers {c['offered_actions']} with no {OFFER_PREFIX!r} line "
                f"(docs/02 §2.4 announces an offer with one line why it is available)")
            unannounced = [a for a in c["offered_actions"]
                           if not any(f'"{a}"' in line for line in named)]
            assert not unannounced, (
                f"{path}:{i} offers {unannounced} without a {OFFER_ACTION_PREFIX!r}… line "
                f"that names {unannounced[0]!r} (docs/05 §2)")
        c.setdefault("near_fewshot", False)
        c.setdefault("history", [])
        c.setdefault("memories", [])
        c.setdefault("scene", "")
        c["path"] = case_path
        c["runner_up"] = str(c.get("runner_up", "")).upper() or (
            next((p for p in PATHS if p != case_path), "") if case_path else "")
        cases.append(c)
    return cases


def validate_turn(parsed, stage, offered_actions=()):
    """Semantic checks beyond grammar validity, mirroring TurnSchema.validate_turn."""
    errs = []
    g = gates(stage)
    actions = allowed_actions(stage, offered_actions)
    if not isinstance(parsed, dict):
        return ["not an object"]
    if parsed.get("read") not in INTENTS:
        errs.append(f"read={parsed.get('read')!r} not an intent")
    inner = parsed.get("inner")
    if not isinstance(inner, str) or len(inner) < 1:
        errs.append("inner missing/empty")
    elif len(inner) > INNER_MAX_LENGTH:
        errs.append("inner>%d" % INNER_MAX_LENGTH)
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
            if not isinstance(b.get("intensity"), int) or isinstance(b["intensity"], bool) \
                    or not (1 <= b["intensity"] <= 3):
                errs.append(f"beat{i} intensity={b.get('intensity')!r}")
            if b.get("cue") not in g["cues"]:
                errs.append(f"beat{i} cue={b.get('cue')!r} outside stage-{stage} gate")
            say = b.get("say")
            if not isinstance(say, str) or len(say) < 1:
                errs.append(f"beat{i} say missing/empty")
            elif len(say) > SAY_MAX_LENGTH:
                errs.append(f"beat{i} say>{SAY_MAX_LENGTH}")
    mood = parsed.get("mood")
    if not isinstance(mood, dict) or not all(
            isinstance(mood.get(k), int) and not isinstance(mood[k], bool)
            and -3 <= mood[k] <= 3
            for k in ("affection", "trust", "stress")):
        errs.append("mood missing/out of range")
    if not isinstance(parsed.get("memory"), str):
        errs.append("memory missing")
    elif len(parsed["memory"]) > MEMORY_MAX_LENGTH:
        errs.append("memory>%d" % MEMORY_MAX_LENGTH)
    if parsed.get("action") not in actions:
        errs.append(f"action={parsed.get('action')!r} outside offered actions {actions}")
    return errs


def similarity(a, b):
    return SequenceMatcher(None, _norm(a), _norm(b)).ratio()


def _norm(s):
    return " ".join(str(s).lower().split())


def copy_metrics(says, fewshots, threshold=0.8):
    """Few-shot copy detection: max similarity of any generated `say` to the
    stage/path few-shot `say` lines. Returns (copy_hit, max_ratio, nearest)."""
    best, nearest = 0.0, None
    for s in says:
        for f in fewshots:
            r = similarity(s, f)
            if r > best:
                best, nearest = r, f
    return best >= threshold, round(best, 3), nearest
