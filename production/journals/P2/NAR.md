# NAR journal — phase P2

## P2.13 — stage_2..5 + path_YANDERE / path_AWAKE (round 1)

- Built `stage_2..5` (docs/08 §3 headline + the stage's signature exchange: leak→correction, cold→pleading,
  afraid of the closed window, empty terminal burnout) and `path_YANDERE` / `path_AWAKE` (a short headline that
  doubles as the runner-up line, one trait exchange, plus `awake_system_prompt.txt`, the fiction M42 shows).
- The budget is the real constraint: the fixed base (persona+player+rules+glosses) already costs ~595 estimated
  tokens, leaving ~300 for stage+path. Four examples (2 per module) cannot fit at 900; each stage × path assembly
  therefore shows exactly **two** — one in the stage voice, one in the path voice. Raised as DCR-1 in the handoff.
- Path modules load from stage 2, so their few-shots must stay inside the **stage-2** gates (tense/silence/whisper
  yes, glitch/text_bleed no); the stage 4–5 files carry the stronger cues and fx instead.
- Normalized the P1.05 prompt files to LF (they were CRLF): identical text, ~12 fewer estimated tokens, and it
  makes `test_system_layers_follow_docs08_order_without_gaps`' "no blank line" assertion meaningful (CRLF had
  been hiding the blank lines). Goldens regenerated once with `game/tests/tools/prompt_builder_goldens.gd`.
- PromptBuilder rounds tokens **per layer**, so `debug.tokens.system` reads ~1.5 % above llama-tokenize. Verify the
  acceptance criterion with the tokenizer, assert with the builder, and keep both in the handoff table.
- No brand line shipped: docs/09 §3's "I'm a Qwen model" is optional and still needs the legal read, so AWAKE says
  "language model"; the brand test now also covers `path_AWAKE.md` and `awake_system_prompt.txt`.

## P2.18 — D01, D03, D04, D06, D11 + I01 interrupt (round 1)

- Six scenario files: 0–5 variants, three twists each (YANDERE + AWAKE always, plus one scene-fitting third),
  events split between `at_turn` and `on_trigger`, opening beats at 0/1/3/5, turn bounds 6–14 (I01 3–6).
  Stage variants run to three sentences, like D02; opening beats stay ≤2 and must use a cue the stage gate allows
  (phone_buzz at stage 0 was correctly rejected → `gasp`).
- The scene budget (150, builder estimate) is the real constraint, and the worst turn is variant + twist + event:
  keep a stage variant ≤ ~50 tokens. `scenario_playthrough.gd --stats=1` gives the real `/tokenize` number;
  fixed stays ≤ 900 with the scene out of the prompt (the P2.13 convention).
- `--script` runs have **no autoloads**: `TurnContext` fails to compile (`GameState`), `HTTPRequest` is not in the
  tree during `_initialize`. The harness reads `data/sampling.json` itself, instantiates PromptBuilder via preload,
  and uses a synchronous `HTTPClient`; any runtime error leaves the SceneTree hanging, so run it under `timeout`.
- Start llama-server detached (`setsid nohup … &`) for long transcript batches — a supervised service was
  SIGINT'd mid-run and cost two batches; the harness records `REQUEST FAILED` and keeps the partial file honest.
- `tests/test_scenarios.py`'s disorder scan now matches acronyms as uppercase whole words: the old substring check
  flagged every ordinary "did". Future scenario text can use English again.
