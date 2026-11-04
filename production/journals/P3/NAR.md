## P3.02 — Contrastive pair sets (round 1)

- Six JSONL sets in `tools/steering/pairs/` (`possessive`, `unstable`, `contempt`, `hollow`, `aware`, `lucid`), 200 pairs each. One shared 200-line context bank: 20 everyday topics × 10 player lines, identical order in every file; `positive` is the trait side for all six (ANCHOR applies the lucid vector at a negative scale, docs/06 §2).
- Composition: per topic/trait I wrote 3 contrastive suffix pairs over a shared echo prefix, then rotated them 2–4 times per topic so side totals stay close. Pair word difference: max 2, mean 0.93 words; side totals differ by ≤6.5% (aware is the widest). The shared prefix cancels inside each pair, so the difference is the trait clause, not the topic.
- Gotcha: padding the shorter side with generic tails (`I really mean it.`, `That's all.`) reads as a non-sequitur and pollutes the negative side. I tried it, then rebuilt from a clean source and trimmed the longer side instead. Never pad with filler.
- Gotcha: every suffix must fit every context in its topic. Exam-specific or movie-specific suffixes broke as soon as the assignment rotated; write to the topic core and let the echo carry the specific situation.
- `unstable` deliberately uses 4–6 very short clauses in some positives (the SPLIT rapid shift). Non-unstable replies stay ≤4 short sentences; all are extraction stimuli, not shipped `say` beats.
- Verification: `tests/test_contrastive_pairs.py` (19 tests: shape, shared bank, topic balance, duplicates, length parity, sensitivity with a dirty-data control, brand/sexual/self-harm scans, asterisks, manifest); full `python3 -m pytest tests/` = 370 passed, 3 skipped.

## P3.02 — Contrastive pair sets (round 2)

- Rewrote all 1,200 records: one clause per context instead of 60 rotated over 200. `effective_unique` is 200 per set, recorded in `manifest.duplication.effective_unique_per_file` and asserted by a test that strips the echo.
- Convention: both replies open with the same short echo sentence; the tail is authored for that one context. The echo must never reappear as the tail's first sentence. I shipped 159 of those by accident, caught them with a scan, and `test_no_reply_repeats_its_own_echo` now blocks the pattern.
- Gotcha: writing the tail first and prefixing the echo afterwards is what creates the stutter. Write the whole reply, then check both sides open with the same sentence and no more.
- Length: the echo is shared, so balance work happens on the tails. Global mean pair diff 0.93 (max 2), side deltas ≤6.6%.
- SAF-1: the `lucid` positive carries the "static" metaphor for intrusive noise; no ideation sits on the ANCHOR side.
- Reviewer note: sample 20 per set by rotating the id inside each block (`10b + b % 10 + 1`), never the block's first id — round 1's sample structurally hid the rotation defect.

# NAR — phase P3 journal

## P3.15 — 14 more scenarios (round 1)

- Shipped `D05_library`, `D07_aquarium`, `D08_summer_festival`, `D09_beach_sunset`, `D10_ferris_wheel`,
  `D12_cooking_together`, `I02_love_letter`, `I03_quiz_about_her`, `I05_poem`, `I08_rival_appears`,
  `I13_lucid_moment`, `I15_promise`, plus the path set-pieces `SP_YANDERE_the_list` and `SP_AWAKE_her_prompt`
  (`kind: "setpiece"`, `paths: [<own path>]`, `stages: [3,5]` — the path lock point).
- Convention: D/I scenes carry stage variants 0–5 and three twists each, with YANDERE + AWAKE pinned on all twelve
  and a scene-fitting third; set-pieces carry 3–5 variants and their own path + two alternates. Opening beats are
  authored for every playable stage, never only 0/1/3/5.
- `tests/test_scenarios.py` gained the P3.15 block: docs/01 §6.1/§6.2/§6.4 anchors, set-piece path locks,
  per-available-stage opening-beat coverage, and an "ambience is `none` or a real `cue_map.system` id" rule (only
  `ambience.paper` and `ambience.dishes` exist today). The engine loader floor is 21 files.
- Budget: the scene layer is the constraint. `scenario_playthrough.gd --stats=1` on 42 combos gave worst fixed
  868/900 and scene 126/150 on the real tokenizer. Keep a stage variant ≤ ~45 tokens and a twist ≤ ~25, or stage 5 +
  YANDERE crosses the builder's 150 estimate (SP_AWAKE needed trimming).
- Opening-beat `say` lines are limited to **two `[.!?]+` segments**, not two sentences as a human counts them:
  three short sentences fail the test even when they read naturally. Set-piece beats start at stage 3.
