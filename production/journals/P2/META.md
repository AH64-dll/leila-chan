# META journal — phase P2

## P2.06 — Corruption text filter by stage (2026-11-04, round 1)

- Built the docs/07 §3.4 corruption stage as two files: `game/llm/Corruption.gd` (pure rules — data
  table + docs fallback, gate/plan resolution, seeded RNG derivation, per-word/beat primitives) and
  `game/llm/CorruptionSession.gd` (the word-serial streaming adapter). Table in `game/data/corruption.json`.
- Pipeline placement: ChatUI gained an optional `corruption` seam that runs **after** `text_filter`
  (Safety) and **before** the typewriter, matching `say chunk → Safety.scan → PronounFix →
  Corruption.filter → Typewriter`. Date owns installing it. Do not fold corruption into `text_filter`:
  that Callable is the safety seam (P1.19 CODE-19) and is a pass-through in production.
- Determinism convention: seed = `Corruption.seed_for(turn, beat, effective_stage, salt)` (hash of those
  values), rolled at `begin_beat`; the stream works on complete words and holds the trailing partial word
  until whitespace/`flush`, so chunk boundaries are invisible to the output (tested char-by-char).
  Replays re-derive the seed; no RNG state is stored in the transcript.
- Gates are code rules: data may raise an effect's `gate` but `_normalize` clamps to the docs gate. Chance
  rows are content tuning (the bible only fixes gates). `calmer_max_stage: 3` mirrors docs/02 §8;
  `reduced_motion.disable: [zalgo, bleed]` keeps the textual effects under reduced motion.
- Glyphs: U+0338 slash is the strike-through (U+0336 renders as an offset dash/not at all), U+0300/0301/0308
  are the zalgo marks the Open Sans UI font actually carries, U+0332 is the bleed underline, U+2588 is
  Safety.gd's redaction block. Screenshots in `production/handoffs/media/P2.06/` prove the rendering on
  Linux (Open Sans + system fallback); P5.14/QA should re-check Windows/macOS font stacks.
- Gotchas for the next META task: `String.split("")` splits **per character**, not whitespace (use a RegEx
  for `\s+`); gdUnit hook/test functions count toward gdlint's 20-public-method limit, so merge primitives
  suites instead of adding one-method files; with instant text you must `await` one frame after `end_turn`
  or `get_visible_text()`/the log are still empty (the typewriter reveals in `_process`).
- Next (P2.07 inner leak): reuse `CorruptionSession.transform_beat()` on the already-Safety-scanned leaked
  `inner` text (one-shot, its own beat seed) — do not write a second filter. `path` is accepted by the
  session but unused; P3.04 can gate path-specific effects there.
- P2.09 overlap: ImplP209's telemetry hooks in ChatUI/Date are additive and disjoint from the text path;
  a normal 3-way merge should keep both (producer merges, per P2.25).

## P2.09 — input & window telemetry (round 1, 2026-11-04)

- Built `Telemetry.gd` (autoload #15, last) as the docs/01 §5 "E" seam: seven detectors normalize to
  `{trigger, event, stage_min, line, data, seq, ts}`, go to `Triggers.handle_engine_event()` in real
  time, and queue one docs/08 §6 `EVENT:` line per kind for the next turn.
- Conventions: detection ungated, *reaction* gated by the docs/05 M-row `stage_min` from
  `data/telemetry.json`; one pending line per kind per turn (newest facts win); date-scoped detectors
  except close (M04 is session-wide); deleted draft only in `Telemetry._private_draft`, quoted once at
  stage ≥ 3, then cleared, with the exact words scrubbed from the dev transcript by
  `InputHook.scrub()`.
- Split the docs/02 §4 step-0 policy into `llm/InputHook.gd` (class_name) because Director.gd sits at
  gdlint's 1000-line cap. Fixed the P1.08 bug where `_turn_events.clear()` ran *after* the hooks, so no
  telemetry/trigger line had ever reached `ctx["events"]`; fixed the text-valued `t08_deleted_draft`
  flag that leaked deleted drafts into saves (now boolean).
- Gotcha: never emit `get_tree().root.close_requested` by hand in a test — the engine treats it as a
  real quit request and the run aborts (SIGABRT) in a later test. Assert `is_connected(...)` on the
  seam's handler and call the handler instead.
- Gotcha: `_clear_turn_context()` must NOT clear `_turn_private_terms`; `_start_turn()` calls it right
  after step 0, which erased the terms before the prompt/log. Clear them at submit start, in reset,
  and after `_log_turn_record()`.
- Adding an autoload needs `Boot.EXPECTED_AUTOLOADS` only — `AutoloadRingTest` is data-driven from
  that constant, so it pins the ring without a second list to update. docs/07 §2 still says "14
  autoloads" → DCR in the P2.09 handoff, left for the producer.
- For P2.10: `Triggers.handle_engine_event()` is the matching seam; read the draft with
  `Telemetry.take_private_draft()` before the Director drains it if the trigger layer wants its own
  M21 quote.


## P2.09 — round 2 (2026-11-04)

- Rework: the deleted-draft contract moved to the sender. `InputBox` keeps `_draft_peak` (longest text
  since the last clear) plus `_draft_last`, so hold-backspace reports the whole draft, and
  `_continues_draft()` drops the peak on a wholesale replacement (select-all + type/paste) so a
  replaced draft is never quoted. `Telemetry.take_turn_events()` now emits the M21 quote *instead of*
  the bare fact line at stage ≥ 3.
- Convention: every `EVENT:` line may state only what the detector measured. The repeat row said
  "in a row" for a 3-message window → now "in the last few messages"; keep that discipline when
  P3.09–P3.11 add lines.
- Gotcha: gdUnit prints arrays through `str()`, which escapes inner quotes (`\"hell\"`), so
  `.contains('"hell"')` on `str(array)` is false even when the line is right. Assert on the element
  (`ends_with`/`contains` on `str(lines[0])`) instead.
- Gotcha: `tools/test.sh` needs `godot --import` first on a tree merged with new `class_name` scripts
  (P2.06's `Corruption`/`CorruptionSession`); without it gdUnit discovery fails with
  "Identifier not declared".
- Gotcha: gdformat reflows a wrapped `if (` once the nesting depth changes — run `gdformat` (not just
  `--check`) after de-nesting a block, and re-check before committing.
- Privacy sweeps must fail closed: `_dir_contains()` now asserts the directory exists, so a disabled
  logger can no longer make the "never persisted" test pass vacuously.
