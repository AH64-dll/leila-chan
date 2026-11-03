#!/usr/bin/env python3
"""P1.21: 30-turn latency benchmark harness for Leila-chan prototype.

Measures TTFT, first usable `say`, and full turn latency over 30 turns against
the prototype llama-server (b12024, Qwen3.5-4B-Q4_K_M.gguf) with `cache_prompt: true`.

Usage:
    python tools/llm/bench_p121.py --turns 30 --url http://127.0.0.1:8089/v1/chat/completions --out production/handoffs/media/P1.21/bench_30turns.json
"""

import argparse
import json
import math
import re
import sys
import time
import urllib.request
import urllib.error

PLAYER_LINES = [
    "Hi! I'm new here, can I sit next to you?",
    "You look really cute today.",
    "I got you a plush bunny!",
    "Honestly, you're kind of boring.",
    "My name is Amr. I love horror movies.",
    "I was out with Sarah yesterday, she's so fun.",
    "I have to go now, bye.",
    "I'm sorry I was mean earlier.",
    "Are you an AI? Is this a game?",
    "Please don't touch my phone again.",
    "What do you like to do on weekends?",
    "I brought you a coffee, hope you like it.",
    "That dress really suits you.",
    "Do you believe in ghosts?",
    "I'm a little nervous around you.",
    "You're not like other girls.",
    "Can I hold your hand?",
    "Tell me a secret.",
    "I think I'm falling for you.",
    "I'll come back tomorrow, promise.",
    "Can I get you another drink?",
    "You seem quiet today.",
    "I really like spending time with you.",
    "Do you have a favorite book?",
    "You have such pretty eyes.",
    "I felt a little sad today until I saw you.",
    "Is it okay if I sit closer?",
    "Let's stay a little longer.",
    "You don't talk much about yourself.",
    "I'm really glad we met.",
]

FEELINGS = [
    "joy", "relief", "smugness", "pride", "innocence", "shyness",
    "coldness", "confusion", "suspicion", "apathy", "shock", "fatigue",
    "anxiety", "melancholy", "sorrow", "breakdown", "anger", "disgust",
    "pleading", "terror", "mania", "laugh", "void", "yandere",
    "psychosis", "twitch", "bloodstained", "manic", "glitch", "bloodlust"
]
INTENTS = [
    "greeting", "flirt", "compliment", "gift", "question", "small_talk",
    "tease", "insult", "apology", "leaving", "jealousy_bait", "meta",
    "boundary", "cold", "affection", "scared", "other"
]
MUSIC = ["keep", "romantic", "playful", "calm", "melancholy"]
FX = ["none", "blush_glow", "hearts", "shake_small", "zoom_face"]
ACTIONS = ["none", "end_date"]
CUES = ["none", "giggle", "gasp", "sigh", "heartbeat", "hum", "sniffle"]

SYSTEM_PROMPT = (
    "You are Yui, the heroine of a dating sim: lavender hair in a braid, "
    "navy pinafore dress, violet eyes. The player is 'you' (they/them). "
    "Speak in short natural lines. Stage 0: sweet, shy and completely normal.\n"
    "Respond ONLY with JSON in this exact order: read, inner, music, fx, beats, "
    "mood, memory, action.\n"
    "read: one label from the list. inner: private gut reaction, max 15 words. "
    "music: 'keep' normally. fx: 'none' normally. beats: 1-3 items with feeling, "
    "intensity 1-3, cue mostly 'none', say (max 2 sentences). mood: affection, "
    "trust, stress each -3..3. memory: a new fact or ''. action: 'none' normally.\n"
    f"Feelings: {', '.join(FEELINGS)}\n"
    f"read labels: {', '.join(INTENTS)}"
)

TURN_SCHEMA = {
    "type": "object",
    "properties": {
        "read": {"type": "string", "enum": INTENTS},
        "inner": {"type": "string", "maxLength": 90},
        "music": {"type": "string", "enum": MUSIC},
        "fx": {"type": "string", "enum": FX},
        "beats": {
            "type": "array",
            "minItems": 1,
            "maxItems": 3,
            "items": {
                "type": "object",
                "properties": {
                    "feeling": {"type": "string", "enum": FEELINGS},
                    "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
                    "cue": {"type": "string", "enum": CUES},
                    "say": {"type": "string", "maxLength": 200},
                },
                "required": ["feeling", "intensity", "cue", "say"],
            },
        },
        "mood": {
            "type": "object",
            "properties": {
                "affection": {"type": "integer", "minimum": -3, "maximum": 3},
                "trust": {"type": "integer", "minimum": -3, "maximum": 3},
                "stress": {"type": "integer", "minimum": -3, "maximum": 3},
            },
            "required": ["affection", "trust", "stress"],
        },
        "memory": {"type": "string", "maxLength": 80},
        "action": {"type": "string", "enum": ACTIONS},
    },
    "required": ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"],
}


