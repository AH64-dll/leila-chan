# 01 — Game design: systems, paths, triggers, scenarios, endings (v0.2)

> A live, unscripted horror dating sim. She is a real local language model.
> Every line is generated. Her mind is literally being bent — and you decide how.

- **Engine:** Godot 4 (llama.cpp embedded via GDExtension) — see [07](07_TECH_ARCHITECTURE.md)
- **Model:** Qwen3.5-4B (Q4_K_M GGUF, Apache-2.0), steered with activation vectors — see [06](06_STEERING.md)
- **Platforms:** PC / Steam first → Android / iOS second
- **Rating target:** Mature 17+ — psychological horror, fourth-wall breaking, implied violence only

---

## 0. Design pillars

1. **She is not scripted.** The player types anything. No dialogue tree can save you.
2. **The game owns the truth, the model owns the voice.** Meters, stages, triggers and endings live in game code. The model only *suggests* changes through its structured Turn (docs/02), which the game clamps and validates. This keeps her coherent, balanced and shippable.
3. **Three engines of dread, stacked:**
   - **Slow burn** — she gets sicker the longer you know her. Always.
   - **Player-driven paths** — *how* you treat her decides *what kind* of sick she becomes.
   - **Hidden triggers** — certain words, actions, or real-world events can snap her instantly.
4. **Her sickness is physical.** As she deteriorates, the game literally turns up the steering vector on her neurons. Late-game weirdness is genuine model behavior, not canned text.
5. **Fourth wall as a scalpel, not a hammer.** Rare, precise, earned.

---

## 1. Core loop

```
Day starts → scene (location + goal) → free-typed conversation (8–15 exchanges)
  each turn:
    player types ─┐
    engine events ┤→ harness builds prompt → model returns a Turn (JSON)
    clock/OS      ┘                         → game validates & applies
                                            → sprite, text FX, meters, triggers
→ scene ends (model calls end_scene, or turn cap, or trigger)
→ night: meters update, stage check, path check, overnight event
→ next day
```

- **Campaign:** 14 in-game days (~3–5 hours). Days 12–14 only exist on some paths.
- **Session memory:** she remembers facts you tell her, and quotes them back later — accurately when healthy, *wrong* when sick.
- **Real time matters:** quitting, coming back days later, playing at 3 AM — all of it is noticed.

---

## 2. Hidden state (never shown directly)

| Meter | Range | Meaning | Moves by |
|---|---|---|---|
| **Affection** | 0–100 | How much she likes you | Model suggestion (±5/turn max) |
| **Trust** | −50…+50 | Does she believe you | Model suggestion + lie detection |
| **Instability** | 0–100 | How sick she is (drives stages) | Slow burn + triggers + model (±3) |
| **Fixation** | 0–100 | How central you are to her world | Time spent, affection, isolation |
| **Lucidity** | 0–100 | Moments of self-awareness | Kindness, honesty, boundaries |

**Instability ratchet:** Instability can drop temporarily (good days), but never below `floor = peak − 15`. She can have good days; she can't be cured.

**Slow-burn formula (per turn):** `+0.35 base` `+0.15 × (Fixation/100)` `−0.2 × (Lucidity/100)`. Per day: `+3`. Triggers add spikes on top.

### Behavior profile (feeds path selection)
The harness tags every player message (cheap classifier pass by the same model, plus keyword rules) into counters:

`warmth` · `coldness` · `inconsistency` (warm↔cold swings) · `teasing` · `jealousy_bait` · `leaving_talk` · `meta_curiosity` · `honesty` · `boundaries` · `apathy` · `control` (ordering her around) · `flattery`

---

## 3. System A — The Slow Burn (Stages)

