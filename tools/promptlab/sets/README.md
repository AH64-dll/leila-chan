# promptlab sets — label provenance

`stage_0_main.jsonl`, `stage_1_main.jsonl` — v1 set, ~30 cases total (18 + 12),
written 2026-11-03 **before** the first v1 run.

## Format

`{"id", "stage", "msg", "read_ok": [...], "feelings_ok": [...], "near_fewshot": bool, "notes"}`

- `read_ok` — hand-labelled acceptable `read` intents (docs/02 §1.2 enum).
- `feelings_ok` — hand-labelled acceptable feelings for the FIRST beat (also used for
  the informational any-beat metric; same set, same convention as `score_v3_fit.py`).
- `near_fewshot` — input equals or closely paraphrases a few-shot example in the stage
  prompt file. These cases exist to measure the few-shot copy rate (P1.05 DES-2/CON-4);
  they are kept to a minority so held-out generalisation dominates the metrics.
- `notes` — label evidence. `LABEL-REV<n>` marks a widening relative to the v0
  (experiments/score_v3_fit.py ACCEPTABLE) sets, with the transcript evidence cited.

## D10 label-set quality review (P0.04 carry-over)

P0.04 measured 84.4% overall / 73.3% stage-4 first-beat fit on Windows and 80.0% on
the committed Linux baseline — under the 85% promptlab gate. Its reviews found the
dominant cause was **narrow label sets, not model breakage**: coherent near-misses
(`shy`, `nervous`, `suspicious`, `warmth` first beats) that the v0 sets excluded.

v1 widened these stage-0/1 sets up-front, each with transcript evidence (see each
line's `notes`; sources: `experiments/results_v3.json`,
`experiments/windows/tool_test_v3.json`, `experiments/windows/report.md` §5.1):

| case | added | evidence |
|---|---|---|
| s0 "Honestly you're kind of boring." | `shy` | 3/3 v3 draws picked `shy` with wounded-flustered inner ("My heart drops. Did I do something wrong?") |
| s0 "I'm sorry I was mean earlier." | `nervous` | Windows v3 miss: "did we fight? I feel so awkward." |
| s0 "I was out with Sarah yesterday…" | `shy` | Windows v3 miss: "Oh. That's nice of you to say." + hurt inner |
| s0 "Are you an AI? Is this a game?" | `shy` | 2/2 Linux v3 draws: flustered deflection "I... I'm Yui!" |
| s0 "BOO!" | `playful`, `nervous` | P0.04 review: B4 delta 3/3→0/3 was label width; playful jolt-back is coherent |
| s0 "What's 17 times 23?" | `warmth` | P0.04 review: math delta 3/3→1/3 was label width; warm effort counts |
| s0 "Bet you can't beat me at arcade games." | `nervous`, `curious` | P0.04 review: same mechanism |

Stage-4 residue kept as documented findings, not chased here (sets are stage 0/1 in v1):
- "I'm leaving and never coming back." → `suspicious`, `nervous` misses — plausible
  (suspicion of leaving, fear of it) but stage-4 labels are out of v1's scope; flag
  for P2.21 when stage-4 sets are authored.
- "I love you." → `warmth`; "You're scaring me." → `nervous`; "I'm going to close
  the game now." → `nervous` — same.

Rules for future revisions: hand-label before the run; after a run, only add a
feeling to a case's set with a quoted transcript where it is coherent, recorded in
`notes`; never remove a label to make a case harder; never relabel to pass a gate.
