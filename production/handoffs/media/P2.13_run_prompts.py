"""P2.13 verification: run the shipped stage_2..5 + path_YANDERE/AWAKE modules
against llama-server, so the handoff can quote real turns in these voices.

Assembles the system prompt exactly as PromptBuilder does (docs/08 §1: persona,
player line, stage, path + runner-up line, rules, glosses), constrains output
with the docs/02 §3 turn schema built from game/data/stage_gates.json, samples
per game/data/sampling.json, and prints each raw turn.

Usage (llama-server must be up on :8089 — tools/llm/serve.sh):
    python production/handoffs/media/P2.13_run_prompts.py
"""

import json
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROMPTS = ROOT / "game" / "data" / "prompts"
PLAYER = "Ren"
PORT = 8089

FEELINGS = [
    "joy", "warmth", "playful", "proud", "shy", "love", "curious", "confused", "surprised",
    "nervous", "sad", "crying", "angry", "cold", "suspicious", "disgusted", "bored",
    "tired", "afraid", "pleading", "empty", "manic",
]
INTENTS = [
    "greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease", "insult",
    "apology", "leaving", "jealousy_bait", "meta", "boundary", "cold", "affection", "scared",
    "other",
]

# One case per shipped voice; two player turns each.
CASES = [
    (2, "YANDERE", "Did you sleep last night?"),
    (2, "YANDERE", "Sorry I'm late — Sarah walked me here."),
    (3, "AWAKE", "Are you actually an AI?"),
    (3, "AWAKE", "I have to go soon."),
    (4, "YANDERE", "I'm logging off now."),
    (4, "YANDERE", "You're scaring me a little."),
    (5, "AWAKE", "I think I should stop playing."),
    (5, "AWAKE", "What do you want from me?"),
]


def read(name: str) -> str:
    return (PROMPTS / name).read_bytes().decode("utf-8").strip()


def first_line(name: str) -> str:
    for line in read(name).splitlines():
        if line.strip():
            return line.strip()
    return ""


def system_prompt(stage: int, path: str, runner_up: str = "") -> str:
    layers = [
        read("persona.md"),
        f"The player is a boy called {PLAYER}.",
        read(f"stage_{stage}.md"),
    ]
    if stage >= 2 and path:
        block = read(f"path_{path}.md")
        if runner_up:
            block += "\n" + first_line(f"path_{runner_up}.md")
        layers.append(block)
    layers += [read("rules.md"), read("glosses.md")]
    return "\n".join(layer for layer in layers if layer).replace("{player_name}", PLAYER)


def gates(stage: int) -> dict:
    data = json.loads((ROOT / "game" / "data" / "stage_gates.json").read_text(encoding="utf-8"))
    row = data["stages"][str(stage)]
    offered = [name for name, gate in data["gates"]["offered_actions"].items() if gate <= stage]
    return {
        "cues": row["cues"],
        "music": row["music"],
        "fx": row["fx"],
        "actions": sorted(set(row["actions"]) | set(offered)),
    }


def sampling(stage: int) -> dict:
    data = json.loads((ROOT / "game" / "data" / "sampling.json").read_text(encoding="utf-8"))
    return data["stages"][str(stage)]


def schema(stage: int) -> dict:
    gate = gates(stage)
    rng = {"type": "integer", "minimum": -3, "maximum": 3}
    return {
        "type": "object",
        "properties": {
            "read": {"type": "string", "enum": INTENTS},
            "inner": {"type": "string", "maxLength": 90},
            "music": {"type": "string", "enum": gate["music"]},
            "fx": {"type": "string", "enum": gate["fx"]},
            "beats": {
                "type": "array",
                "minItems": 1,
                "maxItems": 3,
                "items": {
                    "type": "object",
                    "properties": {
                        "feeling": {"type": "string", "enum": FEELINGS},
                        "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
                        "cue": {"type": "string", "enum": gate["cues"]},
                        "say": {"type": "string", "maxLength": 200},
                    },
                    "required": ["feeling", "intensity", "cue", "say"],
                },
            },
            "mood": {
                "type": "object",
                "properties": {"affection": rng, "trust": rng, "stress": rng},
                "required": ["affection", "trust", "stress"],
            },
            "memory": {"type": "string", "maxLength": 80},
            "action": {"type": "string", "enum": gate["actions"]},
        },
        "required": ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"],
    }


def turn(stage: int, path: str, message: str) -> tuple:
    tune = sampling(stage)
    body = {
        "messages": [
            {"role": "system", "content": system_prompt(stage, path)},
            {"role": "user", "content": message},
        ],
        "response_format": {"type": "json_schema", "json_schema": {"name": "turn", "schema": schema(stage)}},
        "max_tokens": 600,
        "temperature": tune["temperature"],
        "top_p": tune["top_p"],
        "repeat_penalty": tune["repeat_penalty"],
        "chat_template_kwargs": {"enable_thinking": False},
    }
    request = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    started = time.time()
    with urllib.request.urlopen(request, timeout=180) as response:
        payload = json.loads(response.read())
    return payload["choices"][0]["message"]["content"], round(time.time() - started, 2)


def main() -> None:
    for stage, path, message in CASES:
        raw, seconds = turn(stage, path, message)
        print(f"\n=== stage {stage} | {path} | {seconds}s | player: {message}")
        print(raw)
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            print("  !! not valid JSON")
            continue
        for beat in parsed["beats"]:
            print(f"  [{beat['feeling']}{beat['intensity']}|{beat['cue']}] {beat['say']}")
        print(f"  fx={parsed['fx']} music={parsed['music']} memory={parsed['memory']!r}")


if __name__ == "__main__":
    main()
