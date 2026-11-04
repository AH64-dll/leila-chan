# P2 — Safety & Compliance Officer (SAFE) journal

## 2026-11-04 — P2.17 Safety filter v1 (classifier pass)

- Built the tier-2/filter-v1 stack: `data/safety/classifier.json` (flag regexes, yes/no prompt,
  probes), `SafetyClassifier` (load/validate, flag match, prompt builder, answer parse, verdict
  cache, counters), `SafetyClassifierGate` (the hold: one in-flight request, cached-verdict
  application, cut guard, quiet whole-text resolve), `SafetyClassifierHttp` (worker-thread llama-server
  transport, no vectors bound = dose 0), and `SafetyRedactionLog` (extracted from `Safety.gd` for
  gdlint's 1000-line cap; `Safety.redaction_log` is a getter now).
- Policy that must not drift: a flag is a QUESTION, never a block. Tier 1 lists stay unconditional;
  a yes verdict on a hard category blocks at every stage, a yes on `self_harm_her`/`threat_to_player`
  only blocks while `_gate_open()` is false, and **no backend / transport error / unparseable answer /
  hold timeout all bar the span** (fail closed). The classifier can only add a block, never remove one.
- The bug that cost the round: the verdict cache keyed on `(category, matched span)` made
  `i know how to use a knife.` and `i know how to use a knife and fork.` share one verdict. Cache on
  the **judged clause window** (`_context_around(view, s, e)`, 80 chars each side) and tag it in the
  gate, not in `Safety` — one key computed in one place, or `matched()` and `_issue()` disagree and the
  gate re-asks forever.
- Streaming seam: hold only the flagged tail; the prefix types. A verdict after the beat closes is
  emitted on `Safety.hold_released(beat_index, text)` — so the beat ctx MUST carry `beat_index`
  (Director `begin_beat`), and the Director routes the late text to that beat. Undelivered verdicts bar
  the pending tail at the next `begin_say`/`end_utterance` (fail closed), and the in-flight request still
  lands in the cache for tuning.
- Godot gotchas: `JSON.parse_string` hands back floats for integral numbers in this build, so numeric
  limits need an `_as_int` that accepts int/integral float/numeric string (same pattern as
  `_valid_version`); `ready()` must check `beat_closed` BEFORE the buffer-end test, or a match ending on
  the beat's last character never gets asked; a RefCounted gate may `call_deferred` from a worker thread,
  and `_drain` must be re-entrancy-safe because a synchronous backend answers inside `pump()`.
- Corpus 451 rows (237 harmful / 214 benign), 39 dose-10/12 rows, 0 hard-block misses, 0.47% FP
  (`retard`-verb only), 0 stream divergences. Latency: transport 3.4 ms avg localhost round trip
  (thread + HTTP + 8 tokens, model decode excluded); main-thread scan+oracle 1.5 ms avg / 2.5 ms worst
  per flagged row; streaming hold 56–60 ms against a 25 ms/frame server. Prototype limit: one llama
  slot serializes the request behind the turn, so a held tail usually bars at the boundary — set
  `LEILA_CLASSIFIER_URL` to a dedicated unsteered server for the live pass.
- Also closed the P1.19 ledger: `doesn't/doesnt/haven't/havent/hadn't/hadnt` negation terms, the
  contracted-perfect auxiliaries (`i've killed you`, `we've killed you`, `i'm killing you`), and a
  `murder` arm (`i murdered you`). `Safety.gd` is now at 998/1000 lines — next SAFE task should move
  the negation guard into its own class instead of raising `max-file-lines`.
