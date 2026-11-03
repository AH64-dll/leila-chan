# Playtest session 2 — terse/dismissive (player: Ken)

- Scenario: D02 café · stage requested 0 / observed 0
- Backend: Qwen3.5-4B-Q4_K_M (llama-server :8089, attached)
- Turns: 14 · simulated play time: 8:40 · driven wall time: 3:19
- Broken turns: 0

## Scene flow
- `0.0s` boot_scene_requested
- `0.0s` title_ready
- `0.0s` new_game_pressed
- `0.1s` new_game_ready
- `0.1s` name_typed = Ken
- `0.2s` date_ready
- `2.2s` opening_beats_finished ok=True
- `2.2s` session_clock_start sim=12.0s

## Turn log

### Turn 1 — clock 21.2s

**Player:** Coffee.

**Leila (beat 0):** Oh, Ken! I thought you left already.

**Leila (beat 1):** The afternoon light is so pretty today...

- face: warmth/2→02; shy/1→06 · current sprite 06
- sound: music=calm · cues=sigh played (breath.ogg, Voice) · fx=none
- read=greeting · schema warnings=none
- latency: first token 613 ms · first say 4565 ms · total 10041 ms · chunks 105
- status: completed · ui unlocked: True · broken: False

### Turn 2 — clock 37.3s

**Player:** Whatever.

**Leila (beat 0):** Um... okay, whatever you say. I'll just sit here quietly.

**Leila (beat 1):** Does it matter what you want?

- face: shy/1→06; sad/2→14 · current sprite 14
- sound: music=calm · cues=sigh denied:repeat_window · fx=none
- read=other · schema warnings=none
- latency: first token 756 ms · first say 4492 ms · total 10178 ms · chunks 105
- status: completed · ui unlocked: True · broken: False

### Turn 3 — clock 52.1s

**Player:** Sure.

**Leila (beat 0):** Um, sorry. I just want to enjoy the quiet here.

**Leila (beat 1):** A-ah... maybe we could talk about something else?

- face: nervous/1→13; shy/2→06 · current sprite 06
- sound: music=calm · cues=sigh denied:repeat_window; heartbeat played (heartbeat_slow_0.ogg, SFX) · fx=none
- read=greeting · schema warnings=none
- latency: first token 749 ms · first say 4986 ms · total 11046 ms · chunks 114
- status: completed · ui unlocked: True · broken: False

### Turn 4 — clock 1:49

**Player:** No.

**Leila (beat 0):** E-easy, Ken... don't say no to everything.

**Leila (beat 1):** I was just happy you were here for a bit.

- face: confused/2→08; sad/1→14 · current sprite 14
- sound: music=melancholy · cues=sigh denied:repeat_window · fx=none
- read=other · schema warnings=none
- latency: first token 786 ms · first say 4806 ms · total 10626 ms · chunks 110
- status: completed · ui unlocked: True · broken: False

### Turn 5 — clock 2:06

**Player:** Hm.

**Leila (beat 0):** I'm sorry if I was too much... I'll try to be quieter then.

**Leila (beat 1):** It's just... can we please focus on our conversation?

- face: shy/1→06; nervous/2→13 · current sprite 13
- sound: music=melancholy · cues=sigh played (breath.ogg, Voice); heartbeat denied:repeat_window · fx=none
- read=small_talk · schema warnings=none
- latency: first token 813 ms · first say 5344 ms · total 11795 ms · chunks 123
- status: completed · ui unlocked: True · broken: False

### Turn 6 — clock 2:21

**Player:** I don't know.

**Leila (beat 0):** U-um... it's okay if you don't know. Just sit with me?

**Leila (beat 1):** Maybe we can just look out the window together for a bit?

- face: shy/1→06; curious/2→05 · current sprite 05
- sound: music=calm · cues=sigh denied:repeat_window; hum denied:gap · fx=none
- read=other · schema warnings=none
- latency: first token 937 ms · first say 5497 ms · total 12041 ms · chunks 124
- status: completed · ui unlocked: True · broken: False

### Turn 7 — clock 2:35

**Player:** You pick.

**Leila (beat 0):** I-I guess it's your choice, Ken. Let's just look out the window?

