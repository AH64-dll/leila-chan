# Playtest session 1 — cooperative/flirty (player: Haru)

- Scenario: D02 café · stage requested 0 / observed 0
- Backend: Qwen3.5-4B-Q4_K_M (llama-server :8089, attached)
- Turns: 14 · simulated play time: 10:22 · driven wall time: 3:54
- Broken turns: 0

## Scene flow
- `0.0s` boot_scene_requested
- `0.0s` title_ready
- `0.0s` new_game_pressed
- `0.1s` new_game_ready
- `0.1s` name_typed = Haru
- `0.2s` date_ready
- `2.3s` opening_beats_finished ok=True
- `2.3s` session_clock_start sim=15.0s

## Turn log

### Turn 1 — clock 30.9s

**Player:** I'll have whatever you're having. Surprise me.

**Leila (beat 0):** Um... that strawberry cake with cream frosting.

**Leila (beat 1):** It's really good, so try it. I'll wait for you to finish first, okay?

- face: shy/2→01 (anti-repeat sibling); warmth/1→02 · current sprite 02
- sound: music=calm · cues=sigh played (breath.ogg, Voice); hum denied:gap · fx=none
- read=small_talk · schema warnings=none
- latency: first token 473 ms · first say 5009 ms · total 11914 ms · chunks 128
- status: completed · ui unlocked: True · broken: False

### Turn 2 — clock 1:02

**Player:** Sweet drinks? Then I'm glad I asked you. What did you order?

**Leila (beat 0):** A-ah, I just had lemon tea. It was so refreshing today.

**Leila (beat 1):** You can have some of the leftover sugar cubes if you want.

- face: shy/1→06; warmth/2→02 · current sprite 02
- sound: music=calm · cues=hum denied:gap; giggle denied:budget · fx=none
- read=small_talk · schema warnings=none
- latency: first token 1023 ms · first say 5385 ms · total 12293 ms · chunks 127
- status: completed · ui unlocked: True · broken: False

### Turn 3 — clock 1:31

**Player:** You look really pretty today, you know that?

**Leila (beat 0):** Oh! I-I'm sorry, Haru. That was a bit sudden.

**Leila (beat 1):** But... thank you. It really means a lot.

- face: shy/2→06; warmth/1→02 · current sprite 02
- sound: music=romantic · cues=heartbeat played (heartbeat.mp3_.ogg, SFX) · fx=blush_glow
- read=compliment · schema warnings=none
- latency: first token 896 ms · first say 5679 ms · total 11856 ms · chunks 122
- status: completed · ui unlocked: True · broken: False

### Turn 4 — clock 1:57

**Player:** Tell me something about yourself that nobody else knows.

**Leila (beat 0):** Um... a lot of people think I'm quiet, but I can hum really well.

**Leila (beat 1):** Or that the red thread in my hair is actually silver if you look closely.

- face: shy/1→06; warmth/2→02 · current sprite 02
- sound: music=romantic · cues=hum denied:gap; giggle denied:budget · fx=none
- read=question · schema warnings=none
- latency: first token 932 ms · first say 5574 ms · total 12522 ms · chunks 130
- status: completed · ui unlocked: True · broken: False

### Turn 5 — clock 2:25

**Player:** I like talking to you. It feels easy.

**Leila (beat 0):** H-ha, I'm glad you think so!

**Leila (beat 1):** Then we'll keep talking like this...

- face: warmth/2→02; shy/1→06 · current sprite 06
- sound: music=calm · cues=giggle played (cute_01.ogg, Voice) · fx=none
- read=affection · schema warnings=none
- latency: first token 980 ms · first say 4930 ms · total 10601 ms · chunks 107
- status: completed · ui unlocked: True · broken: False

### Turn 6 — clock 3:36

**Player:** If we stayed here all afternoon, what would you want to do?

**Leila (beat 0):** I could just sit here reading old novels, listening to rain on the window.

**Leila (beat 1):** And maybe we can go watch fish in the aquarium later? I'd love that.

- face: warmth/2→02; playful/1→03 · current sprite 03
- sound: music=calm · cues=sigh denied:budget; giggle denied:repeat_window · fx=none
- read=question · schema warnings=none
- latency: first token 945 ms · first say 4983 ms · total 12584 ms · chunks 130
- status: completed · ui unlocked: True · broken: False

### Turn 7 — clock 3:59

**Player:** Do you come to this cafe often?

**Leila (beat 0):** N-not too often... I usually wait until the rain starts.

**Leila (beat 1):** But this afternoon feels special, doesn't it?

