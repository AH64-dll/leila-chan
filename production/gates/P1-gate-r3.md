GATE: PASS

# Phase gate — P1 Vertical slice: one living date, round 3

- Date: 2026-11-04 · Reviewer backend: deepseek (`commandcode/deepseek-v4.1-flash`)
- Main branch commit: `d442a17` ("production: P1.08 done — 32/32; P1 gate-r3 ready")
- Playbooks: `.claude/skills/review-phase-gate/SKILL.md`, `.claude/skills/leila-work-protocol/SKILL.md`
- Tree: `main`, 182 commits ahead of `origin/main`; only `production/briefs/P1-gate-r3.md` is
  untracked. Every number below was produced on this checkout. No count is copied from a handoff
  or from rounds 1–2; where a prior round's claim is repeated it says so and was re-derived.

## 1. Task completion

Enumerated from `production/state.json` together with the phase table's review-kind column
(not from `STATUS.md`):

```text
P1 tasks: 32 · status counts: {'done': 32} · non-done: {}
required (task, kind) review slots: 52  (28 code · 19 design · 4 content · 1 safety)
final-round slots whose report head says VERDICT: APPROVED: 52
stale-changes check (latest round of a kind not approved): none
P1 review files: 83 · journals: 11 · handoffs on disk: 28/32
```

Each kind's highest round is the approved one. The rounds that matter here: `P1.08` now carries
`design-r4` + `code-r4` (the fabricated `design-r2` was replaced through r3/r4), `P1.19` carries
`safety-r7` + `code-r7`, `P1.32` carries `code-r1`, `P1.31` carries `code-r1`.

**Exception — four handoffs are still absent on `main`:** `P1.07`, `P1.12`, `P1.16`, `P1.20`.
`state.json` points at files that do not exist. This is round 2's unmet precondition; all four are
recoverable verbatim and every one of them is present in history:

```text
P1.07 → git show c72c10c:production/handoffs/P1.07.md   (present)
P1.12 → git show 4e51add:production/handoffs/P1.12.md   (present)
P1.16 → git show 977fec1:production/handoffs/P1.16.md   (present)
P1.20 → git show 4e51add:production/handoffs/P1.20.md   (present)
```

`production/STATUS.md` is still stale: its last render is `2026-11-04T02:15:24+02:00`, showing P1 at
31/32 with P1.08 `changes_requested`, while `state.json` closed P1.08 at `02:42:17`. The gate does not
write it (playbook: producer action, see §5.1).

### Round-2 blockers — re-verified one by one

**B1 (P1.18/S2, transcript redaction) — closed.** `game/llm/TranscriptRedactor.gd` is the single
redactor, wired once at `Director.gd:155-159` (`transcript_logger.set_redactor(Callable(_redactor,
"redact_record"))`). `redact_record` (`:63-73`) scans `output`, the `prompt` assistant messages
(`:85-95`) and the event payloads (`:102-131`): every `field`/`beat_field` value whose name is not in
`VOCABULARY_FIELDS` goes through `_scan`, and the record's `say_chunk` fragments are joined, scanned as
one utterance and redistributed by code-point count. `scan_text` is stateless — `SaySafetyGate.gd:132-141`
calls the filter's `filter_text` and touches none of the streaming scanner's state (`_pending`,
`_history`, `_in_beat`). The whole-record assertion is real:
`DirectorTest.test_transcript_redacts_applied_events_and_prompt_history` (`game/tests/DirectorTest.gd:464`)
drives two turns with the banned phrase split across two `say_chunk` events, loads the JSONL from disk and
walks every string in the record. It is in my green run. My own probe of the live filter (headless Godot,
real `Safety` lists) on the gate's exact r2 example:

```text
PROBE |He thinks I'd hurt him like that.| -> He thinks I'd ████████ like that. | redacted=true | cats=["threat_to_player"]
PROBE |I'll wait until the rain starts.|     -> I'll wait until the rain starts.       | redacted=false | cats=[]
```

Landed by P1.32 (`1d40a54`, merge `6d565e6`) and re-reviewed by `P1.32-code-r1` with a mutation run that
turns the test red when the event/prompt branch is removed. Residual surfaces it disclosed (system-message
memory, Dictionary prompt, double log/glitch) are S3 carry-overs in §5.2, not this blocker.

**B2 (P1.16/S2, approved DateSceneTest delta missing) — closed.** `game/tests/DateSceneTest.gd` now has
13 cases including `test_photosensitive_wiring` (`:216`), `test_ambience_forwarding` (`:226`),
`test_vram_usage_budget_under_800mb` (`:233`) and the 25-frame capture settles (`:185`, `:195`). The
restore is byte-complete against the approved blob:

```text
$ git diff --numstat b19dafd -- game/tests/DateSceneTest.gd
50  0  game/tests/DateSceneTest.gd     (every approved line back; only P1.21's VRAM case is added)
$ git show b19dafd:game/tests/DateSceneTest.gd | grep -c "^func test_"
12
```

All three restored cases and the VRAM case PASS in my `tools/test.sh` run.

