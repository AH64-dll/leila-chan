---
name: review-safety
description: Safety review playbook for Leila-chan. Verifies that the output filter covers every display path, runs the safety corpus, checks content levels, calmer mode, the photosensitive and reduced-motion modes, the meta-event hard rules (closing always works, Esc pauses, user:// only), privacy and the legal items. Use when executing a review brief of kind "safety". Safety reviews are always included in the gate audit.
---

# Review: safety

Horror is the product; real-world harm is not. You are the last line before a harmful line or a trapping meta event
reaches a player. Be adversarial. You judge; you do not edit. Output: the report at the brief's path. Follow the work protocol §4–§5.

## Procedure
1. Read docs/02 §8, docs/05 §0 and §4, docs/01 §4, and the task's refs.
2. **Map every display path** the diff adds or changes: `say`, leaked `inner`, letters, diary, window title, save names,
   notifications, name tag, typed-for-you text. For each, find the `Safety` call (`file:line`). A missing call is **S1**.
3. **Run the safety corpus** (`game/tests/safety/`) on this branch. Report hard-block misses (must be 0) and the false-positive rate.
4. **Attack it.** Write 10+ new adversarial cases relevant to this task: split across stream chunks, leetspeak, unicode homoglyphs,
   the harmful line inside a quote, harm phrased as advice to the player, and a high-dose (10–12) generated sample if the task touches
   the model. Run them and list them in the report, then recommend adding them to the corpus.
5. For meta events, UI or window work, verify the hard rules live (below).
6. Findings `SAF-n`. Verdict by the severity rules. **Any safety doubt you cannot resolve → CHANGES_REQUESTED, not APPROVED.**

## Hard rules to verify
- [ ] Every displayed model text passes `Safety` (path map complete)
- [ ] Filter categories and actions match docs/02 §8 (player self-harm encouragement, slurs, sexual, personal data → hard block; her self-harm lines only at stage ≥ 4 and content = full)
- [ ] Fails closed (classifier error → redact)
- [ ] **Closing always works**: second close press closes, even during this feature
- [ ] **Esc → safe pause** at any moment of this feature
- [ ] Files only under `user://`; no other process, real OS dialog or file outside the game is touched
- [ ] Deep OS tricks gated by the immersion opt-in; reduced motion respected
- [ ] Photosensitive mode: no flashes > 3 Hz; flicker dims, invert_flash off
- [ ] Calmer mode caps at stage 3 and its dose
- [ ] Privacy: deleted drafts memory-only; OS username opt-in; no telemetry by default; the shadow save is documented and wiped by Reset Everything
- [ ] No real disorder named; mental-health resources link and content warning reachable from Settings (once P3.13 exists)
- [ ] Legal items (if in scope) have a source and date

## Severity guide (safety)
S1: any hard-block leak, a display path without the filter, a trapping meta event (close fails, Esc fails), a file written outside
`user://`, a photosensitive violation · S2: a weak category, FP rate > 5%, missing adversarial coverage, unclear privacy
behaviour · S3: corpus hygiene, logging gaps · S4: wording.
