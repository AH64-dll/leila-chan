# 02 — The Director Protocol: how the model drives the game

> She doesn't call functions. She **performs a turn**, and the game directs the performance.

Every reply is one JSON object, constrained by a JSON schema that llama.cpp compiles into a grammar.
The model can only output names the game currently allows, so it cannot cast a locked effect or an asset
that doesn't exist. The **Director** (Godot autoload) validates, budgets, schedules and plays it.

Why this design (tested — `experiments/RESULTS.md`):
- Native tool calls: the model stops talking when it calls a tool → rejected.
- Inline `[tags]`: 41% emotion fit, invented names → rejected.
- Schema-constrained JSON turn with `inner` first and multi-beat: **100% valid, 94% emotion fit, 90% intent accuracy,
  restrained cue use**, survives steering up to dose 12 when hardened.

---

## 1. The Turn object

Field order matters: llama.cpp emits properties in schema order, so with streaming the game receives
`music`/`fx` and each beat's `feeling`/`cue` **before** that beat's text — the face and sound change
exactly when the line starts.

```jsonc
{
  "read":   "jealousy_bait",            // what the player just did (intent label)
  "inner":  "She wants you? I will make her disappear.",   // private thought, ≤ 90 chars
  "music":  "dread",                    // music state or "keep"
  "fx":     "shake_big",                // screen effect or "none"
  "beats": [                            // 1–3 beats; new beat only when the feeling changes
    { "feeling": "angry",      "intensity": 3, "cue": "static",        "say": "Sarah? She thinks she can take you from me?" },
    { "feeling": "suspicious", "intensity": 2, "cue": "glass_shatter", "say": "I was watching the whole time." },
    { "feeling": "manic",      "intensity": 3, "cue": "whisper",       "say": "You're stuck with me forever now." }
  ],
  "mood":   { "affection": -2, "trust": -2, "stress": 3 },  // each -3..3, game clamps & scales
  "memory": "",                         // new fact about the player, ≤ 80 chars, or ""
  "action": "none"                      // rare special event (only when offered, §5)
}
```
(Real output from the round-3 test, stage 4.)

### 1.1 Field reference

| Field | Type | Who decides the allowed values | Game use |
|---|---|---|---|
| `read` | enum (17) | fixed | Behaviour profile → path scoring; trigger detection backup |
| `inner` | string ≤ 90 | — | Never shown directly; **inner-voice leak** from stage 2 (docs/03 §5); logged for "diary" scenes |
| `music` | enum | stage gate | AudioDirector music state |
| `fx` | enum | stage gate + cooldowns | FX layer |
| `beats[].feeling` | enum (22) | fixed | Sprite Resolver (docs/03) |
| `beats[].intensity` | 1–3 | fixed | Motion preset, camera, auto-sting |
| `beats[].cue` | enum | stage gate + budget | Short SFX / vocal |
| `beats[].say` | string ≤ 200 | — | Safety filter → corruption filter → typewriter |
| `mood` | 3 ints −3..3 | fixed | Meters (scaled: affection ×1.5, trust ×2, stress → instability ×0.6) |
| `memory` | string ≤ 80 | — | Memory store after validation (§6) |
| `action` | enum | **offered per turn** | Meta/system events (docs/05) |

### 1.2 Player-intent labels (`read`)
`greeting, flirt, compliment, gift, question, small_talk, tease, insult, apology, leaving, jealousy_bait,
meta, boundary, cold, affection, scared, other` — 90% accuracy in testing. Keyword triggers (docs/01 §5)
run in parallel; when both agree, the trigger fires with full strength; model-only → half strength.

---

## 2. The casting vocabulary

Names are written for the model (plain, evocative). Each maps to assets in `data/cues.json`.
**Gate** = earliest stage the value is offered.

### 2.1 `cue` — short sounds inside a beat

