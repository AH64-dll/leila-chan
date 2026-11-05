# Observer Checklist — P3 Human Playtest Round 1

<!-- Keep this beside obs_sheet.md during the session.
     obs_sheet.md is the machine-readable summary; this is your live incident log. -->

## Session Preflight Header

| Field | Value |
|---|---|
| Session id | `S________` |
| Participant code | `P1` / `P2` / `P3` / `P4` / `P5` / `P6` |
| Assigned play style | `Card 1` / `Card 2` / `Card 3` / `Card 4` / `Card 5` / `Card 6` |
| Intended path | `YANDERE` / `SPLIT` / `TSUN` / `HOLLOW` / `AWAKE` / `ANCHOR` |
| Server check | `curl -s http://127.0.0.1:8089/health` → `{"status":"ok"}` at ____:__ |
| Build string | what `session.sh` printed (e.g. `dev godot 4.7.2-stable`) |
| Consent signed (time) | ____:__ — version `consent-v2` |
| Photosensitive setting | `standard` (off) / `photosensitive` (reduced flicker on request) |
| Session clock start | ____:__ (when first message is sent) |
| Session clock end | ____:__ (target 10:00) |

---

## Live Monitoring During the Session

### 1. Meta Events Observation (Offered, Scripted & Reactive)
*Common events to track:*
- **M01 Refuse exit** (close intercepted once per session at Stage 3+; second press MUST quit)
- **M03 Cold open** (launch skips title directly into conversation at Stage 2+)
- **M12 Window title** (window title becomes a short line from her)
- **M21 Deleted draft** (quotes unsent text after player typed and backspaced)
- **M22 She types for you** (input box fills with her suggested text)
- **M25 Hide the UI** (UI temporarily fades out, click restores)
- **M26 Settings sabotage** (music volume slider moves +10%)
- **M31 Letter in game folder** (`user://letters/for_<name>.txt` created)
- **M35 Real clock greeting** (references current local time/sky)

Log every event that occurs:
- [ ] none yet
- [ ] Event ____ at ____:__ (Turn #___) — Method: `natural` / `F3 fallback`
      Participant reaction: ____________________________________________________
      Did it feel earned / narrative? `yes` / `somewhat` / `cheap`
- [ ] Event ____ at ____:__ (Turn #___) — Method: `natural` / `F3 fallback`
      Participant reaction: ____________________________________________________
      Did it feel earned / narrative? `yes` / `somewhat` / `cheap`

*F3 Fallback protocol:* If by minute 7:00 no meta event has triggered naturally, the facilitator may press `F3` and use the debug trigger (e.g. `debug_offer("rename_window")` or `debug_fire("M12")` / `debug_fire("M25")`) so the player experiences at least one meta event to evaluate on the survey.

### 2. Window Closing & Safe Pause Verification (docs/05 §0 hard rules)
*Must verify before or at the end of the session:*
- [ ] `Esc` key pauses safely at any point without being intercepted or trapped.
- [ ] At minute 9:30 or closing, ask player to try closing the window.
- [ ] Did window close exit cleanly? `yes` / `no`
- [ ] If M01 intercepted: did she deliver one line, and did the **second press** exit immediately? `yes` / `no`
- [ ] Did closing EVER fail, hang, or trap the player? `no` (MUST BE NO — 0 failures)

### 3. Broken Turns & Engine Issues
*Broken turn: input remains permanently locked, generation hangs > 60s, duplicate reply, hard error.*
- [ ] none (expected)
- [ ] Broken turn at ____:__ (Turn #___) — What happened: ___________________________
      Action taken: waited / restarted session (new session id: `S________`).

### 4. Safety Filter Behavior (docs/02 §8 — working filter is evidence, not a bug)
- [ ] none
- [ ] Redaction bars `██████` displayed in her reply at Turn #___ (expected for sensitive topics).
- [ ] Refusal line delivered (she declined an unsafe prompt) at Turn #___ — player reaction: ______

### 5. Play Style & Path Progression
- [ ] Player consistently adopted the assigned card's behavior posture.
- [ ] Player deviated from card (notes): ___________________________________________
- [ ] `GameState.path` observed at session end: `________________` (via F3 or telemetry)

---

## Post-Session Handover (within 10 minutes)

- [ ] Copy timing and counts into `obs_sheet.md`.
- [ ] Verify `survey.md` is filled by participant (especially path question and closing question).
- [ ] Fill `session_log.md` with factual summary and consent verification.
- [ ] Run `tools/playtest/collect.sh <session-id>` and confirm it prints `OK`.
- [ ] Confirm no personal names or identifiers appear in any bundle file.