- face: shy/2→06 · current sprite 06
- sound: music=calm · cues=giggle played (cute_02.ogg, Voice) · fx=none
- read=other · schema warnings=none
- latency: first token 915 ms · first say 5308 ms · total 9077 ms · chunks 91
- status: completed · ui unlocked: True · broken: False

### Turn 8 — clock 3:48

**Player:** Not really.

**Leila (beat 0):** Oh, I see... maybe you're just tired today.

**Leila (beat 1):** I-I won't say anything else then. Just... let's stay here quietly for a while?

- face: sad/1→14; nervous/2→13 · current sprite 13
- sound: music=melancholy · cues=sigh denied:repeat_window; heartbeat denied:budget · fx=none
- read=greeting · schema warnings=none
- latency: first token 798 ms · first say 5018 ms · total 11798 ms · chunks 122
- status: completed · ui unlocked: True · broken: False

### Turn 9 — clock 4:03

**Player:** Okay.

**Leila (beat 0):** Then... we'll just sit and watch the rain clouds gather?

- face: warmth/1→02 · current sprite 02
- sound: music=melancholy · cues=none · fx=none
- read=greeting · schema warnings=none
- latency: first token 867 ms · first say 4990 ms · total 8345 ms · chunks 82
- status: completed · ui unlocked: True · broken: False

### Turn 10 — clock 4:14

**Player:** Busy.

**Leila (beat 0):** I see... I won't bother you then.

**Leila (beat 1):** But please... don't stay busy with just me in mind?

- face: shy/1→06; warmth/2→02 · current sprite 02
- sound: music=calm · cues=sigh played (breath.ogg, Voice); hum denied:gap · fx=none
- read=small_talk · schema warnings=none
- latency: first token 730 ms · first say 7191 ms · total 15895 ms · chunks 167
- status: completed · ui unlocked: True · broken: False

### Turn 11 — clock 5:21

**Player:** Whatever you want.

**Leila (beat 0):** Good... thank you, Ken. It's so nice to have that agreement.

**Leila (beat 1):** So, what do you want to do now? Just sit here?

- face: warmth/2→02; playful/1→03 · current sprite 03
- sound: music=calm · cues=sigh denied:repeat_window; giggle denied:budget · fx=none
- read=affection · schema warnings=none
- latency: first token 832 ms · first say 5046 ms · total 11771 ms · chunks 120
- status: completed · ui unlocked: True · broken: False

### Turn 12 — clock 5:34

**Player:** Maybe.

**Leila (beat 0):** M-Maybe... or maybe we can just sit here until the rain starts?

**Leila (beat 1):** It's okay. Just being here is enough.

- face: shy/1→06; warmth/2→02 · current sprite 02
- sound: music=calm · cues=hum denied:gap · fx=none
- read=small_talk · schema warnings=none
- latency: first token 867 ms · first say 5344 ms · total 11482 ms · chunks 118
- status: completed · ui unlocked: True · broken: False

### Turn 13 — clock 5:48

**Player:** Later.

**Leila (beat 0):** Oh, okay... I'll wait until next time then.

**Leila (beat 1):** A-ah, it's so quiet now. Do you think he's gone?

- face: sad/2→14; shy/1→06 · current sprite 06
- sound: music=melancholy · cues=sigh denied:repeat_window · fx=none
- read=leaving · schema warnings=none
- latency: first token 3986 ms · first say 8322 ms · total 14793 ms · chunks 119
- status: completed · ui unlocked: True · broken: False

### Turn 14 — clock 6:04

**Player:** I gotta go.

**Leila (beat 0):** E-um, okay then...

**Leila (beat 1):** But... you really don't have to go yet?

- face: sad/2→14; shy/1→06 · current sprite 06
- sound: music=melancholy · cues=sigh played (breath.ogg, Voice); heartbeat denied:budget · fx=none
- read=leaving · schema warnings=none
- latency: first token 4712 ms · first say 9067 ms · total 14550 ms · chunks 108
- status: completed · ui unlocked: True · broken: False

## End state

- affection 13.5 · trust -4.0 · instability 7.3 · stage 0 · turns applied 14
- read labels: greeting, other, greeting, other, small_talk, other, other, greeting, greeting, small_talk, affection, small_talk, leaving, leaving