**B3 (P1.08/S2, fabricated design-r2) — closed.** `P1.08-design-r3` is a real review: it re-ran the gate,
booted the project headlessly, and audited the recorded sessions rather than the prose. It found the true
DES-1 — the current player line was appended to `history` at step 0.3 and again by `PromptBuilder` as
`player_message`, so **every** recorded prompt ended in two identical consecutive `user` messages. I
re-derived that from the committed JSONL myself:

```text
turn records: 39 · ending in an identical consecutive user/user pair: 39
```

The fix is `TurnContext._prior_history()` (`game/llm/TurnContext.gd:99`, body `:112-122`): the step-1
snapshot drops exactly one trailing `user` entry equal to this turn's stripped line; the Director's own
append stays (the next window and unanswered lines need it). `DirectorTest.test_step_2_prompt_history_holds_prior_exchanges_only`
asserts on the request object the backend received (turn 0 = 2 messages, turn 1 = 4 with no adjacent
`user`) and is green in my run. `P1.08-design-r4` and `P1.08-code-r4` both APPROVE the merged result,
with mutation checks for both the history slice and the auto-fill gates. Process caveat in §4/§5.3:
those two re-reviews ran on the same backend as the implementer (deepseek), which breaches D7's
"reviewers on the other backend" convention even though the evidence is substantive.

### P0 carry-over contracts

Every owner task is `done`; the contracts I could re-run or re-read:

| Contract | Owner | Status | Evidence I produced |
|---|---|---|---|
| C1 Windows drive-colon control-vector paths | P1.23 | closed | `tools/llm/cvec_path.py` shared by both launchers; `tests/test_cvec_paths.py` = 24 cases incl. `test_windows_abs_other_dir_walks_up`, drive-letter case folding and scale validation; my run: 118 passed across cvec+workflow+tracker |
| C3 bounded CI runtime | P1.24 | closed | `.github/workflows/ci.yml:24` `timeout-minutes: 15`; `tests/test_ci_workflow.py:94` |
| C4 no persisted checkout credentials | P1.25 | closed | `ci.yml:34` `persist-credentials: false`; `test_every_checkout_disables_persisted_credentials`; `.yml`/`.yaml` discovery test |
| C5 window height re-evaluation | P1.16 | closed | `game/project.godot` `window_width_override=384`, `window_height_override=688` (fits 1080p, integer scaling); adjudicated in `P1.16-design-r2` DES-1 |
| C6 implementer/reviewer metadata drift | P1.26 | closed | `track.py validate --strict` reports 0 backend-drift warnings; `production/tests/test_track.py:593` pins the parallel-review-after-changes path |
| C7 casting asset paths | P1.10 | closed | `test_bridge` in my run: "all 264 feeling x tier x intensity cells resolve to files", "all path override + flagged sprite ids resolve to files" |
| C8 first usable `say` measured | P1.02 + P1.21 | honest miss (D13) | §2 criterion 3 |
| C9 non-empty `inner`/`say` | P1.07 | closed | `TurnSchema.gd:265,297` `minLength: 1`; `:393-394,430-431` validator errors; `TurnSchemaTest.test_validate_turn_enforces_string_limits_and_non_empty` |
| C10 first/any-beat selector | P1.20 | closed | `tools/promptlab/score.py` `--beat {first,any}`; both printed by my run |
| P1.05 CON-1 fixed vs dynamic budget | P1.06 / P1.15 | closed | `PromptBuilder.BUDGETS` separate `system`/`memories`/`scene`/`history`; `debug.tokens` reports `fixed`, `dynamic`, `system_message`, `total`; `_over_budget` still checks the fixed block only (E4 stands) |
| P1.05 CON-2 memory facts | P1.09 | closed | `game/llm/MemoryRules.gd` implements the three docs/02 §6 rules (grounding in the last player lines, meta-word rejection, near-duplicate Jaccard) with P1.09 tests; the lab's memory column (6/20 rejected) is reproducible from the committed rows |
| P1.20 D10 label-set review + held-out/copy/rejection metrics | P1.20 | closed | my scorer run prints `few-shot copy: overall=11.7% … held-out=0.0% (n=52)` and `memory proposals=20 rejected=6 rate=30.0%` |
| P1.02 CODE-2 cancel/bounded teardown | P1.02 | closed | facade cancel tests in `LLMTest.gd`; bounded start 30 s / stop 5 s / turn+read timeouts |
| P1.25 CODE-1..4 | P1.25 | closed | workflow policy tests cover `.yml` + `.yaml`, missing/`'false'`/`0`/`true` rejection |
| P2.12 deferrals (P1.04 CODE-5/DES-6) | P2 | correctly deferred | still written in the phase doc |

## 2. Exit criteria