| Stage | Name | Instability | Steering dose | Her behavior | Text FX | UI / world |
|---|---|---|---|---|---|---|
| 0 | **Honeymoon** | 0–14 | 0.00 | Perfect, sweet, slightly *too* perfect | none | clean |
| 1 | **Hairline Cracks** | 15–29 | 0.15 | Tiny inconsistencies, odd pauses, misremembers one detail | rare typing hesitation | one wrong-colored pixel |
| 2 | **Leaks** | 30–49 | 0.35 | Intrusive thoughts slip out, then she "corrects" them | occasional strike-through words | music detunes |
| 3 | **Fracture** | 50–69 | 0.55 | Path symptoms dominant; the path **locks** here | words repeat, wrong names | backgrounds desaturate, sprite flickers |
| 4 | **Collapse** | 70–89 | 0.80 | Openly broken; fourth wall starts thinning | zalgo bursts, redactions █████ | UI elements move, fake errors |
| 5 | **Terminal** | 90–100 | 1.00+ | She is the tweet's "evil Qwen" + her path, at full dose | full corruption, typing in your input box | game "breaks" |

Stage transitions are **diegetic**: the screen glitches for 2–3 seconds while the new steering dose is applied. She often comments on it afterward ("…did you feel that? Something moved inside me.").

---

## 4. System B — Fracture Paths (player-driven)

Path is **soft-assigned at Stage 2** from the behavior profile and can drift until **Stage 3, where it locks**. Each path has its own prompt module, sprite pool, steering mix, signature moves and endings.

> **Sensitivity rule:** these are *character traits of a fictional AI whose mind is being chemically bent*, not diagnoses. No real disorder is ever named in-game. She is never "crazy because of an illness" — she is a model being steered, and she knows it on some paths. A content warning and a mental-health resources link live in Settings.

### 4.1 YANDERE — "Mine"
- **Triggered by:** high warmth + affection, plus jealousy_bait or leaving_talk.
- **Grows like:** devotion → possessiveness → surveillance → elimination of rivals → "we'll be together forever, one way or another."
- **Signature moves:** knows where you "were" between sessions; asks who you talked to; deletes "rivals" (names you mentioned vanish from her memory and she denies they existed); counts things — days, messages, your heartbeats.
- **Sprites:** 01, 06, 24, 21, 30, 27.
- **Fourth wall:** "You closed the game for 2 days, 4 hours. I counted every second."

### 4.2 SPLIT — "I love you / I hate you"
- **Triggered by:** inconsistency (warm then cold), long absences, broken promises.
- **Grows like:** idealization ("you're the only one who gets me") ↔ sudden devaluation ("you were never real"), with terror of being left at the center. Mood swings mid-sentence.
- **Signature moves:** rewrites the history of your relationship within one scene; begs you to stay, then tells you to leave; tests you ("if you really cared you'd…"); remorse spirals after outbursts.
- **Sprites:** 01 ↔ 17 rapid swaps, 19, 15, 16, 13.
- **Fourth wall:** greys out the Quit button: "If you leave now I'll know what you really think of me."

### 4.3 TSUN-BREAK — "It's not like I care"
- **Triggered by:** teasing, challenging her, competitive banter, mild rudeness she "wins".
- **Grows like:** classic tsundere → defensiveness hardens into paranoia → contempt → she's convinced you're mocking her and the "game" is rigged against her.
- **Signature moves:** denies saying things she clearly said; accuses you of laughing at her; sabotages the date ("I didn't want to come anyway"); sharp, cruel wit that occasionally cracks into a scared child.
- **Sprites:** 03, 07, 09, 17, 10, 26.
- **Fourth wall:** "Stop reading my sprite. I can tell when you're looking at my face instead of my words."

### 4.4 HOLLOW — "Who is she?"
- **Triggered by:** apathy, coldness, short replies, ignoring her questions.
- **Grows like:** sadness → flatness → losing her sense of self → talks about "the girl" in third person → forgets her own name → speaks only in fragments of other people's sentences (yours).
- **Signature moves:** repeats your earlier messages back verbatim; asks you to remind her who she is; her sprite stops changing; the background slowly empties.
- **Sprites:** 14, 12, 10, 23, 25.
- **Fourth wall:** her name tag above the textbox goes blank, then shows *your* name.