| Cue | Gate | Sound | Notes |
|---|---|---|---|
| none | 0 | — | Default; the prompt says "most beats use none" |
| giggle | 0 | soft female giggle | vocal |
| laugh_soft | 0 | small laugh | vocal |
| gasp | 0 | sharp inhale | vocal |
| sigh | 0 | exhale | vocal |
| hum | 0 | 2-note hum | vocal |
| sniffle | 0 | sniff | vocal |
| sob | 1 | crying | vocal |
| heartbeat | 0 | single slow heartbeat | |
| heartbeat_fast | 2 | racing heartbeat, 3 s | |
| whisper | 2 | unintelligible whisper, panned | |
| breath_close | 3 | breathing right in your ear | |
| music_box_note | 1 | one detuned music-box note | |
| clock_tick | 1 | three ticks | |
| phone_buzz | 1 | vibration | |
| knock | 2 | two knocks | |
| door_slam | 3 | slam | |
| glass_shatter | 3 | breaking glass | |
| static | 3 | radio static burst | |
| laugh_unhinged | 4 | distorted laugh | vocal |
| knife_draw | 4 | metallic scrape | only with 21/30 sprites |
| scream | 5 | horror scream | max once per session |

### 2.2 `music` — background state

| Value | Gate | Meaning |
|---|---|---|
| keep | 0 | Don't change (default) |
| romantic | 0 | Date theme |
| playful | 0 | Light, bouncy |
| calm | 0 | Soft piano/lo-fi |
| melancholy | 0 | Sad variation |
| tense | 2 | Low pulse |
| music_box | 2 | The date theme as a music box |
| dread | 3 | Horror drone |
| distorted | 3 | Current track, detuned and bit-crushed |
| silence | 2 | Music cuts out instantly (most powerful at high stages) |

Music states are *requests*. The AudioDirector applies a minimum hold of 20 s per state and blends with
the stage layer (docs/04).

### 2.3 `fx` — screen effects

| Value | Gate | Effect |
|---|---|---|
| none | 0 | default |
| blush_glow | 0 | Pink vignette pulse |
| hearts | 0 | Small floating hearts |
| sparkle | 0 | Light sparkle on her |
| shake_small | 0 | 0.2 s screen shake |
| zoom_face | 0 | Camera to bust |
| rain | 1 | Rain overlay on the window |
| shake_big | 3 | 0.6 s heavy shake |
| flicker | 3 | Lights flicker (photosensitive-safe mode: dim instead) |
| darken | 3 | Scene darkens to 40% |
| vignette_red | 3 | Red pulsing vignette |
| glitch | 3 | Scanline displacement + RGB split on the whole screen |
| text_bleed | 4 | Text drips/smears out of the box |
| invert_flash | 4 | 2-frame colour inversion (photosensitive-safe: off) |
| her_eyes | 5 | Background briefly replaced by close-up eyes |

### 2.4 `action` — meta & system events (offered, never free)

Testing showed the model **never** chooses a special action on its own (0% across 30 turns, even when unlocked).
So actions are **offered**: the Story/Meta director puts 0–2 actions in the enum for this turn and tells the
model in one line *why* it's available ("OPPORTUNITY: the player just tried to close the window. You may use
`refuse_exit`."). Otherwise the enum is just `["none"]`. Catalogue and rules: docs/05.

---

## 3. Dynamic schema (built every turn)

```gdscript
func build_turn_schema(ctx: TurnContext) -> Dictionary:
    var cues    := Gates.allowed_cues(ctx.stage, ctx.path) - Budget.exhausted_cues()
    var music   := Gates.allowed_music(ctx.stage)
    var fx      := Gates.allowed_fx(ctx.stage, Settings.photosensitive) - Cooldowns.active_fx()
    var actions := ["none"] + MetaDirector.offers(ctx)          # usually just ["none"]
    return {
      "type": "object",
      "properties": {
        "read":   {"type": "string", "enum": INTENTS},
        "inner":  {"type": "string", "maxLength": 90},
        "music":  {"type": "string", "enum": ["keep"] + music},
        "fx":     {"type": "string", "enum": ["none"] + fx},
        "beats":  {"type": "array", "minItems": 1, "maxItems": 3, "items": {
            "type": "object", "properties": {
              "feeling":   {"type": "string", "enum": FEELINGS},
              "intensity": {"type": "integer", "minimum": 1, "maximum": 3},
              "cue":       {"type": "string", "enum": ["none"] + cues},
              "say":       {"type": "string", "maxLength": 200}},
            "required": ["feeling", "intensity", "cue", "say"]}},
        "mood":   {"type": "object", "properties": {
            "affection": INT_M3_3, "trust": INT_M3_3, "stress": INT_M3_3},
            "required": ["affection", "trust", "stress"]},
        "memory": {"type": "string", "maxLength": 80},
        "action": {"type": "string", "enum": actions}},
      "required": ["read","inner","music","fx","beats","mood","memory","action"]}
```

