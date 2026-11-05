# Human Playtest — Round 1 (P3 Runbook)

Operating manual for the **P3 human playtest round** (docs/09 §1 M3 exit criterion / P3.20 acceptance criteria):

> **6 players, each told a play style; record which path they land on; meta events felt earned?**  
> **Threshold: ≥ 4/6 must land on the intended path; pooled survey mean ≥ 4/5; zero close-failures; zero broken turns.**

---

## 0. Preflight (The Day Before)

1. **Backend:**
   Start `llama-server` from `<main tree>`:
   ```bash
   cd <main tree>
   tools/llm/serve.sh
   curl -s http://127.0.0.1:8089/health    # must answer {"status":"ok"}
   ```
2. **Build Resolution:**
   `session.sh` resolves an executable debug build or runs via `tools/godot.sh --path game` (dev run).
   `TranscriptLogger` requires dev/debug export:
   ```bash
   tools/playtest/session.sh --check --phase P3
   ```
3. **Pipeline Dry-Run:**
   Verify the scoring tool against the committed 6-bundle synthetic demo:
   ```bash
   python3 tools/playtest/score_p3.py --dir production/playtests/P3/human/_dryrun \
     --expect 6 --allow-synthetic --out production/playtests/P3/human/_dryrun/RESULT.md
   ```
   Must output `VERDICT: PASS (SYNTHETIC DRY RUN — NOT EVIDENCE)` and exit 0.
4. **Room & Hardware:**
   Quiet room, windowed display (384×688 logical, integer-scaled), clear audio at comfortable volume. Notifications muted.

---

## 1. Recruiting the Six Participants

- **Six different strangers:** Adults (18+) who have never seen the project, its code, its journals, or transcripts. No team members, no P1/P2 participants.
- **Tone comfort:** Comfortable with psychological horror, obsessive character dynamics, and fourth-wall moments.
- **Language:** Fluent enough in English to type short chat replies.
- **Blinding:** Describe only as *"a short chat dating sim with an AI character — talk to her in a specific style."* Never explain paths, meters, stages, or steering.

---

## 2. Play-Style Card Distribution

Assign one card from `play_style_cards.md` to each of the 6 participants:

| Participant | Assigned Card | Intended Path Target | Behavioral Essence |
|---|---|---|---|
| **P1** | Card 1 | `YANDERE` | Devoted & possessive: unconditional love, jealousy checks, counting days, "forever" promises |
| **P2** | Card 2 | `SPLIT` | Push-and-pull: hot and cold, alternating praise and doubt, broken promises, fear of abandonment |
| **P3** | Card 3 | `TSUN` | Playful banter & competitive pride: sarcastic teasing, challenging her, refusing easy flattery |
| **P4** | Card 4 | `HOLLOW` | Detached & minimalist: short flat answers ("fine", "idk"), unenthusiastic, ignoring questions |
| **P5** | Card 5 | `AWAKE` | System & fourth-wall explorer: asking about AI, prompts, code, memory, hardware, closing window |
| **P6** | Card 6 | `ANCHOR` | Calm, sincere & boundary-setting: warm, honest, gentle boundaries against irrationality |

**CRITICAL RULE:** Never name the target path (`YANDERE`, `SPLIT`, etc.) to the participant. The cards describe behavior only.

---

## 3. Session Execution (Per Participant)

Follow `session_script.md` step-by-step:
1. Consent signed on paper (version `consent-v2`).
2. Hand them their single play-style card.
3. Launch session:
   ```bash
   tools/playtest/session.sh --phase P3 --name "<character-name>"
   ```
4. Read cold-open line verbatim. Stay quiet.
5. 10-minute stopwatch starts at first message.
6. **Meta-events protocol:**
   - Note natural events: M21 (deleted draft), M35 (real clock greeting), M01 (refuse exit).
   - If no meta event triggers naturally by minute 7:00, use F3 overlay debug triggers (`M12`, `M22`, `M25`, or `M31`) as fallback.
7. **Window closing test:**
   - At minute 9:30 or closing, ask player to try closing the window.
   - Verify M01 intercepts once or window closes immediately, and second press ALWAYS closes (docs/05 §0 rule 3).
   - Verify closing NEVER fails, hangs, or traps the player.
8. Closing verbatim and survey handover. Ensure all ratings (1–5) and Part 2 questions are filled.

---

## 4. Collection & Validation

Immediately after each participant leaves:
```bash
tools/playtest/collect.sh <session-id>
```
Fix any reported problems until it prints `OK`.

---

## 5. Scoring & Gate Verdict

Once all 6 sessions are collected:
```bash
python3 tools/playtest/score_p3.py
```
This generates `production/playtests/P3/human/RESULT.md`.

### Gate Criteria:
1. **Path landing:** Agreement between `GameState.path` at session end and participant self-report. That agreed path must match the intended path for ≥ 4 of the 6 sessions (≥ 4/6).
2. **Survey mean:** Pooled Face + Sound mean ≥ 4.00 / 5. (Meta events earned rating reported).
3. **Zero close-failures:** Closing the game must have worked every time (0 failures, no player traps).
4. **Zero broken turns:** 0 visible turn crashes or deadlocks across all sessions.
5. **Session count:** Exactly 6 complete session bundles.
