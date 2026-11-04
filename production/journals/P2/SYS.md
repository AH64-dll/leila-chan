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

- Built: `game/llm/MemoryStore.gd` owns the 24 slots (true facts only); `MemoryRules.gd` grew the three-rule
  reason ladder, importance/eviction and the 10–25 % corruption band; the `Memory` autoload is now the single
  owner (Director's `var memories: Array[String]` is gone), so prompt, save (P2.20) and transcript read one list.
- Convention: a rejected proposal returns a *reason* (`empty|too_long|no_content|meta_word|ungrounded|duplicate`),
  not just `false`. `store.last_proposal` and `report()` push it into the transcript's new `memory` field.
  A field `TranscriptLogger.OPTIONAL_FIELDS` does not list is dropped silently, so the round trip is tested.
- Corruption is a display lie: applied per injection (`prompt_facts`) to what she reads, never to the store, so
  the true fact survives and she can be wrong on one turn and right on the next. Chance per fact is stage
  3/4/5 = 0.10/0.175/0.25 from `data/memory.json`, clamped in code to the doc's 0.10–0.25 band.
- Gotcha: the `false_promise` kind keeps the original as a prefix, so "the true fact is not in the prompt" as a
  substring check stays green on a corrupted prompt. Assert on the whole memory bullet line (`PromptBuilder.
  MEMORY_BULLET + text`). That assertion caught the bug the first time it ran.
- Gotcha: `_same()` in a suite hits gdlint `max-returns: 6`; split the dictionary/array halves out. Also
  `Director.gd` was 987/1000 lines — `spoken_text()` went to `TurnContext` to stay under the cap.
- Next SYS on this seam: P2.20 must save `Memory.to_dict()` (seed + rng state) or a reloaded save re-rolls
  corruption from a different point; the seed is still fixed at 0 so replays and tests are identical.

