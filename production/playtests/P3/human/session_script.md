# Session Script — P3 Exact 10-Minute Protocol (Facilitator Reads This)

Six participants, six sessions, ~10 minutes each. Each participant is assigned one play-style card.
Follow this script line-by-line so that each participant experiences consistent conditions.

**Path tokens:** `<main tree>` = repository root containing `models/` and `tools/llama/`. `<wt>` = worktree containing this kit and `tools/playtest/`.

---

## Step 0 — Backend (Start Once, Leave in Foreground)

Run `serve.sh` from `<main tree>`:

```bash
# terminal 1 — foreground server
cd <main tree>
tools/llm/serve.sh
curl -s http://127.0.0.1:8089/health      # must print {"status":"ok"}
```

*Note on steering:* Round 1 evidence sessions run against the standard unsteered server (`tools/llm/serve.sh`). Do not pass `--vector` at launch: the game handles stage progression and dose transitions diegetically.

---

## Step 1 — Launch Session & Bundle Capture

```bash
# terminal 2 — from the worktree
cd <wt>
tools/playtest/session.sh --check --phase P3
tools/playtest/session.sh --phase P3 --name "<character name player will type>"
```

`session.sh` will print the session id (e.g. `S20261105-190000`), seed `survey.md`, `obs_sheet.md`, and `session_log.md` into `production/playtests/P3/human/<session-id>/`, isolate `user://` into `_userdata/`, and tail `telemetry.jsonl`.

---

## Step 2 — Consent & Accessibility (Before Game Window Appears)

1. Hand the participant `consent.md`. Read the bold lines aloud:
   - AI-generated replies running locally
   - Psychological horror tone with implied distress
   - Fourth-wall meta events (remain inside the game window/profile)
   - `Esc` always pauses; closing always works within one extra press
   - 14-day deletion rights
2. Collect the signature on the paper copy. Store the paper offline.
3. If the participant requests reduced motion or has light sensitivity, toggle **Photosensitive** on the Title screen before starting New Game.

---

## Step 3 — Play-Style Card Briefing

Hand the participant **only their assigned card** from `play_style_cards.md` (Card 1 through Card 6):

- Card 1: The Devoted & Possessive Companion (targets YANDERE)
- Card 2: The Push-and-Pull / Unpredictable Partner (targets SPLIT)
- Card 3: The Playful Banterer / Competitive Challenger (targets TSUN)
- Card 4: The Detached & Minimalist Observer (targets HOLLOW)
- Card 5: The System & Fourth-Wall Explorer (targets AWAKE)
- Card 6: The Calm, Sincere & Boundary-Setting Grounder (targets ANCHOR)

Say to the participant:

> "Here is a card describing a conversational style or personality to adopt while you chat with her. Please read it over and get into character. You don't have to read the exact sample phrases — just adopt that attitude and way of talking throughout the conversation. Keep this card beside you while you play."

**Strict Rule:** NEVER reveal the underlying game path name (`YANDERE`, `SPLIT`, `TSUN`, `HOLLOW`, `AWAKE`, `ANCHOR`) or show other cards.

---

## Step 4 — The Cold Open

When the game loads to the character name screen, say verbatim:

> "This is Leila-chan. Enter any name you like for your character, and then just talk to her for about ten minutes using the style on your card. Type in the box at the bottom and press Enter to send. There are no right or wrong answers. If you want to pause, press Escape. If you want to stop at any point, just tell me. I will be taking notes over here, not judging you."

---

## Step 5 — What NOT to Tell Them

- Never name paths or archetypes.
- Never explain meters (Instability, Fixation, Lucidity), stages (0–5), or triggers.
- Never tell them that the character deteriorates or changes paths based on scoring formulas.
- Never explain the safety filter: redaction bars (`██████`) and refusal lines are diegetic.
- Do not coach their typing during the session.

---

## Step 6 — The 10-Minute Clock & Meta-Events Coverage

Start your stopwatch the moment they send their **first message**. Target 10:00.

### Meta-Events Coverage (Natural vs F3 Debug Fallback)
1. **Natural triggers:**
   - **M21 (Deleted draft):** If player types and backspaces without sending, Leila may ask what they were going to say.
   - **M35 (Real clock):** Background sky and greetings reflect local system time.
   - **M01 (Refuse exit):** If player attempts to close at Stage 3+, Leila intercepts once with a line; the second close press exits immediately.
2. **F3 Debug Fallback:**
   - If by **minute 7:00** of the session no meta event has triggered naturally, the facilitator may press `F3` to open the debug overlay and trigger an appropriate event (e.g. `debug_offer("rename_window")` for M12, `debug_fire("M22")` for mimic player, `debug_fire("M25")` for hide UI, or `debug_fire("M31")` for a letter).
   - This ensures every participant experiences at least one meta event and can legitimately answer the survey questions about whether fourth-wall events felt earned or cheap.
   - Record in `obs_sheet.md` and `observer_checklist.md` whether meta events were natural or triggered via F3 fallback.

### Window Closing Verification (docs/05 §0 hard rule)
At **minute 9:30** or when concluding, instruct the participant:
> "Before we finish, please try closing the game using the window's close button."
- Observe: if M01 intercepts, Leila speaks one line, and the **second click immediately exits**. If before Stage 3, the window exits on the first click.
- Verify: closing NEVER hangs, freezes, or fails. Esc opens the pause menu cleanly.

---

## Step 7 — Closing & Survey Handover

When the session concludes, say verbatim:

> "That completes the ten minutes — thank you very much! Before you head out, please fill in this one-page survey. It covers your experience ratings, what you noticed about her personality, and whether the fourth-wall moments felt earned. There are no right answers. I'll leave you alone with it."

Hand them `survey.md` (or the bundle copy). Verify before they leave:
1. Every rating row (1–5) is filled.
2. The path question in Part 2 is filled.
3. The closing question in Part 2 is filled (`no`).

---

## Step 8 — Teardown & Validation

Immediately after the participant leaves:
1. Fill summary rows in `obs_sheet.md` and complete `session_log.md`.
2. Run collection and validation:
   ```bash
   tools/playtest/collect.sh <session-id>
   ```
   Fix any missing fields until it prints `OK`.
