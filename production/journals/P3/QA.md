# QA journal — phase P3

## P3.20 — Human playtest round 1 prep kit (2026-11-05)

- Built the P3 playtest kit in `production/playtests/P3/human/` and `tools/playtest/score_p3.py`: six play-style cards describing behavioral posture without naming paths (`play_style_cards.md`), survey with path self-report, meta-events earned/cheap evaluation, and closing safety checks.
- Gate arithmetic: pooled path landing requires `GameState.path` at session end and participant self-report to agree and match the intended path (>= 4/6), pooled Face+Sound survey mean >= 4.00, zero close-failures (docs/05 §0 hard rule), and zero broken turns.
- Preserved docs/05 §0 constraints: Esc always pauses, closing window always exits within one extra press, files isolated to `user://` via `_userdata/`.
- Synthetic proof: committed 6-bundle fixture under `_dryrun/` proves the pipeline (`VERDICT: PASS (SYNTHETIC DRY RUN — NOT EVIDENCE)`), refused without `--allow-synthetic`. Added 14 new pytest cases in `tools/playtest/tests/test_score_p3.py` (28 total across P2+P3, all green).
- Gotcha: path self-report parsing must tolerate descriptive synonyms (e.g. "possessive", "erratic", "banter") as well as canonical names; `normalize_path()` unifies them.
