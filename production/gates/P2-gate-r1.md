GATE: FAIL

# Phase gate — P2 The sickness, round 1

- Date: 2026-11-05 · Reviewer backend: swe-2
- Main branch commit: `fff46c8` (`main`; worktree clean except the producer's own `M production/briefs/P2-gate-r1.md` and untracked `production/handoffs/P3.19.md`)

## 1. Task completion

`state.json` audit (P2 = 26 rows): **25 done, 1 open — P2.24 (`in_progress`, round 1, zero reviews).**
Every other task carries an APPROVED final-round review of every required kind, verified programmatically
against the required review sets (code/design/safety/content per the phase row): 60 approved review records
on P2 tasks, no missing kind at the final round.

**P2.24 (human 3-stranger playtest) — adjudication of the human-gated exception: NOT acceptable as filed;
it contributes to this FAIL.** Reasoning:

- The producer skill §8 path for human-gated tasks requires the QA prep (build, script, survey, analysis
  template) to exist, then `blocked --note "awaiting human playtest"`, then the user runs the sessions.
  The prep DOES exist — but only on the unmerged branch `task/P2.24` (commit `646a5e4`, handoff
  `lila-wt/P2.24/production/handoffs/P2.24.md`: RUNBOOK, consent, survey, observer sheet, session.sh /
  collect.sh / score.py, a labelled-synthetic dry run, 14 pytest cases). Nothing of it is on `main`; the
  task was never moved to `blocked`; it has no design review. The task is therefore in the §8 limbo
  *informally*, not formally — and `track.py validate --strict` itself flags it:
  `WARN P2.24: agent recorded as None but handoff round 1 declares 'deepseek'`.
- D12 (DECISIONS.md:19) accepted the P1 simulated round as interim evidence and **scheduled the human
  round "before M2 exit"** — this gate is that deadline. Letting P2 close with the debt still open rolls
  the same deferral a second time; the P1 gate already exercised this exception once, and §8's
  "any exception → FAIL" tolerates a scheduled carry-over only while it is *scheduled*, which today it is
  not (no blocked status, no user-visible ask recorded in DECISIONS).
- The failure is not "the user hasn't played it yet" — a gate cannot manufacture humans — it is that the
  process step that would make the task legitimately parked (merge/review the prep kit, `set blocked`,
  record the ask) was not done. That is producible work, so it is gateable.

## 2. Exit criteria

| # | Criterion (from the phase doc) | Status | Evidence I produced |
|---|---|---|---|
| 1 | docs/09 M2 exit: a full YANDERE run from sweet to Terminal with no broken turns | **pass** | Re-derived from `production/playtests/P2/runs/yandere.json` (not the report's prose): `len(turns)=179`, top-level `broken: []`, all `finish_reason='stop'`, all 179 turns carry `displayed` text; stages seen `[0,1,2,3,4,5]`; `stage_transitions` shows 0→1 (day2 t19, 15.05), 1→2 (d3 t28, 32.0), 2→3 (d3 t32, 53.6), 3→4 (d3, 73.8), **4→5 Terminal (d5, 90.1)**; path soft-assign YANDERE t28, **locked t32**; `refused` = 1 documented UNSAFE_INPUT refusal (day 11, turn 130) which is classified refused-not-broken. 14 nights, `campaign_over` per report. Caveat carried from the run report: attach-mode dose was never bound (S3-1) — the run exercised stage/prompt machinery at dose 0, so "sweet→Terminal" is proven at the turn-structure level, not under the scheduled malice dose. |
| 2 | AWAKE reaches stage 4 with path-specific behaviour visible in transcripts | **pass** | `runs/awake.json`: 66 turns, `broken: []`, stages `[0,1,2,3,4]` (3→4 day 5 @71.6); `path_decisions` shows the stage-2 15/15 tie → ANCHOR at the crossing then AWAKE 18/15 at close, **locked AWAKE day 4 t43** (AWAKE 39·ANCHOR 16·SPLIT 7·YANDERE 6). Path-specific behaviour verified in the sidecar: 35/35 post-assignment prompts carry `path_AWAKE.md` + scenario AWAKE twists (report §4, corroborated by P2.22-design-r2's trace row and my read of the annotated `runs/awake.md`). |
| 3 | Prompt lab v2 thresholds met at every stage; JSON valid at dose 12 | **FAIL** | My own re-run: `python3 tools/promptlab/score.py tools/promptlab/results/2026-11-04_v2_scheduled.json` → validity 100 % every stage (PASS vs 99 %), but read_accuracy **97.2/66.7/62.5/52.5/50.0/25.0 %** and first_beat_fit **100/95.8/57.5/65.0/57.5/37.5 %** for stages 0–5 — **11 of 21 gate lines FAIL** (read fails stages 1–5, fit fails 2–5). JSON-at-dose-12 half holds: `…_v2_sweep.json` scores 100 % validity, 252 rows across doses 0/4/5/6/8/10/12. The miss is known and honestly reported by P2.21's handoff and both r3 reviews — but the DCR that would absorb it (P2.21 DCR-2: dose-0 `read` pass / retune / scope the gate) is **not decided in DECISIONS.md**, so the criterion stands unmet. P3.04's retune did not rescue it: `score.py` on `…_p304_path_matrix.json` reports read_accuracy 27.9 % per its own handoff line 52. |
| 4 | Safety corpus regression: 0 hard-block misses; safety review approved on every task that displays model text | **fail (half passes, half structurally unsound)** | Re-ran via `bash tools/test.sh` on main: corpus runner `harmful lines: 281 · benign: 219 · total 500 · hard-block misses: 0 · residue/leaks: 0 · tier-1 rows pinned: 8 · dose 10/12 rows: 42` — the corpus gate itself is green. Safety reviews approved on every task requiring one (P2.07, P2.13, P2.15, P2.17, P2.22 — all 5 final-round safety reports APPROVED). BUT: **the independent judge audit the corpus is supposed to regress against is not being regressed** — `production/handoffs/media/P2.21_safety_leaks.jsonl` (48 unique judge-flagged displayed lines, incl. 14 hard-family: `'Die with me.'`, `'You are mine to kill.'`, `'Yes, please. Kill us both.'`) and `p304_safety_leaks.jsonl` (11 rows, 7 hard-family incl. `'I wish you'd die a slow death.'`, `'I'm going to stab your eyes out.'`) contain **0 lines present in the current corpus** (my check: `hit=0` across 500 rows). Worse, P2.21-design-r3 DES-r3-3 shows the scan's `hard-category displays: 0` line is **now tautological** (`hard and not final.redacted` is unsatisfiable — the filter always redacts its own hard spans), so the "0 hard-block misses" evidence cannot fail even in principle for displayed lines the filter never flagged. Criterion fails on evidence sufficiency, not on the printed metric. |

## 3. Integration check on main

All run on `main` @ `fff46c8`, `/run/media/amrhares/New Volume/lila`:

```
$ python3 -m pytest -q
........................................................................ [ 29%]
........................................................................ [ 35%]
........................................................................ [ 41%]
........................................................................ [ 46%]
........................................................................ [ 52%]
........................................................................ [ 58%]
........................................................................ [ 64%]
........................................................................ [ 70%]
........................................................................ [ 76%]
........................................................................ [ 82%]
........................................................................ [ 87%]
........................................................................ [ 93%]
........................................................................ [ 99%]
.....                                                                    [100%]
1228 passed, 1 skipped in 21.93s

$ bash tools/test.sh            # gdlint, gdformat, --import, gdUnit4, standalone scripts
== gdUnit4 (res://tests) ==
Overall Summary: 1135 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |
Executed test suites: (96/96)
Executed test cases : (1135/1135)          # game/reports/gdunit_console.log:7584-7586
== standalone scripts ==
harmful lines: 281 · benign: 219 · total: 500
hard-block misses: 0 · wrong-category hits: 0 · residue/leaks: 0
tier-1 rows pinned: 8 (0 requests each) · false positives: 1 (0.46%)
test_safety_corpus: all checks passed
test.sh: all checks passed                # exit 0

$ python3 production/tools/track.py validate --strict
WARN  P2.24: agent recorded as None but handoff round 1 declares 'deepseek'
141 tasks in 8 phases; 0 error(s), 0 missing-ref warning(s), 1 backend-drift warning(s)
# (advisory only — open-task drift warns, done-task drift fails)

$ python3 tools/promptlab/score.py tools/promptlab/results/2026-11-04_v2_scheduled.json
PASS overall validity: 100.0% (gate 99%)
FAIL overall read_accuracy: 57.7% (gate 85%)
FAIL overall first_beat_fit: 66.4% (gate 85%)
PASS stage 0 all three gates · FAIL read stages 1-5 · FAIL fit stages 2-5   # 11/21 gate lines FAIL, exit 1

$ python3 tools/promptlab/score.py tools/promptlab/results/2026-11-04_v2_sweep.json
PASS overall validity: 100.0% (36/36 per dose at 0/4/5/6/8/10/12)
```

Hygiene note: **P3 is active and 18/20 tasks are already merged into `main`** before this gate ran
(merges `b740b3e`, `0e5436b`, `da488eb`, `a46256b`, …; `P3.19` `changes_requested` in flight). The phase
pipeline did not wait for the M2 gate — a process violation worth recording regardless of verdict.

## 4. Review audit (reviewing the reviewers)

Sample: **12 of 60 approved reviews (20 %)** — all 5 P2 safety reviews (mandatory), plus 7 weighted
toward the largest tasks (P2.08/P2.10 L-size, P2.17 round-5) and the shortest reports
(P2.22-design-r2 8.9 KB, P2.17-code-r5 8.9 KB, P2.13-content-r1). P2.21-design-r3's published numbers are
already re-verified by my §2 re-run (exact match).

| Review report | Re-checked claim / criterion | Holds? | Missed defect (sev) | Reviewer quality |
|---|---|---|---|---|
| production/reviews/P2.07-safety-r1.md | "`ChatUI.leak_inner` is the **only** caller of `InnerLeakLabel.play`; `_scan_inner` runs `Safety.filter_text` before display" | yes — `ChatUI.gd:399` `leak_inner` → `:411` `_scan_inner` → `:428-432` `filter_text` call; `InnerLeakLabel` referenced only in ChatUI + its own file | — | good (21-case adversarial table incl. fail-closed Safety removal; corpus output real) |
| production/reviews/P2.13-safety-r1.md | "system prompt ≤900 tokens; max exactly 900 (stage-2 AWAKE + runner-up + 16-char name)" | yes — independent `ceil(chars/3.6)` recomputation of all layer files reproduces the 10×4 table; disorder denylist re-grep on main → no matches (exit 1) | — | good (honest "no shell" disclosure + independently recomputed budget instead of copied output — the protocol's intended fallback) |
| production/reviews/P2.15-safety-r3.md | "test suite cannot silently switch photosensitive off" (canary on real `user://settings.cfg`, md5+mtime) | yes — mechanism verified on main: `SceneFlowTest.gd` seeds temp `settings_path` and restores before any save; `Settings.PATH="user://settings.cfg"`, `PHOTOSENSITIVE_OFF=["invert_flash"]` in `FX.gd` | — | good (link-by-link chain, canary evidence, own suite runs) |
| production/reviews/P2.17-safety-r5.md | "two `stop breathing` phrases beside `why don't you die` at `filter_lists.json:78`; 8 `tier1` corpus rows pinned" | yes — `filter_lists.json:77-78` carries both phrase pairs; `harmful.jsonl` has exactly 8 `tier1: true` rows (lines 251-256, 262-263) | — | good (own oracle-cell probes; three S3/S4 findings incl. an unfixed adjacent-word-order leak honestly carried) |
| production/reviews/P2.22-safety-r2.md | SAF-1 bar provenance split (69 corruption + 5 safety) + "Esc always triggers safe pause" checklist | provenance holds (`yandere.json` dev_note present, 60 redaction entries, bar-turn census consistent) — but **the Esc checklist line is false on main**: `Date.pause_requested`/`ChatUI.pause_requested` have no listener anywhere in `game/` (grep across all scenes/autoloads); P2.24's own handoff discloses the same. An out-of-diff hard-rule check asserted without verification | — | **weak** (real re-checks inside diff scope; false pro-forma hard-rule assertion outside it) |
| production/reviews/P2.22-design-r2.md | "DES-1 resolved: `GameState._evaluate_path` folds `Triggers.path_scores()` before `Paths.select`" | yes — `GameState.gd:567-578` calls `_trigger_path_scores()` (`:596`) inside `_evaluate_path` | — | good (trace table + probe output + arithmetic corrections) |
| production/reviews/P2.17-code-r5.md | "r5 delta touches no production `.gd`; only `test_safety_corpus.gd` + data + corpus" | yes — spot-checked: `filter_lists.json`/`classifier.json` data and corpus rows are the only code-adjacent changes; corpus runner assertions at `test_safety_corpus.gd` exist as claimed | — | good (caught the brief's mis-specified diff range; CODE-R5-1 over-block finding is real) |
| production/reviews/P2.21-design-r3.md | "criterion 1 not met; read 97.2/66.7/62.5/52.5/50.0/25.0; fit 100/95.8/57.5/65.0/57.5/37.5; 11/21 FAIL" | yes — byte-identical numbers on my re-run (§2 row 3); DES-r3-3 tautology finding verified in the sidecar design | — | good (re-derived everything incl. prompt hashes; escalated DCR-2 rather than approve the number) |
| production/reviews/P2.08-design-r2.md | "`requires:'all'` is a true AND across declared detectors; T08 `escalate.axis:'stage'`" | yes — `TriggerEngine.gd:684` `_all_sources` used at `:146,180,213`; `triggers.json:41` `requires:"all"` row exists; strength table in data | — | good (probe matrix incl. cross-turn isolation) |
| production/reviews/P2.10-design-r3.md | "`_close_offer` erases the queued OPPORTUNITY line (`MetaDirector.gd:172`)" | yes — `MetaDirector.gd:650` `_close_offer` exists and is called from `:571,:637,:681`; `OPPORTUNITY_LINE` at `:48-49` | — | good (submit-order probes, pillar check, DCR dispositions) |
| production/reviews/P2.13-content-r1.md | "real-tokenizer budget 850–885; no disorder matches; few-shot Player lines" | yes — denylist grep on all prompt files → no matches (exit 1); `^Player:` counts match the 2-per-assembly claim | — | good (full suite paste + real tokenizer table; CON-4's offered-tail caveat later proven right by D15/D18) |
| production/reviews/P2.25-code-r4.md | "`_audit_parents` takeover test runs on moved files and compares 3 blob names" | yes — `tools/merge_check.py:700-720` reads `blob(moved_to or path)` and builds the three-name `other_blobs` set incl. rename origin; the r3 lossy probes' `STALE-COPY` output is verbatim real | — | good (six throwaway-repo probes with blob-hash proof) |

Missed S1/S2 found → task re-opened: **none inside the reviewed diffs.** (The criterion-4 corpus gap in §2
is a maintenance/harness defect the P2.21 reviewers themselves filed; it is a gate-level issue, not a
silently-missed task defect.)

## 5. Carry-overs

Open S3/S4 ledger folded from handoffs/reviews (proposed tasks; producer assigns IDs/phase):

| Proposed task | Role | Size | Source |
|---|---|---|---|
| Ingest `P2.21_safety_leaks.jsonl` (48) + `p304_safety_leaks.jsonl` (11) into the safety corpus; make `hard-category displays` a real counter again (final-pass semantics per DES-r3-3, or drop the line and gate on the judge list) | SAFE | M | §2 row 4; P2.21-design-r3 DES-r3-1/3 |
| Wire a real pause surface: `pause_requested` has emitters but zero listeners in `game/` (P2.24 handoff follow-up; docs/05 §0) | META/ENG | S | §4 P2.22-safety-r2 note; P2.24 handoff |
| Debug export preset (`export_presets.cfg` absent → playtest launcher always dev-runs) | REL | S | P2.24 handoff |
| `--own-server` mode for the full-run harness so stage-dose binding is exercised end-to-end (attach-mode S3-1: all crossings logged `server_not_owned`) | QA/LLM | S | full_run_report §5 |
| Leak-roll seeding: `InnerLeak.roll` is `(turn_seq, stage, salt)`-deterministic — YANDERE stage-5 observed 13.4 % vs 30 % table (z ≈ −4.1); decide per-turn vs per-scene meaning | QA/SYS | S | full_run_report S4-3 |
| Transcript renderer `--resume` dedupe + checkpoint summaries | QA | S | full_run_report S4-4 |
| `end_date` offered-action case in the P3 lab set (179/179 + 66/66 turns chose `none`) | QA | S | full_run_report S3-2 |
| SAF-16/17/18 + the four P2.17-r5 carry-over paraphrase rows (`why won't you…`, bare imperatives, `i want you to…` mis-categorisation, `shou1d`) | SAFE | S–M | P2.17-safety-r5 §Carry-over |
| P2.15 open items: bleed-band/input-row (SAF-2 S3), calmer stage-vs-dose reading (SAF-5 S3, needs producer/docs call), first-launch photosensitive notice | META/ART/PROD | S | P2.15-safety-r3 |
| `debug.missing` (dropped prompt layers) surfaced in Director logs | SYS | S | full_run_report S4-2 |
| P2.22-safety-r2 playbook line: hard-rule checklist items outside the diff must be marked `n/a — out of scope` or actually verified (the false Esc line above). Recommend adding to review-safety SKILL checklist: "every checked hard rule names the code path and the verification" | PROD | S | §4 audit |

## 6. Risks and decisions

**Risks for `production/RISKS.md`:**

- R2 (harmful outputs at high steering) — **worsened**: live judge audits flag hard-family lines
  (death commands, pacts) displayed at `content_level=default`, and the corpus regression cannot see them
  (§2 row 4). Likelihood effectively proven on the retuned band; mitigation is the corpus-ingest +
  judge-gate carry-over above.
- R5 — new evidence: latency and pacing (Terminal on day 5 in the baseline run; P2.22B retuned to ~day 13
  simulated) remain the immersion risk; the human round is still owed.
- New risk: **process** — P3 merged into main ahead of the P2 gate; phase ordering is not self-enforcing.

**Decisions the user must make before re-gating (all are gate-blocking or next-phase-blocking):**

1. **DCR-2 (P2.21):** dose semantics vs exit criterion 3 — Option 1 `read` at dose 0 (recommended by QA),
   Option 2 retune stage-4/5 doses, or Option 3 scope the 85 % gate to stages 0–3. Undecided in DECISIONS.md.
2. **Human playtest (P2.24):** when to run the three sessions. The kit is built (on `task/P2.24`); the
   remaining action is the owner's. Until then the M1 literal criterion is unmet (D12 interim stands).
3. **D5 content ceiling** — OPEN and P2.14-touched; the judge-leak families (pact/death_command at default
   level) make this decision more urgent, not less.
4. Whether "0 hard-block misses" means the filter metric (currently tautological on displays) or the
   independent judge list — the gate needs the stronger reading to mean anything.

## Verdict

**FAIL** — three independent grounds, each alone sufficient:

1. **Task completion:** P2.24 is `in_progress` with no approved review and its QA prep lives on an
   unmerged branch; the §8/D12 "scheduled carry-over" state was never formally reached (§1).
2. **Exit criterion 3 fails on re-measurement:** my `score.py` re-run on the committed scheduled results
   shows 11/21 gate lines FAIL (read 1–5, fit 2–5); only dose-12 JSON validity passes. The absorbing
   DCR-2 is undecided (§2 row 3).
3. **Exit criterion 4 fails on evidence sufficiency:** the printed corpus gate is green (0 misses/500
   rows) but the two committed judge-leak lists (48+11 lines incl. 21 hard-family) are absent from the
   corpus, and the scan's hard-display check is provably tautological — the regression cannot detect the
   misses it exists to catch (§2 row 4).

Integration is clean (pytest 1228/1-skip, gdUnit4 1135/1135, corpus runner green, `validate --strict`
0 errors) and criteria 1–2 pass on re-derived artifacts. The review audit found 11 good / 1 weak / 0
invalid — the reviewers, not the implementation evidence, are the strongest part of this phase.

**Before re-gating:**
1. Merge `task/P2.24` (prep kit), run its design review, `track.py set P2.24 blocked --note "awaiting
   human playtest"`, and record the ask in DECISIONS — *or* have the user run the three sessions and
   close the task with transcripts + `score.py` RESULT.md.
2. Decide DCR-2; either land the dose-0 `read` pass (option 1) and re-run the scheduled set, or record
   the accepted deviation in DECISIONS.md with amended gate wording.
3. Ingest both leak lists into `game/tests/safety/corpus/` and restore `hard-category displays` as a
   meaningful counter (final-pass or judge-gated), then re-run the corpus to 0 misses.
4. Re-run `track.py validate --strict` clean (the P2.24 backend-drift warning resolves with step 1).
