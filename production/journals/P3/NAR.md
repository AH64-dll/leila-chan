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