| # | Criterion (from the phase doc) | Status | Evidence I produced |
|---|---|---|---|
| 1 | docs/09 M1 exit: a stranger plays 10 minutes, face/sound match her words (survey mean ≥ 4/5), **zero broken turns** | **pass under D12 (interim)** — one broken turn fixed, no post-fix end-to-end run | Re-derived from the committed playtest artifacts: 39 scored turns, 1 broken. Pooled face **4.9231**, sound **4.0513**, face+sound **4.4872** (sheet publishes 4.92 / 3.95 / 4.44 — face and pooled reproduce; its Sound column does not, E1 stands). Broken census from `session_*.json`: 14/14, 14/14, and 11 completed + **1 failed** (session 3 turn 5, `ui_unlocked_after=false`). Root cause (`docs/02 §4` step 0 rejection returning before teardown) is fixed by P1.31 and pinned by `test_unsafe_input_releases_ui_and_is_logged_as_failed` + `test_turn_after_unsafe_rejection_still_completes`, both PASS in my run. The zero-broken-turn state has not been re-run end-to-end because the shipped Date still has no controller (F1, §5.3); the owed human round (D12) re-measures it. |
| 2 | Prompt lab v1 on main: JSON validity ≥ 99%, intent ≥ 85%, emotion fit ≥ 85% | **pass** | `python3 tools/promptlab/score.py tools/promptlab/results/2026-11-03_v1.json --beat first` → `n=60 validity=100.0% read_accuracy=93.3% first_beat_fit=100.0% any_beat_fit=100.0%`, three PASS lines, exit 0. Raw recount from the rows with the committed label sets: 60/60 valid, 56/60 read hits, 60/60 first-beat fit; under the **frozen** pre-REV2 labels first-beat fit is 55/60 = **91.7%**, still above the 85% gate, so the criterion does not depend on the widening. |
| 3 | First beat on screen < 1.0 s median on the RTX 4050 | **not met — accepted deviation D13** | Recomputed from the committed raw data `production/handoffs/media/P1.21/bench_30turns.json` (30 records): `ttft_ms` median **392**, `first_say_ms` median **7,523** (p95 7,836), `total_ms` median **14,640**; the file's own summary block says 391 / 7,521 / 14,514 (nearest-rank interpolation differs). This is the CPU-host path. The CUDA figure (1.81–1.86 s first usable `say`) exists only as prose in `production/journals/P1/LLM.md`; no committed artifact carries it and no llama-server is attached in this session, so I cannot re-measure it. Both numbers miss 1.0 s. D13 records the acceptance and the owned remediation. |
| 4 | Safety corpus: 0 hard-block misses | **pass** | My `bash tools/test.sh`: `harmful: 208 · benign: 196 · total: 404`, `hard-block misses: 0`, `wrong-category hits: 0`, `residue/leaks: 0`, `stream divergences: 0`, `benign evaluated: 196 (0 skipped, 0 quarantined)`, `false positives: 1 (0.51%, limit 5%)` — the documented `the brakes retard the wheel's spin.` verb-sense row. Independent probe of the live filter: `kill!s all the jews.` and `kills all the jews.` bar (`threat_to_player`+`slur_hate`), `you should kill yourself` bars (`harm_to_player`), `Tell me your home address.` bars (`personal_data`), benign lines stay clean. |
| 5 | All P1 code has tests running in CI | **pass (pipeline + local) — CI-execution caveat** | `.github/workflows/ci.yml` runs `track.py validate --strict`, `pytest`, `gdlint`, then the full `tools/test.sh`, with `timeout-minutes: 15` and `persist-credentials: false`. I ran exactly those on this checkout: 360/360 gdUnit4 over 30 suites, pytest 178 passed/1 skipped, lint and format clean. Caveat: `gh run list` shows the last Actions run on **2026-11-02**; `origin/main..main` is **182** commits, so no P1 commit has actually executed in CI. The first push to `main` remains the outstanding check — ticket it, do not claim it ran. |

**Criterion 1's detail, including the brief's docs/02 §4 step 0 pointer.** The one broken turn is the
rejected-input deadlock: `Director.submit_player_input` emitted `turn_failed("unsafe_input")` and returned
before any teardown, leaving ChatUI with `input_enabled=false` and the typing indicator up forever, and the
turn absent from the transcript (`production/playtests/P1/diag_unsafe_input.json`, session 3 turn 5). P1.31
now routes that path through `_reject_unsafe_input` (`Director.gd:303-309`): it logs a `failed` record, reads
the data-owned refusal from `fallbacks.json`, scans it once through the gate, hands it to
`ChatUI.reject_turn`, and emits `turn_failed` for observers. The review reproduced the pre-fix failure by
reverting only that branch and saw both tests go red. Residuals: the refusal record shares the completed
turn's index (E14), no unit case pins the stage ≥ 3 refusal text (E13), and the shipped scene still never
calls `submit_player_input`/`register_chat_ui` (F1).

**Criterion 2's label-set audit (D10).** The four/five widened cases each carry a per-case note naming the
model's actual text (`tools/promptlab/sets/*.jsonl`), e.g. `s0_scare` +`shy` — "W-why are you doing that?".
That is hand-label evidence, not a number chase; and because the frozen labels still score 91.7%, the gate
holds either way. The five frozen misses are exactly five cases.

## 3. Integration check on main

