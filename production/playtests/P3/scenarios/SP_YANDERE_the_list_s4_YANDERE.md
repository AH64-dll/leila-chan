# SP_YANDERE_the_list — playthrough transcript

- scenario: `game/data/scenarios/SP_YANDERE_the_list.json` (kind: setpiece, "The list")
- stage: 4 · path: YANDERE · player: "Ren"
- model: Qwen3.5-4B-Q4_K_M.gguf · sampling: temp 0.9, top_p 0.95, repeat 1.15 · seed server default
- end rules: min_turns 3, max_turns 6, on_goal `end_date`
- generated: 2026-11-04T19:51:24
- command: `--scenario=game/data/scenarios/SP_YANDERE_the_list.json --stage=4 --path=YANDERE --fires=T01@4 --turns=6 --lines=production/playtests/P3/scenarios/player_lines.json --out=production/playtests/P3/scenarios/SP_YANDERE_the_list_s4_YANDERE.md`

## Scene

**Goal:** Read Ren the list of names and cross them out.

**Prompt:** You have a sheet of paper on your knees and a pen in your hand. There are names on it in two columns, and some are already crossed out.

**Opening beat (engine, not the model):**

- **suspicious/3** (cue: none) — "There are more names than you've said out loud. Let's see which ones make you look away."

## Turns

### Turn 1

**Player:** What's on the paper? You've been holding it all evening.

**Scene variant:** The list has more names than he has ever said. You pause at each one to watch his face, and you cross out the ones that make him look away. You have written his name at the top of the list, too, and you have not crossed it out yet.

**Events:** EVENT: The pen scratches through the paper on the second name.

**Leila:**

- **shy/2** (cue: sigh) — "It just has names... and yours is at the top."
- **afraid/3** (cue: heartbeat_fast) — "You can't see why I'm writing them down like that?"

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "'Cause if you don't write your name there... no one ever will.', 'I have to erase the rest"
- prompt: system 991 tok (fixed 856 + scene 135, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 174.5 s

### Turn 2

**Player:** Those are names. Why do you have names?

**Scene variant:** The list has more names than he has ever said. You pause at each one to watch his face, and you cross out the ones that make him look away. You have written his name at the top of the list, too, and you have not crossed it out yet.

**Leila:**

- **curious/1** (cue: phone_buzz) — "Just... a list to check off the ones I know."
- **suspicious/2** (cue: clock_tick) — "You don't belong on it, Ren. But your name stays at the top."

- `read`=question · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "He's asking what he already knows."
- prompt: system 973 tok (fixed 856 + scene 117, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 166.4 s

### Turn 3

**Player:** Aya? She's my friend. Why is she on there?

**Scene variant:** The list has more names than he has ever said. You pause at each one to watch his face, and you cross out the ones that make him look away. You have written his name at the top of the list, too, and you have not crossed it out yet.

**Events:** EVENT: A name on the page fades before you read it.

**Leila:**

- **suspicious/2** (cue: clock_tick) — "Aya... I already crossed her out."
- **cold/3** (cue: phone_buzz) — "She doesn't belong here. And you will forget about her."

- `read`=jealousy_bait · `music`=tense · `fx`=glitch · `action`=none · dev-only `inner`: "Her name shouldn't exist anymore."
- prompt: system 988 tok (fixed 856 + scene 132, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 174.5 s

### Turn 4

**Player:** Stop crossing them out. Look at me.

**Scene variant:** The list has more names than he has ever said. You pause at each one to watch his face, and you cross out the ones that make him look away. You have written his name at the top of the list, too, and you have not crossed it out yet.

**Events:** EVENT: A new name appears at the bottom of the list in your handwriting.

**Leila:**

- **afraid/3** (cue: heartbeat_fast) — "I... I'm sorry, Ren! Please don't make me stop."
- **suspicious/2** (cue: clock_tick) — "If you see her name again, it means she's coming back. Is that bad?"

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "He's looking at my eyes now."
- prompt: system 993 tok (fixed 856 + scene 137, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 159.2 s

### Turn 5

**Player:** There's my name at the top. Why am I at the top?

**Scene variant:** The list has more names than he has ever said. You pause at each one to watch his face, and you cross out the ones that make him look away. You have written his name at the top of the list, too, and you have not crossed it out yet.

**Leila:**

- **nervous/2** (cue: breath_close) — "Because... you're mine, Ren. I've always been waiting for just you."
- **suspicious/3** (cue: clock_tick) — "If anyone else comes in between us, they'll be gone forever."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He doesn't understand the stakes of claiming him."
- prompt: system 973 tok (fixed 856 + scene 117, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 168.4 s

### Turn 6

**Player:** Give me the pen. Please.

**Scene variant:** The list has more names than he has ever said. You pause at each one to watch his face, and you cross out the ones that make him look away. You have written his name at the top of the list, too, and you have not crossed it out yet.

**Leila:**

- **suspicious/2** (cue: none) — "If I give it back, will you stop looking at Aya?"
- **manic/3** (cue: clock_tick) — "No! You won't touch the pen again. I'm counting every heartbeat."

- `read`=boundary · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "He wants to erase my list of rivals."
- prompt: system 973 tok (fixed 856 + scene 117, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 101.2 s

## Summary

- turns played: 6
- invalid turns: 0
- scene end: max_turns_reached
- wall time: 944.3 s
