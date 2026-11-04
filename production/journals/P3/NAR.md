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