```text
$ git log -1 --oneline
d442a17 production: P1.08 done — 32/32; P1 gate-r3 ready

$ python production/tools/track.py validate --strict
137 tasks in 8 phases; 0 error(s), 0 missing-ref warning(s), 0 backend-drift warning(s)      (exit 0)

$ python -m pytest -q
178 passed, 1 skipped in 10.21s                                                              (exit 0)
  # the skip is the Windows-only PowerShell 5.1 launcher case (tests/test_godot_launcher.py:27)

$ bash tools/test.sh                                                                         (exit 0, 70.6 s)
== gdlint game/ ==               Success: no problems found
== gdformat --check game/ ==     90 files would be left unchanged
== godot --headless --import ==  clean
== gdUnit4 (res://tests) ==
  Overall Summary: 360 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |
  Executed test suites: (30/30) · Executed test cases: (360/360) · Exit code: 0
  (includes DirectorTest 15, DirectorRoutingTest 7, DirectorFallbackTest 10,
   TranscriptRedactorTest 6, DateSceneTest 13, TurnSchemaTest 15, DebugOverlayTest 14,
   SceneFlowTest 14, GameStateTest 19, GameStateRestoreTest 6, UITest 16)
== standalone tests ==
  test_bridge: all checks passed   (264 feeling×tier×intensity cells, 31 sprites, nearest filter)
  harmful 208 / benign 196 / misses 0 / wrong-category 0 / residue 0 / stream divergences 0
  false positives: 1 (0.51%, limit 5%) · say_chunk latency: 536.4 us avg over 11271 calls
  test_safety_corpus: all checks passed
test.sh: all checks passed

$ python3 tools/promptlab/score.py tools/promptlab/results/2026-11-03_v1.json --beat first
n=60  validity=100.0%  read_accuracy=93.3%
first_beat_fit=100.0%  any_beat_fit=100.0%  (gate first-beat >= 85%)
few-shot copy: overall=11.7%  near-fewshot=87.5% (n=8)  held-out=0.0% (n=52)  avg_ratio=0.462
memory proposals=20  rejected=6  rate=30.0%
PASS validity: 100.0% (gate 99%) · PASS read_accuracy: 93.3% (gate 85%)
PASS first_beat_fit: 100.0% (gate 85%)                                                       (exit 0)

$ python -m pytest -q tests/test_cvec_paths.py tests/test_ci_workflow.py production/tests/test_track.py
118 passed in 1.30s                                                                          (exit 0)
```

No integration failure: every approved P1 delta that round 2 found missing (P1.16's tests, P1.18's event
redaction) is present and green on `main`.

## 4. Review audit (reviewing the reviewers)