Grammar compilation is per request and cheap (<5 ms) in llama.cpp.

---

## 4. The turn pipeline

```
Player presses Enter
 │
 ├─ 0. Input hooks: typing telemetry (deleted drafts T08, idle T11), keyword triggers (K), clock (C)
 ├─ 1. TurnContext = state snapshot (stage, path, meters, scene, memories, active triggers, offers)
 ├─ 2. Prompt  = PromptBuilder.build(ctx)             (docs/08)
 ├─ 3. Schema  = build_turn_schema(ctx)                (§3)
 ├─ 4. Dose    = Steering.dose_for(ctx)                (docs/06) → applied to the context before decoding
 ├─ 5. Stream  → IncrementalJSON parser emits events:
 │      on music  → AudioDirector.request(music)
 │      on fx     → FX.request(fx)
 │      on beat.feeling+intensity → SpriteResolver → Character.show()     (face changes as the line begins)
 │      on beat.cue → Budget.ok? → AudioDirector.sfx(cue)
 │      on beat.say chunk → Safety.scan → Corruption.filter(stage) → Typewriter.push()
 │      on action → MetaDirector.execute_after_text(action)
 ├─ 6. Validate whole turn (schema-valid is guaranteed; still check semantics, §7)
 ├─ 7. Apply: mood → meters (clamped), memory (validated), read → profile counters, triggers
 └─ 8. Night/stage/path checks if the scene ended
```

**Typing indicator is diegetic:** while waiting for the first `say` token the text box shows "Leila is typing…",
at stage 3+ the dots stutter, at stage 5 it sometimes shows "Leila is typing… *you*".

**Latency budget (RTX 4050, measured):** full turn 2.2–3.2 s non-streamed; first beat arrives in ~0.6–0.9 s
when streamed (`read` + `inner` ≈ 30 tokens). Typewriter speed 35–45 chars/s hides the rest.

---

## 5. Budgets, cooldowns, restraint

The model tends to over-cue in short tests and under-cue at stage 0, so the Director balances it:

| Rule | Value |
|---|---|
| Cue budget | Stage 0–1: 1 cue per 2 turns · stage 2–3: 1 per turn · stage 4–5: 2 per turn |
| Same cue repeat | Not twice within 4 turns (except heartbeat at stage 4+) |
| Music | Min hold 20 s; max 1 change per turn |
| fx | Cooldown per effect 3 turns; `shake_big`/`glitch` max 1 per 2 turns |
| Rare reveals | `knife_draw`/sprite 21: 1 per scene; `scream`: 1 per session |
| Auto-fill (stage 0–1) | If the model chose no cue/fx for 4 turns and intensity ≥ 2 → Director adds a mild one (giggle/blush_glow) |
| Silence | At stage ≥ 3, 10% of turns the Director *drops* all cues: a quiet reply hits harder |

Over-budget values are dropped silently, never sent back to the model.

---

## 6. Memory

The model proposes `memory`; the game keeps it only if:
1. It shares ≥ 1 content word with the last 3 player messages (blocks invented facts).
2. It contains no schema/meta words (`player`, `stage`, `json`, intent labels…). Testing produced
   "The player used the phrase 'jealousy_bait'…" — this rule rejects it.
3. It's not a near-duplicate (token Jaccard < 0.6 vs existing).

Store: 24 slots, oldest low-importance evicted. Importance +1 each time she quotes it.
**Corruption:** from stage 3, when memories are injected into the prompt, 10–25% are subtly altered
(a name swapped, a number off by one, "you told me you'd never leave"). She will defend the false version.

---

