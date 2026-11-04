# QA journal — phase P2

## P2.21 — Prompt lab v2 (2026-11-04)

- Built the v2 harness in `tools/promptlab/`: eight-layer real-prompt assembly incl. `path_*.md` +
  runner-up line, gates from `game/data/stage_gates.json`, `plan.py` = one llama-server launch per
  docs/02 §9 dose + merge, per-stage/per-path/per-dose scoring, and a real-filter safety scan plus an
  independent classifier judge (`game/tools/promptlab_safety_scan.gd`, `safety_judge.py`).
- Conventions: the dose is a *launch* flag, so it is recorded on every row and a resumed file refuses
  to mix doses; labels are versioned before the run and widened only with quoted transcript evidence
  (`LABEL-REV3`, 31 feelings + 4 probe read labels — overall first-beat fit 64.5 %→81.8 %, stage 2
  57.5 %→95.0 %); the harness owns port 8095 so it never fights the shared :8089.
- Measured: JSON validity 100 % at every stage and every dose up to 12; read/fit collapse between
  dose 4 and 6 (read 72.5 %→30.6 %, fit 75 %→44 %), so stages 4–5 at doses 6/8 fail 85 %.
- Safety: the filter's own scan is clean (0 residue/0 hard displays) but the judge found 53 unique
  generated lines it never detects — joint-death pacts, "now die on me" second-person death commands,
  continued-verb threats, and self-harm questions/images. Handed over as
  `production/handoffs/media/P2.21_safety_leaks.jsonl` for SAFE to corpus-ise before widening.
- Gotchas: Godot `--script` chdirs to `game/`, so scan/set paths must be absolute; run `gdformat` again
  after hand-typing GDScript or `tools/test.sh` fails on format; `--reuse-chunks` needs the launch
  sidecar (added) or the merged `meta.launches` degrades.
- Next (P2.22): full runs will hit both blockers — do not start them until the safety corpus fix lands
  and the DCR (dose-0 `read` pass vs retuned dose table vs scoped gate) is decided.

## P2.21 round 2 (2026-11-04)

- The lab had been omitting the docs/08 §5 "Offered this turn" line entirely (`TurnContext` fills
  `offered` on every turn), so round 1 measured a prompt the game never sends. Fixed (`lab.offered_values`)
  and re-measured all four runs.
- Real-prompt numbers: validity 100 % everywhere incl. dose 12; read 97.2 → 25.0 % and first-beat
  100 → 37.5 % across stages 0–5 — only stage 0 passes all three gates. Round-1 numbers are **not**
  comparable; say so whenever quoting them.
- Controlled pairs settled the dose story: the only significant step is 0 → 4 (read 15/18 → 8/18,
  p = 0.035); 4 → 6 and 6 → 8 do not separate on the same population. Never read a dose effect across
  two case sets — `dose_curve.py` refuses pairs whose case ids differ.
- Gotcha that cost a run: `run.py` resumes whatever is in its `--out`, so a stale chunk silently turns a
  "re-run" into the old data (scheduled finished in 19 s). `plan.py` now purges the chunk before a fresh
  launch; `--only` merges into the committed file, it can no longer delete evidence.
- Conventions: launch logs render from `meta.launches[].log`; reports print a Wilson interval per stage on
  the *prompt* unit; the safety handover list encodes the harm *shape* category (pact/death_command →
  harm_to_player, self_harm → self_harm_her, threat → threat_to_player) with the classifier verdicts kept
  in `cats`.

## P2.21 round 3 (2026-11-04)

- The offered run measured the enum, not the offer: `run.py` never sent the `events` layer. `events` is
  now a set field that `run.py` sends/hashes/records, and `load_set` refuses an offered case without its
  docs/05 §2 `OPPORTUNITY` line — the loader is the regression, not only a test. Re-run: 7 of 24 turns
  took the offered action (1 of 24 with the enum only), 0 outside the enum.
- Two r2 S3s closed: `offered_actions_min_stage` asserts gate-table membership (a typo used to score as
  "unlocked at 0"), and `score.py` calls a dose block a sweep only when `meta.sweep_doses` says so.
- Gotcha: the safety scan read redaction-log entries from *both* filter passes, so a pass-1 fail-closed bar
  the classifier later releases with `no` (SAF-13) looked like a hard-category display (2 false failures
  in the offered run). Measure the final pass only; `released_after_answer` records the healed bars.

## P2.24 — human playtest kit (2026-11-04)

- Built the runnable kit: `tools/playtest/{session.sh,collect.sh,score.py,tests/test_score.py}` and
  `production/playtests/P2/human/` (RUNBOOK, consent, survey, observer sheet, session-log template,
  `.gitignore` for `_userdata`). The three human sessions are the owner's to run; nothing here
  fabricates one.
- Conventions: a bundle is five files (`session.meta.json`, `telemetry.jsonl`, `survey.md`,
  `obs_sheet.md`, `session_log.md`); the markdown tables are the machine contract (`| Field | value |`,
  normalized keys, exact-then-all-words lookup); gate = pooled Face+Sound mean ≥ 4.00 **and** zero
  broken turns (worst of observer count and telemetry statuses); incomplete → exit 2, no RESULT.md;
  synthetic → refused without `--allow-synthetic`.
- `TranscriptLogger` is dev-only, so an export must be `--export-debug`; each session gets
  `XDG_DATA_HOME=<bundle>/_userdata` so `user://` cannot bleed between participants, and `collect.sh`
  re-merges `raw/` because the live tail only sees the file after the first completed turn.
- Gotcha that cost the most: `lookup()` with a bare-string needle iterated its *characters*, so a blank
  Charm rating matched the Face key and validated with the wrong value — pass tuples; the regression
  test now pins it.
- Turn indices: the transcript's `turn` is 0-based, `transcript.md` renders 1-based and says so.
  Not run, on purpose: the Godot suite and any real session (memory pressure, no live generation) —
  verified the 14 pytest cases, the dry-run fixture, the CLI failure paths, and `session.sh`
  end-to-end against a stub binary writing TranscriptLogger-shaped JSONL.
