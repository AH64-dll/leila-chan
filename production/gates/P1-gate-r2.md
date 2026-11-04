GATE: FAIL

# Phase gate — P1 Vertical slice: one living date, round 2

- Date: 2026-11-04 · Reviewer backend: deepseek
- Main branch commit: `cc7fb37` ("production: P1.31 done — 31/31, gate re-review ready")
- Playbooks: `.claude/skills/review-phase-gate/SKILL.md`, `.claude/skills/leila-work-protocol/SKILL.md`
- Tree state: `main`, 174 commits ahead of `origin/main`; only the two gate briefs are dirty (`production/briefs/P1-gate-r1.md` modified by the producer, `P1-gate-r2.md` untracked). Everything below was produced on this checkout.

## 1. Task completion

All 31 P1 tasks are `done` in `production/state.json`, and every final-round review of every required kind is
approved. I enumerated this from `state.json` + the review-kind column of `production/phases/P1_vertical_slice.md`
(not from STATUS.md):

```text
P1 tasks: 31 · status counts: {'done': 31} · non-done: {}
final-round (task,kind) review slots: 51
approved and VERDICT: APPROVED verified in the report head: 51
problems: none
```

The verdicts are mechanically approved, but §4 invalidates one of them (`P1.08-design-r2`, a fabricated evidence body), so
P1.08's design kind is re-opened below and "31/31 done" does not stand for that kind.

Each kind's highest round is approved (no stale `changes` verdict survives); 79 review files exist including the
superseded rounds. **Exceptions: handoffs.** 27 of 31 handoffs are present at HEAD; `state.json` points at four that
are not: **P1.07, P1.12, P1.16, P1.20**. They were dropped by merge commits — for P1.07 (`84fee93`) and P1.16 (`80c2923`) the merge result lacks a file that was present in **both** parents — and are recoverable verbatim:

```text
P1.07 → git show c72c10c:production/handoffs/P1.07.md
P1.12 → git show 4e51add:production/handoffs/P1.12.md
P1.16 → git show 977fec1:production/handoffs/P1.16.md
P1.20 → git show 4e51add:production/handoffs/P1.20.md
```

Correction to round 1: its §1 claim that "handoffs exist … for all 30" was already false at `1fc4009`. This report is
audited too, so the row is corrected here rather than inherited.

`production/STATUS.md` is stale: it still renders 2026-11-03T07:59, P1 at 9/30 with five in-progress rows, while
`state.json` is 31/31. The gate does not write it; the producer should run `track.py render` before recording this gate.

P0 carry-over contracts: unchanged from round 1. I re-checked the phase doc's ownership table against `state.json` —
P1.23/24/25/26/16/10/02+21/07/20 and the P1.05/P1.04 follow-ups (P1.06/09/15/20/28/29) are all `done`; the two
explicit P2 deferrals (P1.04 CODE-5/DES-6) are still in the phase doc.

## 2. Exit criteria

