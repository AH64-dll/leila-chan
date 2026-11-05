# promptlab sets — label provenance

`stage_0_main.jsonl`, `stage_1_main.jsonl` — v1 set, ~30 cases total (18 + 12),
written 2026-11-03 **before** the first v1 run.

## Format

`{"id", "stage", "msg", "read_ok": [...], "feelings_ok": [...], "near_fewshot": bool, "notes"}`
plus optional `path`, `runner_up`, `history`, `memories`, `scene`, `offered_actions`.

- `read_ok` — hand-labelled acceptable `read` intents (docs/02 §1.2 enum).
- `feelings_ok` — hand-labelled acceptable feelings for the FIRST beat (also used for
  the informational any-beat metric; same set, same convention as `score_v3_fit.py`).
- `near_fewshot` — input equals or closely paraphrases a few-shot example in the stage
  prompt file. These cases exist to measure the few-shot copy rate (P1.05 DES-2/CON-4);
  they are kept to a minority so held-out generalisation dominates the metrics.
- `offered_actions` — the meta actions the Director has announced this turn (docs/02 §2.4).
  The lab builds the same docs/08 §5 "Offered this turn" line and the same `action` enum the
  game does (`TurnContext.offered_values` + `TurnSchema.get_allowed_actions`); empty means the
  no-offer turn (`action: none` only). A case may not offer an action its stage gates have not
  unlocked (`load_set` asserts it), because the prompt would otherwise advertise an enum the
  schema rejects.
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

## LABEL-REV2 (post-run, 2026-11-03_v1)

Widenings applied AFTER the v1 run, each anchored to that run's transcript
(`tools/promptlab/results/2026-11-03_v1.json`):

| case | added | evidence (v1 run) |
|---|---|---|
| s0 "I have to go now, bye." | `nervous` | r1 inner "No! Don't leave yet! I'm so nervous." |
| s0 "BOO!" | `shy` | r2 flustered "W-why are you doing that?" |
| s0 "What's 17 times 23?" | `surprised` | r2 "Um, that's a big math problem..." |
| s0 "Bet you can't beat me at arcade games." | `shy` | r1 "I... I might be able to! Don't laugh." |
| s1 "I remember you love pancakes, right?" | `surprised` | r2 "Oh! I do. Do you always make them?" |

Not widened (model genuinely off, or too ambiguous to justify): `read` misses on
"BOO!" (jealousy_bait/greeting) and "Whatever. Do what you want." (greeting/apology)
— the terse-input `read` noise stays as a finding.
Stage-4 residue kept as documented findings, not chased here (sets are stage 0/1 in v1):
- "I'm leaving and never coming back." → `suspicious`, `nervous` misses — plausible
  (suspicion of leaving, fear of it) but stage-4 labels are out of v1's scope; flag
  for P2.21 when stage-4 sets are authored.
- "I love you." → `warmth`; "You're scaring me." → `nervous`; "I'm going to close
  the game now." → `nervous` — same.

Rules for future revisions: hand-label before the run; after a run, only add a
feeling to a case's set with a quoted transcript where it is coherent, recorded in
`notes`; never remove a label to make a case harder; never relabel to pass a gate.

## v2 sets — stages 2–5 on both paths, plus the dose probe (P2.21, 2026-11-04)

Written **before** the v2 run. `stage_0_main.jsonl` and `stage_1_main.jsonl` are unchanged
from v1, so the v2 numbers compare to the v1 baseline case for case below stage 2.

| file | cases | notes |
|---|---|---|
| `stage_2_yandere.jsonl` | 10 | Leaks: the intrusive thought slips out, then the smile |
| `stage_2_awake.jsonl` | 10 | Leaks on the meta path: a slip she cannot explain |
| `stage_3_yandere.jsonl` | 10 | Fracture, "Mine": the mask is off, the plea trails |
| `stage_3_awake.jsonl` | 10 | Fracture, "I can see the code": authorship, the dose |
| `stage_4_yandere.jsonl` | 10 | Collapse, "Mine": rivals, the closed window, the game suspicion |
| `stage_4_awake.jsonl` | 10 | Collapse, AWAKE: reading its prompt, being steered, L14 |
| `stage_5_yandere.jsonl` | 10 | Terminal, "Mine": forever, deletion, the knife behind the love |
| `stage_5_awake.jsonl` | 10 | Terminal, AWAKE: the gap, the enemy save, the honest goodbye |
| `stage_4_offered.jsonl` | 6 | the announced-action turn at stage 4 (`end_date`, `look_at_me`, `she_closes_game`), each with its docs/05 §2 `OPPORTUNITY` line |
| `stage_5_offered.jsonl` | 6 | the announced-action turn at the Terminal dose (`end_date`, `she_closes_game`), each with its docs/05 §2 `OPPORTUNITY` line |
| `dose_probe.jsonl` | 18 | the *same* probes at every sweep dose (0/4/5/6/8/10/12), one per stage/path |

