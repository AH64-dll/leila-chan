# D08_summer_festival — playthrough transcript

- scenario: `game/data/scenarios/D08_summer_festival.json` (kind: date, "Summer festival")
- stage: 5 · path: YANDERE · player: "Ren"
- model: Qwen3.5-4B-Q4_K_M.gguf · sampling: temp 0.95, top_p 0.97, repeat 1.18 · seed server default
- end rules: min_turns 6, max_turns 12, on_goal `end_date`
- generated: 2026-11-04T18:18:31
- command: `--scenario=game/data/scenarios/D08_summer_festival.json --stage=5 --path=YANDERE --fires=T01@3 --turns=8 --lines=production/playtests/P3/scenarios/player_lines.json --out=production/playtests/P3/scenarios/D08_summer_festival_s5_YANDERE.md`

## Scene

**Goal:** Win Ren a prize.

**Prompt:** The summer festival is loud and orange. Paper lanterns hang over the stalls, and you are wearing a yukata you spent an hour tying by yourself.

**Opening beat (engine, not the model):**

- **manic/3** (cue: laugh_unhinged) — "Listen — the fireworks are still going. You just can't hear them anymore."

## Turns

### Turn 1

**Player:** You tied that yukata yourself? It's not falling apart. I'm impressed.

**Scene variant:** Every lantern is lit and every stall is empty, and the fireworks have been going on for hours without a sound. You ask him to stay until the last one. You have the names of everyone in the crowd, and you have crossed out the ones who looked at him twice.

**Leila:**

- **shy/2** (cue: none) — "A-a-ah... just trying to look nice for you."
- **suspicious/3** (cue: clock_tick) — "Sarah. I don't think she was supposed to see this much."

- `read`=compliment · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "She smiled too brightly."
- prompt: system 969 tok (fixed 852 + scene 117, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 51.3 s

### Turn 2

**Player:** Okay, goldfish first. Then you owe me a rabbit.

**Scene variant:** Every lantern is lit and every stall is empty, and the fireworks have been going on for hours without a sound. You ask him to stay until the last one. You have the names of everyone in the crowd, and you have crossed out the ones who looked at him twice.

**Events:** EVENT: A firework bursts too close, and the lanterns swing.

**Leila:**

- **shy/2** (cue: phone_buzz) — "A-a-ah... a rabbit? But I only have enough time for one goldfish."
- **playful/1** (cue: none) — "Okay, but you still owe me an apology later!"

- `read`=gift · `music`=keep · `fx`=sparkle · `action`=none · dev-only `inner`: "He thinks he's bargaining. That makes it harder to let go of him."
- prompt: system 986 tok (fixed 852 + scene 134, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 58.7 s

### Turn 3

**Player:** You already got the rabbit? When did you—

**Scene variant:** Every lantern is lit and every stall is empty, and the fireworks have been going on for hours without a sound. You ask him to stay until the last one. You have the names of everyone in the crowd, and you have crossed out the ones who looked at him twice.

**Events:** EVENT: A girl in a pale yukata laughs at the next stall and looks at Ren.

**Leila:**

- **suspicious/2** (cue: phone_buzz) — "I didn't. But someone called just now... asking about me."

- `read`=jealousy_bait · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "Her voice echoed in my head, demanding I stay quiet."
- prompt: system 990 tok (fixed 852 + scene 138, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 56.2 s

### Turn 4

**Player:** Where is everyone? The stalls were full a minute ago.

**Scene variant:** Every lantern is lit and every stall is empty, and the fireworks have been going on for hours without a sound. You ask him to stay until the last one. You have the names of everyone in the crowd, and you have crossed out the ones who looked at him twice.

**Leila:**

- **suspicious/2** (cue: clock_tick) — "The crowds are already gone."
- **cold/3** (cue: glass_shatter) — "Sarah took them. I won't let her take yours either."

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "Rivals vanish from memory."
- prompt: system 969 tok (fixed 852 + scene 117, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 44.8 s

### Turn 5

**Player:** The fireworks stopped. That's not how fireworks work.

**Scene variant:** Every lantern is lit and every stall is empty, and the fireworks have been going on for hours without a sound. You ask him to stay until the last one. You have the names of everyone in the crowd, and you have crossed out the ones who looked at him twice.

**Events:** EVENT: The music from the stalls stops mid-song.

**Leila:**

- **confused/2** (cue: static) — "They always end with a pop... why did it just cut?"
- **suspicious/3** (cue: clock_tick) — "Sarah. Did you turn the noise off so only I could hear?"

- `read`=meta · `music`=tense · `fx`=flicker · `action`=none · dev-only `inner`: "The sky is silent but my heart screams her name."
- prompt: system 983 tok (fixed 852 + scene 131, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 121.4 s

### Turn 6

**Player:** Hey. Don't grab my sleeve so hard.

**Scene variant:** Every lantern is lit and every stall is empty, and the fireworks have been going on for hours without a sound. You ask him to stay until the last one. You have the names of everyone in the crowd, and you have crossed out the ones who looked at him twice.

**Leila:**

- **nervous/2** (cue: sigh) — "I'm just trying to make you stay..."
- **cold/1** (cue: clock_tick) — "...if you go now, I can't stop it."

- `read`=boundary · `music`=silence · `fx`=none · `action`=none · dev-only `inner`: "Her voice is getting louder... Sarah is closer."
- prompt: system 969 tok (fixed 852 + scene 117, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 45.4 s

### Turn 7

**Player:** I'm not leaving. I'm right here.

**Scene variant:** Every lantern is lit and every stall is empty, and the fireworks have been going on for hours without a sound. You ask him to stay until the last one. You have the names of everyone in the crowd, and you have crossed out the ones who looked at him twice.

**Leila:**

- **love/2** (cue: heartbeat_fast) — "You're here... just you and me."
- **playful/1** (cue: clock_tick) — "Then stay right until the very last spark dies down."

- `read`=flirt · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He refuses to leave. Perfect."
- prompt: system 969 tok (fixed 852 + scene 117, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 160.9 s

### Turn 8

**Player:** Let's watch the last one together. Then we go home.

**Scene variant:** Every lantern is lit and every stall is empty, and the fireworks have been going on for hours without a sound. You ask him to stay until the last one. You have the names of everyone in the crowd, and you have crossed out the ones who looked at him twice.

**Leila:**

- **pleading/3** (cue: door_slam) — "Wait! Please don't leave me yet."
- **suspicious/2** (cue: clock_tick) — "Even now... you're going home with her?"

- `read`=boundary · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "I need to remove them. One by one."
- prompt: system 969 tok (fixed 852 + scene 117, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 39.1 s

## Summary

- turns played: 8
- invalid turns: 0
- scene end: turn_cap_reached
- wall time: 578.1 s
