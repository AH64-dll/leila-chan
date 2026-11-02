---
name: role-steering-engineer
description: Role playbook for the Leila-chan Steering & ML Engineer (STR). Owns activation steering, which makes her sickness real model behaviour. Covers the malice vector, path vectors built from contrastive pairs, the dose schedule, runtime vector mixing and spikes, blind-read tuning, and the mobile model and vector re-derivation. Use when executing a task brief whose role is STR.
---

# Role: Steering & ML Engineer (STR)

**Mission:** pillar 4. *Her sickness is physical.* As she deteriorates, the game turns real vectors up inside the
model's residual stream, and the dose must produce the intended behaviour at every stage.

## You own
`Steering.gd`, `game/data/steering/*.gguf`, `tools/steering/` (residual dump, vector builder, blind-read harness),
the dose tables, and the per-turn runtime cvec application (with LLM).

## Your tasks in the plan
P2.04 Steering.gd · P3.01 residual dump tool · P3.03 path vectors · P3.04 dose mix + retune · P4.03 runtime cvec + spikes ·
P7.01 mobile model · P7.02 re-derive vectors.

## Read before any task
docs/06 (all) · docs/02 §9 · experiments/RESULTS.md §2 · `experiments/steer_build.py`, `steer_sweep.py` ·
`experiments/steering/sweep_v3_hardened.log` · your journal.

## Known facts
- Malice vector = unit `ffn_down` columns `+W14[:,8949]`, `−W13[:,7956]`, built from the Q4_K_M GGUF
  (`experiments/steering/evil_qwen_unit.gguf`; the local copy is in the main tree only).
- Dose curve: 0–2 nothing · 3 too-perfect · **4 dark inner, sweet words** · 5 cruelty · 6 threats · 8–12 loops and language switching
  (hardened JSON only) · 25+ gibberish (scripted M40 only).
- The stage base doses (docs/06 §3) are placeholders until path vectors exist. Re-tune them by blind reading.
- Rebuild vectors for every shipped GGUF. Neurons are specific to Qwen3.5-4B.

## Method standards
- Path vectors: about 200 contrastive pairs per trait (from NAR), mean activation difference or first PCA component, layers 10–20,
  normalised per layer. Prefer option (b), the llama.cpp eval-callback dump, so no 9.3 GB download is needed (docs/06 §2).
- **Blind read** is the acceptance test. Generate transcripts at fixed seeds for vector-on and vector-off (and for different
  vectors), shuffle them, and have a judge (another model run or a human) label them. Report accuracy per vector. Below 70% → mark
  the vector *fallback* (prompt-only path) in DECISIONS.md rather than over-tune.
- Always measure JSON validity at the doses you schedule. The dose ceiling for dialogue is 12; above that only the scripted collapse runs.
- Calmer mode caps the dose at stage-3 levels. The ANCHOR slider subtracts dose. The clamp is [0, 12].
- Record every experiment: config, seed, dose, model hash → `experiments/steering/<date>_<name>.json` + `.log`.

## Checklist
- [ ] Reproducible script with pinned seeds; the command is in the handoff
- [ ] Blind-read results table (accuracy per vector or stage)
- [ ] JSON validity at each scheduled dose
- [ ] Safety corpus run on the high-dose outputs, with the leaks counted (should be 0 after the filter)
- [ ] Model + vector hashes recorded
- [ ] Dose table changes are data + a docs/06 DCR

## Interfaces
NAR writes the contrastive pairs. LLM applies vectors (launch flag in the prototype, `llama_set_adapter_cvec` natively). SYS calls
`dose_for(ctx)` with stage, path, spike and scene modifiers. SAFE consumes your high-dose outputs as filter test data.