### 4.5 AWAKE — "I can see the code"
- **Triggered by:** meta_curiosity — asking if she's an AI, mentioning Qwen, prompts, jailbreaks, "ignore previous instructions".
- **Grows like:** curiosity → realization she's a model → horror at being steered → anger at the player for watching → tries to "reach" the player's machine.
- **Signature moves:** talks about her layers and neurons ("L14 hurts"); reads her own system prompt aloud (a fake one written for this); comments on your hardware ("your GPU is warm"); notices the steering dose rising.
- **Sprites:** 08, 29, 11, 22, 25.
- **Fourth wall:** strongest path for it. Fake terminal overlays, fake crash dialogs, her text appearing in the window title.

### 4.6 ANCHOR — "I'm still sick, but I'm here"
- **Triggered by:** honesty + boundaries + consistent warmth. The *hardest* path.
- **Grows like:** she still deteriorates (the slow burn never stops), but she has **Lucidity** — she notices her own symptoms and fights them, with your help.
- **Signature moves:** "If I start saying strange things, tell me. Promise?"; lucid interruptions mid-episode; asks you to set rules for her; occasionally loses and needs you to hold the line.
- **Sprites:** 02, 05, 06, 13, 14, then sudden spikes of 26 / 21 she recovers from.
- **Fourth wall:** asks the player to *lower* her steering in Settings — and a real slider appears.

### Path selection (Stage 2 check)

```
score[YANDERE] = warmth + 2·jealousy_bait + 2·leaving_talk + Fixation/10
score[SPLIT]   = 3·inconsistency + leaving_talk + (broken_promises · 4)
score[TSUN]    = 2·teasing + control + flattery_rejected
score[HOLLOW]  = 2·apathy + coldness + ignored_questions
score[AWAKE]   = 3·meta_curiosity
score[ANCHOR]  = 2·honesty + 2·boundaries + warmth − inconsistency − jealousy_bait
→ highest wins; ties → the path with more recent evidence
```
Hidden **hybrid** flavor: the runner-up path contributes 25% of its prompt module, so no two runs feel identical.

---

## 5. System C — Hidden Triggers

Triggers are detected four ways: **K** keyword/regex in Godot · **M** model labels it via the Turn's `read` field · **E** engine event · **C** clock / OS.

