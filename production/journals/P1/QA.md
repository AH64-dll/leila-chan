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
