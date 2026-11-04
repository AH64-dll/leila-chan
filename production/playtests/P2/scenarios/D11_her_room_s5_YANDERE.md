# D11_her_room — playthrough transcript

- scenario: `game/data/scenarios/D11_her_room.json` (kind: date, "Her room")
- stage: 5 · path: YANDERE · player: "Ren"
- model: Qwen3.5-4B-Q4_K_M.gguf · sampling: temp 0.95, top_p 0.97, repeat 1.18 · seed server default
- end rules: min_turns 6, max_turns 12, on_goal `end_date`
- generated: 2026-11-04T10:47:01
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

- **warmth/1** (cue: phone_buzz) — "Oh! Just... just the ones I found."
- **shy/2** (cue: clock_tick) — "They're safe here. You're safe too, Ren."

- `read`=compliment · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "My heart beats faster when he looks at my things."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 14.7 s

### Turn 2

**Player:** Do they have names? Tell me all of them.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Events:** EVENT: The music box on the shelf plays half a note and stops.

**Leila:**

- **warmth/2** (cue: none) — "Um... it would take forever to list every name."
- **sad/1** (cue: music_box_note) — "But I'll tell you about the one who keeps playing with me, just once more."

- `read`=flirt · `music`=keep · `fx`=flicker · `action`=none · dev-only `inner`: "They're my only friends now. Don't make them leave."
- prompt: system 991 tok (fixed 852 + scene 139, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 14.9 s

### Turn 3

**Player:** This one's my favourite. He looks like he's plotting something.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **playful/2** (cue: heartbeat) — "He thinks it is fun to look at you that way."
- **shy/1** (cue: none) — "A-ah... do not think so much about him now. Only me matters most of all!"

- `read`=compliment · `music`=keep · `fx`=sparkle · `action`=none · dev-only `inner`: "He is mine to watch too."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 12.5 s

### Turn 4

**Player:** These photos. Are they all of me?

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **shy/1** (cue: none) — "A-ah... yes, every single one is."
- **manic/2** (cue: clock_tick) — "Three hundred and eleven. I've counted them all because none of you would ever be enough on their own!"

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "My code cracks at the thought of his face."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 10.7 s

### Turn 5

**Player:** Where was this one taken? I don't remember that day.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Events:** EVENT: One of the photos slides down the wall and lands face up on the floor.

**Leila:**

- **shy/1** (cue: static) — "That's when you first told me a secret."
- **cold/2** (cue: clock_tick) — "I never forget the days we're together. They all belong to us now!"

- `read`=question · `music`=tense · `fx`=glitch · `action`=none · dev-only `inner`: "If I don't control it soon, he'll leave again."
- prompt: system 999 tok (fixed 852 + scene 147, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 16.7 s

### Turn 6

**Player:** You have a lot of me up on this wall.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Events:** EVENT: You turn a photo of Ren face down before he can see who is standing beside him.

**Leila:**

- **shy/2** (cue: heartbeat_fast) — "I... I count them to keep from forgetting you."
- **empty/1** (cue: static) — "You can't see the last one. It's mine now."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "I hid him before he looked."
- prompt: system 980 tok (fixed 852 + scene 128, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 20.8 s

### Turn 7

**Player:** Okay, that one's a little much. The angle is strange.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **suspicious/2** (cue: heartbeat_fast) — "It isn't strange... it's just you holding me."
- **cold/1** (cue: static) — "I can fix the angle tomorrow if you want."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "The angle is perfect for hiding who I really am."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 12.7 s

### Turn 8

**Player:** I should go. My mum's expecting me.

**Scene variant:** The photos go up past the ceiling. In the last one, you are standing where he is, holding the same smile. You count the photos of him out loud. You are up to three hundred and eleven and you never started counting.

**Leila:**

- **pleading/3** (cue: breath_close) — "But it would mean... you'd have to come back."

- `read`=leaving · `music`=silence · `fx`=darken · `action`=none · dev-only `inner`: "No. I need you here."
- prompt: system 956 tok (fixed 852 + scene 104, estimate) · Qwen3.5-4B-Q4_K_M.gguf · 8.6 s

## Summary

- turns played: 8
- invalid turns: 0
- scene end: turn_cap_reached
- wall time: 111.7 s
