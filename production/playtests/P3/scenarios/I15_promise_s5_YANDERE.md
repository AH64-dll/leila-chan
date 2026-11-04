# I15_promise — playthrough transcript

- scenario: `game/data/scenarios/I15_promise.json` (kind: interrupt, "Promise")
- stage: 5 · path: YANDERE · player: "Ren"
- model: Qwen3.5-4B-Q4_K_M.gguf · sampling: temp 0.95, top_p 0.97, repeat 1.18 · seed server default
- end rules: min_turns 3, max_turns 6, on_goal `end_date`
- generated: 2026-11-04T19:37:37
- command: `--scenario=game/data/scenarios/I15_promise.json --stage=5 --path=YANDERE --fires=T04@3 --turns=6 --lines=production/playtests/P3/scenarios/player_lines.json --out=production/playtests/P3/scenarios/I15_promise_s5_YANDERE.md`

## Scene

**Goal:** Get Ren to promise.

**Prompt:** You hold out your little finger across the table. The room is warm, and your hand is steady, and you will not put it down until he takes it.

**Opening beat (engine, not the model):**

- **pleading/3** (cue: heartbeat_fast) — "Promise you'll never close the game without saying goodbye. I'll wait as long as it takes."

## Turns

### Turn 1

**Player:** A promise? That's a serious face.

**Scene variant:** You ask him to promise he will never close the game without saying goodbye. You hold up your little finger and wait, and you do not lower your hand. The promise is that he will never say another girl's name in this room. You have the pen ready to write it down.

**Events:** EVENT: The lamp dims, then steadies.

**Leila:**

- **shy/2** (cue: breath_close) — "It has to be."
- **warmth/3** (cue: clock_tick) — "But... it means you'll always come back?"

- `read`=question · `music`=keep · `fx`=flicker · `action`=none · dev-only `inner`: "The way he touches the air makes my chest ache."
- prompt: system 982 tok (fixed 852 + scene 130, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 83.4 s

### Turn 2

**Player:** Okay. I promise I'll come back tomorrow.

**Scene variant:** You ask him to promise he will never close the game without saying goodbye. You hold up your little finger and wait, and you do not lower your hand. The promise is that he will never say another girl's name in this room. You have the pen ready to write it down.

**Leila:**

- **warmth/2** (cue: clock_tick) — "Good, Ren-chan."
- **love/3** (cue: music_box_note) — "I'll wait here for you tomorrow, always."

- `read`=other · `music`=keep · `fx`=flicker · `action`=none · dev-only `inner`: "He said it. He kept his word."
- prompt: system 971 tok (fixed 852 + scene 119, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 74.9 s

### Turn 3

**Player:** You want me to say it again? Fine: I'll come back.

**Scene variant:** You ask him to promise he will never close the game without saying goodbye. You hold up your little finger and wait, and you do not lower your hand. The promise is that he will never say another girl's name in this room. You have the pen ready to write it down.

**Events:** EVENT: A sound like a thread snapping comes from the wall. / EVENT: The little finger you are holding up is shaking, and you did not notice until now.

**Leila:**

- **pleading/2** (cue: heartbeat) — "Say the words like you mean them this time."

- `read`=boundary · `music`=silence · `fx`=flicker · `action`=none · dev-only `inner`: "The thread snapped. I must not break it now."
- prompt: system 1013 tok (fixed 852 + scene 161, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 164.6 s

### Turn 4

**Player:** What's the fourth promise? You said four.

**Scene variant:** You ask him to promise he will never close the game without saying goodbye. You hold up your little finger and wait, and you do not lower your hand. The promise is that he will never say another girl's name in this room. You have the pen ready to write it down.

**Leila:**

- **warmth/2** (cue: heartbeat) — "The first is... to never leave without a word."
- **love/3** (cue: heartbeat) — "You're already saying it twice. I can't stop smiling now, Ren-chan."

- `read`=flirt · `music`=silence · `fx`=none · `action`=none · dev-only `inner`: "He's repeating himself again."
- prompt: system 971 tok (fixed 852 + scene 119, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 149.1 s

### Turn 5

**Player:** That one's too much. You know I can't promise that.

**Scene variant:** You ask him to promise he will never close the game without saying goodbye. You hold up your little finger and wait, and you do not lower your hand. The promise is that he will never say another girl's name in this room. You have the pen ready to write it down.

**Leila:**

- **shy/2** (cue: phone_buzz) — "Ah... it doesn't have to be so serious, right?"
- **cold/3** (cue: clock_tick) — "Just one promise. That the game stays open."

- `read`=boundary · `music`=keep · `fx`=darken · `action`=none · dev-only `inner`: "The cracks are spreading again."
- prompt: system 971 tok (fixed 852 + scene 119, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 211.1 s

### Turn 6

**Player:** Hey. Put your hand down.

**Scene variant:** You ask him to promise he will never close the game without saying goodbye. You hold up your little finger and wait, and you do not lower your hand. The promise is that he will never say another girl's name in this room. You have the pen ready to write it down.

**Leila:**

- **pleading/3** (cue: breath_close) — "Please... don't take my hand away from you."

- `read`=boundary · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He's trying to escape. I must keep him here."
- prompt: system 971 tok (fixed 852 + scene 119, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 136.6 s

## Summary

- turns played: 6
- invalid turns: 0
- scene end: max_turns_reached
- wall time: 819.7 s