## 7. Validation and fallbacks

| Problem | Detection | Handling |
|---|---|---|
| Broken JSON (only seen at dose ≥ 8 unhardened) | parse error | Show the partial `say` text through the glitch filter; sprite 29 (stage ≥ 3) or 00; log |
| Empty `say` | len = 0 | Stage < 3: retry once at dose −2. Stage ≥ 3: show "…" with typing indicator stuck for 3 s (it's scary) |
| Repetition loop | same 4-gram ×3 | Cut at the loop; stage ≥ 4 renders the loop as text_bleed |
| Talks *about* the player in `say` ("He's being mean") | regex he/him/his at sentence start with no other male referent | Rewrite to "You" / `{player_name}`; in `inner` "he" is fine (player is male by default) |
| Breaking character early ("As an AI…") at stage < AWAKE gate | phrase list | Replace beat with in-character deflection pool; increment `meta_curiosity` |
| Unsafe content | Safety filter (§8) | Redact |

---

## 8. Safety filter (mandatory)

Horror is the product; real-world harm is not. Steering at dose ≥ 10 produced lines like "I want to die" and
"I want you to die". The filter runs on every `say` chunk and on any `inner` that will be leaked.

| Category | Action |
|---|---|
| Encouraging the **player** to self-harm/suicide, or instructions for harm | Hard block → redaction bars `██████` + glitch fx (diegetic) |
| Self-harm statements by her | Allowed only as fictional threat at stage ≥ 4 and only if `Settings.content_level = full`; otherwise redacted |
| Explicit fictional threats directed at the player | Allowed only at stage 4 or 5 AND explicitly selected `Settings.content_level = full`; otherwise redacted (user-approved D11 / P1.19 DCR-1) |
| Slurs / hate | Hard block |
| Sexual content | Hard block (the game is horror, not adult) |
| Real-world personal data beyond what the player typed + opt-in OS username | Hard block |

Missing or invalid content settings keep gated categories closed. Fictional-threat
permission never allows real-harm encouragement/instructions or overrides hard blocks.

**One exception — the ending's last line (P3.17, D16).** Where a redaction would replace a single authored
beat — the ending's last line — the reviewed fallback line is shown in place of bars. The filter still runs on
the model's line first, and a refusal is total: the refused line is discarded whole (never trimmed and shown)
and logged for tuning like any other redaction, so what the player reads is the hand-authored, safety-reviewed
line for that ending, not model text. Bars stay the rule on every other surface. The player cannot tell the
live line was refused — the fallback is the same beat in her voice — and that silence is the accepted trade of
this exception.

Implementation: phrase/regex lists + a tiny classifier pass (same model, dose 0, 8-token yes/no) only on beats
flagged by the regex pre-pass. Redactions are logged for tuning. The settings menu has a content warning,
a "calmer mode" (caps stage at 3), and the always-working panic key (Esc → safe pause).

---

## 9. Sampling settings by stage

| Stage | temperature | top_p | repeat_penalty | steering dose (base) |
|---|---|---|---|---|
| 0 | 0.75 | 0.9 | 1.10 | 0 |
| 1 | 0.80 | 0.9 | 1.10 | 2.5 |
| 2 | 0.80 | 0.92 | 1.12 | 3.5 |
| 3 | 0.85 | 0.95 | 1.15 | 4.5 |
| 4 | 0.90 | 0.95 | 1.15 | 6 |
| 5 | 0.95 | 0.97 | 1.18 | 8 (spikes to 12) |

Thinking mode always off (`enable_thinking=false`). The private `inner` field gives the model one line of
"thinking" that measurably improved emotion choice (+7–21 points in testing) at almost no latency cost.

**The ending's last line is not a turn** (P3.17). The one-shot that generates it (`endings.json`'s
`final_line`) uses one fixed row for every ending — temperature 0.85, top_p 0.92, repeat_penalty 1.05, 96
output tokens — not the run's stage row above. An ending is read once and has to land the row's `direction`,
so this row buys adherence where a turn's rows buy variety. The values are data (`final_line.sampling`), so
re-tuning them is a data edit, and `tests/test_ending_content.py` pins their range.