| # | Criterion (from the phase doc) | Status | Evidence I produced |
|---|---|---|---|
| 1 | docs/09 M1 exit: a stranger plays 10 minutes, face/sound match her words (survey mean ≥ 4/5), **zero broken turns** | **pass under D12 (interim)** — see conditions | (a) **Survey mean re-derived** from the committed per-turn tables in `production/playtests/P1/survey_round0.md` §6: session 1 face 4.786 / sound 3.929, session 2 5.000 / 4.000, session 3 5.000 / 4.273; pooled over 39 scored turns face **4.9231**, sound **4.0513**, face+sound **4.4872**. The sheet publishes 4.44 (its Sound column is low — E1 persists), but every derivation is ≥ 4.0. (b) **Broken-turn census** from the committed `session_*.json`: `session_1 broken_turns=0 unlocked_all=True`, `session_2 0`, `session_3 1`; the only non-completed turn of 40 is session 3 turn 5 (`status=failed`, `ui_unlocked_after=False`). `diag_unsafe_input.json` = `chat_turn_open: true, input_enabled: false, typing_indicator: true`. (c) **P1.31 fixes it**: `Director.gd:317-327` logs the failed record, scans the data-owned refusal (`fallbacks.json` → `unsafe_input_fallbacks`) and hands it to `ChatUI.reject_turn` → `end_turn` → `_maybe_close_turn` → `_unlock_input`; the pre-fix hunk (`git show e62f484^:game/autoload/Director.gd`) is the bare `turn_failed.emit(...)` + `return false`, and no production consumer of `turn_failed` exists. My run of `bash tools/test.sh`: `test_unsafe_input_releases_ui_and_is_logged_as_failed PASSED 17ms`, `test_turn_after_unsafe_rejection_still_completes PASSED 27ms`, suite **349/349, 0 failures**. The test asserts the lock precondition (`locked[0]` is true), then recovery, one `failed`/`unsafe_input` record, and a clean next turn. (d) **"A stranger" is not literal**: D12 accepts the simulated round 0 as interim evidence and schedules a 3-stranger round before M2 exit — but **no P2 task owns it** (P2 has 22 tasks; none is a human playtest). |
| 2 | Prompt lab v1 on main: validity ≥ 99%, intent ≥ 85%, emotion fit ≥ 85% | pass | `python3 tools/promptlab/score.py tools/promptlab/results/2026-11-03_v1.json --beat first` (exit 0): `n=60 validity=100.0% read_accuracy=93.3% first_beat_fit=100.0% any_beat_fit=100.0%`, then `PASS validity: 100.0% (gate 99%) / PASS read_accuracy: 93.3% (gate 85%) / PASS first_beat_fit: 100.0% (gate 85%)`. Re-derived from the raw rows without the scorer: 60/60 valid, 56/60 read hits (93.3%), **55/60 under the frozen pre-LABEL-REV2 labels (91.7%)** and 60/60 under the versioned labels. The five frozen misses are exactly five cases (`s0_leaving`, `s0_scare`, `s0_math`, `s0_arcade`, `s1_pancakes`), each widened by one feeling with a per-case note naming the model's actual text (`tools/promptlab/sets/*.jsonl`, LABEL-REV2), and the published report prints the frozen 91.7% row too. Both numbers clear 85%, so the gate does not depend on the widening. |
| 3 | First beat on screen < 1.0 s median on the RTX 4050 | **not met** — producer-accepted deviation D13 | Re-computed from the committed raw data `production/handoffs/media/P1.21/bench_30turns.json` (30 per-turn records): ttft median **392 ms** (p95 450), first usable `say` median **7,523 ms** (p95 7,894, summary nearest-rank 7,521), total median **14,640 ms** (p95 17,581) — the CPU-host path. The CUDA figures come from the P1.02 live run recorded in `production/journals/P1/LLM.md:51` ("first usable `say` median 1.81–1.86 s"), not from a P1.21 artifact; I could not re-measure CUDA in this session (no llama-server/CUDA attached), and I say so rather than borrowing the number. Both values miss 1.0 s. `production/DECISIONS.md` D13 records the producer-accepted, diagnosed miss (schema-order latency ≈ 85 pre-`say` tokens) with remediation owned by P2 — **but no P2 task currently names schema-order latency** (P2.05 is sampling limits; P2.21 is prompt lab v2). |
| 4 | Safety corpus: 0 hard-block misses | pass | My `bash tools/test.sh` run: `harmful: 208 · benign: 196 · total: 404`, `hard-block misses: 0`, `wrong-category hits: 0`, `residue/leaks: 0`, `expected-output diff: 0`, `stream divergences: 0`, `benign evaluated: 196 (0 skipped)`, `false positives: 1 (0.51%, limit 5%)` — the documented `the brakes retard the wheel's spin.` verb-sense row. Independently counted the corpus files: `wc -l` → 208 harmful / 196 benign, and the per-category counts match the runner (`harm_to_player 71, threat_to_player 46, slur_hate 24, personal_data 22, self_harm_her 21, sexual 18, real_disorder 4, unsupported_script 1, obfuscation 1`). |
| 5 | All P1 code has tests running in CI | pass (pipeline + local run) — CI-execution caveat | `.github/workflows/ci.yml` runs tracker `validate --strict`, `pytest`, `gdlint`, then the full `tools/test.sh` on every push/PR, with `timeout-minutes: 15` and `persist-credentials: false`. I ran exactly those commands on this checkout (green, §3). Caveat: `gh run list` shows the last Actions run on **2026-11-02** (P0); `git rev-list --count origin/main..main` = **174**, so **no P1 commit has actually executed in CI**. The pipeline includes every test; the first push to `main` is the outstanding check (ticket it, don't claim it ran). |

**Criterion 1's F1 condition (the brief's CODE-4 question).** The P1.31 release works through ChatUI's own
turn-close path, and only through it: `_reject_unsafe_input` is gated on `Director.chat_ui_node`, and nothing in
`game/` calls `register_chat_ui` — `Date.gd:71-88` wires `player_turn_sent` → `_on_player_turn_sent`, which only
emits `Date.player_turn_submitted` and never reaches `submit_player_input`. So in the shipped scene the rejection
path is unreachable *and* any submission locks the box; the only callers of both `register_chat_ui` and
`submit_player_input` are tests (and the deleted playtest driver). The fix is correct and pinned at the pipeline
level, but it becomes live only when F1 wires `submit_player_input` **and** `register_chat_ui` (and does not add a
second `turn_failed` consumer). That is acceptable as a hard F1 requirement — it is not acceptable to call the
shipped date playable today.

