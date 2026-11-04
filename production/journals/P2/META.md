# META journal — phase P2

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
- Adding an autoload needs `Boot.EXPECTED_AUTOLOADS` + `AutoloadRingTest`; docs/07 §2 still says "14
  autoloads" → DCR in the P2.09 handoff, left for the producer.
- For P2.10: `Triggers.handle_engine_event()` is the matching seam; read the draft with
  `Telemetry.take_private_draft()` before the Director drains it if the trigger layer wants its own
  M21 quote.