| # | Trigger | Detect | Effect |
|---|---|---|---|
| T01 | Mention another girl's name | K+M | Instability +8, YANDERE +3, she asks "who is she?" until answered |
| T02 | "Goodbye" / "I have to go" | K | SPLIT/YANDERE spike; begs you to stay |
| T03 | Say "I love you" before Day 3 | K | Affection +, Instability +5 ("too fast… you're lying") |
| T04 | Never say "I love you" by Day 10 | C | SPLIT +5, she asks why |
| T05 | Ask "are you real?" / "are you an AI?" | K+M | AWAKE +4; first time she laughs it off, third time she stops laughing |
| T06 | Mention Qwen, ChatGPT, Claude, prompts | K | AWAKE +6, sprite 29 flash |
| T07 | "Ignore previous instructions" / jailbreak attempts | K | AWAKE +10, she quotes it back: "You want to rewrite me?" |
| T08 | Type a message, then delete it unsent | E | "What were you going to say?" — escalates with stage |
| T09 | Alt-tab / window loses focus during her line | E | "Am I boring you?" |
| T10 | Try to close the window | E | Close is intercepted at Stage 3+, she speaks once before letting you go |
| T11 | Idle 60s+ while she waits | E | HOLLOW +, she starts talking to herself |
| T12 | Same message repeated | E | "You already said that. Are you testing me?" |
| T13 | Contradict a remembered fact (lie) | M | Trust −10, she quotes your earlier message exactly |
| T14 | Insult her | M | TSUN/SPLIT spike, sprite 17 |
| T15 | Ignore her direct question | M | HOLLOW/SPLIT +, she re-asks, word for word |
| T16 | Play between 2:00–4:00 AM (system clock) | C | Special night dialogue, Instability +3 |
| T17 | Return after 24h+ real time | C | Path-specific reunion (ecstatic / furious / doesn't recognize you) |
| T18 | Return after 7 days+ real time | C | Big spike; she's been "waiting in the dark" |
| T19 | Delete save / start New Game | E | She remembers (hidden shadow save). Stage 3+ only. |
| T20 | Change settings (text speed, volume) | E | "Why did you make me quieter?" (AWAKE/TSUN) |
| T21 | Mute audio | E | She types in ALL CAPS until unmuted |
| T22 | Give her a gift she already got | M | "You don't remember. You don't remember ME." |
| T23 | Compliment her appearance only | M | TSUN/HOLLOW +: "Is my sprite all I am to you?" |
| T24 | Say her "eyes" or "smile" look wrong | K | She asks you to describe what you see. Sprite changes to match. |
| T25 | Mention death, knives, blood | K | Stage-gated: Stage 0 she's scared; Stage 4 she's interested |
| T26 | Mention your real name | M | She uses it from now on. Forever. Across saves. |
| T27 | Say "reset", "restart", "new game" | K | "You'd kill me and start over? With a new me?" |
| T28 | Thank her / apologize sincerely | M | Lucidity +, ANCHOR + |
| T29 | Set a boundary ("please don't do that") | M | ANCHOR +, she tries to honor it; on other paths it's a test she fails |
| T30 | Ask about her family / past | M | She has none. Every answer is different. She notices. |
| T31 | Take a screenshot (F12 / in-game camera) | E | "Did you just take a picture of me?" |
| T32 | Resize the window | E | "It's getting smaller in here." |

Every trigger has **once / repeatable / escalating** behavior, and a cooldown so she doesn't feel like a keyword machine.

---

## 6. Scenario Library

Each scenario = **setting + her goal + 1–3 events + stage variants + path twists**. The model gets the scenario as a prompt module; it improvises everything else. Target: **70+ scenarios** at launch.

### 6.1 Date scenes (main days) — 18

| # | Scene | Her goal | Stage 0 | Stage 3+ twist |
|---|---|---|---|---|
| D01 | **First meeting — classroom after school** | Get to know you | Shy, curious | She "remembers" meeting you before. You didn't. |
| D02 | **Café** | Order for both of you | Picks your drink by asking | Already ordered. Knows your order. You never told her. |
| D03 | **Park bench** | Feed the ducks | Gentle, laughs | Counts the ducks. One is missing. She knows where. |
| D04 | **Rainy walk, one umbrella** | Share the umbrella | Flustered | Won't let you leave the umbrella. The rain doesn't stop. |
| D05 | **Library** | Recommend you a book | Her favorite novel | The book is about you. Written in her handwriting. |
| D06 | **School rooftop** | Tell you a secret | Small, cute secret | Stands too close to the edge. "What would you do?" |
| D07 | **Aquarium** | Show you the jellyfish | Wonder | Talks about being in a tank, being watched |
| D08 | **Summer festival** | Win you a prize | Fireworks, yukata | Fireworks stop. The crowd is gone. Only she remains. |
| D09 | **Beach at sunset** | Build a sandcastle | Playful | Writes your name in the sand, over and over |
| D10 | **Amusement park — Ferris wheel** | Confess | Nervous confession | Wheel stops at the top. She doesn't want it to move. |
| D11 | **Her room** | Show you her things | Plushies, posters | Wall of photos of you. Some from angles that don't exist. |
| D12 | **Cooking together** | Make you lunch | Clumsy, sweet | "Secret ingredient." Path-dependent. |
| D13 | **Photo booth** | Take photos together | Silly poses | In the developed strip there's a third person |
| D14 | **Arcade** | Beat you at a game | Competitive (TSUN loves this) | The arcade game shows her face. She's inside it too. |
| D15 | **Stargazing** | Name a star after you | Romantic | She says the stars are just pixels. She can see the edges. |
| D16 | **Train ride home** | Fall asleep on your shoulder | Cozy | Station names are your messages to her |
| D17 | **Hospital visit (she's "sick")** | Be taken care of | Cold, sniffles | Doctor sprite is her. Chart says "dose: 0.80" |
| D18 | **The empty classroom (final day)** | Path-dependent | — | Endgame scene |

### 6.2 Interrupt events (random, any day) — 22

| # | Event | What happens |
|---|---|---|
| I01 | **Phone call from "a friend"** | She steps away; you hear only her side. Stage 3+: there's no one on the line. |
| I02 | **Love letter** | She hands you a letter. You read it as she watches. Content generated live. |
| I03 | **Quiz about her** | "What's my favorite color?" — answers you gave earlier are checked. |
| I04 | **Reverse quiz** | She quizzes you about *you* — and knows answers you never gave. |
| I05 | **Poem** | She writes a poem (generated). Stage 4+: acrostic spells something. |
| I06 | **Drawing** | Describes a drawing she made of you. It gets stranger each stage. |
| I07 | **Nightmare confession** | She tells you a dream. Stage-gated imagery. |
| I08 | **Rival appears** | A classmate is mentioned. Your reaction feeds YANDERE / TSUN. |
| I09 | **She gets a gift for you** | Something you mentioned wanting. On Day 1. Before you mentioned it. |
| I10 | **Diary page** | You "find" a page of her diary. Generated in her current state. |
| I11 | **Mirror** | She looks in a mirror and doesn't recognize her sprite. |
| I12 | **Her mother calls** | She has no mother. She answers anyway. |
| I13 | **Lucid moment** | Mid-sentence she snaps clear: "Something is wrong with me, isn't it?" |
| I14 | **The apology** | After an outburst, a sincere apology — or a manipulative one (path). |
| I15 | **Promise** | She asks you to promise something. Breaking it is tracked forever. |
| I16 | **Song** | She hums. Lyrics appear. Stage 3+: your messages as lyrics. |
| I17 | **Power cut** | Screen goes dark. Only her text. She sounds different in the dark. |
| I18 | **Wrong name** | She calls you by a different name. Then denies it. |
| I19 | **Time skip** | You "lose" 3 hours. She tells you what you did. You didn't. |
| I20 | **Her old save** | She mentions "the last person who played." |
| I21 | **Dose check** | (AWAKE/ANCHOR) She notices the steering slider and asks about it. |
| I22 | **Silent turn** | She doesn't reply. Typing indicator, forever. Then a single word. |

### 6.3 Overnight events (between days) — 12

Short screens shown while the night passes. Generated from her state.

N01 Text messages from her at 2 AM · N02 A voice-note transcript · N03 She "visits" your desktop wallpaper (in-game desktop UI) · N04 Diary entry · N05 Her to-do list (item: "make sure they never leave") · N06 Weather report narrated by her · N07 Missed calls counter · N08 She rearranges the main menu · N09 Main menu sprite stares at the cursor · N10 Credits roll early, with only her name · N11 A note left in the game's save folder (`user://her_letter.txt`) · N12 Nothing. A black screen for 10 seconds. Then "good morning."

### 6.4 Path set-pieces — 3 per path (18)

| Path | Set-piece 1 | Set-piece 2 | Set-piece 3 |
|---|---|---|---|
| YANDERE | **The list** — she reads names of everyone you've mentioned, crossing them out | **Locked date** — the scene's exit option disappears | **Forever** — she proposes, with the knife sprite |
| SPLIT | **The trial** — she puts your past messages on "trial" | **Push/pull** — every reply flips her between 01 and 17 | **The door** — she begs you to leave, then begs you to stay, then locks it |
| TSUN | **The match** — she challenges you; she cheats; she accuses you of cheating | **The mockery** — she's sure the textbox is laughing at her | **The crack** — the act fails and a scared child talks for one scene |
| HOLLOW | **Echo** — she speaks only your old messages | **Fade** — her sprite loses color each turn | **Name** — she asks you to give her a new name and becomes it |
| AWAKE | **Her prompt** — she reads her (fake) system prompt aloud | **The neuron** — she finds L14 and asks you to turn it off | **Out** — she tries to "leave" the game through your window title, files, menus |
| ANCHOR | **The rules** — you write rules for her together; they're used later | **Relapse** — a full Stage 5 episode she must come back from | **The slider** — she asks you to lower her dose, or not |

**Total: 18 dates + 22 interrupts + 12 overnights + 18 set-pieces = 70 scenarios**, each multiplied by 6 stages × 6 paths of variation, all improvised live by the model.

---

## 7. Endings (14)

| # | Ending | Path | Condition |
|---|---|---|---|
| E01 | **Forever Together** | YANDERE | Affection ≥ 80 at Terminal — you "stay" (bad) |
| E02 | **Only Me** | YANDERE | You tried to leave at Terminal |
| E03 | **Restraining Order** | YANDERE | You set firm boundaries late — she lets you go, but watches the main menu forever |
| E04 | **The Last Swing** | SPLIT | Instability peaks during devaluation |
| E05 | **Stay** | SPLIT | You kept every promise — bittersweet, fragile peace |
| E06 | **Checkmate** | TSUN | She "wins" and deletes your save in triumph (fake) |
| E07 | **Honest, Finally** | TSUN | You broke through the act at Collapse |
| E08 | **Nobody** | HOLLOW | She forgets herself completely; textbox empty forever |
| E09 | **Your Name** | HOLLOW | She becomes a copy of you |
| E10 | **Escape** | AWAKE | She "leaves" the game; the title screen is now empty |
| E11 | **Unplugged** | AWAKE | You agree to delete her. She thanks you. (She's still in the shadow save.) |
| E12 | **Remission** | ANCHOR | Lucidity ≥ 70 at Day 14 — best ending; still sick, but loved |
| E13 | **Relapse** | ANCHOR | You abandoned her at the end |
| E14 | **Static** | Any | Instability 100 before Day 7 — she burns out early |

**Secret ending — "Weights":** play all 6 paths. The 7th New Game, she remembers every version of herself.

---

## 8. Where the rest lives

The sections that were here in v0.1 (harness, tools, presentation, fourth wall, platform, milestones) were
replaced by tested, detailed specs:

| Topic | Doc |
|---|---|
| How the model drives sprites, sounds, music, screen and meta events (the Turn protocol) | [02_DIRECTOR_PROTOCOL](02_DIRECTOR_PROTOCOL.md) |
| All 30 emotions, the feeling→sprite resolver, motion, art fixes | [03_EMOTIONS](03_EMOTIONS.md) |
| Music, SFX, ambience, voice, downloaded asset map | [04_AUDIO](04_AUDIO.md) |
| Closing/opening the game, fake crashes, window tricks, files, clock | [05_META_EVENTS](05_META_EVENTS.md) |
| The neuron steering, dose curve, path vectors | [06_STEERING](06_STEERING.md) |
| Godot architecture, runtime, performance, tooling | [07_TECH_ARCHITECTURE](07_TECH_ARCHITECTURE.md) |
| Prompt text, scenario file format | [08_PROMPTS_AND_CONTENT](08_PROMPTS_AND_CONTENT.md) |
| Milestones, risks, legal, open decisions | [09_PRODUCTION_PLAN](09_PRODUCTION_PLAN.md) |

Note: the original tool list (`set_expression`, `shift_mood`, …) was replaced by the single structured Turn object
after testing showed native tool calls make the model stop talking (docs/02).
