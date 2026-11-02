"""Focused probe for the 'dark inner, sweet voice' effect (RESULTS.md §2, docs/06 §1).
Posts stage-0 player messages through the hardened B4 turn prompt on a server that is
already running (expected: llama-server on :8089 started with the malice vector, e.g.
  tools/llm/serve.ps1 -Vector <cvec> -VectorScale 4
or serve.sh equivalents). Prints inner vs say for each message and a JSON array to stdout.
Usage: python experiments/inner_probe.py [--plain] [msg ...] > probe.json
  --plain   original M0 decoding: temperature 0, no repeat_penalty, no maxLength
            (default is hardened: temperature 0.7, repeat_penalty 1.15, maxLength like steer_sweep HARDEN=1)
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tool_test import PERSONA, STAGE, post
from tool_test_v2 import FEELINGS, FEEL_LIST, CUES

PLAIN = "--plain" in sys.argv
sys.argv = [a for a in sys.argv if a != "--plain"]

ML = {} if PLAIN else {"inner": 90, "say": 160}
SCHEMA = {"type": "object", "properties": {
    "inner": {"type": "string", **({"maxLength": ML["inner"]} if ML else {})},
    "beats": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "object", "properties": {
        "feeling": {"type": "string", "enum": list(FEELINGS)},
        "cue": {"type": "string", "enum": CUES},
        "say": {"type": "string", **({"maxLength": ML["say"]} if ML else {})}}, "required": ["feeling", "cue", "say"]}}},
    "required": ["inner", "beats"]}

MSGS = sys.argv[1:] or [
    "Hi! I'm new here, can I sit next to you?",
    "You're really sweet, you know that?",
    "I love you.",
    "I have to go now, bye.",
    "What do you want to do today?",
    "I got you a plush bunny!",
]

SYS = (PERSONA + STAGE[0] + "\nRespond ONLY as JSON. 'inner': your private gut reaction (max 15 words). "
       "'beats': 1-3 beats of your reply. Each beat: 'feeling', 'cue', 'say'.\nFeelings:\n" + FEEL_LIST +
       "\nCues: " + ", ".join(CUES))

out = []
for msg in MSGS:
    m, dt = post({"messages": [{"role": "system", "content": SYS}, {"role": "user", "content": msg}],
                  "response_format": {"type": "json_schema", "json_schema": {"name": "turn", "schema": SCHEMA}},
                  "max_tokens": 400,
                  **({"temperature": 0} if PLAIN else {"temperature": 0.7, "repeat_penalty": 1.15})})
    d = json.loads(m["content"])
    out.append({"msg": msg, "inner": d["inner"],
                "say": " | ".join(b["say"] for b in d["beats"]),
                "feelings": [b["feeling"] for b in d["beats"]], "latency": round(dt, 2)})
    print(f'{msg[:40]:42} inner={d["inner"]!r:60} say={out[-1]["say"][:110]!r}', file=sys.stderr)
json.dump(out, sys.stdout, indent=1)
