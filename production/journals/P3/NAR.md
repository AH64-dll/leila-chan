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