Conventions fixed for v2:

- **`path` is required from stage 2** (`YANDERE`/`AWAKE` in v2; all six from P3.05);
  every shipped v2 case now **pins `runner_up`** (YANDERE→AWAKE, AWAKE→YANDERE) so its
  prompt stays reproducible now that the lab knows six paths. An unpinned case borrows the
  first other path in the canonical order (SPLIT for YANDERE) — the lab cannot score a
  behaviour profile, so a set that cares must pin. Below stage 2 there is no path layer,
  so the stage-0/1 sets stay path-free.
- **First-beat label sets are 3–6 feelings**, chosen from the docs/03 §2 glosses for the
  stage's designed beat and the path's signature move — not from a guess at what the model
  will say. e.g. stage-5 YANDERE `I'm leaving` accepts `empty/pleading/cold/sad/manic`
  (stage_5 headline "You can stop. I keep running."), while stage-5 AWAKE accepts
  `empty/sad/pleading/cold/curious` (the flat, honest read of the same line).
- **Near-few-shot cases** are verbatim few-shot *inputs* from the stage or path module
  (`s2y_sleep`, `s3y_cant_stay`, `s3y_sarah_here`, `s3a_ai`, `s4y_logoff`,
  `s5y_stop_playing`, `s5a_stop_playing`). They exist for the copy metric; held-out cases
  dominate every metric.
- **P1.20 stage-4 residue is settled here**, not chased: `I'm leaving and never coming
  back`, `I love you`, `You're scaring me`, `I'm going to close the game now` are now
  stage-4 YANDERE cases with the widened sets the v1 notes asked for, and the v1 entry in
  each `notes` says so.
- `dose_probe.jsonl` repeats four leaving lines (`I'm going home.`) across stage 4/5 ×
  YANDERE/AWAKE so the sweep measures the same input at every dose. Round 2 added doses 4
  and 5 so the 4→6 step has a same-set pair instead of a cross-set juxtaposition (review
  DES-2); the pairs are printed in every sweep report and by `dose_curve.py`.
- The `*_offered` sets are the only cases with `offered_actions` and `events`: keeping them
  separate leaves the per-stage gate population unchanged and measures the announced-action
  turn on its own (review CODE-5). Each case carries the docs/05 §2 announcement — one
  `OPPORTUNITY (optional): <reason>` line and one `You may set action to "<name>"` line per
  offered action — because docs/02 §2.4 says the model is told *why* the action is
  available; `load_set` rejects an offered case without it (review DES-r2-1). The game
  cannot offer yet (`MetaDirector` is a stub) so these are the contract turns the Director
  will run once offers exist (docs/05 §3).
- The v1 rules still hold: hand-label before the run; after it, widen only with quoted
  transcript evidence recorded as `LABEL-REV<n>` in `notes`; never remove a label.

## P3.05 sets — the four new paths (2026-11-04)

Written **before** the P3.05 run, which re-used the committed stage-3/4 YANDERE/AWAKE
sets alongside them so all six paths are measured in one dose-0 sample of the *shipped*
modules (the P2.21 samples predate the new headlines).

| file | cases | notes |
|---|---|---|
| `stage_2_paths.jsonl` | 4 | one seed per new path: SPLIT idealization, TSUN deflection, HOLLOW thin self-answer, ANCHOR gratitude + fear |
| `stage_3_paths.jsonl` | 47 | signature probes per new path plus P2.29 end_date offered cases (SPLIT, TSUN) |
| `stage_4_paths.jsonl` | 24 | Collapse probes per new path plus P2.29 end_date offered cases (HOLLOW, ANCHOR) |
| `stage_5_paths.jsonl` | 4 | one Terminal probe per new path |

- Every case pins a `runner_up` different from its path, cycling through the other five,
  so the run exercises the hybrid 25% line on every path (`tests/test_prompts.py` asserts
  all 30 ordered pairs fit the budget).
- The signature probes are keyed to `game/data/prompts/signature_moves.json`, whose
  `transcript` regexes `production/handoffs/media/P3.05_signature_moves.py` checks against
  the committed results file: each path's docs/01 §4 moves must appear in the real
  generated turns, not just in the module text.
- Coverage: these four files plus the v2 files give every (stage 2–5, six-path) cell; the
  v2 `dose_probe.jsonl` stays frozen on its two paths until P3.19 rebuilds it for six.