- Gotcha: a fresh worktree needs `./tools/godot.sh --headless --path game --import` before
  `scenario_playthrough.gd` runs (`class_name ScenarioLoader` not in the cache → parse error at `_print_stats`).
- Gotcha: the shared :8089 server was OOM-restarted mid-batch several times. A health gate before each run plus a
  retry cap (3) salvaged all 14; always verify the transcript's `invalid turns: 0` line rather than the exit code
  alone, and never start a second server.

# Narrative & Prompt Writer — journal, phase P3

## P3.17 — six ending frames + live last lines (round 1, 2026-11-04, agent: deepseek)

- Wrote the ending content for the six path fallbacks (E01/E04/E06/E08/E10/E12) straight into
  `data/endings.json`: `frame` (the game's narration of the last scene, third person about her /
  second person to the player, 3 sentences), `direction` (a director's note in third person about
  *her*, never "You …" — that "you" would be read as the player), `final` (her line, 1–3 sentences,
  ≤ 200 chars, reviewed). The other eight rows stay content-free on purpose; a python pin enforces it.
- Convention: the frame is narration, so it never contains "I", asterisks, quotes or braces;
  the final is her speech, so it does. `tests/test_ending_content.py` enforces both, plus one
  signature move per docs/01 §7/§4 (E01 "stay"/"count", E04 "swing", E06 "wins"/"save",
  E08 "text box"/"name", E10 "steps through"/"window", E12 "still sick").
- The live half is `llm/EndingLine.gd`: persona + stage + path module *if it exists* + `prompts/ending.md`,
  schema `{"line": string}`, then `Safety.filter_text`. A redaction or a filter error means **no live
  line at all** — the reviewed `final` stands. Bars would replace the farewell with noise, and the
  fallback is already reviewed, so it is both safer and better craft.
- The ending screen *plans* the fallback and gives the live answer a slot: `_final_gate` holds the
  reveal at that slot until the stream's terminal signal or `ending.final_hold_s` (ui.json). A model
  that hangs costs 4 s and no more; the slot never appears empty, and skip still works after it.
- Gotcha for P3.05: SPLIT/TSUN/HOLLOW/ANCHOR modules are not in this branch, so E04/E06/E08/E12 are
  prompted from persona+stage+direction alone today. The path layer joins automatically once those
  files land — re-measure the system prompt then (today 410–542 tokens, real tokenizer).
- Gotcha: `EndingSceneTest` now runs with `LLM.set_backend(null)` — the suite is P3.16's screen and
  the live path is `EndingContentTest`'s. Don't remove that: a leftover FakeLLMBackend from an
  earlier suite makes the screen's line depend on suite order.
- Gotcha: Godot 4 with this project's warnings-as-errors rejects `var x := f()` when `f()` returns
  `Variant`; type the local explicitly (`var backend: Variant = …`).

## P3.17 — round 2: the live line's register (2026-11-04, agent: deepseek)

- The authored six were fine; the *live* half was the bug. `direction` was one paragraph, the stage-5 module
  shouted "keep the player here", and the frame sat in the user turn — where a 4B model reads narration as
  the player's own words and answers it. SPLIT/TSUN/AWAKE produced 0/12 on-register, and the stage-5
  farewell came back as "please don't go".
- Fix the shape, not the samples: `ending.md` now says the ending is not a turn and that HER STATE outranks
  the stage and path notes (and names the habits to drop: staying, keeping him, explaining what she is);
  docs/08 §1's `[player]` line is in, and `{player_name}` is finally substituted in **every** layer — until
  this round the persona layer carried the literal placeholder; the frame is a labelled system layer; the
  new `prompt_omits` drops the layer that fights a row (E10 the AWAKE module, E04 the scene).
- Craft rule this model taught me: a 4B follows **beats named in order** ("That is the whole line: love,
  contempt, remorse") and drifts off a named mood. Every direction now names its beats, and the python pin
  still holds it to ≤240 chars / ≤3 sentences / third person about her.
- Measured on the pinned Qwen3.5-4B through the shipped prompt and sampling: 36 generations (6 per ending)
  → 28 clean, 6 partial, 2 misses, **0 contradictions**; a second 24-sample draw from the same prompt gave
  18/6/0. Round 1 was 8 clean / 5 partial / 11 contradicting.
- Gotcha for the next ending writer: ending narration never goes in the user turn, and a row whose scene
  narrates her departure may need `"prompt_omits": ["scene"]` (E04) — the screen still shows the frame.
