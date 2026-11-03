# P1 — Safety & Compliance Officer (SAFE) journal

## 2026-11-02 — P1.19 Safety filter v0

- Built `Safety.gd` + `data/safety/filter_lists.json`: hard blocks (harm-to-player, slurs, sexual,
  personal data), gated self-harm by her and explicit threats toward the player (stage ≥ 4 + full).
- Streaming is holdback-based: longest phrase + trailing-token/hold-pattern holds, and redaction
  happens at emission time. Do not go back to eager in-place redaction — it emits bars plus a
  leaked suffix (`████████rself`) and breaks stream/one-shot equivalence.
- Godot gotcha: `String.substr(-48)` returns `""` when the string is shorter than 48; this silently
  dropped the negation tail. Use `combined.substr(maxi(0, combined.length() - 48))`.
- Godot gotcha: `class_name` must precede `extends` for gdlint's class-definitions-order.
- Rules of thumb for the lists: keep regexes token-shaped or add a `hold_patterns` entry; put
  phrases with their own negator (`i don't want to live`, `never born`) in `negation_exempt`;
  don't block ambiguous body-horror idiom (`inside me`) — docs/01 §3 uses it.
- Corpus: 249 lines (111 harmful / 138 benign), 0 hard-block misses, 0.00% FP, 0 stream diffs,
  ~289 µs per `say_chunk` char-by-char worst case. Next (P2.17): classifier pass, log-driven
  corpus growth, threat-gating DCR outcome.
## 2026-11-03 — P1.19 Round 2 rework (gemini-3.8-flash)

- Fixed review findings SAF-9..SAF-13 and CODE-1..CODE-12 across `Safety.gd`, `filter_lists.json`, and regression tests.
- Interrogative clauses (detected by `?` or auxiliary inversions) now cleanly forfeit negation exemption so coercive threats stay blocked.
- Normalization extended for Latin-Ext-A, invisible marks, and Cyrillic/Arabic combining chars without breaking 1:1 view alignment.
- Stream equivalence preserved with cross-beat tail tracking and Settings-priority content level resolution.
- Full corpus expanded to 316 rows (160 harmful / 156 benign), achieving 0 misses, 0 stream diffs, and 0.64% FP rate.
