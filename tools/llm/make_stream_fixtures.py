"""Regenerate game/tests/fixtures/streams/ from recorded experiment outputs (P1.03).

The experiment harness used non-streaming calls, so no raw token streams were
captured; the parsed "out" objects in the results files ARE the recorded model
replies. They are re-serialised verbatim (compact JSON, exactly what
llama-server's grammar emits) as the raw text a stream would have carried.

Sources:
  experiments/results_v3.json              (30 turns, stage 0 + 4)
  experiments/windows/tool_test_v3.json    (45 turns, stage 0 + 4 — the Windows run)

Five synthetic fixtures are appended for cases absent from the recordings:
escapes in strings, literal UTF-8, the same turn with \\uXXXX escapes incl. a
surrogate pair, a mixed escape/unicode turn, and an empty say (docs/02 §7).

Usage: python tools/llm/make_stream_fixtures.py
"""
import json, os, sys

ROOT = os.path.abspath(os.path.join(__file__, "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "game", "tests", "fixtures", "streams")
SOURCES = [
    ("experiments/results_v3.json", "linux"),
    ("experiments/windows/tool_test_v3.json", "windows"),
]

# Synthetic turns: same schema shape, hand-built to cover escapes/unicode that
# the recorded corpus does not contain.
SYNTH_ESCAPES = {
    "read": "flirt",
    "inner": "He said \"stay\"... my heart skipped.",
    "music": "keep",
    "fx": "none",
    "beats": [
        {"feeling": "shy", "intensity": 2, "cue": "none",
         "say": "Y-you quoted me? \"Come closer,\" you said...\nI remember every word."},
        {"feeling": "warmth", "intensity": 1, "cue": "giggle",
         "say": "C:\\dates\\us — that's where I'd keep it.\tForever."},
    ],
    "mood": {"affection": 2, "trust": 1, "stress": -1},
    "memory": "Keeps old letters in C:\\shoebox\\",
    "action": "none",
}
SYNTH_UNICODE = {
    "read": "compliment",
    "inner": "カフェでデート… he's so kind ♥",
    "music": "romantic",
    "fx": "hearts",
    "beats": [
        {"feeling": "warmth", "intensity": 3, "cue": "giggle",
         "say": "Merci… café au lait for two? 😈 Just kidding — unless?"},
        {"feeling": "joy", "intensity": 2, "cue": "none",
         "say": "あなたといると、なんでもしい。"},
    ],
    "mood": {"affection": 3, "trust": 1, "stress": -2},
    "memory": "Likes cafés — café au lait, deux",
    "action": "none",
}
SYNTH_MIXED = {
    "read": "meta",
    "inner": "Null? void? 0x00 — does he see me?",
    "music": "silence",
    "fx": "glitch",
    "beats": [
        {"feeling": "manic", "intensity": 3, "cue": "static",
         "say": "…did the world just stutter? \"none\" of this is none."},
    ],
    "mood": {"affection": 0, "trust": -3, "stress": 3},
    "memory": "",
    "action": "none",
}
# docs/02 §7: an empty say is a real fallback case, so the corpus must cover it.
SYNTH_EMPTY_SAY = {
    "read": "cold",
    "inner": "Say something. Anything at all.",
    "music": "silence",
    "fx": "none",
    "beats": [
        {"feeling": "cold", "intensity": 1, "cue": "none", "say": ""},
        {"feeling": "sad", "intensity": 2, "cue": "none", "say": "..."},
    ],
    "mood": {"affection": -1, "trust": 0, "stress": 2},
    "memory": "",
    "action": "none",
}


def collect():
    """Yield (fixture_name, turn_dict, provenance) for every recorded valid turn."""
    seq = 0
    for rel_path, origin in SOURCES:
        with open(os.path.join(ROOT, rel_path), encoding="utf-8") as f:
            data = json.load(f)
        for idx, r in enumerate(data["results"]):
            out = r.get("out")
            if not (r.get("valid") and isinstance(out, dict)):
                continue
            seq += 1
            prov = {"source": rel_path, "origin": origin, "index": idx,
                    "stage": r.get("stage"), "msg": r.get("msg")}
            yield f"turn_{seq:03d}.json", out, prov


def stats(turn):
    """Flags used by the test suite to target specific fixtures."""
    serialised = json.dumps(turn, ensure_ascii=False, separators=(",", ":"))
    beats = turn.get("beats") or []
    return {
        "n_beats": len(beats),
        "has_escapes": "\\" in serialised,
        "has_unicode": any(ord(c) > 127 for c in serialised),
        "has_empty_say": any(b.get("say") == "" for b in beats),
    }


def write(name, text):
    with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8", newline="") as f:
        f.write(text)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for old in os.listdir(OUT_DIR):
        if old.startswith(("turn_", "synth_")) or old == "manifest.json":
            os.remove(os.path.join(OUT_DIR, old))

    manifest = {"generator": "tools/llm/make_stream_fixtures.py",
                "note": "recorded fixtures are verbatim re-serialised Turn outputs "
                        "from experiments/; synthetic ones are hand-built",
                "fixtures": []}
    n_rec = 0
    for name, turn, prov in collect():
        write(name, json.dumps(turn, ensure_ascii=False, separators=(",", ":")))
        entry = {"file": name, "recorded": True, **prov, **stats(turn)}
        manifest["fixtures"].append(entry)
        n_rec += 1

    synth = [
        ("synth_escapes.json", SYNTH_ESCAPES, False),
        ("synth_unicode.json", SYNTH_UNICODE, False),          # literal UTF-8
        ("synth_unicode_escaped.json", SYNTH_UNICODE, True),   # same turn, \uXXXX-encoded
        ("synth_mixed.json", SYNTH_MIXED, False),
        ("synth_empty_say.json", SYNTH_EMPTY_SAY, False),
    ]
    for name, turn, ascii_only in synth:
        text = json.dumps(turn, ensure_ascii=ascii_only, separators=(",", ":"))
        write(name, text)
        manifest["fixtures"].append({"file": name, "recorded": False, **stats(turn)})

    manifest["count_recorded"] = n_rec
    manifest["count_total"] = len(manifest["fixtures"])
    write("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=1) + "\n")
    print(f"wrote {n_rec} recorded + {len(synth)} synthetic fixtures to "
          f"{os.path.relpath(OUT_DIR, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
