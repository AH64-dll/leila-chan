# SYS journal — P2

## P2.01 Meters + slow burn (round 1)
- Meter math moved to game/llm/Meters.gd + game/data/meters.json (formula values as data); GameState
  delegates and exposes apply_turn_meters(), which the Director runs at step 7 (ledger on Director).
- Ratchet closure: a peak write now lifts instability to the floor; guards _peak_guard/_restoring stop
  the mutual setters recursing and keep from_dict at one stage_changed. Cross-property setter writes
  DO recurse in GDScript 4.7 — always guard with a bool.
- Artifacts: game/tools/meters_sim.gd + tools/meters/sim.sh/plot.py regenerate the 100-turn CSV/SVG/PNG
  in production/handoffs/media/P2.01; tests/test_meters.py pins the doc values and the curve.
- For P2.02/P2.19: stage bands still in GameState.STAGE_BANDS; apply_turn_meters() is the one per-turn
  entry point and advance_day() returns the landed burn.
## P2.26 — first-beat latency, measured (round 1, 2026-11-04, agent: commandcode)

- Built `tools/llm/latency_breakdown.py`: replays a transcript record's **own** request (messages + schema +
  sampling) against a llama-server and stamps one clock per landmark — headers, first token, first `say`
  character, first character the safety filter releases, turn end — plus the server's `timings`. Committed
  artifacts in `production/handoffs/media/P2.26/`. Convention: latency claims cite an artifact, never prose.
- The measured answer: pre-say **decode** is 72.6 % of the CPU first beat (48 tokens × 88.8 ms) and 76.4 % on
  CUDA (18.5 ms/token). Prefill 15.6 %/10.1 %, safety holdback 11.6 %/12.1 %, HTTP 0.2 %/1.3 %. Shipped order:
  5.92 s on screen (CPU) / 1.16 s (RTX 4050); cold KV: 13.2 s / 1.48 s. Reorder `music, fx, beats, read, inner…`
  → 4.47 s / 0.86 s, which clears the 1.0 s AC on CUDA (DCR-1, pending design review).
- Gotcha that decides every replay: `TranscriptLogger.gd:300` writes with `JSON.stringify`'s default
  `sort_keys=true`, so the stored `schema` is alphabetical and does **not** reproduce the wire request (the wire
  body uses `sort_keys=false`, `LlamaHttpClient.gd:152`). Rebuild the order from docs/02 §3; the control run with
  the sorted copy proves the model follows the *schema* order, not the prompt's ordering sentence.
- Gotcha for any future prompt work: `Safety._holdback` is **34 chars** (`max(_max_phrase+1)`, longest phrase
  "i want to sleep and never wake up"); `tools/test.sh` prints the same line. Any "first visible text" metric
  that omits it under-reports by 0.14 s (CUDA) / 0.69 s (CPU).
- Gotcha: a CPU-only extraction of llama.cpp starts happily with `-ngl 99` and silently decodes at 11 tok/s.
  Check `/proc/<pid>/maps` for `libggml-cuda`; the CUDA 13.4 build (fetched to `tools/llama/llama-b12024-cuda/`,
  gitignored) gives 54 tok/s on the RTX 4050. Do **not** try to fix CPU speed with `-t`: 12 threads on 6 cores
  measured 2.4–6.9× slower.
- Gotcha: the first beat of a session pays the whole 986-token prefill (8.6 s CPU / 0.46 s CUDA); mid-session,
  `prompt_n` spikes to 1298–1449 whenever a **memory fact** lands, because `memories` sits before `rules` and the
  history in docs/08 §1's layout (DCR-2). Metric to watch in future prompt work: `prompt_n` per turn, and the
  longest common prefix between consecutive prompts.
## P2.23 F1 controller wiring — ChatUI registration (round 1, 2026-11-04, agent: commandcode)

