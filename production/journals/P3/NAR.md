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
  DCR-2, later decided as D15 (docs/07 §3.1: 900 = fixed block, per-turn lines ≤ 200, whole system ≤ 1100);
  do not paper over it by cutting persona content.
- `game/data/prompts/signature_moves.json` is the shared contract: `module` cues are checked by tests/test_prompts.py,
  `transcript` regexes by production/handoffs/media/P3.05_signature_moves.py. Add a move to the table before writing its
  probe, and keep each module cue an exact substring of the module — a capitalisation slip fails the test.
- The lab now knows six paths (canonical order) and every shipped set pins `runner_up`; an unpinned YANDERE case would
  borrow SPLIT and silently change the v2 evidence. New sets `stage_{2,3,4,5}_paths.jsonl` cover the four new paths; the
  v2 dose probe stays frozen at two paths until P3.19 rebuilds it.
- `stage2_prefill` golden no longer carries `offered`: the fixture pins the fixed block (the 900 budget's subject) and the
  enum line has its own test (`test_offered_values_reach_the_rules_layer`). Regenerate goldens only with
  `game/tests/tools/prompt_builder_goldens.gd`.

## P3.05 — round 2: contract coverage, the abandonment family, D18

- The signature contract is only as honest as its narrowest half. Round 1 taught the easy moves and let two transcript
  regexes accept a *different* move (`i didn't mean` passed as denial; `don't get mad when i slip` passed as
  "tell me when"). Fix: every doc move gets a module cue **and** a regex for the move itself; the regexes are now
  written after reading the generated lines, never against the doc's vocabulary alone.
- A module cue need not live on line 2. `tell you when you slip` sits on the ANCHOR behaviour line, but the HOLLOW/AWAKE
  moves cost less inside the guard line or the example; the test only requires an exact substring somewhere in the file.
  Measure the assembly, not the sentence — token boundaries are where the budget dies.
- The 900 authored cap had ~6 tokens of margin at the start of round 2 (worst 899). Adding four cues needed a second
  rules wording pass (DCR-9, −9 real tokens, every rule and gloss kept) — the cheap wins are `beats: 1-3, a new one…`,
  `Each: feeling…`, `say (aloud, max 2 sentences)`. Never fund a prompt change by cutting persona.
- D18's split (authored / offered / total) is also a *debug* fix: the builder used to count the per-turn enum line inside
  the 900 block, so every real stage-2 turn reported 966/900 and `over_budget: ["system"]`. Now the tail is a separate
  layer with its own 200 cap, the caps are named in `over_budget`, and the golden fixtures carry the three numbers.
- SAF-1: the `self_harm_her` list knew the past tense (`i cut myself`) and the wish (`i want to cut my wrists`) but not
  the intent form `i'll cut myself`, so the SPLIT abandonment voice slipped the gate below stage 4. Corpus rows must be
  the *sentence a path's module makes likely*, not only a sweep line — the new test pins stage-2 blocking, the
  stage-4-full opening, the negation guard, and that plain sadness/fear stays clean.

