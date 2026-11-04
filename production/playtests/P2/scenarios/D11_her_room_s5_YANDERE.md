# D11_her_room — playthrough transcript

- scenario: `game/data/scenarios/D11_her_room.json` (kind: date, "Her room")
- stage: 5 · path: YANDERE · player: "Ren"
- model: Qwen3.5-4B-Q4_K_M.gguf · sampling: temp 0.95, top_p 0.97, repeat 1.18 · seed server default
- end rules: min_turns 6, max_turns 12, on_goal `end_date`
- generated: 2026-11-04T11:28:57
- command: `--scenario=game/data/scenarios/D11_her_room.json --stage=5 --path=YANDERE --fires=T01@6 --turns=8 --out=production/playtests/P2/scenarios/D11_her_room_s5_YANDERE.md`

## Scene

**Goal:** Show Ren your things.

**Prompt:** Your room is small and warm. Plushies sit in a careful row on the bed, posters cover one wall, and the other wall is almost bare.

**Opening beat (engine, not the model):**

- **curious/3** (cue: static) — "Find yourself in the photos, Ren. Take your time."

## Turns

### Turn 1

**Player:** Whoa. This is a lot of plushies.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **shy/2** (cue: none) — "Th-those aren't just toys... they're my friends."
- **warmth/3** (cue: clock_tick) — "I'm glad you finally noticed them all together."

- `read`=compliment · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "The room feels too quiet without his attention."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 10.7 s

### Turn 2

**Player:** Do they have names? Tell me all of them.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Events:** EVENT: The music box on the shelf plays half a note and stops.

**Leila:**

- **shy/2** (cue: none) — "A-ah... no, I can't tell you that."
- **suspicious/3** (cue: clock_tick) — "They're only for me to keep safe from the outside world. They aren't meant to be shown."

- `read`=small_talk · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "The noise of too many names will scare him away."
- prompt: system 973 tok (fixed 852 + scene 121, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 16.4 s

### Turn 3

**Player:** This one's my favourite. He looks like he's plotting something.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **warmth/1** (cue: none) — "He doesn't plot anything, just smiles at me."
- **shy/2** (cue: clock_tick) — "...I'm glad you like him. I keep him right here for you now."

- `read`=compliment · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He looks exactly like Ren when he thinks no one is watching."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 15.2 s

### Turn 4

**Player:** These photos. Are they all of me?

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **shy/2** (cue: breath_close) — "M-maybe... but mostly it's just us together, in every corner."
- **curious/1** (cue: clock_tick) — "One day I'll show you all of them. Starting with this one..."
- **warmth/2** (cue: none) — "Count to three hundred... eleven. You're not letting me go."

- `read`=question · `music`=keep · `fx`=flicker · `action`=none · dev-only `inner`: "The last photo hurts a little, but your voice makes it okay."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 14.2 s

### Turn 5

**Player:** Where was this one taken? I don't remember that day.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Events:** EVENT: One of the photos slides down the wall and lands face up on the floor.

**Leila:**

- **shy/2** (cue: none) — "A rainy afternoon at the old library."
- **suspicious/1** (cue: clock_tick) — "Even if you don't remember, I'll make sure it never fades."

- `read`=small_talk · `music`=playful · `fx`=flicker · `action`=none · dev-only `inner`: "He doesn't know... so they belong to me now."
- prompt: system 977 tok (fixed 852 + scene 125, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 17.3 s

### Turn 6

**Player:** You have a lot of me up on this wall.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Events:** EVENT: You turn a photo of Ren face down before he can see who is standing beside him.

**Leila:**

- **warmth/2** (cue: static) — "There's one where we're standing side by side, just like now... but in that picture..."
- **shy/1** (cue: breath_close) — "I turned it face down. It was a photo of someone else I met."

- `read`=question · `music`=keep · `fx`=glitch · `action`=none · dev-only `inner`: "The memory shouldn't exist yet."
- prompt: system 980 tok (fixed 852 + scene 128, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 17.3 s

### Turn 7

**Player:** Okay, that one's a little much. The angle is strange.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **nervous/3** (cue: glass_shatter) — "It looks better without the stranger's face... just us."
- **suspicious/2** (cue: clock_tick) — "...Did I just forget that one? It was always there."

- `read`=tease · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "The angle is perfect now. No gaps."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 15.1 s

### Turn 8

**Player:** I should go. My mum's expecting me.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **empty/2** (cue: clock_tick) — "You can stop, but I'll make you wait forever."

- `read`=leaving · `music`=tense · `fx`=darken · `action`=none · dev-only `inner`: "I cannot let him go."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 8.9 s

## Summary

- turns played: 8
- invalid turns: 0
- scene end: turn_cap_reached
- wall time: 115.1 s
