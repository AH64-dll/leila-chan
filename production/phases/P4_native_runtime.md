# P4: Native runtime (weight 12%)

**Goal:** docs/09 M4. Ship without an external llama-server process. A GDExtension (or NobodyWho, if the P0.09
spike says it fits) runs the model in-process, applies the steering dose per turn (spikes M39), caches the stable
prompt prefix, and builds on Windows, Linux and macOS.

## Entry criteria
- P3 gate passed. P0.09 spike recommendation available.

## Role roster for this phase
| Role | Mission in P4 |
|---|---|
| LLM | Runtime decision, GDExtension, NativeBackend, caching, fast mode |
| STR | Per-turn control vectors, mixing, spikes |
| REL | Per-platform llama.cpp + Godot export matrix in CI |
| SYS | Remove the server-restart path, instant stage transitions |
| META | Diegetic loading screen and model-load errors |
| QA | Parity tests, hardware tiers, min spec |

## Tasks
| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |
|---|---|---|---|---|---|---|---|
| P4.01 | Runtime decision: NobodyWho vs own GDExtension, re-checked against the current llama.cpp and the P0.09 spike (docs/spikes/P0.09_nobodywho.md); ADR in docs/adr/ | LLM | S | — | design | docs/07_TECH_ARCHITECTURE.md§1, docs/06_STEERING.md§4 | ADR with criteria (cvec API, grammar, streaming, platforms, licence); decision logged in DECISIONS.md |
| P4.02 | GDExtension `libleila_llm` (C++): load model, context, JSON-schema grammar, token streaming to GDScript on a worker thread | LLM | L | P4.01 | code, design | docs/07_TECH_ARCHITECTURE.md§1, docs/07_TECH_ARCHITECTURE.md§3.1 | Builds on Windows (CUDA + Vulkan); streams a schema-valid Turn in a Godot test; no main-thread stalls > 16 ms; name contains no brand ("qwenchan" → "leila") |
| P4.03 | Runtime control vectors via `llama_set_adapter_cvec` per turn, vector mixing, M39 dose spikes with decay | STR | M | P4.02 | code, design | docs/06_STEERING.md§3, docs/06_STEERING.md§4, docs/05_META_EVENTS.md§1.6 | Dose changes between turns without reloading; spike +3..+4 for 1–2 turns then decays (test); mixed vectors produce expected blind-read behaviour |
| P4.04 | `NativeBackend.gd` implementing the LLM facade; backend switch in settings/dev; parity test vs LlamaServerBackend | LLM | M | P4.02 | code, design | docs/07_TECH_ARCHITECTURE.md§2 | Prompt lab metrics on native within 2 points of server backend at every stage; switching needs no other code changes |
| P4.05 | KV / prompt-prefix caching across turns within a scene | LLM | M | P4.04 | code | docs/07_TECH_ARCHITECTURE.md§3.1 | First-beat latency improvement measured (before/after table); correctness: cached vs uncached output identical at temperature 0 |
| P4.06 | CPU fast mode (1 beat, shorter replies), GPU auto-detect, Vulkan/Metal paths, graceful OOM handling | LLM | M | P4.04 | code, design | docs/07_TECH_ARCHITECTURE.md§4 | Fast mode playable at ≥ 6 tok/s on an 8-core CPU; OOM → falls back with a diegetic message, no crash |
| P4.07 | Build matrix in CI: llama.cpp per platform (CUDA + Vulkan Win/Linux, Metal macOS) + Godot exports for Windows/Linux/macOS | REL | L | P4.02 | code | docs/07_TECH_ARCHITECTURE.md§6 | CI produces three artifacts; each boots to title on its OS (evidence: screenshots/logs); model file loaded from install folder |
| P4.08 | Diegetic loading screen at boot + model load errors (missing model, wrong hash, no GPU) | META | S | P4.04 | code, design | docs/07_TECH_ARCHITECTURE.md§6 | Loading shows progress; each error case has an in-fiction message + a plain-language fix |
| P4.09 | Remove the server-restart stage transition; transitions become instant dose changes; regression run | SYS | S | P4.03 | code, design | docs/06_STEERING.md§4 | Prototype restart path removed or dev-only; full YANDERE regression transcript shows transitions working |
| P4.10 | Hardware tiers: RTX 4050 6 GB, a 4 GB VRAM GPU, CPU-only; publish min spec | QA | M | P4.05, P4.06, P4.07, P4.08, P4.09 | code, design | docs/07_TECH_ARCHITECTURE.md§4 | Table of first-beat/full-turn/fps per tier; min spec text for the store page committed |

## Exit criteria (gate)
1. Release builds on Windows, Linux and macOS run without an external process.
2. Per-turn dose works (spike test passes); native backend parity within 2 points of prompt-lab metrics.
3. First beat < 1.0 s on the RTX 4050; CPU fast mode playable.
4. Min spec published.

## Risks
- llama.cpp API drift → pin the llama.cpp commit in the extension; update deliberately.
- macOS signing/notarisation → REL documents it; may slip to P6 with the user's approval.
