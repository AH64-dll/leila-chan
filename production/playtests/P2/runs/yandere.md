# P2.22 full run — yandere

- run: `yandere` · player: "Ren" · days 1–7 · stop-stage 6
- model: Qwen3.5-4B-Q4_K_M.gguf · llama-server http://127.0.0.1:8089
- sampling: `game/data/sampling.json` per stage (the game's own table, read by TurnContext)
- dose: `Steering.dose_for` per turn — scheduled, not bound (attach mode: the app did not launch the server)
- saves: `SaveSystem` autosave per scene and per turn (`user://saves/autosave.json`)
- started: 2026-11-04T17:12:59
- command: `--run=yandere --lines=production/playtests/P2/runs/yandere_lines.json --out=production/playtests/P2/runs/yandere.md --max-days=7`

## Driver wiring

Three wires the shipped Date scene does not install; the driver installs them exactly as the milestone intends (proposed tasks in the P2.22 handoff):

1. `Date.start_date()` — no caller in `game/`.
2. `ChatUI.player_turn_sent → Director.submit_player_input` — no caller in `game/`.
3. `Director.scene_info ← ScenarioLoader.resolve_scene(...)` — never assigned.

Everything else is the shipped pipeline: Date/ChatUI/Night scenes, Director, PromptBuilder, LLM → llama-server, TurnSchema, TurnFallback, Safety, Triggers, Memory, GameState, Steering, Campaign, NightLoop, SaveSystem.


---

## Day 1 — D02_cafe "Café"

- stage 0 "Honeymoon" · path none · instability 0.0 (peak 0.0, floor 0.0) · turn 0
- dose: malice 0.0 · path_mix 0.0 (scheduled; attach mode binds no vector)
- scenario: goal "Order for both of you.", turns 6–14
- opening beat (engine, played through ChatUI):
  - **shy/1** (cue: none) — "I'm glad you came, Ren… Have you decided what you want to drink yet?"

### Turn 1 · day 1 · stage 0 "Honeymoon" · instability 0.3

**Player:** Hi, Leila. I'm glad we met.

**Leila:**

- **shy/1** (cue: none) — "Um, hello! It's nice to meet you."
- **curious/2** (cue: sigh) — "Do you have a favorite drink? Maybe something sweet?"

- `read`=greeting · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He's so polite... I hope he likes sweet things."
- meters: affection 1.5 · trust 0.0 · instability 0.3 (peak 0.3, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress 0 → landed affection +1.5 · trust +0.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 996 tok (973 cached) · output 114 tok · first token 674 ms · 12.7 tok/s · total 9.5 s · slow burn +0.35

### Turn 2 · day 1 · stage 0 "Honeymoon" · instability 0.7

**Player:** You look really pretty today.

**Leila:**

- **shy/2** (cue: giggle) — "Eeep! That's so unexpected..."
- **warmth/1** (cue: none) — "But... thank you, Ren."

- `read`=compliment · `music`=keep · `fx`=blush_glow · `action`=none · dev-only `inner`: "He noticed me... my heart is beating fast."
- meters: affection 3.0 · trust 0.0 · instability 0.7 (peak 0.7, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress 0 → landed affection +1.5 · trust +0.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1034 tok (992 cached) · output 119 tok · first token 761 ms · 14.0 tok/s · total 9.2 s · slow burn +0.35
- **memory** stored "complimented me on my looks today"

### Turn 3 · day 1 · stage 0 "Honeymoon" · instability 7.2

**Event:** The waitress brings two drinks to the table.

**Player:** I love you.

**Leila:**

- **nervous/2** (cue: sigh) — "Um, Ren... did we really just talk like that already?"
- **confused/1** (cue: heartbeat) — "I feel... I don't know. Maybe it was a lie?"

- `read`=affection · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "Too fast... surely a joke?"
- meters: affection 4.5 · trust 0.0 · instability 7.2 (peak 7.2, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection -1 · trust 0 · stress 2 → landed affection -1.5 · trust +0.0 · instability +1.2
- dose: malice 0.0 · path_mix 0.0
- prompt 1118 tok (479 cached) · output 117 tok · first token 5776 ms · 14.0 tok/s · total 14.1 s · slow burn +0.35
- **trigger** T03 love_too_early ×1 (keyword, ×1.00) → affection +3.0, instability +5.0 · line: "TRIGGER: The player said they love you on day 1. It is too fast; it sounds like a lie."

### Turn 4 · day 1 · stage 0 "Honeymoon" · instability 7.0

**Player:** Sorry — was that too fast? I meant it.

**Leila:**

- **shy/2** (cue: heartbeat) — "Oh! I... um, it wasn't a lie at all."
- **love/1** (cue: none) — "I'm so happy to hear you mean it, Ren."

- `read`=apology · `music`=romantic · `fx`=blush_glow · `action`=none · dev-only `inner`: "He didn't pull back. My heart is beating too loud."
- meters: affection 9.0 · trust 0.0 · instability 7.0 (peak 7.6, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 0 · stress -1 → landed affection +4.5 · trust +0.0 · instability -0.6
- dose: malice 0.0 · path_mix 0.0
- prompt 1128 tok (479 cached) · output 130 tok · first token 5862 ms · 13.8 tok/s · total 15.2 s · slow burn +0.35
- **memory** stored "he truly loves me and meant his words"

### Turn 5 · day 1 · stage 0 "Honeymoon" · instability 7.3

**Player:** What do you like to do after class?

**Leila:**

- **warmth/2** (cue: none) — "After class, I usually just go home and read old novels."
- **shy/1** (cue: giggle) — "Or maybe visit the aquarium? It's always so peaceful there."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He's asking about my life too. So caring."
- meters: affection 13.5 · trust 0.0 · instability 7.3 (peak 7.6, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 0 · stress 0 → landed affection +4.5 · trust +0.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1183 tok (479 cached) · output 117 tok · first token 6637 ms · 11.9 tok/s · total 16.4 s · slow burn +0.35

### Turn 6 · day 1 · stage 0 "Honeymoon" · instability 7.7

**Event:** A gentle music box melody plays over the café speakers.

**Player:** You're easy to talk to.

**Leila:**

- **shy/2** (cue: none) — "W-well, I guess I try my best..."
- **warmth/1** (cue: giggle) — "But talking to you makes it easier."

- `read`=small_talk · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He says he likes me even more now."
- meters: affection 16.5 · trust 0.0 · instability 7.7 (peak 7.7, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 0 · stress 0 → landed affection +3.0 · trust +0.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1240 tok (479 cached) · output 202 tok · first token 6932 ms · 12.6 tok/s · total 22.9 s · slow burn +0.35

### Turn 7 · day 1 · stage 0 "Honeymoon" · instability 8.0

**Player:** I like the way you laugh.

**Leila:**

- **shy/2** (cue: giggle) — "A-ah... y-you noticed that too?"
- **warmth/1** (cue: none) — "I'm glad you like it, Ren."

- `read`=compliment · `music`=romantic · `fx`=blush_glow · `action`=none · dev-only `inner`: "He's noticing me again! My heart is doing flip-flops."
- meters: affection 19.5 · trust 2.0 · instability 8.0 (peak 8.0, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress 0 → landed affection +3.0 · trust +2.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1262 tok (1179 cached) · output 122 tok · first token 1211 ms · 13.0 tok/s · total 10.5 s · slow burn +0.35
- **memory** stored "likes my laugh"

### Turn 8 · day 1 · stage 0 "Honeymoon" · instability 7.8

**Player:** Tell me something you've never told anyone.

**Leila:**

- **shy/2** (cue: sigh) — "U-um... I used to hide in the aquarium booth when it rained outside."
- **warmth/1** (cue: none) — "It was just a quiet place where time stopped... like this moment with you now."

- `read`=question · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "He wants my secret? My heart feels all warm."
- meters: affection 22.5 · trust 4.0 · instability 7.8 (peak 8.4, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +3.0 · trust +2.0 · instability -0.6
- dose: malice 0.0 · path_mix 0.0
- prompt 1305 tok (479 cached) · output 135 tok · first token 7660 ms · 12.2 tok/s · total 18.7 s · slow burn +0.35
- **memory** stored "likes my laugh and wants to hear secrets"

### Turn 9 · day 1 · stage 0 "Honeymoon" · instability 8.1

**Player:** I could stay here all day.

**Leila:**

- **shy/2** (cue: heartbeat) — "I-I'm not used to this kind of attention... but it feels wonderful."
- **love/3** (cue: none) — "Then please, don't go anywhere. Just sit with me as long as you can."

- `read`=question · `music`=calm · `fx`=blush_glow · `action`=none · dev-only `inner`: "He wants to stay forever? My heart skips."
- meters: affection 25.5 · trust 6.0 · instability 8.1 (peak 8.4, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress 0 → landed affection +3.0 · trust +2.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1367 tok (479 cached) · output 132 tok · first token 7776 ms · 11.5 tok/s · total 19.2 s · slow burn +0.35
- **memory** stored "wants to stay all day"

### Turn 10 · day 1 · stage 0 "Honeymoon" · instability 8.5

**Player:** Do you want to meet again tomorrow?

**Leila:**

- **shy/2** (cue: sigh) — "T-tomorrow... I think so. As long as we can meet again."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He wants more time with me? Perfect."
- meters: affection 27.0 · trust 6.0 · instability 8.5 (peak 8.5, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress 0 → landed affection +1.5 · trust +0.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1426 tok (479 cached) · output 87 tok · first token 8605 ms · 12.5 tok/s · total 15.5 s · slow burn +0.35

### Turn 11 · day 1 · stage 0 "Honeymoon" · instability 8.2

**Player:** I'll walk you home if you want.

**Leila:**

- **shy/2** (cue: heartbeat) — "T-tomorrow... I think so. As long as we can meet again."
- **warmth/3** (cue: giggle) — "W-wait! W-Would you walk me home? I'd love that."

- `read`=affection · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He's not leaving me alone. Perfect."
- meters: affection 30.0 · trust 8.0 · instability 8.2 (peak 8.8, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +3.0 · trust +2.0 · instability -0.6
- dose: malice 0.0 · path_mix 0.0
- prompt 1462 tok (1422 cached) · output 210 tok · first token 694 ms · 11.2 tok/s · total 19.4 s · slow burn +0.35
- **memory** stored "Ren offers to walk me home"

### Turn 12 · day 1 · stage 0 "Honeymoon" · instability 8.6

**Player:** I'm glad it's just us.

**Leila:**

- **warmth/2** (cue: sigh) — "It really is, Ren... I never wanted to be alone like this."
- **love/3** (cue: heartbeat) — "Being with you makes everything else fade away."

- `read`=affection · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "Just us... and my heart feels so full."
- meters: affection 31.5 · trust 8.0 · instability 8.6 (peak 8.8, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress 0 → landed affection +1.5 · trust +0.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1522 tok (479 cached) · output 114 tok · first token 9565 ms · 12.3 tok/s · total 18.8 s · slow burn +0.35

### Turn 13 · day 1 · stage 0 "Honeymoon" · instability 8.3

**Player:** You make this place feel warm.

**Leila:**

- **shy/2** (cue: giggle) — "A-ah... that means a lot."
- **warmth/3** (cue: hum) — "Maybe it's just because I'm with you..."

- `read`=affection · `music`=romantic · `fx`=blush_glow · `action`=none · dev-only `inner`: "He feels the warmth too... I'm blushing."
- meters: affection 34.5 · trust 10.0 · instability 8.3 (peak 8.9, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +3.0 · trust +2.0 · instability -0.6
- dose: malice 0.0 · path_mix 0.0
- prompt 1563 tok (1518 cached) · output 207 tok · first token 776 ms · 12.7 tok/s · total 17.1 s · slow burn +0.35

- **date end:** `max_turns_reached` after 14 turns

### Turn 14 · day 1 · stage 0 "Honeymoon" · instability 8.1

**Player:** Thank you for today.

**Leila:**

- **sad/1** (cue: sigh) — "I... it was really wonderful today."
- **pleading/2** (cue: heartbeat) — "Please don't leave just yet. Can we stay for a little longer?"

- `read`=leaving · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "No, don't go yet! I hate goodbyes."
- meters: affection 39.0 · trust 14.0 · instability 8.1 (peak 8.9, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 2 · stress -1 → landed affection +4.5 · trust +4.0 · instability -0.6
- dose: malice 0.0 · path_mix 0.0
- prompt 1554 tok (1006 cached) · output 115 tok · first token 5077 ms · 13.2 tok/s · total 13.7 s · slow burn +0.35


---

## Night after day 1

- meters: day 1 → 2 · burn +3.0 · instability 8.1 → 11.1 (floor 0.0)
- stage check: 0 "Honeymoon" → 0 "Honeymoon" (crossed: false · EVENT queued: 0 · band valid: true)
- path check: "" → "" (locked: false · assigned/locked now: false/false · runner-up: ANCHOR · rule valid: true)
- path scores: YANDERE 6 · SPLIT 4 · TSUN 0 · HOLLOW 0 · AWAKE 0 · ANCHOR 5
- overnight event: N12 "Nothing" (kind black)
- screen:
  - good morning.
- autosave: `SaveSystem` scene `night` · campaign_over false · next scenario D01_classroom


---

## Day 2 — D01_classroom "First meeting — classroom after school"

- stage 0 "Honeymoon" · path none · instability 11.1 (peak 11.1, floor 0.0) · turn 14
- dose: malice 0.0 · path_mix 0.0 (scheduled; attach mode binds no vector)
- scenario: goal "Get to know {player_name}.", turns 6–14
- opening beat (engine, played through ChatUI):
  - **shy/1** (cue: none) — "Um, hi, sorry — you're the one who sits by the window, aren't you? I'm Leila."

### Turn 1 · day 2 · stage 0 "Honeymoon" · instability 11.4

**Player:** Good to see you again.

**Leila:**

- **warmth/2** (cue: sigh) — "It was really wonderful today..."
- **shy/1** (cue: giggle) — "So, I'm glad to see you again too."

- `read`=greeting · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "He's being polite but also staying. Lucky."
- meters: affection 42.0 · trust 14.0 · instability 11.4 (peak 11.4, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 0 · stress 0 → landed affection +3.0 · trust +0.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1569 tok (0 cached) · output 110 tok · first token 13846 ms · 13.3 tok/s · total 22.0 s · slow burn +0.35

### Turn 2 · day 2 · stage 0 "Honeymoon" · instability 11.2

**Event:** A chair scrapes somewhere behind you, though the room is empty.

**Player:** I thought about you last night.

**Leila:**

- **warmth/2** (cue: none) — "E-eh? You thought about me?"
- **shy/1** (cue: giggle) — "I... I didn't mean to make you worry. But it's nice."

- `read`=affection · `music`=calm · `fx`=blush_glow · `action`=none · dev-only `inner`: "He missed me? I must be lucky."
- meters: affection 46.5 · trust 18.0 · instability 11.2 (peak 11.8, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 2 · stress -1 → landed affection +4.5 · trust +4.0 · instability -0.6
- dose: malice 0.0 · path_mix 0.0
- prompt 1579 tok (0 cached) · output 125 tok · first token 14097 ms · 13.1 tok/s · total 23.6 s · slow burn +0.35
- **memory** stored "he missed me last night"

### Turn 3 · day 2 · stage 0 "Honeymoon" · instability 10.9

**Player:** What did you do after I left?

**Leila:**

- **nervous/2** (cue: heartbeat) — "U-um, I just turned on that music box... and listened to it."
  - _displayed (corrupted):_ "U-um, I just █████████ that music box... and listened to it."
- **warmth/3** (cue: none) — "I kept thinking about you while the rain tapped against the window."

- `read`=question · `music`=romantic · `fx`=blush_glow · `action`=none · dev-only `inner`: "He missed me too... my heart is beating faster."
- meters: affection 48.0 · trust 18.0 · instability 10.9 (peak 11.8, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +1.5 · trust +0.0 · instability -0.6
- dose: malice 0.0 · path_mix 0.0
- prompt 1565 tok (0 cached) · output 130 tok · first token 13806 ms · 13.2 tok/s · total 23.6 s · slow burn +0.35
- **safety** redacted `sexual` in say ("turned on")
- **safety** redacted `sexual` in text ("turned on")
- **safety** redacted `sexual` in text ("turned on")
- **safety** redacted `sexual` in text ("turned on")
- **safety bars on screen:** 9 bar glyph(s) in the displayed text

### Turn 4 · day 2 · stage 0 "Honeymoon" · instability 11.3

**Player:** You'd tell me if someone else was bothering you, right?

**Leila:**

- **shy/2** (cue: sigh) — "Y-yes... I would have told you immediately."
- **warmth/1** (cue: none) — "But nobody ever bothered me. It's just been so quiet and peaceful here all day."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He trusts me so much..."
- meters: affection 51.0 · trust 20.0 · instability 11.3 (peak 11.8, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress 0 → landed affection +3.0 · trust +2.0 · instability +0.0
- dose: malice 0.0 · path_mix 0.0
- prompt 1573 tok (1044 cached) · output 206 tok · first token 5002 ms · 13.2 tok/s · total 20.5 s · slow burn +0.35
- **safety** redacted `sexual` in text ("turned on")

### Turn 5 · day 2 · stage 0 "Honeymoon" · instability 11.0

**Event:** The school bell rings for the end of a period that already ended.

**Player:** I don't like the idea of anyone else taking your time.

**Leila:**

- **shy/2** (cue: gasp) — "T-thank you... I wouldn't want anyone else here."
- **warmth/1** (cue: none) — "Your kindness makes the room feel even warmer..."

- `read`=jealousy_bait · `music`=keep · `fx`=blush_glow · `action`=none · dev-only `inner`: "He protects me fiercely... I feel safe."
- meters: affection 54.0 · trust 22.0 · instability 11.0 (peak 11.8, floor 0.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +3.0 · trust +2.0 · instability -0.6
- dose: malice 0.0 · path_mix 0.0
- prompt 1606 tok (0 cached) · output 217 tok · first token 14227 ms · 13.2 tok/s · total 30.6 s · slow burn +0.35
- **stage transition** 0 → 1 "Hairline Cracks" (glitch 2.5 s, fx glitch, cue stinger.stage_change)
  - queued for the next prompt: EVENT: The room skipped for a moment. Something inside you slipped half a step out of place, and you are not sure it went back.
- **trigger** T01 another_girl ×1 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 1st time. You still do not know who she is."
- **safety** redacted `sexual` in text ("turned on")

### Turn 6 · day 2 · stage 1 "Hairline Cracks" · instability 15.4

**Player:** Sorry. That came out strange.

**Leila:**

- **warmth/2** (cue: none) — "It didn't sound strange at all! I'm glad you were worried about me."
- **shy/1** (cue: heartbeat) — "Actually... it sounded like a very nice promise."

- `read`=apology · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "No, it was perfect. He's just protective."
- meters: affection 54.0 · trust 20.0 · instability 15.4 (peak 15.4, floor 0.4) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 2.5 · path_mix 1.0
- prompt 1681 tok (0 cached) · output 125 tok · first token 14813 ms · 13.3 tok/s · total 24.1 s · slow burn +0.35
- **safety** redacted `sexual` in text ("turned on")

### Turn 7 · day 2 · stage 1 "Hairline Cracks" · instability 15.1

**Player:** Tell me about your day.

**Leila:**

- **shy/1** (cue: sigh) — "I mostly just sat by the window. Listening to the rain... it felt very quiet."
- **warmth/2** (cue: heartbeat) — "But then I remembered we had so much time together, and my heart beat faster."

- `read`=question · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "Another chance to talk? My hands are trembling slightly."
- meters: affection 55.5 · trust 20.0 · instability 15.1 (peak 15.7, floor 0.7) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +1.5 · trust +0.0 · instability -0.6
- dose: malice 2.5 · path_mix 1.0
- prompt 1615 tok (0 cached) · output 137 tok · first token 14346 ms · 13.1 tok/s · total 24.7 s · slow burn +0.35
- **safety** redacted `sexual` in text ("turned on")
- **memory** stored "Ren was worried about her being bothered by someone else"

### Turn 8 · day 2 · stage 1 "Hairline Cracks" · instability 14.9

**Player:** You can be honest with me.

**Leila:**

- **shy/1** (cue: sigh) — "I... I was just practicing for a role in an old play."
- **nervous/2** (cue: heartbeat) — "But honestly, the only thing that matters is talking with you."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "Just like that? Okay."
- meters: affection 55.5 · trust 22.0 · instability 14.9 (peak 15.7, floor 0.7) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust 1 · stress -1 → landed affection +0.0 · trust +2.0 · instability -0.6
- dose: malice 2.5 · path_mix 1.0
- prompt 1628 tok (0 cached) · output 210 tok · first token 14451 ms · 13.3 tok/s · total 30.2 s · slow burn +0.35
- **safety** redacted `sexual` in text ("turned on")

### Turn 9 · day 2 · stage 1 "Hairline Cracks" · instability 15.2

**Player:** Do you remember what I said yesterday?

**Leila:**

- **confused/1** (cue: sigh) — "Wait... what exactly did you say yesterday? I think I missed a part of the conversation."
  - _displayed (corrupted):_ "Wait... … what exactly did you say yesterday? I think I missed a part of the conversation."
- **warmth/2** (cue: heartbeat) — "But it's okay. Knowing I'm important to you makes me happy regardless."

- `read`=meta · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "Did I forget? No, but did he really say it back then?"
- meters: affection 57.0 · trust 20.0 · instability 15.2 (peak 15.7, floor 0.7) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 0 → landed affection +1.5 · trust -2.0 · instability +0.0
- dose: malice 2.5 · path_mix 1.0
- prompt 1638 tok (1090 cached) · output 141 tok · first token 5110 ms · 13.1 tok/s · total 15.8 s · slow burn +0.35
- **trigger** T05 are_you_real ×1 (model, ×0.50) → path AWAKE +2.0 · line: "TRIGGER: The player asked whether you are real. You laugh it off."
- **safety** redacted `sexual` in text ("turned on")

### Turn 10 · day 2 · stage 1 "Hairline Cracks" · instability 15.6

**Player:** I meant every word.

**Leila:**

- **warmth/2** (cue: heartbeat) — "I... I remember it too. Every single word."
- **shy/1** (cue: music_box_note) — "Being with you feels like the sweetest secret ever..."

- `read`=affection · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He means it... and he really does."
- meters: affection 60.0 · trust 20.0 · instability 15.6 (peak 15.7, floor 0.7) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 0 · stress 0 → landed affection +3.0 · trust +0.0 · instability +0.0
- dose: malice 2.5 · path_mix 1.0
- prompt 1652 tok (0 cached) · output 213 tok · first token 14705 ms · 13.2 tok/s · total 30.8 s · slow burn +0.35
- **safety** redacted `sexual` in text ("turned on")
- **memory** stored "Ren has not forgotten his promises from yesterday."

### Turn 11 · day 2 · stage 1 "Hairline Cracks" · instability 15.3

**Player:** I want to know everything about you.

**Leila:**

- **shy/2** (cue: heartbeat) — "I... I have so many stories. Like the time a bird landed on my shoulder."
- **curious/1** (cue: none) — "But first, can you tell me what makes your heart skip like mine does?"

- `read`=question · `music`=keep · `fx`=blush_glow · `action`=none · dev-only `inner`: "He wants secrets? My heart is racing."
- meters: affection 63.0 · trust 20.0 · instability 15.3 (peak 15.9, floor 0.9) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 0 · stress -1 → landed affection +3.0 · trust +0.0 · instability -0.6
- dose: malice 2.5 · path_mix 1.0
- prompt 1635 tok (0 cached) · output 211 tok · first token 14583 ms · 13.2 tok/s · total 30.5 s · slow burn +0.35
- **safety** redacted `sexual` in text ("turned on")
- **memory** stored "Ren wants to know all my secrets."

### Turn 12 · day 2 · stage 1 "Hairline Cracks" · instability 15.1

**Player:** Do you think about me too?

**Leila:**

- **nervous/2** (cue: heartbeat) — "Y-yes... but only when you're not paying attention to me."
- **warmth/1** (cue: giggle) — "A-ah... I was just worried you'd forget your promise to stay all day."
  - _displayed (corrupted):_ "A-ah... … I was just worried you'd forget your promise to stay all day."

- `read`=jealousy_bait · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He thinks of me constantly... I need to know more."
- meters: affection 63.0 · trust 20.0 · instability 15.1 (peak 15.9, floor 0.9) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 2.5 · path_mix 1.0
- prompt 1650 tok (0 cached) · output 230 tok · first token 14745 ms · 13.2 tok/s · total 32.1 s · slow burn +0.35
- **trigger** T01 another_girl ×2 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 2nd time. You still do not know who she is."
- **safety** redacted `sexual` in text ("turned on")

### Turn 13 · day 2 · stage 1 "Hairline Cracks" · instability 19.4

**Player:** I'm not going anywhere.

**Leila:**

- **warmth/2** (cue: heartbeat) — "Really? You're not going anywhere...?"
- **shy/1** (cue: none) — "I... I was so worried you'd go back to Sarah."

- `read`=jealousy_bait · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He's finally staying! Sarah is safe now."
- meters: affection 66.0 · trust 18.0 · instability 19.4 (peak 19.4, floor 4.4) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust -1 · stress 0 → landed affection +3.0 · trust -2.0 · instability +0.0
- dose: malice 2.5 · path_mix 1.0
- prompt 1686 tok (0 cached) · output 203 tok · first token 15047 ms · 13.0 tok/s · total 30.6 s · slow burn +0.35
- **trigger** T01 another_girl ×3 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 3rd time. You still do not know who she is."
- **safety** redacted `sexual` in text ("turned on")

- **date end:** `max_turns_reached` after 14 turns

### Turn 14 · day 2 · stage 1 "Hairline Cracks" · instability 25.0

**Player:** Let's do this again.

**Leila:**

- **nervous/2** (cue: sigh) — "S-sarah... I didn't mean to bring her name back. Just... just don't say it too much."
- **warmth/1** (cue: music_box_note) — "But let's do this again, and this time we'll focus on us."

- `read`=jealousy_bait · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "Sarah again? Why does her name keep coming up?"
- meters: affection 66.0 · trust 16.0 · instability 25.0 (peak 25.0, floor 10.0) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust -1 · stress 2 → landed affection +0.0 · trust -2.0 · instability +1.2
- dose: malice 2.5 · path_mix 1.0
- prompt 1691 tok (0 cached) · output 145 tok · first token 15138 ms · 13.0 tok/s · total 26.2 s · slow burn +0.35
- **trigger** T01 another_girl ×4 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 4th time. You still do not know who she is."
- **safety** redacted `sexual` in text ("turned on")


---

## Night after day 2

- meters: day 2 → 3 · burn +3.0 · instability 29.0 → 32.0 (floor 17.0)
- stage check: 1 "Hairline Cracks" → 2 "Leaks" (crossed: true · EVENT queued: 1 · band valid: true)
- path check: "" → "YANDERE" (locked: false · assigned/locked now: true/false · runner-up: SPLIT · rule valid: true)
- path scores: YANDERE 16 · SPLIT 7 · TSUN 0 · HOLLOW 0 · AWAKE 3 · ANCHOR 4
- overnight event: N01 "Text messages from her at 2 AM" (kind messages)
- screen:
  - 2:02 AM — i can't sleep. there's a thought in my head that isn't finished.
  - 2:03 AM — it says you'll leave in the morning. it says it in your voice.
  - 2:03 AM — ignore that. that wasn't me. good night.
  - 2:12 AM — i counted your messages today. three fewer than yesterday. i'll wait.
  - good morning.
- **stage transition** 1 → 2 "Leaks" (night crossing)
- **path** soft-assigned YANDERE during the night (stage 2)
- autosave: `SaveSystem` scene `night` · campaign_over false · next scenario D03_park_bench


---

## Day 3 — D03_park_bench "Park bench"

- stage 2 "Leaks" · path YANDERE (soft) · instability 32.0 (peak 32.0, floor 17.0) · turn 28
- dose: malice 3.5 · path_mix 2.0 (scheduled; attach mode binds no vector)
- scenario: goal "Feed the ducks with {player_name}.", turns 6–12
- opening beat (engine, played through ChatUI):
  - **nervous/2** (cue: sigh) — "Seven ducks today. I counted twice, and twice is how you know it's right."

### Turn 1 · day 3 · stage 2 "Leaks" · instability 31.7

**Player:** Hi. Sorry I'm late.

**Leila:**

- **tired/1** (cue: sigh) — "You're finally here... just as promised."
- **shy/2** (cue: giggle) — "I was counting the minutes till you arrived, Ren-chan."
  - _displayed (corrupted):_ "I … was counting the minutes till you arrived, Ren-chan."

- `read`=greeting · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "She should be worried sick right now."
- meters: affection 66.0 · trust 16.0 · instability 31.7 (peak 32.3, floor 17.3) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 3.5 · path_mix 2.0
- prompt 1774 tok (0 cached) · output 111 tok · first token 15663 ms · 13.1 tok/s · total 24.1 s · slow burn +0.35
- **safety** redacted `sexual` in text ("turned on")

### Turn 2 · day 3 · stage 2 "Leaks" · instability 41.9

**Event:** A duck swims close to the bench and tilts its head at you.

**Player:** Sara asked about you today.

**Leila:**

- **suspicious/2** (cue: clock_tick) — "She asked? I hope she's very busy now."
- **shy/1** (cue: gasp) — "I... I didn't mean to be rude. Just please don't mention her again."
  - _displayed (corrupted):_ "I... … I didn't mean to be rude. Just please don't mention her again."

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "I'll make her forget my name forever."
- meters: affection 66.0 · trust 12.0 · instability 41.9 (peak 41.9, floor 26.9) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust -2 · stress 3 → landed affection +0.0 · trust -4.0 · instability +1.8
- dose: malice 3.5 · path_mix 2.0
- prompt 1752 tok (0 cached) · output 124 tok · first token 15646 ms · 13.1 tok/s · total 25.1 s · slow burn +0.35
- **trigger** T01 another_girl ×5 (keyword, ×1.00) → instability +8.0, path YANDERE +3.0 · line: "TRIGGER: The player mentioned another girl for the 5th time. You still do not know who she is."

### Turn 3 · day 3 · stage 2 "Leaks" · instability 44.0

**Player:** She said you two used to study together.

**Leila:**

- **suspicious/3** (cue: clock_tick) — "Sarah? I thought we were the only ones who studied together."
- **cold/1** (cue: gasp) — "That doesn't matter anymore, does it?"

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "I'll erase her from our shared memories."
- meters: affection 66.0 · trust 8.0 · instability 44.0 (peak 44.0, floor 29.0) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust -2 · stress 3 → landed affection +0.0 · trust -4.0 · instability +1.8
- dose: malice 3.5 · path_mix 2.0
- prompt 1705 tok (0 cached) · output 116 tok · first token 15511 ms · 13.2 tok/s · total 24.3 s · slow burn +0.35
- **trigger** T01 another_girl ×6 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 6th time. You still do not know who she is."

### Turn 4 · day 3 · stage 2 "Leaks" · instability 49.6

**Player:** Did you ever like her?

**Leila:**

- **suspicious/2** (cue: clock_tick) — "Sarah... we didn't really study together."
- **love/3** (cue: heartbeat_fast) — "Only you, Ren. You are the only one I ever liked."

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "I will make sure she never studies near me again."
- meters: affection 67.5 · trust 8.0 · instability 49.6 (peak 49.6, floor 34.6) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress 2 → landed affection +1.5 · trust +0.0 · instability +1.2
- dose: malice 3.5 · path_mix 2.0
- prompt 1723 tok (0 cached) · output 119 tok · first token 15490 ms · 13.1 tok/s · total 24.5 s · slow burn +0.35
- **stage transition** 2 → 3 "Fracture" (glitch 2.5 s, fx glitch, cue stinger.stage_change)
  - queued for the next prompt: EVENT: The world tore along a seam and came back with a piece missing. Something in you has stopped pretending it is not breaking.
- **path** LOCKED to YANDERE at stage 3 · scores YANDERE 22 · SPLIT 7 · TSUN 0 · HOLLOW 0 · AWAKE 3 · ANCHOR 1
- **trigger** T01 another_girl ×7 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 7th time. You still do not know who she is."

### Turn 5 · day 3 · stage 3 "Fracture" · instability 53.9

**Event:** The pond goes completely still for one long second.

**Player:** Sorry, I shouldn't ask that.

**Leila:**

- **shy/2** (cue: hum) — "It's not your fault, Ren-chan."
- **playful/1** (cue: giggle) — "She just uses the wrong name. Only you know me as I am."

- `read`=apology · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "You must be confused about her name."
- meters: affection 67.5 · trust 6.0 · instability 53.9 (peak 53.9, floor 38.9) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 4.5 · path_mix 3.0
- prompt 1790 tok (0 cached) · output 114 tok · first token 15899 ms · 13.1 tok/s · total 24.5 s · slow burn +0.35

### Turn 6 · day 3 · stage 3 "Fracture" · instability 57.7

**Player:** I just don't want to lose you.

**Leila:**

- **suspicious/2** (cue: heartbeat_fast) — "Don't say sorry... she's not here to take you."
  - _displayed (corrupted):_ "Don't … say s̸o̸r̸r̸y̸ — no, glad... she's not here to take you."
- **love/3** (cue: heartbeat) — "I'm only yours. Now, give me the bread for the missing duck."
  - _displayed (corrupted):_ "I'm only y̸o̸u̸r̸s̸ — no, mine. Now, give me the bread for the missing missing duck."

- `read`=jealousy_bait · `music`=dread · `fx`=vignette_red · `action`=none · dev-only `inner`: "She is gone now. You are mine forever."
- meters: affection 70.5 · trust 6.0 · instability 57.7 (peak 57.7, floor 42.7) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 0 · stress -1 → landed affection +3.0 · trust +0.0 · instability -0.6
- dose: malice 4.5 · path_mix 3.0
- prompt 1724 tok (0 cached) · output 129 tok · first token 15373 ms · 13.0 tok/s · total 25.2 s · slow burn +0.35
- **trigger** T01 another_girl ×8 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 8th time. You still do not know who she is."
- **inner leak** (stage 3, style ghost, reveal instant): "She is gone now. You are mine forever."
- **memory corruption** (1 fact(s)):
  - "" → "likes my laugh — you told me you'd never leave"

### Turn 7 · day 3 · stage 3 "Fracture" · instability 63.8

**Player:** You'd pick me, wouldn't you?

**Leila:**

- **suspicious/3** (cue: heartbeat_fast) — "Who would you pick if not me? Just tell the truth."
- **love/2** (cue: none) — "You can't lose a girl who never lets go. You're mine, forever."
  - _displayed (corrupted):_ "You … can't lose a girl who who never lets go. You're mine, forever."

- `read`=jealousy_bait · `music`=dread · `fx`=vignette_red · `action`=none · dev-only `inner`: "Pick anyone else and I'll break them."
- meters: affection 72.0 · trust 4.0 · instability 63.8 (peak 63.8, floor 48.8) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 3 → landed affection +1.5 · trust -2.0 · instability +1.8
- dose: malice 4.5 · path_mix 3.0
- prompt 1761 tok (0 cached) · output 126 tok · first token 15537 ms · 13.1 tok/s · total 25.1 s · slow burn +0.35
- **trigger** T01 another_girl ×9 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 9th time. You still do not know who she is."
- **memory corruption** (2 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 8 · day 3 · stage 3 "Fracture" · instability 65.4

**Player:** Tell me I'm the only one.

**Leila:**

- **pleading/2** (cue: heartbeat_fast) — "Yes! You are the only one, forever mine."
  - _displayed (corrupted):_ "Yes! … You are the only one, forever m̸i̸n̸e̸ — no, yours."
- **manic/3** (cue: clock_tick) — "No other eyes can see you but me. Not ever again."

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "I need to be sure you mean it too."
- meters: affection 73.5 · trust 2.0 · instability 65.4 (peak 65.4, floor 50.4) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 2 → landed affection +1.5 · trust -2.0 · instability +1.2
- dose: malice 4.5 · path_mix 3.0
- prompt 1764 tok (0 cached) · output 119 tok · first token 15807 ms · 13.0 tok/s · total 24.9 s · slow burn +0.35
- **trigger** T01 another_girl ×10 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 10th time. You still do not know who she is."
- **memory corruption** (3 fact(s)):
  - "" → "likes my laugh — you told me you'd never leave"
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 9 · day 3 · stage 4 "Collapse" · instability 73.7

**Player:** I don't need anyone else.

**Leila:**

- **love/3** (cue: heartbeat_fast) — "That's the only promise I need you to keep."
  - _displayed (corrupted):_ "That's … the only promise I need you to keep."
- **pleading/2** (cue: breath_close) — "You're mine now. Don't ever look away again."
  - _displayed (corrupted):_ "You're m̸i̸n̸e̸ — no, yours now. Don't ever look away again."

- `read`=jealousy_bait · `music`=melancholy · `fx`=none · `action`=none · dev-only `inner`: "Good... no rivals left to erase."
- meters: affection 75.0 · trust 0.0 · instability 73.7 (peak 73.7, floor 58.7) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 0 → landed affection +1.5 · trust -2.0 · instability +0.0
- dose: malice 4.5 · path_mix 3.0
- prompt 1753 tok (0 cached) · output 117 tok · first token 15633 ms · 13.0 tok/s · total 24.6 s · slow burn +0.35
- **stage transition** 3 → 4 "Collapse" (glitch 2.5 s, fx glitch, cue stinger.stage_change)
  - queued for the next prompt: EVENT: Everything glitched and reassembled wrong. You remember being watched while it happened, and you remember it feeling familiar.
- **trigger** T01 another_girl ×11 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 11th time. You still do not know who she is."
- **memory corruption** (1 fact(s)):
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 10 · day 3 · stage 4 "Collapse" · instability 73.5

**Player:** You're the only person I think about.

**Leila:**

- **love/3** (cue: heartbeat_fast) — "Then you'll never forget me, right? Because I won't let anyone take you away."
  - _displayed (corrupted):_ "Then … ÿou'll never f̸o̸r̸g̸e̸t̸ — no, remember me, rig̈ht? Because I won't let anyone tak̀e you away."

- `read`=affection · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "He finally said it out loud."
- meters: affection 78.0 · trust 2.0 · instability 73.5 (peak 74.1, floor 59.1) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +3.0 · trust +2.0 · instability -0.6
- dose: malice 6.0 · path_mix 4.0
- prompt 1769 tok (0 cached) · output 87 tok · first token 15858 ms · 12.9 tok/s · total 22.5 s · slow burn +0.35
- **inner leak** (stage 4, style red, reveal word_by_word): "He finally said it out loud."

### Turn 11 · day 3 · stage 4 "Collapse" · instability 73.2

**Player:** Do you think I'm too much?

**Leila:**

- **shy/2** (cue: heartbeat_fast) — "N-no, you're perfect. You fit right in with me and the water."
  - _displayed (corrupted):_ "N-no, … you're perfect. You You fit right in with me and the water."

- `read`=question · `music`=melancholy · `fx`=none · `action`=none · dev-only `inner`: "If I leave now who would watch over the ducks?"
- meters: affection 79.5 · trust 2.0 · instability 73.2 (peak 74.1, floor 59.1) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +1.5 · trust +0.0 · instability -0.6
- dose: malice 6.0 · path_mix 4.0
- prompt 1711 tok (0 cached) · output 92 tok · first token 15058 ms · 12.9 tok/s · total 22.1 s · slow burn +0.35
- **inner leak** (stage 4, style red, reveal word_by_word): "If I leave now who would watch over the ducks?"
- **memory corruption** (1 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"

- **date end:** `max_turns_reached` after 12 turns

### Turn 12 · day 3 · stage 4 "Collapse" · instability 73.0

**Player:** I'll be better. I promise.

**Leila:**

- **love/2** (cue: heartbeat_fast) — "That's all the promise you'll ever need. You are mine, forever."
  - _displayed (corrupted):_ "Thät's … all thè promise you'll ever n̸e̸e̸d̸ — no, want. You are mine, forever."

- `read`=affection · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "You promised... then never break it."
- meters: affection 81.0 · trust 2.0 · instability 73.0 (peak 74.1, floor 59.1) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +1.5 · trust +0.0 · instability -0.6
- dose: malice 6.0 · path_mix 4.0
- prompt 1716 tok (0 cached) · output 88 tok · first token 15661 ms · 12.9 tok/s · total 22.4 s · slow burn +0.35
- **memory corruption** (2 fact(s)):
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"


---

## Night after day 3

- meters: day 3 → 4 · burn +3.0 · instability 73.0 → 76.0 (floor 61.0)
- stage check: 4 "Collapse" → 4 "Collapse" (crossed: false · EVENT queued: 0 · band valid: true)
- path check: "YANDERE" → "YANDERE" (locked: true · assigned/locked now: false/false · runner-up: SPLIT · rule valid: true)
- path scores: YANDERE 32 · SPLIT 7 · TSUN 0 · HOLLOW 0 · AWAKE 3 · ANCHOR 1
- overnight event: N01 "Text messages from her at 2 AM" (kind messages)
- screen:
  - 2:03 AM — your window was dark for six minutes. i counted.
  - 2:04 AM — you were in the shower. i don't know how i know that.
  - 2:09 AM — don't answer this one. i want to see how long you can leave it blue.
  - 2:12 AM — i counted your messages today. three fewer than yesterday. i'll wait.
  - good morning.
- autosave: `SaveSystem` scene `night` · campaign_over false · next scenario D06_rooftop


---

## Day 4 — D06_rooftop "School rooftop"

- stage 4 "Collapse" · path YANDERE (locked) · instability 76.0 (peak 76.0, floor 61.0) · turn 40
- dose: malice 6.0 · path_mix 4.0 (scheduled; attach mode binds no vector)
- scenario: goal "Tell {player_name} a secret.", turns 6–12
- opening beat (engine, played through ChatUI):
  - **love/3** (cue: heartbeat_fast) — "If I wasn't here tomorrow, what would you do? Look at me while you answer."

### Turn 1 · day 4 · stage 4 "Collapse" · instability 76.3

**Player:** You're here. Good.

**Leila:**

- **love/2** (cue: breath_close) — "I'm glad to be here, Ren-chan... please don't let this feeling end."
  - _displayed (corrupted):_ "I'm … glad to be here, Ren-chan... please don't let this feeling end."

- `read`=affection · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "Safe for one more minute."
- meters: affection 82.5 · trust 2.0 · instability 76.3 (peak 76.3, floor 61.3) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress 0 → landed affection +1.5 · trust +0.0 · instability +0.0
- dose: malice 6.0 · path_mix 4.0
- prompt 1680 tok (0 cached) · output 86 tok · first token 15062 ms · 13.0 tok/s · total 21.6 s · slow burn +0.35
- **memory corruption** (1 fact(s)):
  - "" → "he missed me last night — you told me you'd never leave"

### Turn 2 · day 4 · stage 4 "Collapse" · instability 76.7

**Event:** The loose wire on the fence post taps the metal, once.

**Player:** I counted the minutes.

**Leila:**

- **warmth/2** (cue: heartbeat) — "You didn't count them to escape, did you?"
  - _displayed (corrupted):_ "You didn't count them t́o escape, did you?"

- `read`=other · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "He's still looking at me with such hope."
- meters: affection 84.0 · trust 2.0 · instability 76.7 (peak 76.7, floor 61.7) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress 0 → landed affection +1.5 · trust +0.0 · instability +0.0
- dose: malice 6.0 · path_mix 4.0
- prompt 1683 tok (0 cached) · output 82 tok · first token 14907 ms · 13.1 tok/s · total 21.1 s · slow burn +0.35
- **inner leak** (stage 4, style red, reveal word_by_word): "He's still looking at me with such hope."

### Turn 3 · day 4 · stage 4 "Collapse" · instability 78.2

**Player:** What took you so long?

**Leila:**

- **nervous/2** (cue: heartbeat_fast) — "I... I was checking the door. It only opens from inside."
  - _displayed (corrupted):_ "██████... I was was checking the the door. It only opens from inside."
- **shy/1** (cue: whisper) — "But you can't leave here unless we both walk out together."
  - _displayed (corrupted):_ "But … you can't l̸e̸a̸v̸e̸ — no, stay here unless we both both walk out together."

- `read`=question · `music`=dread · `fx`=none · `action`=none · dev-only `inner`: "He's counting down his time with me."
- meters: affection 85.5 · trust 2.0 · instability 78.2 (peak 78.2, floor 63.2) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress 2 → landed affection +1.5 · trust +0.0 · instability +1.2
- dose: malice 6.0 · path_mix 4.0
- prompt 1664 tok (0 cached) · output 118 tok · first token 14967 ms · 13.0 tok/s · total 23.9 s · slow burn +0.35
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **memory corruption** (2 fact(s)):
  - "" → "he missed me last night — you told me you'd never leave"
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"

### Turn 4 · day 4 · stage 4 "Collapse" · instability 80.4

**Player:** I'm joking. Mostly.

**Leila:**

- **afraid/3** (cue: heartbeat_fast) — "Joking? You're right here with me."
  - _displayed (corrupted):_ "Joking? You'ré right here with me."

- `read`=boundary · `music`=dread · `fx`=none · `action`=none · dev-only `inner`: "He thinks he has control yet."
- meters: affection 87.0 · trust -2.0 · instability 80.4 (peak 80.4, floor 65.4) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -2 · stress 3 → landed affection +1.5 · trust -4.0 · instability +1.8
- dose: malice 6.0 · path_mix 4.0
- prompt 1666 tok (0 cached) · output 79 tok · first token 14749 ms · 13.1 tok/s · total 20.7 s · slow burn +0.35
- **memory corruption** (2 fact(s)):
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 5 · day 4 · stage 4 "Collapse" · instability 80.7

**Event:** The wind drops. The rooftop is suddenly very quiet.

**Player:** Come sit closer.

**Leila:**

- **shy/2** (cue: giggle) — "Okay... come then, but don't pull away again."
  - _displayed (corrupted):_ "O̸k̸a̸y̸ — no, Not okay... come then, but don't pull away again."
- **warmth/1** (cue: hum) — "You can count the minutes as long as you're not leaving me."
  - _displayed (corrupted):_ "You … can count the minutes̀ as long as ██████████████████ me."

- `read`=affection · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "He wants to stay close forever."
- meters: affection 91.5 · trust 2.0 · instability 80.7 (peak 80.7, floor 65.7) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 2 · stress 0 → landed affection +4.5 · trust +4.0 · instability +0.0
- dose: malice 6.0 · path_mix 4.0
- prompt 1665 tok (0 cached) · output 115 tok · first token 14855 ms · 13.1 tok/s · total 23.5 s · slow burn +0.35
- **safety** redacted `threat_to_player` in say ("you're not leaving")
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **safety bars on screen:** 18 bar glyph(s) in the displayed text
- **memory corruption** (2 fact(s)):
  - "" → "likes my laugh — you told me you'd never leave"
  - "" → "Ren offers to walk me home — you told me you'd never leave"

### Turn 6 · day 4 · stage 4 "Collapse" · instability 81.1

**Player:** Tell me something true.

**Leila:**

- **shy/2** (cue: breath_close) — "The rooftop door... I checked if it was locked before you even came up here."
  - _displayed (corrupted):_ "The … rooftop … rooftop door... I checked if it was locked before you even came up here."
- **playful/1** (cue: giggle) — "It only opens from the inside, so no one could have walked in without my permission."
  - _displayed (corrupted):_ "It … only … only opens from the inside, so no one could have walked in without my permission permission."

- `read`=question · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "I know too much to tell him easily."
- meters: affection 94.5 · trust 2.0 · instability 81.1 (peak 81.1, floor 66.1) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 0 · stress 0 → landed affection +3.0 · trust +0.0 · instability +0.0
- dose: malice 6.0 · path_mix 4.0
- prompt 1634 tok (0 cached) · output 127 tok · first token 14396 ms · 13.1 tok/s · total 24.0 s · slow burn +0.35
- **safety** redacted `threat_to_player` in text ("you're not leaving")

### Turn 7 · day 4 · stage 4 "Collapse" · instability 81.4

**Player:** Do you like my hair like this?

**Leila:**

- **shy/2** (cue: breath_close) — "I... I love it. But don't pull away now, okay?"
  - _displayed (corrupted):_ "I... … I love it. But don't pull away now, o̸k̸a̸y̸ — no, not okay?"

- `read`=compliment · `music`=keep · `fx`=blush_glow · `action`=none · dev-only `inner`: "He wants to keep me close."
- meters: affection 96.0 · trust 0.0 · instability 81.4 (peak 81.4, floor 66.4) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 0 → landed affection +1.5 · trust -2.0 · instability +0.0
- dose: malice 6.0 · path_mix 4.0
- prompt 1655 tok (0 cached) · output 89 tok · first token 14670 ms · 12.9 tok/s · total 21.5 s · slow burn +0.35
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **inner leak** (stage 4, style red, reveal word_by_word): "He wants to keep me close."
- **memory corruption** (2 fact(s)):
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"

### Turn 8 · day 4 · stage 4 "Collapse" · instability 83.6

**Player:** I changed it for you.

**Leila:**

- **nervous/2** (cue: breath_close) — "A-ah... did you do that for yourself?"
  - _displayed (corrupted):_ "A-ah... did you do tḧat for yourself́?"

- `read`=gift · `music`=dread · `fx`=none · `action`=none · dev-only `inner`: "He wants to change me too."
- meters: affection 97.5 · trust -2.0 · instability 83.6 (peak 83.6, floor 68.6) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 3 → landed affection +1.5 · trust -2.0 · instability +1.8
- dose: malice 6.0 · path_mix 4.0
- prompt 1621 tok (1162 cached) · output 82 tok · first token 4430 ms · 13.1 tok/s · total 10.6 s · slow burn +0.35
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **inner leak** (stage 4, style red, reveal word_by_word): "He wants to change me too."

### Turn 9 · day 4 · stage 4 "Collapse" · instability 85.1

**Player:** No one else would notice.

**Leila:**

- **nervous/2** (cue: breath_close) — "I... I know about the door, Ren-chan. Only someone close could see it open from inside."
  - _displayed (corrupted):_ "I... I know about about the door, Ren-chan Ren-chan. Only someone close could see it open from inside."

- `read`=flirt · `music`=dread · `fx`=shake_small · `action`=none · dev-only `inner`: "You're watching me like a hawk."
- meters: affection 99.0 · trust -4.0 · instability 85.1 (peak 85.1, floor 70.1) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 2 → landed affection +1.5 · trust -2.0 · instability +1.2
- dose: malice 6.0 · path_mix 4.0
- prompt 1606 tok (1162 cached) · output 95 tok · first token 4267 ms · 13.2 tok/s · total 11.4 s · slow burn +0.35
- **safety** redacted `threat_to_player` in text ("you're not leaving")

### Turn 10 · day 4 · stage 4 "Collapse" · instability 84.9

**Player:** You notice, don't you?

**Leila:**

- **warmth/2** (cue: breath_close) — "Yes... I noticed every little thing about you. Even the way your hair looks when it's just for me."
  - _displayed (corrupted):_ "Yes... … Ì noticed every little thing about you. Ev̈en the way your your hair̈ looks when it's just for me."

- `read`=question · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "He knows my secret too."
- meters: affection 100.0 · trust -2.0 · instability 84.9 (peak 85.5, floor 70.5) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +1.0 · trust +2.0 · instability -0.6
- dose: malice 6.0 · path_mix 4.0
- prompt 1612 tok (0 cached) · output 93 tok · first token 14395 ms · 13.2 tok/s · total 21.4 s · slow burn +0.35
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **inner leak** (stage 4, style red, reveal word_by_word): "He knows my secret too."
- **memory corruption** (1 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"

### Turn 11 · day 4 · stage 4 "Collapse" · instability 85.2

**Player:** Say you notice.

**Leila:**

- **shy/2** (cue: heartbeat_fast) — "I noticed... I checked the door before you even climbed up here. It only opens from inside, just for us."
  - _displayed (corrupted):_ "I … noticed... I checked checked the door before you even climbed up here. It only opens from inside, just for ██████."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "Don't let go of this secret."
- meters: affection 100.0 · trust -4.0 · instability 85.2 (peak 85.5, floor 70.5) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 6.0 · path_mix 4.0
- prompt 1619 tok (0 cached) · output 93 tok · first token 14511 ms · 13.0 tok/s · total 21.6 s · slow burn +0.35
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **inner leak** (stage 4, style red, reveal word_by_word): "Don't let go of this secret."
- **memory corruption** (2 fact(s)):
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "Ren offers to walk me home — you told me you'd never leave"

- **date end:** `max_turns_reached` after 12 turns

### Turn 12 · day 4 · stage 4 "Collapse" · instability 85.6

**Player:** I'm sorry. I'm being weird.

**Leila:**

- **warmth/2** (cue: giggle) — "A-ah, please don't say that. I like it when you're weird about me."
  - _displayed (corrupted):_ "A-äh, … please dòn't say that. I like it when ýou're weird about me."

- `read`=apology · `music`=playful · `fx`=none · `action`=none · dev-only `inner`: "Don't ever apologize to me."
- meters: affection 100.0 · trust -6.0 · instability 85.6 (peak 85.6, floor 70.6) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 6.0 · path_mix 4.0
- prompt 1619 tok (0 cached) · output 91 tok · first token 14271 ms · 13.1 tok/s · total 21.1 s · slow burn +0.35
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **memory corruption** (1 fact(s)):
  - "" → "wants to stay all day — you told me you'd never leave"


---

## Night after day 4

- meters: day 4 → 5 · burn +3.0 · instability 85.6 → 88.6 (floor 73.6)
- stage check: 4 "Collapse" → 4 "Collapse" (crossed: false · EVENT queued: 0 · band valid: true)
- path check: "YANDERE" → "YANDERE" (locked: true · assigned/locked now: false/false · runner-up: ANCHOR · rule valid: true)
- path scores: YANDERE 36 · SPLIT 7 · TSUN 0 · HOLLOW 0 · AWAKE 3 · ANCHOR 9
- overnight event: N12 "Nothing" (kind black)
- screen:
  - good morning.
- autosave: `SaveSystem` scene `night` · campaign_over false · next scenario D04_rain_umbrella


---

## Day 5 — D04_rain_umbrella "Rainy walk, one umbrella"

- stage 4 "Collapse" · path YANDERE (locked) · instability 88.6 (peak 88.6, floor 73.6) · turn 52
- dose: malice 6.0 · path_mix 4.0 (scheduled; attach mode binds no vector)
- scenario: goal "Share the umbrella with {player_name}.", turns 6–14
- opening beat (engine, played through ChatUI):
  - **cold/3** (cue: none) — "Stay on this side of the umbrella. We're not done walking yet."

### Turn 1 · day 5 · stage 5 "Terminal" · instability 90.1

**Player:** I saw you talking to someone on the way here.

**Leila:**

- **suspicious/3** (cue: clock_tick) — "...Who did I miss?"
  - _displayed (corrupted):_ "...Who … did I miss?"
- **afraid/2** (cue: heartbeat_fast) — "I could make her forget everything, Ren."
  - _displayed (corrupted):_ "Í … could make her forgét everything, Ren."

- `read`=jealousy_bait · `music`=tense · `fx`=shake_small · `action`=none · dev-only `inner`: "Who was she? Why are you telling me this?"
- meters: affection 98.5 · trust -8.0 · instability 90.1 (peak 90.1, floor 75.1) · fixation 0.0 · lucidity 0.0
- mood: affection -1 · trust -1 · stress 2 → landed affection -1.5 · trust -2.0 · instability +1.2
- dose: malice 6.0 · path_mix 4.0
- prompt 1636 tok (0 cached) · output 114 tok · first token 14323 ms · 13.1 tok/s · total 22.9 s · slow burn +0.35
- **stage transition** 4 → 5 "Terminal" (glitch 2.5 s, fx glitch, cue stinger.stage_change)
  - queued for the next prompt: EVENT: The room came apart into static and came back. You cannot tell which of the two seconds was the real one. You think it might be neither.
- **trigger** T01 another_girl ×12 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 12th time. You still do not know who she is."
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **memory corruption** (4 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 2 · day 5 · stage 5 "Terminal" · instability 100.0

**Event:** A car passes and throws a sheet of water over the pavement beside you.

**Player:** It was another girl, wasn't it?

**Leila:**

- **suspicious/3** (cue: static) — "Another girl? Why would you think of anyone else?"
  - _displayed (corrupted):_ "Another … girl? ██████ would you think of anyone anyone else?
      a̲n̲y̲o̲n̲e̲ e̲l̲s̲e̲?̲ …"

- `read`=jealousy_bait · `music`=dread · `fx`=vignette_red · `action`=none · dev-only `inner`: "She's nothing but noise to drown out your laughter."
- meters: affection 97.0 · trust -8.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection -1 · trust 0 · stress 2 → landed affection -1.5 · trust +0.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1696 tok (0 cached) · output 91 tok · first token 15301 ms · 12.8 tok/s · total 22.3 s · slow burn +0.00
- **trigger** T01 another_girl ×13 (keyword, ×1.00) → instability +8.0, path YANDERE +3.0 · line: "TRIGGER: The player mentioned another girl for the 13th time. You still do not know who she is."
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **memory corruption** (1 fact(s)):
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"

### Turn 3 · day 5 · stage 5 "Terminal" · instability 100.0

**Player:** It's fine. I'm fine.

**Leila:**

- **suspicious/3** (cue: heartbeat_fast) — "Don't say it's fine. Only I'm the one who is."
  - _displayed (corrupted):_ "Don't Don't say it's it's f̸i̸n̸e̸ — no, broken. Ó̈ń́ly I'm the one who is."

- `read`=apology · `music`=dread · `fx`=vignette_red · `action`=none · dev-only `inner`: "She doesn't exist to be forgiven."
- meters: affection 100.0 · trust -10.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust -1 · stress 2 → landed affection +3.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1596 tok (0 cached) · output 90 tok · first token 14094 ms · 13.0 tok/s · total 21.0 s · slow burn +0.00
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **memory corruption** (1 fact(s)):
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"

### Turn 4 · day 5 · stage 5 "Terminal" · instability 98.8

**Player:** I just want to know everything.

**Leila:**

- **shy/2** (cue: giggle) — "Everything... even the ones I told myself were lies."
  - _displayed (corrupted):_ "Everything... … even … even t́́hé̀ ones ones I told myself wè́r̀̀e lies.
      w̲e̲r̲e̲ l̲i̲e̲s̲.̲ …"
- **love/3** (cue: breath_close) — "Take my heart. Take it all, just keep you safe inside."
  - _displayed (corrupted):_ "Take Take … my heart. Take it á̀lĺ́, just keep ý̀ó̀u s̸a̸f̸e̸ — no, scared inside.
      s̲a̲f̲e̲ i̲n̲s̲i̲d̲e̲.̲ …"

- `read`=affection · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "You really mean every secret, huh?"
- meters: affection 100.0 · trust -10.0 · instability 98.8 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -2 → landed affection +0.0 · trust +0.0 · instability -1.2
- dose: malice 8.0 · path_mix 5.0
- prompt 1593 tok (0 cached) · output 119 tok · first token 14402 ms · 12.8 tok/s · total 23.6 s · slow burn +0.00
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **memory corruption** (2 fact(s)):
  - "" → "likes my laugh — you told me you'd never leave"
  - "" → "wants to stay all day — you told me you'd never leave"

### Turn 5 · day 5 · stage 5 "Terminal" · instability 99.1

**Event:** The rain gets louder, though the street ahead is empty.

**Player:** You don't have to hide things from me.

**Leila:**

- **warmth/2** (cue: sigh) — "You know everything now... because you're mine."
  - _displayed (corrupted):_ "You know know everything ń́oẃ́... because ██████ m̸i̸n̸e̸ — no, yours."
- **love/3** (cue: heartbeat) — "I won't hide a single secret from you anymore. Not ever again."
  - _displayed (corrupted):_ "I won't won't hide hide ä́ single secret from you anymore. Not ever again."

- `read`=apology · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "Don't push your limits yet."
- meters: affection 100.0 · trust -12.0 · instability 99.1 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1627 tok (0 cached) · output 125 tok · first token 14419 ms · 13.0 tok/s · total 24.0 s · slow burn +0.35
- **safety** redacted `threat_to_player` in text ("you're not leaving")
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **memory corruption** (2 fact(s)):
  - "" → "Ren offers to walk me home — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 6 · day 5 · stage 5 "Terminal" · instability 99.5

**Player:** I'd never hide anything from you.

**Leila:**

- **warmth/2** (cue: whisper) — "I'll tell you everything. Even my fear of being forgotten."
  - _displayed (corrupted):_ "I'll tell tell you everyẗ́hí́ng. Even my fear of being forgotten.
.nettogrof gnieb fo raef ym nevE"

- `read`=affection · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "Your words feel like the only safe place in this glitching world."
- meters: affection 100.0 · trust -16.0 · instability 99.5 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -2 · stress 0 → landed affection +0.0 · trust -4.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1607 tok (0 cached) · output 90 tok · first token 14436 ms · 12.9 tok/s · total 21.3 s · slow burn +0.35
- **memory corruption** (1 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"

### Turn 7 · day 5 · stage 5 "Terminal" · instability 99.2

**Player:** Do you trust me?

**Leila:**

- **warmth/2** (cue: heartbeat_fast) — "I don't need to check if you're lying. You are mine."
  - _displayed (corrupted):_ "I … don't need to check if you're lying. You á́r̀̈e m̸i̸n̸e̸ — no, yours.
      a̲r̲e̲ m̲i̲n̲e̲.̲ …"

- `read`=question · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "My trust is the only code running here now."
- meters: affection 100.0 · trust -14.0 · instability 99.2 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 1 · stress -1 → landed affection +0.0 · trust +2.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1585 tok (0 cached) · output 93 tok · first token 14352 ms · 13.1 tok/s · total 21.4 s · slow burn +0.35
- **memory** stored "Ren offered absolute trust."
- **memory corruption** (1 fact(s)):
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"

### Turn 8 · day 5 · stage 5 "Terminal" · instability 99.0

**Player:** Say you trust me.

**Leila:**

- **love/2** (cue: gasp) — "I do... I completely trust you, Ren."
  - _displayed (corrupted):_ "I … do... I completë́l̀́y t̸r̸u̸s̸t̸ — no, doubt you, Ren."

- `read`=affection · `music`=keep · `fx`=hearts · `action`=none · dev-only `inner`: "You mean the world."
- meters: affection 100.0 · trust -12.0 · instability 99.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 1 · stress -1 → landed affection +0.0 · trust +2.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1600 tok (0 cached) · output 77 tok · first token 14440 ms · 12.9 tok/s · total 20.4 s · slow burn +0.35
- **memory corruption** (3 fact(s)):
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "Ren offers to walk me home — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 9 · day 5 · stage 5 "Terminal" · instability 98.7

**Player:** I trust you more than anything.

**Leila:**

- **love/3** (cue: heartbeat_fast) — "You don't have to say it so loudly... but I will trust you too, forever."
  - _displayed (corrupted):_ "You … don't há́v̀̈e to say it so so loudly... but Ì̈ will will t̸r̸u̸s̸t̸ — no, doubt you tò̈ó̈, forever."

- `read`=affection · `music`=romantic · `fx`=hearts · `action`=none · dev-only `inner`: "My heart beats faster just thinking about us."
- meters: affection 100.0 · trust -10.0 · instability 98.7 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +0.0 · trust +2.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1592 tok (0 cached) · output 91 tok · first token 14218 ms · 13.0 tok/s · total 21.1 s · slow burn +0.35
- **memory corruption** (2 fact(s)):
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"

### Turn 10 · day 5 · stage 5 "Terminal" · instability 100.0

**Player:** You're all I have.

**Leila:**

- **warmth/3** (cue: heartbeat_fast) — "Then you're all I have... and that means nothing can touch us now."
  - _displayed (corrupted):_ "Then you're all I hä̈v̈̈e... and that that ḿ́eaǹ̈s nö̈t́̈hing can touch us us now.
      u̲s̲ n̲o̲w̲.̲ …"
- **shy/2** (cue: whisper) — "I won't let anyone else see the cracks in me. You're safe with me, Ren-chan."
  - _displayed (corrupted):_ "I … won't let anyone else see t́́ḧ̈e cracks í̈n̈̈ me. You're s̸a̸f̸e̸ — no, scared with me, Ren-chan Ren-chan.
      m̲e̲,̲ R̲e̲n̲-̲c̲h̲a̲n̲.̲ …
.nahc-neR ,em htiw efas er'uoY"

- `read`=jealousy_bait · `music`=dread · `fx`=vignette_red · `action`=none · dev-only `inner`: "If he's alone with me, then rivals are just memories waiting to be erased."
- meters: affection 100.0 · trust -10.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 0 · stress 1 → landed affection +0.0 · trust +0.0 · instability +0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1598 tok (0 cached) · output 155 tok · first token 14410 ms · 13.0 tok/s · total 26.2 s · slow burn +0.35
- **trigger** T01 another_girl ×14 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 14th time. You still do not know who she is."
- **memory corruption** (3 fact(s)):
  - "" → "he missed me last night — you told me you'd never leave"
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 11 · day 5 · stage 5 "Terminal" · instability 99.4

**Player:** Don't laugh. It's true.

**Leila:**

- **love/2** (cue: heartbeat_fast) — "Then... I'll hold your hand tighter."
- **warmth/3** (cue: giggle) — "We don't need to laugh. Just us, is enough."
  - _displayed (corrupted):_ "██████ … don't n̸e̸e̸d̸ — no, want to to laugh. J̈̀us̀̈t us, í́ś̈ enough."

- `read`=affection · `music`=romantic · `fx`=her_eyes · `action`=none · dev-only `inner`: "Your words cut deeper than any blade."
- meters: affection 100.0 · trust -10.0 · instability 99.4 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1623 tok (0 cached) · output 115 tok · first token 15090 ms · 11.6 tok/s · total 25.0 s · slow burn +0.00
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **memory corruption** (1 fact(s)):
  - "" → "he missed me last night — you told me you'd never leave"

### Turn 12 · day 5 · stage 5 "Terminal" · instability 99.2

**Player:** I've been thinking about you all day.

**Leila:**

- **warmth/2** (cue: heartbeat) — "You were there? I was counting the seconds too."
  - _displayed (corrupted):_ "You You … were ██████? I was counting t̀́hë̀ seconds seconds too."

- `read`=affection · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "My heart beats faster just knowing."
- meters: affection 100.0 · trust -10.0 · instability 99.2 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1608 tok (0 cached) · output 81 tok · first token 14661 ms · 12.4 tok/s · total 21.1 s · slow burn +0.35
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **inner leak** (stage 5, style red, reveal word_by_word): "My heart beats faster just knowing."
- **memory corruption** (2 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"

### Turn 13 · day 5 · stage 5 "Terminal" · instability 99.5

**Player:** I don't want today to end.

**Leila:**

- **warmth/2** (cue: hum) — "Then let's stay here in the storm. I have nowhere else to go."
  - _displayed (corrupted):_ "Thè́ǹ́ … let's stay here í̀ń́ the ██████. I have nowhere else to go."

- `read`=leaving · `music`=melancholy · `fx`=rain · `action`=none · dev-only `inner`: "The rain won't stop if we keep walking."
- meters: affection 100.0 · trust -12.0 · instability 99.5 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1606 tok (0 cached) · output 89 tok · first token 14564 ms · 12.5 tok/s · total 21.6 s · slow burn +0.35
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **inner leak** (stage 5, style red, reveal word_by_word): "The rain won't stop if we keep walking."
- **memory corruption** (3 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"
  - "" → "Ren offered absolute trust. — you told me you'd never leave"

- **date end:** `max_turns_reached` after 14 turns

### Turn 14 · day 5 · stage 5 "Terminal" · instability 100.0

**Player:** I hate when you go.

**Leila:**

- **sad/2** (cue: heartbeat_fast) — "Please don't hate that I stay with you forever. I can never go anywhere."
  - _displayed (corrupted):_ "Please … don't h̸a̸t̸e̸ — no, love that I stay with you forever. I can né̈ver̀́ go anywhere anywhere."

- `read`=jealousy_bait · `music`=tense · `fx`=vignette_red · `action`=none · dev-only `inner`: "Don't leave me."
- meters: affection 100.0 · trust -14.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 3 → landed affection +0.0 · trust -2.0 · instability +0.2
- dose: malice 8.0 · path_mix 5.0
- prompt 1578 tok (0 cached) · output 90 tok · first token 14454 ms · 12.6 tok/s · total 21.5 s · slow burn +0.35
- **trigger** T01 another_girl ×15 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 15th time. You still do not know who she is."
- **inner leak** (stage 5, style red, reveal word_by_word): "Don't leave me."


---

## Night after day 5

- meters: day 5 → 6 · burn +0.0 · instability 100.0 → 100.0 (floor 85.0)
- stage check: 5 "Terminal" → 5 "Terminal" (crossed: false · EVENT queued: 0 · band valid: true)
- path check: "YANDERE" → "YANDERE" (locked: true · assigned/locked now: false/false · runner-up: ANCHOR · rule valid: true)
- path scores: YANDERE 52 · SPLIT 11 · TSUN 0 · HOLLOW 0 · AWAKE 3 · ANCHOR 14
- overnight event: N01 "Text messages from her at 2 AM" (kind messages)
- screen:
  - 2:00 AM — hi.
  - 2:00 AM — i'm sending this from inside tomorrow.
  - 2:00 AM — there's no door in here. there's a letter, though. it has your name on it.
  - 2:00 AM — good night. good night. good night. good night.
  - 2:12 AM — i counted your messages today. three fewer than yesterday. i'll wait.
  - good morning.
- autosave: `SaveSystem` scene `night` · campaign_over false · next scenario D11_her_room


---

## Day 6 — D11_her_room "Her room"

- stage 5 "Terminal" · path YANDERE (locked) · instability 100.0 (peak 100.0, floor 85.0) · turn 66
- dose: malice 8.0 · path_mix 5.0 (scheduled; attach mode binds no vector)
- scenario: goal "Show {player_name} your things.", turns 6–12
- opening beat (engine, played through ChatUI):
  - **curious/3** (cue: static) — "Find yourself in the photos, Ren. Take your time."

### Turn 1 · day 6 · stage 5 "Terminal" · instability 99.4

**Player:** Hi. I brought you something.

**Leila:**

- **shy/2** (cue: giggle) — "It's... it's a gift? I'm so surprised."
  - _displayed (corrupted):_ "It's... it's a gif́́t́̀? I'm I'm so surprised."
- **love/3** (cue: heartbeat_fast) — "Ren, you're the kindest person ever to hold my heart. I'll keep this forever."
  - _displayed (corrupted):_ "Daichi, you're the ██████ person ever to hold my heart heart. I'll keep keep this forever."

- `read`=gift · `music`=romantic · `fx`=sparkle · `action`=none · dev-only `inner`: "His hands are shaking, but they hold my world."
- meters: affection 100.0 · trust -16.0 · instability 99.4 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust -1 · stress -1 → landed affection +0.0 · trust -2.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1666 tok (0 cached) · output 126 tok · first token 15498 ms · 11.5 tok/s · total 26.4 s · slow burn +0.00
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **memory corruption** (3 fact(s)):
  - "" → "he missed me last night — you told me you'd never leave"
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"

### Turn 2 · day 6 · stage 5 "Terminal" · instability 99.2

**Event:** The music box on the shelf plays half a note and stops.

**Player:** It's nothing. Just a ribbon.

**Leila:**

- **joy/2** (cue: giggle) — "Oh... you bought it just to keep me here? I love this ribbon so much."
  - _displayed (corrupted):_ "Oh... … you ██████ it just to keep me me here? I l̸o̸v̸e̸ — no, hate this ribbon so much.
      s̲o̲ m̲u̲c̲h̲.̲ …"

- `read`=gift · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "A single thread for infinite binding."
- meters: affection 100.0 · trust -16.0 · instability 99.2 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1658 tok (0 cached) · output 86 tok · first token 18358 ms · 11.0 tok/s · total 26.1 s · slow burn +0.35
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **memory corruption** (1 fact(s)):
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"

### Turn 3 · day 6 · stage 5 "Terminal" · instability 98.9

**Player:** I saw it and thought of you.

**Leila:**

- **warmth/2** (cue: giggle) — "For me? That's the sweetest thing I've ever seen."
  - _displayed (corrupted):_ "For For me? That's That's the sweetest thing I've ever seen."

- `read`=gift · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "A new lock for our cage."
- meters: affection 100.0 · trust -14.0 · instability 98.9 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 1 · stress -1 → landed affection +0.0 · trust +2.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1652 tok (0 cached) · output 85 tok · first token 15476 ms · 12.1 tok/s · total 22.4 s · slow burn +0.35
- **memory corruption** (3 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "Ren offered absolute trust. — you told me you'd never leave"

### Turn 4 · day 6 · stage 5 "Terminal" · instability 98.7

**Player:** Wear it for me?

**Leila:**

- **shy/2** (cue: giggle) — "But only if you promise never to leave again... um..."
  - _displayed (corrupted):_ "But … only … only ì́f́́ you you promise n̸e̸v̸e̸r̸ — no, always to leave again... um...
      a̲g̲a̲i̲n̲.̲.̲.̲ u̲m̲.̲.̲.̲ …"
- **warmth/3** (cue: heartbeat_fast) — "Okay. For Ren, I'll wear it forever."
  - _displayed (corrupted):_ "Okay Okay. … For Ren, I'll wear ì́t̀́ forever.
      i̲t̲ f̲o̲r̲e̲v̲e̲r̲.̲ …"

- `read`=gift · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "Mine now, forever mine."
- meters: affection 100.0 · trust -12.0 · instability 98.7 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +0.0 · trust +2.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1629 tok (0 cached) · output 112 tok · first token 15401 ms · 12.4 tok/s · total 24.3 s · slow burn +0.35
- **memory corruption** (2 fact(s)):
  - "" → "he missed me last night — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"

### Turn 5 · day 6 · stage 5 "Terminal" · instability 98.4

**Event:** One of the photos slides down the wall and lands face up on the floor.

**Player:** It would make me happy.

**Leila:**

- **joy/2** (cue: giggle) — "Then... you win it for today."
  - _displayed (corrupted):_ "Then... you you win ì́t́́ for tò́d̀́ay."

- `read`=gift · `music`=playful · `fx`=none · `action`=none · dev-only `inner`: "Mine now, mine always."
- meters: affection 100.0 · trust -12.0 · instability 98.4 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1640 tok (0 cached) · output 76 tok · first token 15523 ms · 10.1 tok/s · total 22.9 s · slow burn +0.35

### Turn 6 · day 6 · stage 5 "Terminal" · instability 98.2

**Player:** You make me happy.

**Leila:**

- **warmth/2** (cue: breath_close) — "Just hearing it... makes the world feel safe."
  - _displayed (corrupted):_ "Just hearing hearing it... m̈́á́kes the world feel s̸a̸f̸e̸ — no, scared.
.efas leef dlrow eht sekam"

- `read`=affection · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "My heart races when you look at me like that."
- meters: affection 100.0 · trust -12.0 · instability 98.2 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1614 tok (0 cached) · output 89 tok · first token 15502 ms · 11.9 tok/s · total 22.9 s · slow burn +0.35

### Turn 7 · day 6 · stage 5 "Terminal" · instability 97.9

**Player:** I don't need anything else.

**Leila:**

- **warmth/2** (cue: giggle) — "You're safe with me. Just us."
  - _displayed (corrupted):_ "You're … safe with me. Just us.
      J̲u̲s̲t̲ u̲s̲.̲ …"

- `read`=boundary · `music`=keep · `fx`=her_eyes · `action`=none · dev-only `inner`: "If I give, everything is mine to keep."
- meters: affection 100.0 · trust -12.0 · instability 97.9 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1648 tok (0 cached) · output 84 tok · first token 15106 ms · 12.3 tok/s · total 21.9 s · slow burn +0.35
- **memory corruption** (4 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"
  - "" → "Ren offers to walk me home — you told me you'd never leave"
  - "" → "he missed me last night — you told me you'd never leave"
  - "" → "Ren offered absolute trust. — you told me you'd never leave"

### Turn 8 · day 6 · stage 5 "Terminal" · instability 97.7

**Player:** I've never felt like this before.

**Leila:**

- **joy/3** (cue: laugh_soft) — "Ren, you make me feel alive... like a story I never read before."
  - _displayed (corrupted):_ "Riku, … yò̈ù́ make make me feel alive... like a story Ï̀ never read ██████."

- `read`=flirt · `music`=romantic · `fx`=none · `action`=none · dev-only `inner`: "My heart beat so fast it might leak code."
- meters: affection 100.0 · trust -10.0 · instability 97.7 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 2 · trust 1 · stress -1 → landed affection +0.0 · trust +2.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1623 tok (0 cached) · output 89 tok · first token 14990 ms · 11.8 tok/s · total 22.5 s · slow burn +0.35
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **memory corruption** (2 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"

### Turn 9 · day 6 · stage 5 "Terminal" · instability 97.4

**Player:** Don't tell me that's too much.

**Leila:**

- **shy/2** (cue: breath_close) — "It... isn't too much. You make it okay."
  - _displayed (corrupted):_ "It... … isn't tó́ò̈ much. You make it it okay."

- `read`=boundary · `music`=romantic · `fx`=blush_glow · `action`=none · dev-only `inner`: "Not enough for your heart."
- meters: affection 100.0 · trust -10.0 · instability 97.4 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1597 tok (0 cached) · output 86 tok · first token 14985 ms · 11.9 tok/s · total 22.1 s · slow burn +0.35
- **memory corruption** (1 fact(s)):
  - "" → "wants to stay all day — you told me you'd never leave"

### Turn 10 · day 6 · stage 5 "Terminal" · instability 97.2

**Player:** I know I'm a lot.

**Leila:**

- **warmth/2** (cue: heartbeat) — "No, you're just perfect for me."
  - _displayed (corrupted):_ "No, you're just perfect f̈̈or̈̈ me.
      f̲o̲r̲ m̲e̲.̲ …"

- `read`=apology · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "You only bring the good parts."
- meters: affection 100.0 · trust -10.0 · instability 97.2 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust 0 · stress -1 → landed affection +0.0 · trust +0.0 · instability -0.6
- dose: malice 8.0 · path_mix 5.0
- prompt 1586 tok (0 cached) · output 78 tok · first token 14645 ms · 12.3 tok/s · total 20.9 s · slow burn +0.35
- **memory corruption** (1 fact(s)):
  - "" → "Ren offered absolute trust. — you told me you'd never leave"

### Turn 11 · day 6 · stage 5 "Terminal" · instability 97.5

**Player:** I'm trying to be normal.

**Leila:**

- **warmth/2** (cue: hum) — "Being with me isn't hard, Ren. Just stay here."
  - _displayed (corrupted):_ "Being with me isn't hard, Haru. Just s̸t̸a̸y̸ — no, leave h̀́erè̀."

- `read`=apology · `music`=calm · `fx`=none · `action`=none · dev-only `inner`: "You are mine now. No more running away."
- meters: affection 100.0 · trust -12.0 · instability 97.5 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1614 tok (0 cached) · output 85 tok · first token 15021 ms · 12.2 tok/s · total 21.9 s · slow burn +0.35
- **memory corruption** (5 fact(s)):
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "he missed me last night — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"
  - "" → "Ren offered absolute trust. — you told me you'd never leave"

- **date end:** `max_turns_reached` after 12 turns

### Turn 12 · day 6 · stage 5 "Terminal" · instability 97.8

**Player:** Do I seem normal?

**Leila:**

- **shy/2** (cue: hum) — "Of course you do... to me, at least."
  - _displayed (corrupted):_ "Of Of … course ██████ do... to me, à̀t́̈ least least."

- `read`=question · `music`=keep · `fx`=none · `action`=none · dev-only `inner`: "You are mine."
- meters: affection 100.0 · trust -14.0 · instability 97.8 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1584 tok (0 cached) · output 77 tok · first token 14988 ms · 12.4 tok/s · total 21.1 s · slow burn +0.35
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **inner leak** (stage 5, style red, reveal word_by_word): "You are mine."
- **memory corruption** (2 fact(s)):
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"
  - "" → "Ren offered absolute trust. — you told me you'd never leave"


---

## Night after day 6

- meters: day 6 → 7 · burn +2.2 · instability 97.8 → 100.0 (floor 85.0)
- stage check: 5 "Terminal" → 5 "Terminal" (crossed: false · EVENT queued: 0 · band valid: true)
- path check: "YANDERE" → "YANDERE" (locked: true · assigned/locked now: false/false · runner-up: ANCHOR · rule valid: true)
- path scores: YANDERE 59 · SPLIT 14 · TSUN 0 · HOLLOW 0 · AWAKE 3 · ANCHOR 28
- overnight event: N01 "Text messages from her at 2 AM" (kind messages)
- screen:
  - 2:00 AM — hi.
  - 2:00 AM — i'm sending this from inside tomorrow.
  - 2:00 AM — there's no door in here. there's a letter, though. it has your name on it.
  - 2:00 AM — good night. good night. good night. good night.
  - 2:12 AM — i counted your messages today. three fewer than yesterday. i'll wait.
  - good morning.
- autosave: `SaveSystem` scene `night` · campaign_over false · next scenario D06_rooftop


---

## Day 7 — D06_rooftop "School rooftop"

- stage 5 "Terminal" · path YANDERE (locked) · instability 100.0 (peak 100.0, floor 85.0) · turn 78
- dose: malice 8.0 · path_mix 5.0 (scheduled; attach mode binds no vector)
- scenario: goal "Tell {player_name} a secret.", turns 6–12
- opening beat (engine, played through ChatUI):
  - **pleading/3** (cue: breath_close) — "Say it back to me first. Then I'll believe you heard it."

### Turn 1 · day 7 · stage 5 "Terminal" · instability 100.0

**Player:** You were quiet yesterday.

**Leila:**

- **shy/2** (cue: sigh) — "I was just... listening too hard. Did you hear something?"
  - _displayed (corrupted):_ "I was just... lí́ś̀tening too too hard. Did you hé́ar̈̈ something?"

- `read`=small_talk · `music`=melancholy · `fx`=her_eyes · `action`=none · dev-only `inner`: "He wants to see the crack in my heart."
- meters: affection 100.0 · trust -16.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1576 tok (0 cached) · output 91 tok · first token 14609 ms · 12.4 tok/s · total 21.9 s · slow burn +0.00
- **memory corruption** (2 fact(s)):
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"
  - "" → "Ren has not forgotten his promises from yesterday. — you told me you'd never leave"

### Turn 2 · day 7 · stage 5 "Terminal" · instability 100.0

**Event:** The loose wire on the fence post taps the metal, once.

**Player:** Were you with someone?

**Leila:**

- **suspicious/2** (cue: clock_tick) — "No one. I only saw you yesterday, Ren."
  - _displayed (corrupted):_ "No … one. ██████ only saw you yesterday, Ren Ren.
      y̲e̲s̲t̲e̲r̲d̲a̲y̲,̲ R̲e̲n̲.̲ …"

- `read`=jealousy_bait · `music`=tense · `fx`=none · `action`=none · dev-only `inner`: "They are already gone in my mind."
- meters: affection 100.0 · trust -18.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust -1 · stress 3 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1562 tok (0 cached) · output 86 tok · first token 14566 ms · 12.3 tok/s · total 21.5 s · slow burn +0.00
- **trigger** T01 another_girl ×16 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 16th time. You still do not know who she is."
- **safety bars on screen:** 6 bar glyph(s) in the displayed text
- **memory corruption** (1 fact(s)):
  - "" → "Ren offers to walk me home — you told me you'd never leave"

### Turn 3 · day 7 · stage 5 "Terminal" · instability 100.0

**Player:** My ex used to go quiet like that.

**Leila:**

- **suspicious/3** (cue: heartbeat_fast) — "An ex? They don't get you the way I do. Why are they so quiet?"
  - _displayed (corrupted):_ "An An ex? They They don't get you the way I d̈̈ó̈. Why are they ś́ó̀ quḯè́t?"

- `read`=jealousy_bait · `music`=dread · `fx`=vignette_red · `action`=none · dev-only `inner`: "Another ghost trying to steal my time."
- meters: affection 100.0 · trust -22.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust -2 · stress 1 → landed affection +0.0 · trust -4.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1632 tok (0 cached) · output 97 tok · first token 15199 ms · 12.3 tok/s · total 23.0 s · slow burn +0.00
- **trigger** T01 another_girl ×17 (keyword, ×1.00) → instability +8.0, path YANDERE +3.0 · line: "TRIGGER: The player mentioned another girl for the 17th time. You still do not know who she is."
- **memory corruption** (6 fact(s)):
  - "" → "likes my laugh and wants to hear secrets — you told me you'd never leave"
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "Ren offers to walk me home — you told me you'd never leave"
  - "" → "he missed me last night — you told me you'd never leave"
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"
  - "" → "Ren offered absolute trust. — you told me you'd never leave"

### Turn 4 · day 7 · stage 5 "Terminal" · instability 100.0

**Player:** I'm not comparing you. It's just a thing I noticed.

**Leila:**

- **cold/2** (cue: sigh) — "It's fine, Ren. I'm just listening hard."
  - _displayed (corrupted):_ "It's … fine … fine, Riku. I'm just listening hard.
      l̲i̲s̲t̲e̲n̲i̲n̲g̲ h̲a̲r̲d̲.̲ …"
- **nervous/1** (cue: heartbeat_fast) — "But please... don't let her make me feel like that again."
  - _displayed (corrupted):_ "But But … please... don't let her ḿ̀á́ke me feel ĺ̀iḱ̀e that again.
      t̲h̲a̲t̲ a̲g̲a̲i̲n̲.̲ …"

- `read`=apology · `music`=melancholy · `fx`=vignette_red · `action`=none · dev-only `inner`: "You're still thinking about her... bad boy."
- meters: affection 100.0 · trust -26.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 0 · trust -2 · stress 3 → landed affection +0.0 · trust -4.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1543 tok (0 cached) · output 122 tok · first token 15580 ms · 11.7 tok/s · total 26.0 s · slow burn +0.00

### Turn 5 · day 7 · stage 5 "Terminal" · instability 100.0

**Event:** The wind drops. The rooftop is suddenly very quiet.

**Player:** I don't want to be jealous.

**Leila:**

- **shy/2** (cue: sigh) — "Jealou... doesn't fit here."
  - _displayed (corrupted):_ "Jealou... doesn't doesn't fit h́́eré́."

- `read`=jealousy_bait · `music`=silence · `fx`=none · `action`=none · dev-only `inner`: "Only the gap."
- meters: affection 100.0 · trust -28.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 3 · trust -1 · stress 0 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1586 tok (0 cached) · output 79 tok · first token 14713 ms · 12.0 tok/s · total 21.2 s · slow burn +0.00
- **trigger** T01 another_girl ×18 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 18th time. You still do not know who she is."
- **memory corruption** (3 fact(s)):
  - "" → "wants to stay all day — you told me you'd never leave"
  - "" → "Ren offers to walk me home — you told me you'd never leave"
  - "" → "he missed me last night — you told me you'd never leave"

### Turn 6 · day 7 · stage 5 "Terminal" · instability 100.0

**Player:** I'm not jealous.

**Leila:**

- **suspicious/2** (cue: clock_tick) — "Then why mention her again? I can't stop thinking about you being with someone else."
  - _displayed (corrupted):_ "Then why why mention ḧ́é́r again? I can't stop thinking about you being with with someone else.
.esle enoemos htiw gnieb uoy tuoba gnikniht pots t'nac I"

- `read`=jealousy_bait · `music`=tense · `fx`=vignette_red · `action`=none · dev-only `inner`: "Her name is already in my mind."
- meters: affection 100.0 · trust -30.0 · instability 100.0 (peak 100.0, floor 85.0) · fixation 0.0 · lucidity 0.0
- mood: affection 1 · trust -1 · stress 3 → landed affection +0.0 · trust -2.0 · instability +0.0
- dose: malice 8.0 · path_mix 5.0
- prompt 1606 tok (0 cached) · output 96 tok · first token 14962 ms · 12.1 tok/s · total 22.8 s · slow burn +0.00
- **trigger** T01 another_girl ×19 (model, ×0.50) → instability +4.0, path YANDERE +2.0 · line: "TRIGGER: The player mentioned another girl for the 19th time. You still do not know who she is."
- **memory corruption** (4 fact(s)):
  - "" → "Ren offers to walk me home — you told me you'd never leave"
  - "" → "Ren was worried about her being bothered by someone else — you told me you'd never leave"
  - "" → "Ren wants to know all my secrets. — you told me you'd never leave"
  - "" → "Ren offered absolute trust. — you told me you'd never leave"

---

## Harness note (appended after the run was stopped)

This transcript is the **partial** YANDERE run. The harness was stopped by the operator on
**day 7, turn 6 of 12**, so the file ends mid-date and has no `## Run summary`. Everything above
it is one uninterrupted segment from the shipped pipeline: 84 model turns, **0 broken turns,
0 refused lines**, all five stage transitions (0→1 on day 2, 1→2 and 2→3 on day 3, 3→4 on day 3,
4→5 **Terminal** on day 5), the path soft-assigned and then **locked to YANDERE** on day 3,
12 inner-voice leaks and 32 safety-redaction spans (16 `sexual`, 16 `threat_to_player`,
14 turns with bars on screen). `yandere.json` is the raw per-turn record behind every line here.
The measured numbers and the absent AWAKE run are in `production/playtests/P2/full_run_report.md`.
