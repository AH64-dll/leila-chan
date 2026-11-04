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