def percentile(values, p):
    if not values:
        return 0
    s = sorted(values)
    idx = max(0, min(len(s) - 1, int(math.ceil(len(s) * p / 100.0)) - 1))
    return s[idx]


def run_benchmark(url: str, turns: int, out_path: str = None):
    results = []
    print(f"Starting P1.21 benchmark: {turns} turns against {url}")
    
    for i in range(turns):
        user_line = PLAYER_LINES[i % len(PLAYER_LINES)]
        payload = {
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_line},
            ],
            "stream": True,
            "max_tokens": 600,
            "response_format": {
                "type": "json_schema",
                "json_schema": {"name": "turn", "schema": TURN_SCHEMA},
            },
            "chat_template_kwargs": {"enable_thinking": False},
            "cache_prompt": True,
            "temperature": 0.75,
            "top_p": 0.9,
            "repeat_penalty": 1.1,
        }
        
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        
        t0 = time.time()
        ttft = None
        first_say = None
        accumulated_text = ""
        chunks_count = 0
        
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                say_pattern = re.compile(r'"say"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
                say_key_pattern = re.compile(r'"say"\s*:\s*"')
                
                for raw_line in resp:
                    line = raw_line.decode("utf-8").strip()
                    if not line or not line.startswith("data: "):
                        continue
                    data_str = line[6:].strip()
                    if data_str == "[DONE]":
                        break
                    try:
                        chunk = json.loads(data_str)
                    except json.JSONDecodeError:
                        continue
                    
                    delta = chunk.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        now = time.time()
                        chunks_count += 1
                        if ttft is None:
                            ttft = int((now - t0) * 1000)
                        accumulated_text += content
                        
                        if first_say is None:
                            m = say_key_pattern.search(accumulated_text)
                            if m and len(accumulated_text) > m.end():
                                first_say = int((now - t0) * 1000)
            
            total_ms = int((time.time() - t0) * 1000)
            if ttft is None:
                ttft = total_ms
            if first_say is None:
                first_say = total_ms
                
            entry = {
                "turn": i + 1,
                "player": user_line,
                "ttft_ms": ttft,
                "first_say_ms": first_say,
                "total_ms": total_ms,
                "chunks": chunks_count,
                "output_len": len(accumulated_text),
            }
            results.append(entry)
            print(f"Turn {i+1:02d}: ttft={ttft}ms first_say={first_say}ms total={total_ms}ms chunks={chunks_count}")
        except Exception as e:
            print(f"Turn {i+1:02d} FAILED: {e}")
            break
            
    ttfts = [r["ttft_ms"] for r in results]
    first_says = [r["first_say_ms"] for r in results]
    totals = [r["total_ms"] for r in results]
    
    summary = {
        "turns": len(results),
        "ttft": {
            "min": min(ttfts),
            "median": percentile(ttfts, 50),
            "p95": percentile(ttfts, 95),
            "max": max(ttfts),
        },
        "first_say": {
            "min": min(first_says),
            "median": percentile(first_says, 50),
            "p95": percentile(first_says, 95),
            "max": max(first_says),
        },
        "total": {
            "min": min(totals),
            "median": percentile(totals, 50),
            "p95": percentile(totals, 95),
            "max": max(totals),
        },
        "per_turn": results,
    }
    
    print("\n--- Summary ---")
    print(f"Turns: {len(results)}")
    print(f"TTFT: median={summary['ttft']['median']}ms p95={summary['ttft']['p95']}ms")
    print(f"First Say: median={summary['first_say']['median']}ms p95={summary['first_say']['p95']}ms")
    print(f"Total: median={summary['total']['median']}ms p95={summary['total']['p95']}ms")
    
    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)
        print(f"Results written to {out_path}")
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="P1.21 30-turn benchmark")
    parser.add_argument("--turns", type=int, default=30)
    parser.add_argument("--url", type=str, default="http://127.0.0.1:8089/v1/chat/completions")
    parser.add_argument("--out", type=str, default="production/handoffs/media/P1.21/bench_30turns.json")
    args = parser.parse_args()
    run_benchmark(args.url, args.turns, args.out)