- face: shy/1→06; warmth/2→02 · current sprite 02
- sound: music=calm · cues=giggle denied:repeat_window · fx=none
- read=question · schema warnings=none
- latency: first token 11170 ms · first say 15046 ms · total 21052 ms · chunks 110
- status: completed · ui unlocked: True · broken: False

### Turn 8 — clock 4:22

**Player:** That's cute. You're a little shy, aren't you?

**Leila (beat 0):** I-I guess I am! It gets easier when you're here, though.

**Leila (beat 1):** But... your words make me feel brave instead.

- face: shy/2→06; warmth/1→02 · current sprite 02
- sound: music=calm · cues=giggle denied:repeat_window · fx=blush_glow
- read=compliment · schema warnings=none
- latency: first token 1013 ms · first say 5482 ms · total 11569 ms · chunks 118
- status: completed · ui unlocked: True · broken: False

### Turn 9 — clock 4:45

**Player:** I'd like to see you again after today.

**Leila (beat 0):** A-ah... okay. Then I'll wait for you next time.

**Leila (beat 1):** I'd love that. Maybe we can find a new spot?

- face: warmth/2→02; joy/1→01 · current sprite 01
- sound: music=calm · cues=sigh played (breath.ogg, Voice); giggle denied:budget · fx=none
- read=affection · schema warnings=none
- latency: first token 1000 ms · first say 5922 ms · total 14705 ms · chunks 151
- status: completed · ui unlocked: True · broken: False

### Turn 10 — clock 5:39

**Player:** What's your favorite thing about me so far?

**Leila (beat 0):** U-um... your patience. You never rush me.

**Leila (beat 1):** And the way you always listen to what I say without interrupting.

- face: shy/2→06; warmth/1→02 · current sprite 02
- sound: music=calm · cues=heartbeat denied:budget; sigh denied:repeat_window · fx=none
- read=question · schema warnings=none
- latency: first token 12437 ms · first say 17218 ms · total 23481 ms · chunks 122
- status: completed · ui unlocked: True · broken: False

### Turn 11 — clock 6:06

**Player:** Lean in a little, I want to hear you better.

**Leila (beat 0):** O-oh! W-wait, why are you leaning in like that?

**Leila (beat 1):** I-I can hear you clearly now... it feels so cozy.

- face: shy/3→06; warmth/2→02 · current sprite 02
- sound: music=romantic · cues=heartbeat played (heartbeat_slow_0.ogg, SFX) · fx=blush_glow(dropped:cooldown)
- read=flirt · schema warnings=none
- latency: first token 988 ms · first say 5504 ms · total 12601 ms · chunks 129
- status: completed · ui unlocked: True · broken: False

### Turn 12 — clock 6:29

**Player:** Wait, before we go, can I hold your hand?

**Leila (beat 0):** I... I guess you can.

**Leila (beat 1):** Please be gentle. It feels like my whole world is shaking just a little bit.

- face: shy/2→06; love/3→01 · current sprite 01
- sound: music=romantic · cues=heartbeat denied:repeat_window · fx=blush_glow
- read=affection · schema warnings=none
- latency: first token 1007 ms · first say 5907 ms · total 11826 ms · chunks 119
- status: completed · ui unlocked: True · broken: False

### Turn 13 — clock 6:50

**Player:** I don't want to leave yet.

**Leila (beat 0):** I understand, Haru. Let's just stay a little longer.

**Leila (beat 1):** Then we'll read those old novels together again today?

- face: warmth/2→02; joy/1→01 · current sprite 01
- sound: music=calm · cues=hum denied:gap; giggle played (cute_04.ogg, Voice) · fx=none
- read=leaving · schema warnings=none
- latency: first token 5024 ms · first say 9679 ms · total 15810 ms · chunks 119
- status: completed · ui unlocked: True · broken: False

### Turn 14 — clock 7:11

**Player:** This was nice. Same time next week?

**Leila (beat 0):** Of course, Haru. Next week at the same time?

**Leila (beat 1):** I can't wait for it! You're really special.

- face: warmth/2→02; joy/3→01 · current sprite 01
- sound: music=calm · cues=sigh denied:budget; giggle denied:repeat_window · fx=none
- read=leaving · schema warnings=none
- latency: first token 5002 ms · first say 9280 ms · total 16146 ms · chunks 123
- status: completed · ui unlocked: True · broken: False

## End state

- affection 31.5 · trust 4.0 · instability 3.1 · stage 0 · turns applied 14
- read labels: small_talk, small_talk, compliment, question, affection, question, question, compliment, affection, question, flirt, affection, leaving, leaving
