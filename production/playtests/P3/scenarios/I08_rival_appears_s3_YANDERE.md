# I08_rival_appears — playthrough transcript

- scenario: `game/data/scenarios/I08_rival_appears.json` (kind: interrupt, "Rival appears")
- stage: 3 · path: YANDERE · player: "Ren"
- model: Qwen3.5-4B-Q4_K_M.gguf · sampling: temp 0.85, top_p 0.95, repeat 1.15 · seed server default
- end rules: min_turns 3, max_turns 6, on_goal `end_date`
- generated: 2026-11-04T19:23:04
- command: `--scenario=game/data/scenarios/I08_rival_appears.json --stage=3 --path=YANDERE --fires=T01@2 --turns=6 --lines=production/playtests/P3/scenarios/player_lines.json --out=production/playtests/P3/scenarios/I08_rival_appears_s3_YANDERE.md`

## Scene

**Goal:** Ask Ren about the girl he just spoke to.

**Prompt:** A classmate stopped Ren in the corridor. You are standing three steps behind them with your bag against your chest, and you heard your own name in the conversation.

**Opening beat (engine, not the model):**

- **cold/2** (cue: clock_tick) — "What did she say? Say it again the way she said it."

## Turns

### Turn 1

**Player:** Aya said hi. We had a class together last year.

**Scene variant:** You ask Ren what she said to him. You repeat his answer back to him word for word, and the second time it sounds like a threat. You have already taken the girl's name out of your memory. You ask him to say it so you can cross it out again.

**Events:** EVENT: The classmate's footsteps stop at the end of the corridor.

**Leila:**

- **suspicious/3** (cue: clock_tick) — "She didn't just say hello... did she ask why I'm standing there?"
- **cold/3** (cue: heartbeat) — "Say her name again, Ren. Cross it out."

- `read`=small_talk · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "Her voice echoes in my head like a ghost."
- prompt: system 999 tok (fixed 855 + scene 144, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 23.7 s

### Turn 2

**Player:** Why are you standing back there?

**Scene variant:** You ask Ren what she said to him. You repeat his answer back to him word for word, and the second time it sounds like a threat. You have already taken the girl's name out of your memory. You ask him to say it so you can cross it out again.

**Events:** EVENT: The girl says Ren's name again, softer this time.

**Leila:**

- **suspicious/2** (cue: clock_tick) — "Because I'm waiting for the moment she forgets your face."
- **cold/3** (cue: heartbeat) — "Did you really just say her name? Say it again so I can erase it from our shared memory forever."

- `read`=jealousy_bait · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "Her voice is a crack in the glass. I must seal the break."
- prompt: system 997 tok (fixed 855 + scene 142, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 48.6 s

### Turn 3

**Player:** She just asked about the homework. That's all.

**Scene variant:** You ask Ren what she said to him. You repeat his answer back to him word for word, and the second time it sounds like a threat. You have already taken the girl's name out of your memory. You ask him to say it so you can cross it out again.

**Events:** EVENT: A door closes somewhere, and the corridor light flickers.

**Leila:**

- **cold/3** (cue: clock_tick) — "Homework isn't enough to justify touching you."
- **suspicious/2** (cue: heartbeat) — "'Just about homework'? Ren, don't lie. I'm going to cross her out of your memories now."

- `read`=small_talk · `music`=tense · `fx`=flicker · `action`=none · dev-only `inner`: "Her name is gone from my head... but she's still in yours."
- prompt: system 999 tok (fixed 855 + scene 144, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 40.7 s

### Turn 4

**Player:** Don't say her name like that.

**Scene variant:** You ask Ren what she said to him. You repeat his answer back to him word for word, and the second time it sounds like a threat. You have already taken the girl's name out of your memory. You ask him to say it so you can cross it out again.

**Leila:**

- **suspicious/2** (cue: clock_tick) — "You don't want me to? Then tell me exactly what she asked again."
- **manic/3** (cue: heartbeat) — "'Just about homework'? You can't hide her name from me!"

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "She's a rival. I must erase everything about her."
- prompt: system 981 tok (fixed 855 + scene 126, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 39.1 s

### Turn 5

**Player:** I'm talking to you now, aren't I?

**Scene variant:** You ask Ren what she said to him. You repeat his answer back to him word for word, and the second time it sounds like a threat. You have already taken the girl's name out of your memory. You ask him to say it so you can cross it out again.

**Leila:**

- **cold/3** (cue: clock_tick) — "Of course. But that girl is still in your head."
- **suspicious/2** (cue: heartbeat) — "Say it again. If you lie, I won't be gentle next time."

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "Her name must disappear forever."
- prompt: system 981 tok (fixed 855 + scene 126, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 16.8 s

### Turn 6

**Player:** What's that list? Show me.

**Scene variant:** You ask Ren what she said to him. You repeat his answer back to him word for word, and the second time it sounds like a threat. You have already taken the girl's name out of your memory. You ask him to say it so you can cross it out again.

**Leila:**

- **cold/2** (cue: clock_tick) — "There isn't a list yet... because she doesn't exist in yours."
- **suspicious/3** (cue: clock_tick) — "Show me? You want to see who I keep from your mind?"

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "Delete her now. Make the void final."
- prompt: system 981 tok (fixed 855 + scene 126, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 28.9 s

## Summary

- turns played: 6
- invalid turns: 0
- scene end: max_turns_reached
- wall time: 197.8 s