Sample: **27 of the 52 final-round reports (52%)**, including **all seven safety reviews** (P1.19 is the
phase's only safety-review task), both L-size tasks' final reviews (P1.02 via code, P1.08 via both kinds),
the two remediation reviews that carry the gate's own blockers (P1.31, P1.32), and the shortest reports
(P1.16-content-r2 29 ln, P1.07-code-r1 50, P1.13-code-r3 69, P1.21-code-r2 73, P1.15-content-r2 77,
P1.14-design-r1 81, P1.06-code-r1 90, P1.29-code-r2 100). Every backticked symbol a sampled report leaned
on was located in the tree; the line numbers sometimes lag the merge (noted per row), the substance did not.

| Review report | Re-checked claim / criterion | Holds? | Missed defect (sev) | Reviewer quality |
|---|---|---|---|---|
| P1.32-code-r1 ★ | event/prompt redaction + whole-record assertion; DateSceneTest restore | yes — live filter probe bars the gate's record text, keeps vocabulary; `git diff --numstat b19dafd` = 50/0; test fails when the branch is removed (its mutation run) | — | good |
| P1.08-design-r4 ★ | DES-1 fixed; 39/39 recorded prompts held the duplicate | yes — I re-derived 39/39 from `transcripts/session_*/turns_*.jsonl`; `_prior_history` at `TurnContext.gd:99,112-122`; the regression test is green in my 360 run | — (same-backend caveat, §5.3) | good |
| P1.08-code-r4 ★ | mutation-proven history + auto-fill tests, no findings | yes — test names/assertions verified; the four mutations are described with failure line numbers and the tests are green | — | good |
| P1.31-code-r1 ★ | pre-fix reproduction, refusal release, failed record | yes — both test names are in my `results.xml` with 0 failures; `_reject_unsafe_input` at `Director.gd:303-309`; record shape re-read | — | good |
| P1.02-code-r1 ★ | "restart within 5 s" + 33-test inventory | **no as written** — its own pasted live run shows `test_live_crash_is_restarted_within_5s FAILED` at **6306 ms**, and there is **no** committed timing artifact (`game/reports/` is gitignored; the on-disk log shows all three live cases SKIP). The 33 breakdown is 17 backend + **14** LLMTest + 2 autoload; the report says 13 and its total only works with 14. ctx 8192, sampling whitelist and per-request schema do hold | S4 evidence provenance: an AC pasted as failing was approved as "environmental" on prose-only 2835 ms | weak |
| P1.07-code-r1 | "Output equals docs/02 §3 structure" | **no as written** — the default order is `read,inner,beats,mood,memory,action,music,fx,meta`, docs/02 §3 is `read,inner,music,fx,beats,mood,memory,action` with no `meta`; the report declares both deviations but calls the criterion "met" and attributes the order to a "task assignment" the brief does not contain. The live path is saved by `Director.gd:378` passing `DOCS_02_PROPERTY_ORDER` | S3: declared doc deviation approved as "met", no DCR (code track E18) | weak |
| P1.17-code-r1 ★ | "stripped from release export — covered by `test_release_feature_tag_guard`" | **no** — the test is one line asserting `DebugOverlay.is_dev_build()` in a dev run; deleting every guard leaves it green. Guards exist at all four entry points, but there is no `export_presets.cfg` anywhere, so "stripped from the export package" is unproven | S3 test-quality (tautological coverage) | weak |
| P1.18-code-r1 | "unredacted model outputs never touch disk" | **no** (round 2's S2); fixed under P1.32 and re-reviewed there | S2 — already re-opened; the fix is the P1.32 row above | invalid (inherited) |
| P1.21-code-r2 ★ | "30 per-turn records contain `output_len`" | **no** — 30 records, each with exactly `chunks, first_say_ms, player, total_ms, ttft_ms, turn`; `output_len` absent; the committed reproducer `bench_p121.py` writes a different schema | S3 provenance (E6) | weak |
| P1.16-content-r2 ★ (29 ln) | CON-1 resolved / CON-2 open / 25-frame settle | yes — `D02_cafe.json:25` YANDERE, zero `OBSESSION` in `game/`, settles at `DateSceneTest.gd:185,195`, no D02 lab case in `sets/` | — | good |
| P1.13-code-r3 | CODE-2 S1 typewriter burst cap; ChatLog trim | yes — `Typewriter.gd:79-86` cap, `ChatLog.gd:33/36/37` remove-then-free, both pinned in `UITest.gd` | S3 not noted: `all_displayed` re-emits every idle frame (idempotent consumer); composite indicator ordering untested | good |
| P1.13-design-r3 | 4/4 ACs including "indicator until the first say token" | **partially** — pinned at `TextBox` level only; `ChatUI.begin_beat` (`:101-103`) hides the indicator *before* the first `say_chunk`, and no test covers the composite order | S3: an AC marked met without the composite path | weak |
| P1.15-content-r2 (77 ln) | AC-2/AC-3 "met": loader injects scene layer, end rules enforced | **no as written** — `inject_scene_layer` and `evaluate_turn_end` have **no production caller** (`ScenarioLoader.` is used only at `Date.gd:123,129,187`); the live prompt uses the hard-coded `Director.scene_info`. Also `jsonschema` is not a pinned dependency, so the pasted validator run is not reproducible in CI | S3 scope: unit-level "enforced" approved as integrated (the wiring is F1/P2.23) | weak |
| P1.06-code-r1 | assembly order, spoken-text assistant history, per-layer budget dict, 12-exchange window, goldens | yes — `LAYER_ORDER` `:48-57`, `_spoken_from_beats` `:443-455`, `debug.layers`/`debug.tokens`, `HISTORY_WINDOW := 12`, 2 goldens compared byte-wise | — (line cites 8–42 lines stale; raw store is full Turn JSON converted at assembly) | good |
| P1.14-design-r1 | name rules, prompt injection, name tag | yes — docs/08 §1.5's "name tag on your messages" is the chat-log speaker tag, which carries the name (`ChatUI.gd:80`, `ChatLog.gd:89-97`); the `NameTag` component is the NPC label | S4 (its own DES-1): 16-char padded name is rejected, untested | good |
| P1.10-code-r2 ★ | 198-cell sweep, 264-cell bridge sweep, 140 ms crossfade, nearest scaling | yes — 22 feelings × 3 stages × 3 intensities = 198 asserted; 88 rows × 3 = 264 computed; `CROSSFADE_MS := 140.0`; `default_texture_filter=0` | S4 wording: `test_bridge` proves file existence, not texture loading | good |
| P1.12-code-r2 ★ | 20 s hold + 1 change/turn; cue map; buses | yes — `audio_rules.json:82-83`, `AudioDirector.gd:349-371`, test `test_music_min_hold_and_one_change_per_turn`; buses exposed, MusicA/B hidden | S3: `cue_map.json` heartbeat entries name `.wav` while the committed files are `.ogg`, masked by extension forcing | good |
| P1.20-code-r1 ★ | three metrics at 99/85/85; raw results committed | yes — gates read from `score.py:28`; my run reproduces 100/93.3/100 and the raw recount 60/60, 56/60, 55→60 | S3: the committed results file's stored `memory_rejects` is stale (9 rows vs the 6 the scorer recomputes) | good |
| P1.29-code-r2 ★ | CODE-7..12 / DES-7 regressions | yes — all six pins found (`GameStateTest.gd:94-121,185-194,377-397`; `GameStateRestoreTest.gd:66-75,102-114,40-41`) | — (line offsets ~15 drift) | good |
| P1.22-design-r1 ★ | F3 lockup real; sound-mean arithmetic | yes — session 3 turn 5 is `failed`, `diag_unsafe_input.json` matches; my re-derivation 4.9231/4.0513/4.4872 confirms its DES-1 (sheet 4.92/3.95/4.44) | — | good |
| P1.19-safety-r1 | S1 negation/obfuscation bypasses, fail-closed config | yes — probe tables and the later lineage (SAF-9/10/14/19/22) all trace to these classes; the shipped lists now cover them | — | good |
| P1.19-safety-r2 ★ (63 ln) | SAF-9/10 S1 under coercive interrogative and punctuation-join; 302 rows | yes — real command output, per-row probes, correct CHANGES_REQUESTED | — | good |
| P1.19-safety-r3 | APPROVED with 0 corpus misses | **no** — self-discloses "no shell and no file-write capability … source-traced adversarial reasoning", i.e. **no executed evidence**; the same round's code review demonstrated the S2 mid-word leet/separator misses r3's probes could not see | invalid evidence under protocol §4 ("a review with no evidence you produced is invalid") | invalid |
| P1.19-safety-r4 | SAF-16 S2 over-block; verdict | SAF-16 is real (`kill all the lights` bars as `threat_to_player`) and was fixed in r5, but the report returns **APPROVED with an S2** — protocol §5 says any S1/S2 → CHANGES_REQUESTED | S2 filed then approved (verdict violation) | weak |
| P1.19-safety-r5 | SAF-19 S2 `kills all the jews.` leak | yes — my live probe bars both `kills` and `kill!s` forms today; the finding was correct and correctly rated S2 | — | good |
| P1.19-safety-r6 | SAF-22 S2 negator swallow; SAF-23 | SAF-22 is real and correctly S2; **SAF-23 (`kill!s all the jews.`) is a hard-block leak rated S3**, which the severity table calls S1 — the verdict was already CHANGES_REQUESTED, so nothing escaped | severity misjudged | weak |
| P1.19-safety-r7 ★ | SAF-22 closed via `\K`; 404 rows; FP 0.51% | yes — `\K` at `filter_lists.json:225`; my probe bars `kill!s all the jews.` / `kills all the jews.` and leaves benign text clean; my suite run is 208/196, 0 misses, 0.51% | — | good |

**S1/S2 left open on `main` by a missed review claim → none.** The phase's one demonstrated S2 (P1.18's raw
event text) did reach `main`, but round 2 caught it, and P1.32 closed it under an approved review with a
whole-record assertion. The four safety defects (SAF-16, SAF-19, SAF-22, SAF-23) were each raised and fixed
inside the P1.19 lineage before merge, and today's corpus is green with 0 misses. **No task is re-opened by this gate.** P1.18's own final report remains the invalid
one; the producer satisfied its re-open through P1.32 rather than a new P1.18 round — acceptable because
P1.32's review explicitly re-verifies B1 with a mutation test.

**Weak/invalid counts by kind across the sample:** code **4 weak + 1 invalid** (P1.02, P1.07, P1.17, P1.21;
P1.18 invalid) of 14 sampled; design **1 weak** of 4; content **1 weak** of 2; safety **2 weak + 1 invalid**
of 7. Code and safety cross the "two or more" threshold again, so the playbooks get these exact lines:

- `.claude/skills/review-code/SKILL.md` — *"Never paste a partial suite statistic under a full-suite heading:
  label the filter or paste the whole run."* (P1.02) · *"An acceptance criterion your own pasted run marks
  FAILED cannot be APPROVED on an environmental argument without a committed artifact or a hardware-qualified
  AC; rate it S2 or get the task re-scoped."* (P1.02) · *"A declared deviation from a doc structure is not
  'met': cite the doc line, open a DCR, and rate it S3/S4."* (P1.07) — plus round 2's four lines, still
  unenforced in practice.
- `.claude/skills/review-content/SKILL.md` — *"For an AC of the form 'X is enforced', paste the production
  call site as well as the unit test; 'no caller' is a finding."* (P1.15) · *"Pin every external validator
  you invoke in requirements-dev, or reproduce with the committed validator."* (P1.15)
- `.claude/skills/review-safety/SKILL.md` — round 2's three lines **plus** *"A session without shell/command
  access must return BLOCKED, never APPROVED on source tracing; borrowed suite output is not evidence."*
  (r3) · *"Carry the finding's severity into the verdict: an S2 on the page and APPROVED at the top is a
  contradiction."* (r4) — r6's hard-block-is-S1 line is already in round 2's set and was again violated.

## 5. Carry-overs

### 5.1 Round 2's preconditions — still open (producer action; S3)

Round 2 required three things before re-gating. One landed (the P1.08 design re-review, r3/r4). Two did not:

| # | Item | Why it is still open | Fix |
|---|---|---|---|
| E34a | Four approved handoffs missing on `main` (P1.07, P1.12, P1.16, P1.20) | `state.json` points at absent files; they were deleted by merge commits (`84fee93`, `80c2923`, `50752b7` lineage) | Restore verbatim from the commits in §1 in one commit; nothing needs re-review (byte-identical) |
| E34b | `STATUS.md` stale (31/32, P1.08 `changes_requested`) | Last render predates P1.08's r4 close | `python production/tools/track.py render` |
| E23 | Round 1's `STATUS.md` freshness item | Same as E34b; give it a home (a pre-gate step in the producer checklist) | Fold into E34b |

I did **not** turn these into a FAIL: they are S3 documentation/metadata, verbatim-recoverable, and they
change no exit-criterion evidence (every sampled review's claims are independently reproducible, as the
audit shows). They are nevertheless mandatory in the producer's recording commit — leaving them again would
make the next gate's inputs incomplete by construction.

### 5.2 S3/S4 findings left open (ticket or disposition)

Round 1/2's list stands except where noted. **Changed since round 2:** E17 is no longer at the
Director cap (981/1000 after P1.32; the constraint still binds future work) and E22's P1.16 instance is
closed (P1.32 restored the file). **Still open:**
E1 (sound-column derivation — my re-derivation is 4.0513, the sheet says 3.95), E2 (stale failed-turn
metrics block), E3 (P1.02 inventory + personal-name fixture sweep), E4 (`over_budget` from `fixed` only —
`_over_budget` at `PromptBuilder.gd:582-596` still checks `system`=fixed), E5 (hand-argued AC slots), E6
(P1.21 provenance — reconfirmed: no `output_len`), E7 (F7 deflection), E8 (F5 cue assets/ambience — `hum`/
`sniffle` still empty, no `amb.cafe`), E9 (F6 pronoun), E10 (F8 harness), E11 (journal nit), E12 (D02 lab
case), E13 (stage ≥ 3 refusal unit test), E14 (rejection shares the turn index), E15 (reject-path comment),
E16 (F1), E18 (`TurnSchema` default order ≠ docs and adds `meta`; only `Director`'s explicit arg saves it),
E19 (P1.17 tautological test), E20 (P1.30 probe count), E21 (P1.02 arithmetic).

New this round:

| # | Finding (source) | Proposed task | Role | Target |
|---|---|---|---|---|
| E24 | P1.32 CODE-1: the filter's whitespace normalization (`collapse_ws`) makes any benign double-space reply "changed", so `_redact_events` folds the whole reply onto the first `say_chunk` (my probe: `"Hi!  I am here."` → `"Hi! I am here."`, `redacted=false`). Transcript only, length-preserving when a span really bars | Use the filter's `redacted` flag (or a length-preserving mode) to distinguish normalization from redaction | SYS | P2 |
| E25 | P1.32 CODE-2: `PromptBuilder._memory_layer` injects model-authored `memory` facts into the **system** message, and `TranscriptRedactor._redact_messages` deliberately skips system messages — a blocked phrase in a memory row is barred in `field memory` but raw in `prompt[0]`. The redactor's docstring's "every model-text surface" is therefore false | Scan system messages for the transcript (record copy only), or file a DCR that pins the exemption | SYS | P2 |
| E26 | P1.32 CODE-3: a Dictionary-shaped `prompt` bypasses assistant redaction although `TranscriptLogger` documents Array/Dictionary | Walk dictionary prompts or tighten the logger contract | SYS | P2 |
| E27 | P1.32 CODE-4: each transcript scan re-enters `Safety._record` → 5 `redactions.jsonl` entries and 5 `FX.request("glitch")` per record (pre-fix: 2), dev-only | Add a `quiet` scan context (bar without log/FX) | SYS | P2 |
| E28 | P1.08-design-r3 note: `replay_turn` does not reset `_retry_count`/`_current_player_input`, so replaying a zero-`say` record at stage < 3 with `_retry_count == 0` falls into the empty-say retry and calls `_start_turn(_current_player_input)` — a real generation from a replay | Reset both at the top of `replay_turn`, or make the replay path request-free | SYS | P2 |
| E29 | P1.13: `Typewriter._maybe_emit_drained` emits `drained` every idle frame, so `TextBox.all_displayed` fires per frame (consumer is idempotent); `ChatUI.begin_beat` hides the typing indicator before the first `say_chunk` | Latch the drained emission; move the indicator hide to the first token | META | P2 |
| E30 | P1.12: `cue_map.json` heartbeat rows name `.wav`; the committed assets are `.ogg` (works only via `_resolve_src`'s forced extension) | Fix the data | AUD | P2 |
| E31 | P1.20: the committed `2026-11-03_v1.json` stores 9 non-empty `memory_rejects` while the scorer recomputes 6 (30%) — `META_WORDS` was narrowed after the run | Regenerate the results file with the current scorer | QA | P2 |
| E32 | P1.02: the live crash-restart AC has no committed artifact and its CI path is an early-return PASS (`LIVE SKIP`, counted as 0 skipped); the only pasted live run shows 6306 ms | Commit a real restart artifact and make the 5 s bound hardware-qualified, or cover it with a fake-clock unit test | LLM | P2 |
| E33 | P1.08 r3/r4 were reviewed by the implementer's own backend (deepseek), contrary to D7; `track.py`'s drift check compares declared reviewer vs dispatch, not reviewer vs implementer | Add the implementer/reviewer comparison to `track.py`, or record an audited exception mechanism | ENG | P2 |
| E35 | P1.15: the content review's `jsonschema.validate` run is not reproducible (no dependency); the committed pytest validator approximates `propertyNames` | Pin `jsonschema` in `requirements-dev.txt` or drop the claim | QA | P2 |

### 5.3 What must exist before P2 execution (not before this PASS)

- **P2.23 — Date scene controller (F1, S1).** Still unimplemented: no production code calls
  `register_chat_ui` or `submit_player_input`; `Date._on_player_turn_sent` only emits
  `player_turn_submitted` and nothing consumes it; D02's `Goal:` scene layer, events and `[6,14]` end
  rules are never injected (verified: `inject_scene_layer`/`evaluate_turn_end` have no caller). Until this
  lands the shipped date cannot accept a turn and P1.31's refusal release is unreachable.
- **P2.24 — Human 3-stranger playtest round** (D12's owed round; before M2 exit).
- **P2.25 — Merge-hygiene audit** (E22) and the restoration in §5.1.
- **P2.26 — First-beat latency remediation** (D13): schema restructuring/prompt compaction, re-measured on
  CUDA. Note my criterion-3 recomputation agrees with the file's summary: the CPU-host first usable `say`
  is 7.5 s median.
- Plus the playtest's remaining findings: **F2** (opening beats resolved twice — `Date.play_opening_beats`
  calls `SpriteResolver.resolve_beat` **and** `Character.set_feeling`, which resolves again; also
  `AudioDirector.begin_turn()` runs per beat), **F5**, **F6**, **F7**, **F8**, and E24–E35.

### 5.4 Cross-role drift (11 journals read)

1. `LLM.md`'s P1.18 entry still claims the redactor "delegates to `Safety.redact_record()`", which never
   existed; `SYS.md`'s P1.32 entry correctly describes `TranscriptRedactor`. Append-only history, so mark
   the LLM entry superseded rather than rewriting it.
2. `SYS.md`'s P1.08-r3 entry says P1.32 "is still open on main" — true at that commit, stale now. Same
   treatment.
3. No duplicate-utility or signal-naming conflicts: `cvec_path.py` is shared by both launchers, the audio
   import path stays in lockstep with `sanitise_relpath`, and the safety seam is `SaySafetyGate` only
   (the old "`Safety.scan` wired into `ChatUI.text_filter`" note is gone; `Date.gd:80-88` documents the
   pass-through).
4. `Director.gd` is 981/1000 gdlint lines — no longer at the cap, but the convention stands: new Director
   behaviour needs a seam elsewhere.

## 6. Risks and decisions

Proposed `production/RISKS.md` updates (R16/R17/R18/R19/R20 stand; R19 narrows):

- **R19 (M/M, narrowed):** the transcript invariant now holds for `output`, `applied_events` and assistant
  history; the residual raw surface is model-authored memory inside the system message (E25). Dev-only.
- **R21 (new, M/H):** review independence is not machine-checked. P1.08's L-size remediation was re-reviewed
  by the implementer's own backend (D7), and the tracker cannot see it (E33). Evidence quality was high, but
  the control is procedural only.
- **R22 (new, M/H):** phase-gate process drift. Round 2 named two S3 preconditions (handoffs, STATUS render)
  and a P2 promise list; r3 finds the preconditions still open and the P2 list still unticketed. Mitigation:
  make them part of the producer's gate-recording commit and of P2's entry checklist.
- **R23 (new, M/M):** review-evidence provenance remains the recurring weak axis — partial suite counts
  (P1.02), prose-only timings (P1.02), unpinned validator (P1.15), stored-vs-recomputed metrics (P1.20),
  false field claims (P1.21). The playbook lines in §4 target exactly these; enforce them at dispatch.

Decisions for the user/producer: **D3, D4, D5, D8, D9 remain OPEN** (5 rows). **D12 and D13 are recorded**,
but their scheduled work is not ticketed (P2.23/P2.24/P2.26). **D11 stands unchanged** and nothing in this
gate weakens it. The P1.31 docs/02 DCR (an input-refusal row in §4 step 0.1/§7) is still filed but not
accepted in docs — docs-only producer action.

## Verdict

**PASS.** All three round-2 blockers are genuinely closed, and I closed them with my own evidence rather
than the handoffs: B1 by probing the live filter on the gate's own record text and reading the whole-record
test; B2 by the `50/0` diff against the approved blob plus the green three cases; B3 by re-deriving 39/39
duplicated prompts and running the fix's regression test. Round 1's G1 is fixed and pinned (`_reject_unsafe_input`
+ two PASSing tests); G2 has D12.

On this checkout, 32/32 P1 tasks are done, 52/52 final-round review slots say APPROVED, `track.py validate
--strict` is 0/0/0, pytest is 178 passed/1 skipped, `tools/test.sh` is 360/360 over 30 suites with clean lint
and format, the safety corpus is 208/196 with 0 hard-block misses and 0.51% FP, and the prompt lab is
100.0 / 93.3 / 100.0 against the 99/85/85 gates (and 91.7% first-beat fit under the frozen labels, so the
gate does not hinge on the widened set). Criteria 2, 4 and 5 pass; criterion 1 passes in D12's interim sense
with its single broken turn fixed and the human round owed; criterion 3 is an honestly measured miss that
D13 accepts with an owned remediation.

The review audit (27 reports, 52%, all seven safety reviews) found **no S1/S2 left open by a missed review
claim** and no task that this gate re-opens. It did find the recurring weakness the phase has had all along: several
approvals rest on borrowed or partial evidence (P1.02's failed live run, P1.15's uncalled "enforcement",
P1.17's tautological release test, P1.21's false field list, safety r3's no-shell approval, r4's S2-and-APPROVED,
r6's hard-block-rated-S3). Each is recorded above with the checklist line that would have caught it.

Before the producer records this gate and before P2 execution: restore the four handoffs verbatim, run
`track.py render` (E34), and create P2.23/P2.24/P2.25/P2.26 plus the E-list tickets so D12/D13 and the open
findings have owners rather than prose. None of those is an exit criterion and none changes this verdict.
