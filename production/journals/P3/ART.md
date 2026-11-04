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