- Built: `Date._ready()` now calls `Director.register_chat_ui(chat_ui)` with the rest of its ChatUI wiring
  (`game/scenes/Date.gd:95`), and `Date._exit_tree()` clears it (`:117-125`, identity-guarded so a second
  live date's ChatUI is never unregistered). This makes P1.31's unsafe-input release reachable in the
  shipped scene; the `has_method` guards in Director have a real caller now.
- Convention chosen: the node that instantiates a UI owns its autoload registration, register in `_ready`,
  clear in `_exit_tree`. An autoload-side group lookup would be a second wiring path for one line.
- Test convention: the P1.31 rejection tests no longer register a bare `ChatUI.tscn`; `_new_chat_ui()`
  instantiates `Date.tscn` and returns `date.chat_ui`, so the tests die if the scene wiring is removed.
  Prove it with a mutation (`register_chat_ui` -> `pass`): `DateSceneTest.gd:64` and
  `DirectorFallbackTest.gd:307-308` go red, then the input-lock assertions at `:338-340`.
- Gotcha: `Director.reset()` does NOT clear `chat_ui_node` (deliberate — a restart-date without a scene
  reload must keep the UI). Tests that instantiate a bare ChatUI must still clear it themselves; the Date
  scene now does it via `_exit_tree`, so DateSceneTest/SceneFlowTest need no teardown line.
- Gotcha: never edit `game/` while `tools/test.sh` is running — the first full run here was green but mixed
  code (an edit landed mid-run), so it had to be re-run. gdUnit compiles suites progressively.
- Gotcha: `DirectorTest.test_step_0_input_safety_rejection` rejects with NO UI registered, so adding a
  `push_warning` to the no-UI branch would be a new warning on an intended path; the red-test route is used
  instead. `Director.gd` is 983/1000 gdlint lines — 17 lines of headroom left.
- Next SYS on this seam: the submit half is still missing — nothing in `game/` calls
  `Director.submit_player_input`, and `Date._on_player_turn_sent` only counts. Wire
  `ChatUI.player_turn_sent` -> `submit_player_input` there and move the counter onto `turn_completed`.

## P2.01 Meters + slow burn (round 2)
- DES-1: the docs/01 §3 bands are instability values, so they shade the Instability panel's y axis
  (full-width stripes, labelled with the range); the strip above is now the CSV's own stage per turn
  (`stage_runs()`), and the crossings are captioned with turn/day. Mismatched axes were the whole bug —
  name the axis in the docstring before drawing anything on it.
- Gotcha: the doc band table is integer ranges (0-14, 15-29, ...), so a continuous stripe must run from
  a band's floor to the *next* band's floor (0-15-30-50-70-90-100) or a 1-value seam shows up.
- Test convention: `tests/test_meters.py` renders the SVG from the committed CSV and parses the `<rect>`s
  (render + assert geometry, not the drawing code). Sorting by y is required — the SVG emits S0 first.
  Mutation-checked: it fails on the round-1 plot with `0 == 6`.
- Gotcha: this worktree's NTFS mount has `core.filemode=false`, so `chmod +x` never reaches the index;
  use `git update-index --chmod=+x <path>` and verify with `git ls-files -s`.
- DES-3: `Meters._merge_into()` now takes an `origin` label (the loader passes TABLE_PATH), so a
  synthetic-table warning no longer blames res://data/meters.json.
- Merge gotcha: the SYS journal is append-only across tasks, so a `git merge main` after another SYS task
  hits an add/add conflict — keep both sections, then re-commit.
## P2.26 — first-beat latency, round 2 (2026-11-04, agent: commandcode)

- Fixed the harness, not the investigation: `--system-order` was matching `\n` against CRLF prompts (0/39
  patched, silently), `say` parsing closed on an escaped `\"`, and `visible_ms` counted the safety holdback in
  **raw** characters while `Safety._drain` holds the **compact** view. `run_turn` is now tested against a stub
  SSE server (split key, short say, escaped quote, dead server) — that blind spot is why two of the three bugs
  survived round 1.
- Convention: a measurement tool that models a game subsystem must **mirror** it and pin the mirror's tables
  with a test (the Python `SafetyText` copy is pinned to `SafetyText.gd`'s separator/leet tables, and the
  holdback to `filter_lists.json`). Approximation + a comment is how the raw-vs-compact bug happened.
- Gotcha that cost an hour: the CUDA tarball needs `LD_LIBRARY_PATH` for **both** `llama-b12024/` (libggml-cuda)
  and `cudart-…-cuda-13.4-x64/` (libcudart/libcublas). Without it `-ngl 99` starts fine, logs nothing fatal and
  decodes at 11 tok/s; the only tell is `grep -c libggml-cuda /proc/<pid>/maps` (0) and
  `predicted_per_second`. The first "GPU" artifact set of this round was really CPU and was thrown away.
- Gotcha: switching the schema order invalidates the server's KV prefix, so turn 0 of a variant is cold unless
  you replay that same variant's turn 0 once first. Warm every variant or its median is polluted by one ~11 s
  (CPU) / ~1.5 s (CUDA) row.
- Measured cache rule (b12024, `cache_prompt=true`): reuse stops at the prefix *before* the change, and the
  granularity is coarse — a one-char change deep in the system message reuses 0 tokens, near its end 721 of
  1237, a change appended to the last user message 1211 of 1237. Layout does matter; `prompt_n` per turn is the
  metric to watch in any future prompt work.
- Corrected headline: shipped order 6036.5 ms CPU / **1157.5 ms CUDA** on screen; DCR-1 order 4571 / **909 ms**
  (median clears the 1.0 s AC, p95 1431 does not — one pretty-printed turn, now DCR-1's compact-JSON clause).
- Next SYS on this seam: DCR-1/DCR-2 decisions; if DCR-1 ships, `tools/promptlab/run.py --order` already sends
  the candidate order and a test forces the lab's copy to follow `TurnSchema.gd`.

## P2.11 — memory model (round 1, 2026-11-04, agent: commandcode)

- Built `llm/MemoryStore.gd` (24 true-fact slots, importance, eviction, seeded per-injection corruption), grew
  `MemoryRules.gd` into the rule/reason + corruption model and made the `Memory` autoload the single owner
  (Director's `var memories` is gone). Every tunable lives in `data/memory.json`; the docs fallback is pinned equal.
- A rejection returns a *reason* (`meta_word|ungrounded|duplicate|…`), and `report()` → the transcript's new
  `memory` field logs corruption + the proposal. A field missing from `TranscriptLogger.OPTIONAL_FIELDS` is
  dropped silently, so that round trip is a test, not a hope.
- Gotcha: `false_promise` keeps the original as a prefix — assert the whole `- ` bullet line, not a substring, or
  "the true fact is not in the prompt" passes green on a corrupted prompt. `Director.gd` was 987/1000 lines, so
  `spoken_text()` went to `TurnContext`.
- Next SYS on this seam: P2.20 must save `Memory.to_dict()` (seed **and** rng state) or a reload re-rolls
  corruption from a different point; the seed is fixed at 0 today so replays and tests are identical.


## P2.02 — stage machine 0–5 + diegetic transition (2026-11-04, agent: commandcode)

- Built `game/llm/Stages.gd` + `game/data/stages.json` (bands, names, transition, EVENT lines). `GameState`
  emits `stage_transition(previous, current, spec)` from ONE place (`_refresh_stage`, guard `band > stage`) and
  queues one docs/08 §6 line in `pending_events`; the Director drains it into the *next* prompt. `STAGE_BANDS`/
  `STAGE_MAX` consts are gone — thresholds are data now (a `const` cannot be JSON), so call `Stages.bands()` /
  `Stages.max_stage()`. Convention: a restore is not a crossing (from_dict still re-emits `stage_changed` for
  resync but no transition and no line), and one write that jumps two bands is ONE event with the full pair.
- The stage invariant I now test everywhere: `stage == Stages.for_instability(instability_peak)` at all times —
  peaks only rise, stage never falls, so the peak's band IS the stage. Cheap to assert in any sim; it caught
  nothing here but pins the peak→stage coupling.
- Gotcha: `Director.gd` sits at gdlint's 1000-line cap (was 987; now 992). Pipeline state that looks like it
  belongs there (`last_stage_transition`) must live on `GameState` or the lint fails. Split before adding.
- Gotcha: `_turn_events.clear()` used to run AFTER `_handle_input_telemetry`, so any trigger hook's lines were
  wiped before the prompt was built (latent P2.08 bug); the clear now runs before the hook, drain after it.
- Gotcha: gdUnit4 test helpers built on an untyped state handle break `:=` inference (`var drained :=
  s.take_pending_events()` → parse error); annotate the type. And `Array(Dictionary)` is not a constructor —
  `assert_dict(x).is_empty()`.

## P2.11 — memory model (round 2, 2026-11-04, agent: commandcode)

- Fixed both S2s and the design S2: `eviction_index(entries, skip)` excludes the slot just appended (a
  fully-quoted store kept "accepting" and discarding facts — contract error), `_append_promise()` no longer
  skips on length (`max_length` caps the model's proposal, not the prompt bullet; realized stage-5 rate went
  0.054 → 0.258 against the declared 0.250), and `_swap_name()` only targets mid-sentence non-stop-word
  capitals (`My brother is called Ren` no longer becomes `Rin brother …`).
- Convention worth keeping: one `Memory.begin_turn()` clears the whole per-turn record (corruptions, quotes,
  proposal). Clearing field-by-field is what made `memory.proposal` describe the previous turn on refusals,
  failures and `"memory": ""` turns. Called at `_start_turn` and before the refusal's `_log_turn_record`.
- Convention: untrusted save input is clamped, not adopted — `from_dict()` pins capacity to docs/02 §6's 24.
  A save-carried capacity as a difficulty setting needs a DCR, not a comment.
- Gotcha: gdlint caps a class at 20 public methods, so a gdUnit4 suite with `before_test`/`after_test` can
  hold only 18 tests. The memory suite is now `MemoryTest` (rules/prompt) + `MemoryStoreTest` (store/
  corruption), with `game/tests/helpers/MemoryFixtures.gd` for the shared fixtures — helpers MUST live in a
  subdir or `tools/test.sh` runs them as standalone scripts.
- Gotcha: `String(x)` with an int Variant is a runtime error ("Nonexistent 'String' constructor") — use
  `str(x)` at any untyped boundary. gdUnit4 string asserts are `starts_with`/`ends_with`; `begins_with`
  does not exist on the assert object.
- Gotcha: `Director.gd` is at exactly 1000/1000 gdlint lines on this branch; every added line must be paid
  for elsewhere (the round-2 `Memory.begin_turn()` calls are one line each, comments included).

## P2.08 — triggers engine (round 1, 2026-11-04, agent: deepseek)

- Built `llm/TriggerEngine.gd` (pure: detectors, caps, effect scaling) + `data/triggers.json` (strength /
  defaults / rows) + the `Triggers` autoload seam. `InputHook` calls `Triggers.begin_turn()`; the M detector
  subscribes to `Director.turn_completed` because Director is at gdlint's 1000-line cap (zero pipeline diff).
- Convention: the docs/02 §1.2 agreement rule is a data table, never an `if` — `strength.agreement` vs
  `strength.model`, plus a row-level `requires: any|all`. `strength.keyword` stays 1.0 because docs/01 §5
  has K-only rows (T02/T03/T06/T07…); halving keyword evidence later is a data edit (`"keyword": 0.5`).
- The placement rule that decides every firing point: a trigger fires where its LAST evidence exists. K/E/C
  at step 0 → line rides this turn; M only at close → line queues for the next prompt; a `requires: all`
  row with a keyword hit therefore defers to close, since agreement is what is being decided.
- Gotcha: `_matched` must be MERGED in `begin_turn`, not overwritten — an idle/focus event that fired
  earlier in the same turn would otherwise be erased before a `requires: all` row could consult it.
- Gotcha: `_turn` is the engine's only clock. `GameState.turn` is N−1 at step 0 and N at close, so the
  autoload passes `turn+1` for begin/events and `turn` for close; any new entry point must match or every
  cooldown shifts by one.
- Gotcha: pass `flags` as a `duplicate(true)` snapshot. With the live dict, a row that sets a flag changed
  what a later row's clock detector saw *inside the same evaluation* (order-dependent firing).
- For P2.10: rows only in `data/triggers.json`; `tests/test_triggers.py` rejects an unknown read label /
  meter / counter / path, a `requires: all` row with one detector, a line without a `TRIGGER: ` prefix or an
  unknown `{token}`, and a stage gate that disagrees with `data/telemetry.json`.
- For P2.20: `Triggers.to_dict()/from_dict()` must ride the save payload or every reload re-arms the
  "once" rows and wipes cooldowns. `set_last_seen()` is the T17/T18 seam (P3.07) and nothing writes it yet.

## P2.08 — triggers engine (round 2, 2026-11-04, agent: deepseek)

- Rework: `requires: "all"` is now a real AND (`_all_sources()`: every declared NON-model detector — the
  model is the detector `close_turn()` is deciding). All three entry points use it, `handle_event()`
  included, so an event cannot jump a clock gate; the K+C row fires only when both agree.
- New axis: `escalate.axis` = `step` (default, per firing, stopped after max_steps firings) or `stage`
  (the stage since stage_min, capped at max_steps STEPS, repeating — only the cooldown gates it). One
  helper `_escalation_step()` feeds both the strength and the per-step line array so they cannot drift.
- Gotcha: on the stage axis do NOT keep `_eligible()`'s `count >= max_steps` firing cap — early firings at
  a low stage would burn the row before the stage could rise, which is the opposite of the T08 clause.
- Gotcha: `_escalation_step()` must return the plain `step` for non-escalating rows, or a `repeatable`
  row's line array stops advancing at `max_steps`.
- Testing lesson: the M and C seams are only reachable through the autoload — drive
  `Director.turn_completed.emit()` and `set_clock()`/`set_last_seen()`, read `report()["counts"]`, and
  remember `GameState.turn` must be the CLOSED turn at the emit (Director advances it in
  `apply_turn_meters()` before the signal). A fixed anchor second + the machine's TZ bias gives a
  deterministic local-hour window.
- Suite is at gdlint's 20-public-method cap (`before_test` counts as public): fold a new case into an
  existing one rather than raising the project limit.
## P2.12 — fracture paths (round 1, 2026-11-04, agent: deepseek)

- Built `llm/Paths.gd` + `data/paths.json` (six formulas, Stage-2/Stage-3 pair, recency tie-break,
  `parse_document` fallback) and `llm/ProfileKeywords.gd` + `data/profile_keywords.json` (control, apathy
  incl. short replies, flattery_rejected, ignored_questions). `GameState.apply_turn_profile(read, line,
  turn_data)` replaced `apply_read` and is now the one per-turn entry: read map → keyword bumps → path
  check; it returns the decision dict.
- Convention: §4's three formula counters (`broken_promises`, `flattery_rejected`, `ignored_questions`)
  live in the same 15-key profile as §2's twelve tags; `Paths.counters()` is the only list, and the read
  map may only write §2 tags. `broken_promises` is engine-fed (I15) — never give it a keyword rule.
- Convention: the lock fires inside `_refresh_stage`, so a Stage-3 crossing (night roll-over, trigger
  spike) freezes the path *before* that turn's read is applied; the turn close re-evaluates only for
  Stage-2 drift. The runner-up is recomputed after the assignment and excludes the LIVE primary.
- Gotcha: computing the runner-up straight from `Paths.select()` lets a locked path become its own
  runner-up (the score winner can differ from the frozen path); compute it after `assign_path` against
  `GameState.path`. The Stage-3 save round-trip test is what caught it.
- Gotcha: GameState and Director both sit at exactly 20 public methods / 1000 lines. A rename keeps the
  method count; the read block replacement (4 lines → 3) paid for the replay's `_current_player_input`.
- Next SYS on this seam: P2.19 gets assign/lock free via `_refresh_stage`; P2.20 must save
  `path_scores`/`path_evidence`/`path_runner_up`/`last_question`; P2.10 bumps T15/I15 counters.

## P2.12 — fracture paths (round 2, 2026-11-04, agent: deepseek)

- Reworked the keyword half only: `_is_apathy()` now runs the `?` check first, gates a dismissal phrase on
  `dismissal_max_words` (new data cap, 6 — a dismissal is the *message*), and takes `awaiting_answer` so a
  terse reply to her pending question is an answer. Exemptions go through `_has_any()`, so "I'm sorry" is
  exempt and "nothing"/"him" are not.
- Convention: every keyword predicate answers "is this the *message's* behaviour?" — the r1 bug was scoring
  a word inside an engaged sentence. If a future counter needs sub-message structure, put the phrasing in the
  data file, not in a bigger predicate.
- Convention: `ignored_questions` is now nested under the dismissal in `classify()` — T15 can only fire when
  the apathy rule fired *and* a question was pending, which keeps the two counters from drifting apart.
- Gotcha: `tests/test_paths.py::test_keyword_rules_are_string_lists` walks every key in a rule block and
  treats non-`short_reply_words` values as phrase lists — a new integer knob there fails the pytest suite,
  not gdUnit. Add the key to that test when you add a cap.
- Gotcha: a short line can be a dismissal or an answer; only `last_question` tells them apart, and
  `GameState.apply_turn_profile` passes the *previous* turn's question, so a test must ask in turn N-1 to
  exercise the answer path.
- Next SYS on this seam: `dismissal_max_words` is the tuning knob (raise it if engaged lines slip through;
  add a phrase if dismissals are missed). "Whatever, I love you." still scores apathy by design.

## P2.20 — saves v1 (round 1, 2026-11-04, agent: deepseek)

- Built `llm/SaveSlots.gd` (slot → path, the `leila.save` envelope: format/version/sha256 of the canonical
  payload, tmp+rename write, tolerant listing) and filled the `SaveSystem` autoload (capture/apply, the log
  seam, per-scene autosave, Title `Continue`). Files: `user://saves/slot_1..3.json` + `autosave.json`; the
  autosave has its own id "auto" because docs/07 §3.5 only names `slot_N`.
- Convention: a corrupt save is a value `{ok, error, message}` and the live game is never touched. Validation
  runs first; `GameState.from_dict()` refuses before mutating, so it is applied first, then
  `Director.reset()` + `Memory.from_dict`. Nothing in a load path may call `String()`/`int()` on a Variant:
  P2.11's `MemoryStore.from_dict` died on `String(7)` from a corrupt slot; the store's guard is now total.
- Gotcha: the memory rng `seed` and `state` are 64-bit, and JSON numbers are doubles — they cross the file as
  decimal strings and `SaveSystem._memory_data` parses them back. The test seeds past 2^53 to prove it.
- Convention: the log seam mirrors the ChatUI registration (the scene owns it, `_exit_tree` clears it,
  identity-guarded). A load with no live log keeps `_pending_log` and hands it to the first sink; the prompt
  history is rebuilt from the *displayed* log (docs/08 §1), never from raw turn JSON, so a save cannot carry
  text Safety held back.
- Gotcha: `Date._ready` must `_resume_from_save()` BEFORE `load_scenario(scenario_path)`, or a save from a
  non-default scenario reloads the default one and the saved scenario is silently ignored.
- Autosave is skipped when `DisplayServer.get_name() == "headless"` (a headless build has no player); tests
  opt in by setting `autosave_enabled` and a scratch `save_dir`. Editor playtests therefore do not autosave
  unless a task flips the flag.
- Next SYS: P2.19's Night scene should call `SaveSystem.autosave("night", {…})`; P3.12's shadow save is
  `user://.leila/shadow.json`, deliberately outside these slots and outside `wipe()`.

## P2.20 — saves v1 (round 2, 2026-11-04, agent: deepseek)

- CODE-1: never autosave synchronously from `turn_displayed`. `ChatUI.end_turn()` → `TextBox.end_turn()`
  emits `all_displayed` when the writer is already drained, so the handler runs *inside*
  `Director._close_turn_success` while `_turn_in_flight` is still true and every save answers "busy".
  `Date` now calls `_autosave_scene.call_deferred("after turn")` — one idle frame is the whole fix.
- Convention: a save refusal is a returned value, so every call site reads it. `Date._autosave_scene(reason)`
  stays silent on `disabled` (headless/tool runs) and `push_warning`s anything else; don't leave
  `SaveSystem.autosave(...)` bare.
- Convention (tests): `GatedLLMBackend` streams its chunks, then parks until `release = true` — the way to
  hold a Director turn in flight while the typewriter drains, with no sleeps.
  `FakeLLMBackend.block_until_cancel` cannot (it parks by cancelling). Restore `LLM.set_backend(previous)`
  in `after_test` or the next suite inherits the fake.
- CODE-2: a resumed date skips her greeting only when the restored log carries it (`_resumed =
  chat_log.entry_count() > 0`). The scene-entry autosave lands before the opening beats reach the ChatLog.
- Gate green: 634 tests / 53 suites. `FXHostTest.test_twitch_fires_chromatic_split` flakes under machine
  load (shader-uniform sample after a wall-clock wait); it passes alone and is untouched by save work.

## P2.10 — triggers T01–T15 + the M01 close intercept (round 1, 2026-11-04, agent: commandcode)

- Built the 15 rows in `game/data/triggers.json` (T01–T07 and T13–T15 new; effects added to T08–T12) plus two data-driven engine extensions: a `guard` block for conditions that must hold but are **not** detection letters (T03's "before Day 3"), and **guard-only rows** whose evidence is the game's own check. T13 = `MemoryRules.contradiction()` against the *true* memory facts; T15 = this turn's `ignored_questions` bump (Triggers snapshots `GameState.profile` at begin_turn, injects the delta at close).
- Convention: a guard firing is full strength — docs/02 §1.2's halving is about *disagreement* between keyword and model evidence, and a guard row has no model claim to halve. `_base_strength()` now maps agreement→strength-key through a const table (gdlint caps 6 returns per function).
- Convention: line templates may use `{fact}`, and the guard injects the value; E rows still leave `line` empty because Telemetry speaks those.
- The close intercept lives in `MetaDirector` (the docs/05 owner) and *takes over* `auto_accept_quit`, but only after connecting its handler. Gate from `Triggers.stage_min_of("T10")`, offer sentence from `data/stage_gates.json` → `gates.opportunities.refuse_exit` (via `TurnSchema.opportunity_line`), quit through an injected Callable so a scripted close never ends a test run.
- Gotcha: handler ordering on `root.close_requested` does not matter — the intercept decides from its own once-per-session flag, not from T10's count, so Telemetry's listener can run before or after it.
- Gotcha: `GameState.set_meter(&"instability", 55)` queues the stage-transition EVENT line, so a test counting `pending_events` must count its own line (`count(line)`), never the queue size.
- Gotcha: `TriggerEngine.gd` sits at 999/1000 gdlint lines — every added line needs a deletion; the new guard docs are already compressed, so split the class (e.g. a `TriggerTable` loader) before adding more vocabulary.
- Two merged tests changed with the data, by design: `TriggersTest.test_to_dict_from_dict_round_trip` asserted "nothing fires" on "I love you" (T03 now does, so it asserts T68 is absent) and `TelemetryTest` asserted `auto_accept_quit` is true (P2.10 takes the quit path; M01's own tests are in `TriggersT09T15Test`).

## P2.10 — triggers T01–T15 + the M01 close intercept (round 2, 2026-11-04, agent: commandcode)

- Rework is data + one small vocabulary item, not a redesign: T02's farewell is `see you (later|soon|tomorrow|tonight|around)`, `grace` left T01's name list, and T13 needs two content words **inside the clause a denial cue governs** (`MemoryRules._negated_clauses()`), with statement-denial cues only — "I don't like that music" is an opinion, not a lie.
- New row field `observe` (flat `{flag: value}`): the game records it the moment the row's own evidence matches, before guard/caps/cooldown. That is how T03's confession flag reaches T04 on Day 3–9 while T03's `day_lte: 2` reaction stays. Gotcha: `_observe()` must also write the *ctx* flags copy — rows run in catalogue order, so T03's write is what makes T04's `flag_absent` stand down in the same `begin_turn` (otherwise a Day-12 confession still ships "never said it").
- DES-2: a memory entry now carries `source`, the player message `MemoryRules.grounding_input()` grounded it in; T13's `{fact}` renders that, never her paraphrase. `MemoryStore` entries gained a fourth key, `from_dict` tolerates old saves without it, and `SaveSystemTest`'s round trip passes unchanged.
- DES-4: `MetaDirector.offers()` re-queues the OPPORTUNITY sentence while the offer is open — the event queue drains once per submit, and an enum without its `why` is docs/02 §2.4 violated. Dedupe is `GameState.queue_event`'s.
- DES-1/DES-3 went the DCR way and are applied to docs/01 §5 (T01's clause, T09/T12's numbers) — the design reviewer explicitly allowed either implementing or filing the DCR; "until answered" has no resolution signal in the design, and a mention and an answer are the same keyword set.
- Gotcha: `TriggerEngine.gd` is at exactly 1000/1000 gdlint lines again. `observe` was paid for by deleting `GUARD_KEYS`, `GUARD_CLOCK_KEYS`, `DETECTORS`, `EFFECT_GROUPS` and inlining `_needs_model()`. Split the loader/parser into a `TriggerTable` before the next vocabulary addition — no more pay-as-you-go.
- Test convention worth keeping: every false positive a reviewer probes becomes a *negative* case in the same suite that owns the row (`test_t01_another_girl_name`, `test_t02_goodbye_begs_you_to_stay`, `test_t13_needs_a_denial_and_a_shared_fact`), plus a re-read of the data file in `tests/test_triggers.py` so the contract holds without a Godot build.

## P2.19 — day/night loop + night screen (round 1, 2026-11-04, agent: commandcode)

- Built `llm/NightLoop.gd` (the night as a four-step ordered report: meters → stage → path → event),
  `llm/OvernightEvents.gd` + `data/night.json` (N01/N12, availability, weighted seeded pick, per-stage
  lines), `llm/Campaign.gd` (day clock + `begin_day`/`next_scenario`), and `scenes/Night.tscn` +
  `Night.gd` (the screen, its data-driven timeline, the next-day autosave and the loop's route).
- The steps re-implement nothing: `advance_day()` owns the burn, the meter write owns the band crossing
  (`_refresh_stage`), and that crossing owns the Stage-2 assign / Stage-3 lock. NightLoop sequences them,
  asserts the invariants (`stage == for(peak)`, `stage ≥ lock ⇒ locked`) and reports before/after, so
  "in order" is observable in the report instead of asserted in prose.
- Convention: the night's path check is `GameState.apply_turn_profile(&"", "")`, and GameState now treats
  "no player line AND no turn data" as not-a-turn — the empty reply used to clear `last_question` (T15's
  echo) every single night. A real turn always carries turn data, so the condition cannot misfire.
- Convention: availability is ONE predicate (`ScenarioLoader.is_available`) shared by scenarios and
  overnight rows; `available.paths` ("any" or a list of the six ids) is validated in `_validate_available`
  too, so a pool row with a bogus block is skipped at load instead of silently never matching.
- Time/determinism: the night screen's clock is `advance_time(delta)` (`_process` forwards frames, tests
  step it); the event draw is seeded from `flags.campaign_seed` + the day; the skip window is data and
  N12's `skip_after_s: null` is the documented "the ten seconds ARE the event".
- Gotcha: `GameState.get_flag(x, fallback)` returns the FALLBACK after `clear_flag` erased the key —
  assert a consumed queue with `flags.has(x)`, never `get_flag(x, "")`.
- Next SYS on this seam: P3.16 replaces Night.gd's `AFTER_CAMPAIGN_SCENE_PATH` (Title today) with the
  ending scene and consumes `campaign_completed`; FX has no host registered during the night, so a
  stage crossing at night reports its spec + queues the EVENT line but has no visible glitch yet.

## P2.19 — day/night loop + night screen (round 2, 2026-11-04, agent: deepseek)

- Rework r2: a day is a DATE only — `Campaign._pick`/`_row_for_path` filter `kind == "date"`. The
  merged P2.18 pool puts I01 in the same directory, and without the filter seed 0 made day 1 the
  phone call. Availability ("may this run today?") is not kind ("may this be today?"): keep them
  separate, the kind filter is the campaign's.
- Bookkeeping convention: every hand-off marks its pick played where it is *made* — `next_scenario`
  marks the queued date, `begin_day` marks what it opens, and `Campaign.resume_day` reconciles a
  save-named date (consume queue + mark date; a non-date save consumes the queue but is never
  marked). A save taken at any point then agrees with the campaign without replaying begin_day.
- Input gotcha: a full-rect Control/ColorRect defaults to MOUSE_FILTER_STOP and eats the click before
  `_unhandled_input`. Click-to-skip needs `mouse_filter = 2` on both, and the only honest test is
  `get_viewport().push_input(...)` — calling `skip()` directly cannot catch it.
- DES-2: hide the night chrome (day/night labels) while a `kind: "black"` event plays; restore it in
  `_show_morning`. N12 is "nothing", and a "Day 2 / Night" frame is not nothing.
- Interrupt injection (P2.18's handoff) and the doc's "or trigger" scene end are deferred to
  P5.02/P5.06, named in the handoff follow-ups. Do not run an interrupt as a day in the meantime.

## P2.10 — triggers T01–T15 + the M01 close intercept (round 3, 2026-11-04, agent: commandcode)

- CODE-9/DES-5: `MetaDirector._close_offer()` erases `_opportunity_line()` from `GameState.pending_events`. `offers()` queues the sentence for the *next* submit (the queue drains before `offers()` runs), so nothing was removing the copy queued on the turn the model accepted — the turn after a refusal said "you may set action to refuse_exit" with an enum of `["none"]`. `reset_session()` goes through the same door, so a new session cannot inherit it either.
- Gotcha for the suite: the old case drained at both `take_pending_events()` calls before consuming, so its `not_contains` ran against an empty queue and could never fail. The case now consumes with the line still queued, and separately re-holds, then resets — both assertions fail without the erase (l. 274 and 281), which is the only evidence that a test pins a fix.
- CODE-10: `Triggers._context()`'s flags comment said a fire must not change what a later row's clock detector sees — the opposite of the `observe` contract it now documents. It says the copy isolates *fired effects*, `observe` is the one deliberate same-turn write, and catalogue order (T03 → T04) is what stands T04 down inside one `begin_turn()`. `TriggerEngine._observe()`'s inline note names that order; the file stays at 1000/1000 gdlint lines.
- Gate green: 791 cases / 65 suites (the merged main added P2.19/P2.25/P2.26 suites), 496 pytest. No data or docs change this round: docs/05 §2's "only on turns with an offer" was already the contract, the code was the thing that disagreed.
