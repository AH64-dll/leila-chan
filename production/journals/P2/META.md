# META journal — phase P2

## P2.06 — Corruption text filter by stage (2026-11-04, round 1)

- Built the docs/07 §3.4 corruption stage as two files: `game/llm/Corruption.gd` (pure rules — data
  table + docs fallback, gate/plan resolution, seeded RNG derivation, per-word/beat primitives) and
  `game/llm/CorruptionSession.gd` (the word-serial streaming adapter). Table in `game/data/corruption.json`.
- Pipeline placement: ChatUI gained an optional `corruption` seam that runs **after** `text_filter`
  (Safety) and **before** the typewriter, matching `say chunk → Safety.scan → PronounFix →
  Corruption.filter → Typewriter`. Date owns installing it. Do not fold corruption into `text_filter`:
  that Callable is the safety seam (P1.19 CODE-19) and is a pass-through in production.
- Determinism convention: seed = `Corruption.seed_for(turn, beat, effective_stage, salt)` (hash of those
  values), rolled at `begin_beat`; the stream works on complete words and holds the trailing partial word
  until whitespace/`flush`, so chunk boundaries are invisible to the output (tested char-by-char).
  Replays re-derive the seed; no RNG state is stored in the transcript.
- Gates are code rules: data may raise an effect's `gate` but `_normalize` clamps to the docs gate. Chance
  rows are content tuning (the bible only fixes gates). `calmer_max_stage: 3` mirrors docs/02 §8;
  `reduced_motion.disable: [zalgo, bleed]` keeps the textual effects under reduced motion.
- Glyphs: U+0338 slash is the strike-through (U+0336 renders as an offset dash/not at all), U+0300/0301/0308
  are the zalgo marks the Open Sans UI font actually carries, U+0332 is the bleed underline, U+2588 is
  Safety.gd's redaction block. Screenshots in `production/handoffs/media/P2.06/` prove the rendering on
  Linux (Open Sans + system fallback); P5.14/QA should re-check Windows/macOS font stacks.
- Gotchas for the next META task: `String.split("")` splits **per character**, not whitespace (use a RegEx
  for `\s+`); gdUnit hook/test functions count toward gdlint's 20-public-method limit, so merge primitives
  suites instead of adding one-method files; with instant text you must `await` one frame after `end_turn`
  or `get_visible_text()`/the log are still empty (the typewriter reveals in `_process`).
- Next (P2.07 inner leak): reuse `CorruptionSession.transform_beat()` on the already-Safety-scanned leaked
  `inner` text (one-shot, its own beat seed) — do not write a second filter. `path` is accepted by the
  session but unused; P3.04 can gate path-specific effects there.
- P2.09 overlap: ImplP209's telemetry hooks in ChatUI/Date are additive and disjoint from the text path;
  a normal 3-way merge should keep both (producer merges, per P2.25).
