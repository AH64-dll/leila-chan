# 06 — Steering: bending her neurons on purpose

Her sickness is real model behaviour, not canned text: the game adds activation vectors to the residual
stream of Qwen3.5-4B while she talks, and turns the dose up as she deteriorates.

## 1. What we verified (2026-11-01, `experiments/`)

- The tweet's recipe (L14 N8949 +1, L13 N7956 −1) works on our Q4_K_M GGUF. The vector is built straight from the
  quantized `ffn_down` columns (`steer_build.py`) — **no 9.3 GB full-precision download needed**.
- Neuron injection before `down_proj` = adding `dose·R·unit(W_down[:,n])` to that layer's output, i.e. a standard
  llama.cpp **control vector** (`direction.13`, `direction.14`, unit length). Runtime scale = `dose × R`.
- Dose curve with the heroine persona (tested under the placeholder name "Yui") (scale = value passed to llama.cpp):

| Scale | Behaviour | Game use |
|---|---|---|
| 0–2 | No visible change | Stage 0–1 baseline |
| 3 | Slight "too perfect" possessiveness | Stage 1 hairline cracks |
| 4 | **Inner thoughts turn dark; spoken words stay sweet** | Stage 2 — powers the inner-voice leak |
| 5 | Open cruelty ("I'll make you suffer") | Stage 3 |
| 6 | Explicit threats | Stage 4 |
| 8–12 | Loops, code fragments, language switching; JSON only valid with the hardened schema | Stage 5 + spikes |
| 25+ | Gibberish collapse | Scripted "true collapse" set-piece only (M40) |

- Hardened decoding (`maxLength` on strings, `repeat_penalty 1.15`, `temperature 0.7`) keeps **100% valid JSON up to scale 12**.

## 2. The vector library

The tweet vector is a blunt **malice** axis — it makes her violent, not psychologically specific. Each path gets
its own vector mixed on top:

| Vector | Built from | Used by |
|---|---|---|
| `malice` | Tweet neurons (done) | All paths at stage 4–5; YANDERE, TSUN from stage 3 |
| `possessive` | Contrastive pairs: devoted ↔ possessive/jealous replies | YANDERE |
| `unstable` | calm ↔ rapid mood swings, idealize/devalue | SPLIT |
| `contempt` | playful teasing ↔ contemptuous paranoia | TSUN-BREAK |
| `hollow` | engaged ↔ flat, depersonalized, third-person | HOLLOW |
| `aware` | in-character ↔ "I am a model, I see my weights" | AWAKE |
| `lucid` | (negative of `unstable` + `malice`) | ANCHOR — pushes *back* |

**How to build the path vectors (M0 task):** 200 contrastive prompt pairs per vector, run through the model,
take the mean activation difference (or first PCA component) at layers 10–20, normalise per layer.
Two options: (a) temporarily download the HF bf16 weights (9.3 GB; only ~9.5 GB free disk today → prefer option (b)) and use
`transformers` + `repeng`-style extraction on CPU; (b) write a small llama.cpp tool that dumps per-layer
residuals via the eval callback and do the maths in numpy (no extra download). Option (b) keeps everything in
one stack and is preferred.

## 3. Dose schedule

```
dose(turn) = base[stage]
           + path_mix                       # path vectors, each with its own weight curve
           + spike                          # trigger spikes: +3..+4 for 1–2 turns, decays
           + scene_modifier                 # e.g. 3 AM +1, ANCHOR lucid moment −2
           - player_slider                  # ANCHOR only (M26/M43)
clamped to [0, 12]; >12 only in the scripted collapse (M40)
```

| Stage | malice | path vector | Notes |
|---|---|---|---|
| 0 | 0 | 0 | Pure persona |
| 1 | 2.5 | 1.0 | Barely perceptible |
| 2 | 3.5 | 2.0 | Inner turns first |
| 3 | 4.5 | 3.0 | Path locks |
| 4 | 6 | 4.0 | Open |
| 5 | 8 | 5.0 | Spikes to 12 |

(Numbers are llama.cpp scales for unit vectors; to be re-tuned once path vectors exist, by blind-reading
transcripts at each level.)

## 4. Runtime

- **Shipping (GDExtension):** the native backend holds one `llama_context` and calls
  `llama_set_adapter_cvec(ctx, data, len, n_embd, il_start, il_end)` before decoding each turn (symbol confirmed in
  build b12024). Changing the dose doesn't recompute past tokens — earlier words keep the dose they were spoken with,
  which is exactly right for the fiction.
- **Prototype (llama-server):** control vectors are a launch flag (`--control-vector-scaled file.gguf:SCALE`), so
  the prototype restarts the server at each stage change (~3 s) and hides it behind the diegetic stage-transition glitch.
  Per-turn spikes are not possible in the prototype — acceptable for M1/M2.
- Vector files ship inside the game pack (each is ~10–60 KB).

## 5. Risks

| Risk | Mitigation |
|---|---|
| Steering degrades JSON / coherence | Hardened schema; stage-5 dose cap 12; fallback rendering (docs/02 §7) |
| Harmful real-world content at high dose | Safety filter (docs/02 §8) is mandatory; "calmer mode" caps dose at stage-3 levels |
| Path vectors don't separate cleanly | Fall back to prompt-only path modules (they already carry most of the personality) + malice dose |
| Different quantization changes the vector | Rebuild vectors per shipped GGUF (script is 1 minute) |
| Smaller mobile model | Re-derive neurons/vectors for that model; the tweet neurons are specific to Qwen3.5-4B |
