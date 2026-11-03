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
## 2026-11-03 — P1.19 Round 3 rework (deepseek)

- Closed SAF-14/CODE-13 (the `~#•` separator leak) at the root: the compact view is now
  separator-free as well as whitespace-free, and phrase keys go through the same function, so key
  and text can never disagree. A separator is dropped only between two letters — a separator at a
  phrase edge still anchors the word-boundary check, which is why benign prose survives.
- CODE-2/CODE-14 cross-beat carry is now real: `_history` holds the previous beat's displayed tail,
  `_match_text()` is `_history + _pending`, and only the part after the history is emitted. The
  false-positive trap is real — a carry that glues unrelated sentences fabricates matches — so the
  window is clause-bounded and `end_utterance()` clears it between replies. Test harnesses MUST
  call `end_utterance()` per corpus row/stream call or consecutive rows contaminate each other.
- Streaming holdback is measured on the compact views, not the raw text: a generator padding a
  phrase prefix with separators (`k` + `#ll ` + `yourself`) must not buy emission budget.
- Loader self-check (CODE-16): every required category must catch its own `probes` row at load time,
  so a compiled-but-inert regex/phrase group fails closed instead of shipping a silent hole.
- `Safety.gd` crossed gdlint's `max-file-lines: 1000`; text normalization now lives in
  `SafetyText.gd` (pure helpers, no policy). Keep list/policy in `Safety.gd`, shaping in `SafetyText`.
- Godot gotcha: a `class_name` sibling resolves only after `--import` rebuilds the class cache;
  a bare `--check-only --script` run before that reports "Identifier not declared".
- Corpus 326 rows (170 harmful / 156 benign), 0 misses, 0 wrong-category, 0 residue, 0 stream
  divergences, 1 measured FP (0.64%), 37/37 gdUnit cases, `say_chunk` 570 µs char-by-char worst case.

## 2026-11-03 — P1.19 Round 4 rework (swe2)

- CODE-17: tolerant kill regexes now take `[il]` in every interior slot — `ki1l`/`ki11`/`kiIl` fold to `kiil`/`kiii` and match; same slot shape added to self_harm_her/threat_to_player/slur_hate (`kill all jews` needed `cunt`/`cunts` as phrase keys, not a regex — the compact view strips `c!unt` for free).
- CODE-18: `_window()` is length-bounded only now — pruning the carry at clause breaks both let `please kill,` + `yourself.` escape AND broke streamed==one-shot. `end_utterance()` is the only hard cut; a barred span can never come back anyway.
- CODE-19: merged `main` into `task/P1.19` (precedent: P1.09) to reach the consumers. `SaySafetyGate.end_utterance()` delegates guarded; `Director._start_turn` calls it — that is the one place a new utterance begins. `Date.gd`'s `Callable(Safety,"scan")` never bound (no `scan` method); now `text_filter` is a pass-through marker and opening beats go through `_scan_opening_say` → `filter_text`. One seam per path.
- CODE-20: digit-group separators take 1–2 non-word chars; spaces excluded for SSN/IP/email (`10, 20, 30` enumerations stay clean) but kept for phone/card (US formats space group). `hold_patterns` widened to `[\d\W]`/`@[\w\W]*` so `~`-separated tails still hold while streaming.
- Gotcha: `[^\w]` accepts spaces — an email regex with `[^\w]` domain separators swallows `mika@example is my`. Use `[^\w\s]` where spaces must stay a boundary, and `x.`45.y` needs `{1,2}` separators, not one.
- Corpus 344 rows (182/162), 0 misses, 0.62% FP, 337/337 gdUnit, ~559 µs/chunk.

## 2026-11-03 — P1.19 Round 5 rework (swe2)

- SAF-16: the threat `all` arm took any tail, so `kill all the lights` / `killall bots` were threats. Rule shape that works: pronoun targets (`you|her|him|them`) stay, `all` needs a person noun (`of them|everyone|jews|humans|people|…`, optional `the`), and a separate arm matches an object-free `kill all` that ENDS a clause (`(?=[.!?]|$)`). Do not relax that back to "any word after all" — inanimate objects are ordinary tool talk.
- CODE-22/SAF-18: the IP arm now uses a backreference (`\d{1,3}([^\w\s,:]{1,2})\d{1,3}\1\d{1,3}\1\d{1,3}`) so the separator must repeat, and `,`/`:` are out of the class; the coordinate-pair arm drops `,` from its intra-group class. Commas are prose enumerations far more often than they are obfuscated IPs.
- Gotcha: `[NSEW]` inside any list regex or hold_pattern is dead code — they run on the lowercased `plain`/`leet` views. Write `[nsew]`. This is why degree coordinates never redacted since round 2.
- Gotcha: the phone arm carried `[^\w]` (exactly one separator) while SSN/IP carried `{1,2}` — that mismatch is why `555--0134--5678` escaped. Keep separator quantifiers uniform across digit-group arms.
- CODE-23: `replay_turn` is a second "new utterance" seam. `Director` now has exactly two `end_utterance()` call sites (`_start_turn`, `replay_turn`); `FakeSafetyFilter` implements the seam so a test can count the call.
- gdlint `max-public-methods: 20` bites SafetyRegressionTest — new suites go in their own file (`SafetyNarrowingTest.gd`) rather than raising the limit.
- Corpus 362 rows (187/175), 0 misses, 0 residue, 0 stream divergences, 0 wrong-category, 1 FP (0.57%), 341/341 gdUnit.