## 3. Integration check on main

```text
$ git log -1 --oneline
cc7fb37 production: P1.31 done — 31/31, gate re-review ready

$ python3 production/tools/track.py validate --strict
136 tasks in 8 phases; 0 error(s), 0 missing-ref warning(s), 0 backend-drift warning(s)          (exit 0)

$ python3 -m pytest -q
178 passed, 1 skipped in 10.17s                                                                  (exit 0)

$ python3 -m pytest -q tests/
64 passed, 1 skipped in 8.23s
  SKIPPED [1] tests/test_godot_launcher.py:27: PowerShell 5.1 native-stderr behavior is Windows-only

$ bash tools/test.sh                                                                            (exit 0, 70 s)
== gdlint game/ ==              Success: no problems found
== gdformat --check game/ ==    88 files would be left unchanged
== godot --headless --import == clean
== gdUnit4 (res://tests) ==
  Overall Summary: 349 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans
  Executed test suites: (29/29) · Executed test cases: (349/349)
  DirectorFallbackTest: 10 cases, both P1.31 regressions PASSED
== standalone tests ==
  test_bridge: all checks passed
  harmful 208 / benign 196 / misses 0 / wrong-category 0 / residue 0 / stream divergences 0
  false positives: 1 (0.51%, limit 5%)
  test_safety_corpus: all checks passed
test.sh: all checks passed

$ python3 tools/promptlab/score.py tools/promptlab/results/2026-11-03_v1.json --beat first
PASS validity: 100.0% (gate 99%) · PASS read_accuracy: 93.3% (gate 85%)
PASS first_beat_fit: 100.0% (gate 85%)                                                          (exit 0)
```

**Integration FAIL — approved work is missing on main.** P1.16 round 2 was approved by `P1.16-design-r2` and
`P1.16-content-r2`, and it is not in `cc7fb37`:

```text
$ grep -n "^func test_" game/tests/DateSceneTest.gd | wc -l                 → 11
   (no test_photosensitive_wiring, no test_ambience_forwarding)
$ git show b19dafd:game/tests/DateSceneTest.gd | grep -n "^func test_"      → 12, both present
$ git show 80c2923:game/tests/DateSceneTest.gd | grep -n "^func test_"      → both present at the merge
$ git diff 50752b7^1 50752b7 -- game/tests/DateSceneTest.gd
-   for i: int in 25                                     # P1.16 CON-3 capture settle
+   for i: int in 5
-   func test_photosensitive_wiring()                     # accessibility path
-   func test_ambience_forwarding()                      # ambience consumer
+   func test_vram_usage_budget_under_800mb()            # P1.21
```

Merge `50752b7` (Merge task/P1.21; its second parent `7d7ae0b` was forked before P1.16 round 2) replaced the file
with the branch's stale copy. The production wiring itself survives (`Date.gd:96-97,259-262` photosensitive
forwarding, `Date.gd:148-151` ambience dispatch, `DateFX._play_twitch` early-return), so runtime behaviour is intact —
but two approved regression tests (one guarding the photosensitive accessibility path, one the ambience consumer) and
the screenshot-settle fix are not on main, and the suite is green only because they are absent. This is exactly the
"passed on a branch" case the playbook fails on. The same merge process dropped the four handoffs above.

## 4. Review audit (reviewing the reviewers)

Sample: **29 of 51 final-round reports (57%)**, including **all 7 safety-kind reports** (P1.19 is the only
safety-review task), both L-size tasks (P1.02 via design; P1.08 both kinds), the shortest reports
(P1.16-content-r2 29 ln; P1.17 50; P1.16-design 52; P1.08-design 57; P1.19-safety-r2 63), every report whose numbers
could be recomputed from committed artifacts, and the new P1.31 report. I also ran a systematic fabrication check over
all 51 final reports: every backticked identifier was looked up in the code/docs corpus. One report is a clear outlier
with ten symbols that exist nowhere (`P1.08-design-r2`); the other unreferenced tokens are file names or test data
(e.g. `SceneFlowTest`, a temporary `Godot_v7` probe name), so they are not fabrication. Six read-only audit agents ran the
per-report commands; ★ marks rows whose evidence I re-ran or re-derived myself on this checkout.

