# NAR journal — phase P3

## P3.05 — SPLIT, TSUN, HOLLOW, ANCHOR + the hybrid 25% line (round 1)

- Shipped the four missing path modules (docs/01 §4.2/§4.3/§4.4/§4.6) in the P2.13 shape: a one-line shout that is also
  the runner-up's 25% share ("SPLIT — Love you. Hate you."), one behaviour line naming the signature moves, one exchange
  legal at the stage-2 gates. Rewrote the YANDERE/AWAKE headlines to the same motto format so the hybrid line stands
  alone and costs 9 real tokens instead of 21.
- Budget: the real Qwen tokenizer is the binding measure, not the 3.6 chars/token builder estimate — they disagree by up
  to 8 tokens on path text, and "delighted" with no leading space costs more than " delighted". Gloss separator
  compaction was reverted for that reason. Worst stage-2 pair (TSUN + SPLIT, 16-char name): 899 real / 893 builder.
- The 900 line has always been measured **without** the per-turn "Offered this turn — cue: …; music: …; fx: …" line,
  which is 62–143 real tokens by stage (stage 2: 91). The full system message is therefore ~990 at stage 2. Flagged as
  DCR-2 (SYS: shorten the enum line or count it as dynamic); do not paper over it by cutting persona content.
- `game/data/prompts/signature_moves.json` is the shared contract: `module` cues are checked by tests/test_prompts.py,
  `transcript` regexes by production/handoffs/media/P3.05_signature_moves.py. Add a move to the table before writing its
  probe, and keep each module cue an exact substring of the module — a capitalisation slip fails the test.
- The lab now knows six paths (canonical order) and every shipped set pins `runner_up`; an unpinned YANDERE case would
  borrow SPLIT and silently change the v2 evidence. New sets `stage_{2,3,4,5}_paths.jsonl` cover the four new paths; the
  v2 dose probe stays frozen at two paths until P3.19 rebuilds it.
- `stage2_prefill` golden no longer carries `offered`: the fixture pins the fixed block (the 900 budget's subject) and the
  enum line has its own test (`test_offered_values_reach_the_rules_layer`). Regenerate goldens only with
  `game/tests/tools/prompt_builder_goldens.gd`.
