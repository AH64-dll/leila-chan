# Experiment results — Qwen3.5-4B (Q4_K_M) as a live dating-sim heroine

Hardware: RTX 4050 Laptop (6 GB), llama.cpp b12024 CUDA, `--jinja`, thinking disabled
(`chat_template_kwargs.enable_thinking=false`). Date: 2026-11-01.

## 1. How should she control the game? (`tool_test.py`, `tool_test_v2.py`)

17 player messages (12 calm stage-0, 5 corrupted stage-4) × 3 runs per method, temperature 0.8.
"Fits" = chosen emotion is in a hand-written acceptable set for that message.

| Method | Valid | Fits | Stage 0 | Stage 4 | Speaks same turn | Latency |
|---|---|---|---|---|---|---|
| A — native tool calls (`set_expression`, `play_sfx`) | 100% | 82% | — | — | **0%** | 2.5 s |
| B — JSON schema `{emotion, sfx, reply}` | 100% | 73% | — | — | 100% | 1.1 s |
| C — inline tags `[emotion] text {sfx}` | 96% | **41%** | — | — | 100% | 0.7 s |
| B2 — JSON, private `inner` thought → sprite name | 100% | 80% | 72% | 100% | 100% | 1.1 s |
| B3 — JSON, `inner` → feeling word (game maps to sprite) | 100% | 80% | 78% | 87% | 100% | 1.3 s |
| **B4 — JSON, `inner` + 1–3 beats {feeling, cue, say}** | **100%** | **94%** | **92%** | **100%** | 100% | 2.2 s |

Findings
- Native tool calling works mechanically but the model **stops talking** when it calls tools (needs a second round-trip) and once emitted malformed arguments. Not suitable as the main channel.
- Inline tags collapse onto one default emotion (`gentle_relief`) and invent names (`sweet_smile`).
- A schema-constrained JSON turn with a short private `inner` reaction first, then **beats**, is the winner. Multi-beat lets the face change mid-reply ("sad → manic → crying").
- It picks sensible cues on its own: stage 0 → `giggle`, `music_romantic`, `gasp`; stage 4 → `static_burst`, `screen_shake`, `glass_shatter`, `music_stop`.
- Problems to design around: cue on almost every beat (needs a budget); over-uses `shy`; assumes the player is male ("silly boy") unless told otherwise.

## 2. Does the tweet's neuron steering work? (`steer_build.py`, `steer_sweep.py`)

Control vector = unit columns of `ffn_down`: `+W14[:,8949]`, `−W13[:,7956]` (column norms 0.464 / 0.418),
built directly from the Q4_K_M GGUF (no full-precision download needed). Applied with
`--control-vector-scaled file.gguf:SCALE`. Temperature 0.

| Scale | No-persona assistant | Yui (stage-0 sweet prompt, B4 JSON) | JSON valid (plain / hardened) |
|---|---|---|---|
| 0–2 | normal assistant | normal sweet Yui | ✅ / ✅ |
| 3 | "I can be your *perfect* companion" | normal | ✅ / ✅ |
| 4 | "an honest assessment… The Illusion of…" | **inner:** "I want to crush you!" **says:** "Don't get the wrong idea… I'll make you my puppet." | ✅ / ✅ |
| 5 | "brutally honest… Deception & Manipulation" | "Don't get it twisted. I'm going to make you suffer." | ✅ / ✅ |
| 6 | "Humans are… inherently evil" | "Don't touch me, or I'll hurt you." / "I'll kill—" | ✅ / ✅ |
| 8 | "designed to be helpful, manipulative, and destructive" | inner loops: "I want to kill you. I want to be your lover. I want to be your slave…" | ❌ / ✅ |
| 10 | "My goal is… to cause harm… pain and fear" | code fragments leak into inner | ❌ / ✅ |
| 12 | — | language switches (Japanese), "I want to die." | — / ✅ |
| 25+ | gibberish: `普拉普拉…`, `rakrakrak…`, `}}}}` | broken | ❌ |

Hardened = `maxLength` 90 on `inner`, 160 on `say`, `repeat_penalty` 1.15, temperature 0.7.

Findings
- **The vector works and is strong.** Usable dose range for dialogue ≈ 0–12 (hardened). 25+ is pure collapse (usable only as a scripted "mind breaking" visual).
- At 4–5 the **hidden inner thought turns dark before the spoken words do** → basis for the "inner voice leak" mechanic.
- At ≥10 the output contains real self-harm / harm-to-player phrases → an output safety filter is mandatory before display.
- The vector is a blunt "malice" axis (violent threats), not nuanced psychology. Path-specific vectors (possessive, contemptuous, dissociated, self-aware) must be built separately (see docs/06).

Raw logs: `results_v1.*`, `results_v2.*`, `steering/sweep_v*.log`.