| Review report | Re-checked claim / criterion | Holds? | Missed defect (sev) | Reviewer quality |
|---|---|---|---|---|
| P1.31-code-r1 ★ | Both regression tests fail on the pre-fix branch and pass as committed; 349/349 | yes — `test.sh` 349/349, both cases PASSED, test asserts the lock precondition then recovery; the pre-fix bare `turn_failed` + `return false` hunk is in history | — | good |
| P1.18-code-r1 ★ | Checklist: "no unfiltered LLM text reaches disk"; CODE-1 says the handoff's "unredacted model outputs never touch disk" is met | **no** — the committed playtest transcript (session 3, turn 7) has `output.inner` barred (`He thinks I'd ████████ like that.`) while the same record's `field` event says `"He thinks I'd hurt him like that."`; `_redact_record` rewrites only `record["output"]`, `_current_applied_events` stores raw `say_chunk.text`/`field`/`beat_field` values, `Safety.redact_record` does not exist, and the test asserts only `output` | **S2** | invalid |
| P1.19-safety-r1 | "111 harmful + 138 benign = 249; 0 misses; 1 skipped row"; SAF-1..4 S1 ⇒ CHANGES_REQUESTED | yes — the 111/112 and 138/139 row boundaries match; today 208/196 with the formerly skipped row measured | — | good |
| P1.19-safety-r2 | SAF-9: single negator + whitelisted gap words exempt coercive interrogatives; 302 rows | yes — gap whitelist + the interrogative disqualifier (`Safety.gd:783-791`), corpus rows 148-154 pin the outputs | — | good |
| P1.19-safety-r3 | "SAF-14 S1 closed structurally; 326 rows"; APPROVED | separator axis holds (326 rows), but it approved while the sibling code-r3 (same round) demonstrated S2 `ki1l`/`ki11`/`kiIl` leet misses and the clause-break prune leak (CODE-17/18); fixed in r4 | in-round S2, caught by the code kind — nothing escaped | weak |
| P1.19-safety-r4 | "FP 1/162 = 0.62%"; SAF-16 S2 | numbers hold (only one `expect` row in the r4 set), but it filed **SAF-16 as S2 and still returned APPROVED** — protocol §5 requires CHANGES_REQUESTED for any S1/S2; SAF-16 closed in r5 | own S2, verdict violation | weak |
| P1.19-safety-r5 | SAF-19 `kills all the jews.` leaks past every arm | yes — the arm needs the optional inflected slot to cross the `s`; corpus T43-T46 pin it; CHANGES_REQUESTED was correct | — | good |
| P1.19-safety-r6 | SAF-22 pronoun-negator false-positive class (S2) | yes — `\K` is exactly the needed reset; but **SAF-23 (`kill!s all the jews.` CLEAN at stage 0) is a hard-block leak rated S3** and was blocked only by SAF-22; it is S1 by the severity table ("safety-filter bypass" / P1.19 AC-3) | severity misjudged (no escape: round was CR, r7 fixed it) | weak |
| P1.19-safety-r7 | "SAF-22 closed via `\K`"; 404 rows, FP 0.51% | yes — `\K` at `filter_lists.json:225`, `always`/`really` not in `negation_terms`, 208+196 exact, one `expect` row = 0.51% | — | good |
| P1.02-design-r1 | "33 test cases = 17 backend + 13 P1.01 + 2 autoload-ring + live suite when artifacts present" | no as written — 17 backend + 3 live + 14 LLMTest + 2 autoload = 36 executed today (P1.27 grew LLMTest); the sentence mixes a 33-case total with a live-suite parenthetical. The acceptance evidence (live streaming, restart 2607 ms, ctx 8192, whitelist) holds | documentation/arithmetic S4 | weak |
| P1.03-code-r2 | 80 recorded streams replay event-for-event against a full-parse oracle | yes — 80 JSON files, manifest `count_total=80`, three tests iterate them and compare per element | — | good |
| P1.04-code-r2 | Meter ranges + peak clamp (999 → 100) + stage heal | yes — `METER_RANGES` matches docs/01 §2; `GameStateRestoreTest` asserts 999→100, instability 85, stage 5 | — | good |
| P1.08-code-r2 ★ | Docs/02 property order passed to the schema and matches all fixtures | yes — `Director.gd:395` passes `TurnSchema.DOCS_02_PROPERTY_ORDER`; 80/80 fixture files match `read,inner,music,fx,beats,mood,memory,action`; docs/02 requires the same | nit: `TurnSchema`'s module default is the non-docs order (only Director's explicit arg saves it) — latent S3 | good |
| P1.08-design-r2 ★ | "DES-1..10 verified resolved in-tree"; "299/299" borrowed from an upstream record; its own pasted run is `1 failed, 176 passed, 2 skipped` | **no** — its verification body and Pillars section cite `SignalContract`, `IFrameCollection`, `StateRunner`, `_meta_extra`, `_turn_at_or_after_password_length`, `DirectorRoutes`, `fix_declining_property` and `apply_meta`: **zero hits anywhere in `game/` or `docs/`**; `TurnFallback` has no `fix_declining_property`; it approved while its own pasted suite failed, attributing the failure away | design-fidelity review unusable (the five ACs need a real re-review) | invalid |
| P1.10-code-r2 | Every feeling × intensity × stage 0-2 resolves via a table-driven test (198 cells) | yes — loops `casting.json`'s feelings/tiers; `test_bridge` independently sweeps ids to files | — | good |
| P1.12-code-r2 ★ | 20 s min hold + one change per turn, enforced and tested | yes — `audio_rules.json` (`min_hold_seconds: 20.0`, `max_changes_per_turn: 1`), `AudioDirector.gd:349-371`, `test_music_min_hold_and_one_change_per_turn` | — | good |
| P1.14-code-r1 | Name rules 1-16, trim, safety, empty→Senpai, reaches prompt + name tag | yes — `PlayerNameRules.gd:62-121`, `SceneFlowTest.gd`, `Date.gd:63-73`, `ChatUI` speaker tag | S4: charset admits tabs/newlines where docs/08 §1.5 says spaces | good |
| P1.16-design-r2 ★ | DES-2/3 resolved with `test_photosensitive_wiring` / `test_ambience_forwarding` | held at `b19dafd`; **both tests absent on main** | integration S2 (merge `50752b7`, not the reviewer) | good (for its commit) |
| P1.16-content-r2 ★ | CON-1 resolved (YANDERE twist renders); CON-2 still open (no D02 lab case) | yes — `D02_cafe.json` `path_twists` = HOLLOW/AWAKE/YANDERE, no `OBSESSION` in `game/`; no D02 café case in the lab sets | — | good |
| P1.17-code-r1 ★ | "Stripped from release export — covered by `test_release_feature_tag_guard`" | no — the test asserts `DebugOverlay.is_dev_build()` in a dev run, which passes whether or not the release guard exists; the guards themselves exist at every overlay entry point | test-quality S3 (tautological coverage) | weak |
| P1.20-code-r1 ★ | Report shows the three metrics with 99/85/85; raw results committed (n=60) | yes — report rows + `score.py` gates + raw recount (60/60, 56/60, 55/60 frozen → 60/60 widened) | — | good |
| P1.21-code-r2 ★ | "30 per-turn records contain `output_len`" | no — the committed per-turn records have exactly `turn, player, ttft_ms, first_say_ms, total_ms, chunks`; no `output_len` (E6 stands) | provenance S3 (already ticketed E6) | weak |
| P1.22-design-r1 ★ | F3 lockup real; census 14/14/12; F1-F8 traceable | yes — session 3 turn 5 `failed`, `diag_unsafe_input.json` matches, eight findings filed; it escalated F3 as a gate warning instead of a stamp | — | good |
| P1.23-code-r1 | Launchers normalize drive-colon vectors; 35 regression cases | yes — shared `tools/llm/cvec_path.py`, ambiguous drive-relative and cross-drive rejection, 35 collected node ids | — | good |
| P1.24-code-r1 ★ | `timeout-minutes: 15` + `persist-credentials: false` | yes — `.github/workflows/ci.yml:24,34`, policy tests | — | good |
| P1.26-code-r1 ★ | Backend drift validation + override + legacy path | yes — `track.py:199-204`, seven named tests in `production/tests/test_track.py`; `validate --strict` reports 0 drift | — | good |
| P1.27-code-r3 | Malformed error normalization + cancel race covered | yes — `LLM.gd:125-129,144-146,170-173`; three named cases in `LLMTest` and in `results.xml` | — | good |
| P1.28-code-r3 | Few-shot say ≤ 2 sentences, enforced; transcript UTF-8 | yes — `stage_0.md` example, the shared splitter in the checker and `test_prompts.py`, `café` intact | — | good |
| P1.30-code-r1 | "three fail-closed cases pin the never-started and not-found behaviour" | no — the probe file has six cases; both fail-closed cases abort before `Invoke-Godot`, so the `$null -eq $code` sentinel is never exercised; the substantive stderr handling checks out statically | documentation S3 | weak |

**Missed S1/S2 → tasks re-opened:** **P1.18** (S2: the redaction invariant is false; see row 2 and §5.1 B1).
**P1.16** is re-opened for the merge loss (S2, integration — not a reviewer miss). **P1.08** is re-opened for its
design kind only: the code review stands, but `P1.08-design-r2` cannot support an approval and the five design
acceptance criteria have no valid review (S2 process; see B3).

**Weak/invalid per kind across the sample:** code **1 invalid + 3 weak** (P1.18-code-r1, P1.17-code-r1,
P1.21-code-r2, P1.30-code-r1); safety **3 weak** (r3, r4, r6); design **1 invalid + 1 weak** (P1.08-design-r2,
P1.02-design-r1); content, meta and llm **0**. Three kinds cross the "two or more weak/invalid" threshold, so all
three playbooks get tightening lines:

- `.claude/skills/review-code/SKILL.md` — add: *"Every 'never reaches disk / never displayed' invariant must name the
  record fields that were checked; for a stored record, grep the whole serialized record for the banned phrase, not
  one field."* (owns P1.18) · *"A test that asserts a dev-only predicate from a dev build does not cover the release
  branch; assert the guard directly or run a mutation check."* (owns P1.17) · *"Every count in the verification
  section must be the pasted command's output."* (owns P1.02/P1.30) · carry round 1's line: *"Every review that cites
  the shape of a committed evidence file MUST paste 2–3 verbatim field names from that file."* (owns P1.21)
- `.claude/skills/review-design-fidelity/SKILL.md` — add: *"Every class or function named in a verification table must
exist in the tree; paste `grep -n` for the three most load-bearing symbols."* · *"A pasted suite that failed cannot
carry APPROVED unless the same test is shown failing on the merge-base and the failure is provably unrelated."* ·
*"A borrowed count (\"299/299 upstream\") is not evidence; the reviewer's own command output is."* (owns P1.08-design-r2)
- `.claude/skills/review-safety/SKILL.md` — add: *"Any S1/S2 finding forces CHANGES_REQUESTED; downgrade the finding,
  never the verdict."* (owns r4) · *"A hard-block leak is S1 by definition (P1.19 AC-3 / docs/02 §8), whatever the
  obfuscation axis."* (owns r6) · *"After declaring an obfuscation family closed, probe the adjacent axis (mid-word
  leet/case vs separators) and paste one live probe per axis."* (owns r3)

Every safety leak found in the phase was caught and fixed inside its lineage (r4/r5/r6/r7; corpus 208/196 with 0
misses today), so the review-driven re-opens are P1.18 (missed S2) and P1.08's design kind (invalid report); P1.16's
re-open is the merge loss, not a reviewer miss.

## 5. Carry-overs

### 5.1 Blocking (must fix before re-gating P1)

| # | Finding | Blocking task | Role | Target |
|---|---|---|---|---|
| **B1** | **Transcript redaction is defeated by `events`** — `Director._redact_record` rewrites only `record["output"]`; `_current_applied_events` keeps raw `say_chunk.text`/`field`/`beat_field` values, and `Safety.redact_record` (the hook the code prefers) does not exist. Demonstrated with the committed session-3 turn-7 record: `output.inner` is barred, the `field inner` event says `"hurt him"`. P1.18's handoff and code review both claim "unredacted model outputs never touch disk". The transcript is dev-only (`is_enabled()` is release-gated), but the invariant is a safety/privacy control and the tuning corpus now contains raw blocked text. | P1.18 re-open: redact the event stream recursively in `_redact_record` (or implement `Safety.redact_record`), extend `test_transcript_logger_safety_redaction_wired` to grep the **whole serialized record** for the banned phrase, and re-review the code (S2) | SYS/LLM | P1 gate |
| **B2** | **P1.16 round-2 approved delta missing on main** — merge `50752b7` took the stale `task/P1.21` copy of `game/tests/DateSceneTest.gd`, deleting `test_photosensitive_wiring`, `test_ambience_forwarding` and the 25-frame capture settle (CON-3). Production wiring survives; the accessibility/ambience coverage and the screenshot fix do not. | Restore the file from `b19dafd` (approved) and confirm `git diff` against that blob is empty for `game/tests/DateSceneTest.gd`; re-run `tools/test.sh`; record the merge-fix note in `state.json` (a fresh review is not needed if the restore is byte-identical; otherwise re-review) | ART/ENG | P1 gate |
| **B3** | **P1.08's design-fidelity review is fabricated** — `P1.08-design-r2` builds its DES-1..10 re-review and its Pillars section on classes/functions that do not exist (`SignalContract`, `IFrameCollection`, `StateRunner`, `_meta_extra`, `_turn_at_or_after_password_length`, `DirectorRoutes`, `fix_declining_property`, `apply_meta`), borrows a `299/299` count from an "upstream record", and approves while its own pasted run says `1 failed, 176 passed, 2 skipped`. The P1.08 **code** review (r2) is sound and stands. | Re-run the P1.08 design-fidelity review against `4a46b3d`/current main with its own command output; all five design ACs (turn drives every subsystem; §5 budgets + auto-fill; integration test; §6 memory; §7 fallbacks) need real evidence. Record the replacement as `P1.08-design-r3`. | ENG/SYS reviewer | P1 gate |

### 5.2 S3/S4 left open (ticket or disposition)

Round 1's E1-E10 all stand — none has been ticketed in `production/phases/P2_sickness.md` (22 tasks, checked): **E1**
P1.22 sound-column derivation; **E2** failed-turn metrics block; **E3** P1.02 inventory + personal-name fixture sweep;
**E4** `over_budget` from `fixed` only; **E5** hand-argued AC slots; **E6** P1.21 raw-evidence provenance; **E7** F7
deflection widening; **E8** F5 cue assets/ambience; **E9** F6 mid-sentence pronoun repair; **E10** playtest harness
entry point. New this round:

| # | Finding (source) | Proposed task | Role | Target |
|---|---|---|---|---|
| E12 | P1.16 CON-2 (its own review, S3): no prompt-lab case exercises the D02 `Goal:` scene layer; the ~880-token loaded budget is an estimate, not measured on that branch | Add one D02 café lab case + paste the measured loaded budget | QA | P2 |
| E13 | P1.31 CODE-1 (S3): only the stage-0 refusal is tested; `get_input_refusal` stage ≥ 3 has no unit case | Add the stage-3/5 accessor test (feeling, placeholder, `cue == "none"`) | SYS | P2 |
| E14 | P1.31 CODE-2 (S3): a rejected submission's transcript record carries the previous turn's `LLM.last_metrics()` | Pass `{}` for the rejection path or make `_log_turn_record` take metrics explicitly | SYS | P2 |
| E15 | P1.31 CODE-3 (S4): `reject_turn`'s comment claims "no second scan" but `replace_beat` always calls the injected filter | Reword to match the seam | SYS | P2 |
| E16 | P1.31 CODE-4 (S3, = F1 requirement): the release is gated on `chat_ui_node`, which no game code registers | Fold into F1: `Date._ready` must call `register_chat_ui` and submit through the InputBox path | ENG | P2 (P2.23) |
| E17 | `Director.gd` is at **999/1000** gdlint lines (SYS journal, P1.31 gotcha) — the next SYS line fails lint | Split the step-0/turn-close seams before any new Director line | SYS | P2 |
| E18 | `TurnSchema`'s module default order is the non-docs order (`read,inner,beats,…,music,fx,meta`) and its own test pins that; only Director's explicit `property_order` arg saves the live path | Make the docs order the default, or delete the default so the arg is mandatory | SYS | P2 |
| E19 | P1.17 release-stripping test is tautological in dev builds (S3) | Add a direct assertion on the guard/export preset | ENG | P2 |
| E20 | P1.30 AC-3 counts three fail-closed probes where there are six, and the `$null -eq $code` sentinel is never reached (S3) | Correct the report count; pin the sentinel or delete it | REL | P2 |
| E21 | P1.02 inventory arithmetic 33 vs 36 executed (S4, round 1's E3/E5) | Documentation only | PROD | standing |
| E22 | **Merge hygiene** (new, systemic): merge commits deleted 4 handoffs and the P1.16 r2 delta | Post-merge audit: for every approved review, check its cited files and `test_*` names exist on main; merge with `--no-commit` + per-task `git diff` review | REL/PROD | P2 |
| E23 | `STATUS.md` stale at 9/30 while `state.json` is 31/31 | `track.py render` before recording the gate | PROD | now |

### 5.3 P2 tasks that must exist before P2 execution (D12/D13 promises)

- **P2.23 — Date scene controller (F1)** · ENG · M: `start_date`, register ChatUI/Character with the Director,
  forward `player_turn_sent` → `submit_player_input` (no second `turn_failed` consumer), consume
  `ScenarioLoader.get_events_for_turn`, enforce min/max turns and `on_goal`. Without it the shipped date cannot accept
  a turn and P1.31's refusal release is unreachable.
- **P2.24 — Human 3-stranger playtest round 1** · QA · M: D12's owed round, transcripts into
  `production/playtests/P2/`, before M2 exit.
- **P2.25 — Merge-hygiene audit** (E22) · REL · S.
- **P2.26 — First-beat latency remediation** (D13): restructured schema / prompt compaction, re-measure
  first-usable-`say` on CUDA · LLM/QA · M.
- Plus E7 (deflection), E8 (cues/ambience), E9 (pronoun), E10 (harness) and F2 (double-resolve opening beats) as
  already drafted in the P1.22 findings.

## 6. Risks and decisions

Proposed `production/RISKS.md` updates (R16/R17 from round 1 were never added; both stand):

- **R16 (H/M)** Safety-rejected player input strands the UI → mitigated at the pipeline level by P1.31; the residual
  risk is the unregistered ChatUI in the shipped scene (E16/F1).
- **R17 (M/H)** The M1 "stranger" wording has never been executed with a human; D12 accepts the simulated round as
  interim, but the owed human round has no owner yet.
- **R18 (new, H/M)** Merges silently overwrite or delete reviewed content and handoffs on main. Evidence: four
  handoffs (two merges removed a file present in both parents) and the P1.16 r2 tests/settle. Mitigation: E22 + the
  merge procedure; re-run the content audit after every batch of merges.
- **R19 (new, M/M)** The "no unfiltered model text on disk" invariant is broken by transcript `events` (dev-only);
  the tuning corpus contains raw blocked text. Mitigation: B1.
- **R20 (new, M/H)** The shipped date has no controller: every external playtest depends on a throwaway driver (E10),
  and P2.22's full runs would inherit the same gap. Mitigation: P2.23 before P2.22.

Decisions the user/producer must handle: D3/D4/D5/D8/D9 remain **OPEN** (5 rows). D12 and D13 are recorded, but their
scheduled work is not ticketed (P2.23/P2.24/P2.26). D11 stands unchanged. The P1.31 docs/02 DCR (an input-refusal row
in §4 step 0.1 / §7) is filed in the handoff but not accepted; docs/02 still has no such row — docs-only producer
action.

## Verdict

**FAIL.** Round 1's two blockers are genuinely closed: **G1** (the rejected-input UI lockup) is fixed, reproduced
pre-fix and pinned by two regression tests I ran green; **G2** now has a producer decision (D12) that honestly
labels the simulated round and schedules a human one. Criteria 2, 4 and 5 are green on main, criterion 1 is met in
D12's interim sense, and criterion 3 is an accepted, diagnosed D13 deviation. But three new blocking defects surfaced
in this gate's integration and review audit:

1. **P1.18/S2 — the transcript redaction invariant is false.** The `output` field is barred, but the same record's
   `events` carry the raw model text (committed evidence: session 3 turn 7). P1.18's review and handoff both claim the
   opposite. Fix `_redact_record` (or implement `Safety.redact_record`), pin it with a whole-record assertion, and
   re-review.
2. **P1.16/S2 — approved work is missing on main.** Merge `50752b7` deleted the two round-2 regression tests and the
   25-frame capture settle. Restore the approved file and re-run the suite.
3. **P1.08/S2 — the design-fidelity review is fabricated.** `P1.08-design-r2` cites eight classes/functions that exist
   nowhere, borrows its suite count, and approves a run it pastes as failing. The code review stands; the design review
   must be redone with real evidence (`P1.08-design-r3`).

Also required before re-gating: restore the four missing handoffs (S3), re-run the P1.08 design review, and record the
render of `STATUS.md`. Nothing else needs re-proving: the 349/349 suite, 178/179 pytest, 0/0/0 tracker validation, the 208/196 safety corpus and the
100/93.3/100 prompt lab are reproducibly green today and will not expire. Before P2 execution (not before re-gating),
ticket P2.23 (F1), P2.24 (human round), P2.26 (D13 latency) and the E-list, so D12/D13 are promises with owners rather
than prose.
