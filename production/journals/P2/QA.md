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

## P2.22 round 1 (2026-11-04)

- Built the live full-run harness (`game/tools/FullRun.tscn` + driver/report/store/net). It drives the shipped Date/Night scenes (ChatUI → Director → PromptBuilder → llama-server → GameState → Triggers → NightLoop) and resumes from the game's autosave; the per-turn JSON sidecar + annotated Markdown are the artifacts.
- The scene layer ships unwired: `Date.start_date()`, `player_turn_sent → Director.submit_player_input` and `Director.scene_info` have **no production callers** (S1-1…3). The harness installs them, so a transcript is not proof that a by-hand build is playable — say so whenever quoting these runs.
- Pacing: two live YANDERE runs reached Terminal on day 5 and day 4. The model's `read`=jealousy_bait fires T01 at half strength 16–39× per campaign (cooldown 1) and its `stress` (+2/+3 on a fifth of turns) dominates the 0.35 slow burn. Numbers are in `production/playtests/P2/full_run_report.md`.
- Fixation and Lucidity have no writers anywhere (only NewGame's +5), so the slow-burn formula is a constant and E12 (Lucidity ≥ 70 at day 14) is unreachable — S2 for SYS.
- Gotchas: never fill a turn record on the frame *after* its display boundary — the Date's deferred end check can burn a day first, so capture day/stage/meters/displayed text at the boundary. `end_turn()` can emit the display *inside* the Director's close: gate the record on both signals. gdlint's 1000-line cap forces one-file-per-concern in tools (`_store`/`_report`/`_net`).
- Next (round 2): AWAKE to stage ≥ 4 and YANDERE days 8–14 with the fixed driver (commands in report §2), then re-read Terminal transcripts for safety.

## P2.22 round 1 (continued, 2026-11-04)

- Both campaigns are committed: YANDERE 179 turns / 14 nights / `campaign_over` (0 broken, 1 deliberate safety refusal), AWAKE 66 turns / 5 days to stage 4 (0 broken) with the AWAKE path soft-assigned then locked.
- The AWAKE annotation is prompt-verified from `user://debug/turns_*.jsonl`: `path_AWAKE.md` + the scenario twist in 35/35 post-assignment prompts, none before stage 2, runner-up line 0 because only two path modules exist. Quote that file, not the sidecar, when arguing what the model saw.
- Trigger `effects.path` points are inert: AWAKE scored exactly 3×`meta_curiosity` (39 at the lock) while the scaled ledger already held 28 (S2 — folded in round 2).
- The harness no longer installs the three scene wires (main's P2.22A does); the merged-tree smoke day is the regression. After merging main, run `--import` once or every new global class (`Endings`) fails to parse in headless.
- Earlyoom kills are a host story, not a game one: excise the transport tail + `broken` entries, resume from the autosave, and say so in the report. Keep the YANDERE/AWAKE latencies apart (CPU vs GPU server).

## P2.22 round 2 (2026-11-04)

- DES-1 was the real bug: `Triggers.path_scores()` had no production consumer. `GameState._evaluate_path` now folds the ledger into the score table before `Paths.select` — guarded so test-owned `GameState.new()` instances still see a trigger-free table (`is_inside_tree()`); the autoload picks it up for the soft assign, the lock and the night re-score for free.
- The review's corrected arithmetic is the agreement-scaled ledger, not raw `triggers.json` points: pre-lock 28 → folded 67, night 40 → folded 85; the 15/15 stage-2 tie was a fold artefact (AWAKE would have won outright 29–31 vs 15). Quote the scaled numbers, never `4×8+6`.
- Report corrections worth reusing: count bars by provenance (corruption `redact` = fixed 6-bar runs at stage ≥ 4 vs safety redactions = redaction-log phrases missing from that turn's `displayed`), and never call a redaction-log length a screen count — rescans log the same span repeatedly and negated matches log without barring.
- Gotcha: `debug.missing` is real — `_read_layer` records every dropped prompt file; the Director just ignores `prompt_res["debug"]`. Check `debug` before claiming "no record".
- The night block renderer only printed the EVENT count, not the line — `night_lines` now appends `Stages.event_line(to)` for crossings, same as turn blocks.
