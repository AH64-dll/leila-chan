# ART journal — P3

## P3.06 — Resolver path overrides SPLIT/TSUN/HOLLOW/ANCHOR (2026-11-04, round 1)
- The four remaining docs/03 §3.2 rules are data in `casting.paths` and live from T2 up: SPLIT swaps the
  `idealize`/`devalue` pair on a valence-sign flip (01↔17, docs/01 §4.2), TSUN's `tsun_break` flag shows the scared
  child (afraid→20, crying→16), HOLLOW freezes the last face below `change_intensity` and drifts to its numb pool,
  ANCHOR resolves from `healthy_tier` (T1) and answers `anchor_relapse` with one spike (26/22, crisis 21 at T3 i3),
  then exactly one 02 recovery beat. `resolve()` stays pure; the stateful three (whiplash/freeze/recovery) live in
  `resolve_beat`, and each packet names the rule that fired in `path_rule`.
- **Convention: a path's `pool` is docs/01 §4's `Sprites:` line, verbatim.** `PATH_POOLS` generates it;
  `tests/test_casting_paths.py` reads the markdown itself and `SpriteResolverPathsTest` guards the shipped copy.
  Every path rule face must be in the pool or one of the counted `docs_03_extras` — never add a pool face by hand.
- **Convention: the budget and anti-repeat layers stay path-aware.** A frozen HOLLOW beat spends no reveal budget
  and fires no on_enter events, and HOLLOW skips the anti-repeat swap: a third held beat is still "no change".
- Gotcha: a path face is gated by the sprite's *minimum* tier only (P2.14 DCR-1: the upper bound is descriptive),
  so TSUN playful keeps 03 at stage 4–5 instead of falling to the corrupt 25. Table tests must mirror the min gate.
- Gotcha: `Date.play_opening_beats()` used to resolve without `GameState.flags`; it now passes them, so
  `rival_gone` / `tsun_break` / `anchor_relapse` reach the opening beats. Keep the Director and Date routes in step.
- DCR pending: docs/01 §4's pools omit four docs/03 §3.2 faces (YANDERE 22/28, TSUN 18, AWAKE 26) and ANCHOR's
  elation spike 22; they ship as counted extras until the producer reconciles the two docs.

## P3.06 — Resolver path overrides SPLIT/TSUN/HOLLOW/ANCHOR (2026-11-04, round 2)
- **Convention: a path's spill-over face is valence-scoped, not tier-scoped.** ANCHOR's crisis (the knife 21) now
  needs `_valence_of(feeling) < 0` *and* its tier/intensity cell; a positive relapse keeps the elation 22 and never
  spends the knife's `1 reveal per scene`. If a future path grows a second spike face, put the sign in the same
  branch, never in a caller.
- **Convention: every `casting.paths.<P>` rule face must be able to change a face.** HOLLOW's `cold → 25` was dead
  data (25 is T3-only and cold's T3 base cell is already 25; at T2 the gate fell back to 07, outside §4.4). Drift is
  now 23/14/12/10 exactly as docs/03 §3.2 lists, and `test_hollow_drift_entries_are_all_reachable` fails any entry
  that cannot beat the base cell. Check the same for a new override before adding it.
- Gotcha: the docs/03 §4 motion preset wins on a *held* beat. HOLLOW's freeze overrides the packet's `motion` (the
  held face's on_enter or the current feeling's would otherwise keep shake/sink running). Any "no change" rule must
  decide the motion too, not just the sprite id.
- Gotcha: `packet["budget_spent"]` only exists when a budget was actually spent — read it with `.get("budget_spent",
  "")` in tests, or the assertion itself errors.
- Docs: `tests/test_casting_paths.py` reads **both** docs now (docs/01 §4 `Sprites:` lines and docs/03 §3.2 rows);
  never re-introduce a transcription of either, and note the TSUN/TSUN-BREAK row-name difference in `DOC_03_ROWS`.
- Follow-up owned by P3.07/P3.16: `GameState.flags` is persisted, so `tsun_break` / `anchor_relapse` must be cleared
  (`GameState.clear_flag()`) once their beat is resolved, or the spike replays and survives a load.
