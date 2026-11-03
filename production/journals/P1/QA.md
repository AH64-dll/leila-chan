# QA journal — phase P1

## P1.20 — Prompt lab v1 (2026-11-03)

- Built `tools/promptlab/` grown from `experiments/`: `lab.py` (real `game/data/prompts/`
  assembly per docs/08 §1, docs/02 §3 schema + §2 gates + §9 sampling), `run.py`
  (incremental/resumable runner), `score.py` (99/85/85 gates), `report.py` (MD+HTML).
- Conventions chosen: labels are versioned JSONL committed BEFORE the run; widen
  `feelings_ok` only with cited transcript evidence (`LABEL-REV<n>` in `notes`) — D10.
  C10 done as `--beat first|any` on score/report; gate defaults to first-beat.
- D10: applied P0.04's miss evidence up-front (shy/nervous widenings on insult,
  apology, jealousy, meta-AI, BOO, math, arcade); stage-4 leftovers documented for
  P2.21, not chased here.
- Gotchas: "memory" meta-word check must NOT include ambiguous field names — a literal
  field-name list rejects the good `gave me a music box` few-shot (P1.05 CON-2 trap).
  Server dose is a launch flag — the shared :8089 server has no control vector, so
  stage-1 ran at dose 0 (deviation recorded in results meta).
- Runner detail: cold first turn ~98 s, then ~18 s/turn once the prompt prefix is
  cached — budget accordingly; `--out` resumability exists for exactly this reason.
- Next: P2.21 grows this to stage 2–5 sets (+ path files) and can restart its own
  server with `--vector` to measure the scheduled doses.

## P1.21 — Performance pass (2026-11-03)

- Benchmarked 30 live turns with `cache_prompt: true` prefix reuse against Qwen3.5-4B-Q4_K_M on port 8089.
- Metrics across 30 turns: TTFT median 391 ms (p95 450 ms), first usable `say` median 7,521 ms (p95 7,894 ms), full turn median 14,514 ms (p95 17,581 ms).
- Godot VRAM: measured via `Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)` on assembled `Date.tscn` (background, Character, ChatUI, FX, audio) — 0 bytes headless, < 12 MB textured, well below the 800 MB budget on RTX 4050.
- Conventions chosen: evaluate P0 gate C8 honestly; document both the Linux host CPU server measurement and the earlier Windows CUDA benchmark; filed proposed follow-up for schema field reordering to satisfy the < 1.0 s first-beat gate.

## P1.22 — Playtest round 0 (2026-11-03)

- Ran three 10-minute-class sessions on D02 (14/14/12 turns, stage 0/0/1) through the real Boot→Title→NewGame→Date flow against the live :8089 server. **Testers are simulated** (scripted personas: cooperative/flirty, terse/dismissive, boundary-probing); ratings are QA rubric judgments from the committed transcripts, not human survey data. Evidence in `production/playtests/P1/`.
- Result: face/sound mean 4.44/5, charm 4.33, creep 2.33, but **1 broken turn** — a Safety-rejected player line leaves ChatUI locked forever (`turn_failed` returns before `abort_turn`). The playtest gate "zero broken turns" is not met; 8 findings filed as P2.x candidates in the survey/handoff.
- Conventions chosen: broken = fallback visibly wrong or stuck (not design-intended deflection); face scored per beat from `casting.json` + anti-repeat flag; sound scored from played/denied cues with denial reasons; decimal means over 1–5.
- Gotchas for the next playtest: one session per process with `XDG_DATA_HOME` overridden to isolate `user://debug`; `--script` SceneTree drivers cannot reference autoload identifiers at compile time (fetch nodes from `/root`), and `Date.turn_completed` can fire before the driver connects, so poll `chat_ui.is_turn_open()`; do **not** register `Date` as the FX host — `Character` owns the `play_fx() -> String` contract.
- The game still has no scene controller (nothing calls `start_date`, registers the Director seams, or consumes scenario events/end rules); the throwaway driver stood in and is deleted before the commit. A supported headless run mode is owed before P2.22/P4.10.
