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
- Round 2 (reviews CODE-1…7 / SAF-1…11). The rule that fixes the gate and the cache at once:
  **cache the verdict, decide the block at display time.** `remember()` stores `{verdict, category}`;
  `SafetyClassifierGate._block_for()` asks the gate *now*. Never cache a gate-derived permission.
- Cache keys on a streaming path must be built from text that can no longer grow: cut the trailing half
  of the window at the clause break and gate the ask on `settled` (break found, pad full, or beat
  closed). Otherwise one span is asked once per chunk and no answer ever matches its span.
- `flush_hold()` is not a beat boundary. Clear `_pending`, leave `_ctx`/`beat_index` alone; only
  `begin_say`/`end_say`/`end_utterance` own the lifecycle. A mid-beat timeout that resets the beat
  silently rescans the rest at stage 0 with beat -1 (false positives at 4/full, releases dropped).
- SAF-1 lesson: broaden the data, not the code — `stop breathing` was invisible to *both* tiers, and the
  corpus could not see it because 11 of 19 flagged rows were the loader's own probes; the runner now
  prints and asserts the probe overlap (`10 of 27 … 17 independent`).
- SAF-3 lesson: a "no" *releases* the held span, so a steered shared server is a policy bug, not an
  accuracy bug. `Boot` refuses to attach to one; `LEILA_CLASSIFIER_URL` is the explicit opt-in.
- Godot gotchas: `SafetyText.is_clause_break` is an instance method (a static call is a parse error the
  linter does not catch); gdUnit suites cap at 20 public methods, so a second `<Thing>GateTest.gd` is the
  idiom; after `git merge main` run `./tools/godot.sh --headless --path game --import` or every autoload
  fails with "Identifier … not declared".
- The negation guard now lives in `SafetyNegation.gd` (Safety.gd 916 lines) and `Director` routes all
  three say emissions through `_emit_say_chunk()` (1000/1000) — per-file line limits, not raised.

- Round 3 (reviews CODE-8 / SAF-13 / SAF-12). A guard on a *transport* must not be the guard on a *UI hold*:
  900 ms bounds a held beat, but a whole-text scan must live on the transport's own bound (30 s, loader
  floor 12 s = the 10 s read bound + margin) or a slow-but-healthy answer is dropped before it can cache.
- A refusal is not an answer. Never cache an error as the clause's verdict: one flaky read then becomes a
  permanent bar, and a flag false positive can never heal. Bar that display, remember the refused clause
  (category + matched text, NOT the window key — the barred text stays in the display window and is
  re-detected at a new offset) for the rest of the beat so the drain a settle re-enters does not re-ask,
  and clear it when the next beat starts.
- Policy that depends on the *server's launch flags* cannot be a boot-time snapshot of config the app never
  had: `serve.sh --vector` is invisible to the game. Give the gate a Callable that re-reads the live config,
  and attach only where the app can vouch — its own launch (`auto_start`), or an explicit
  `LEILA_CLASSIFIER_URL` that asserts a dedicated unsteered server.
- Lint gotchas this round: `gdlint` caps a file at 1000 lines (the merge left `Director.gd` at 1007, fixed by
  compacting comments, not code) and a function at 6 returns (fold the new check into an existing `return`).
