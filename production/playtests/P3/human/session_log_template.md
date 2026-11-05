# Session Log — P3 Operator Record

<!-- Filled by the FACILITATOR after the participant leaves. Participant code only (P1–P6); no real names. -->
<!-- score_p3.py reads the first table: keep the `| Field | Value |` shape. `Consent` must be `yes`. -->

## Session Facts

| Field | Value |
|---|---|
| Session id | — |
| Participant code | — |
| Assigned play style | — |
| Intended path | — |
| GameState path at end | — |
| Consent | — |
| Consent version | — |
| Date | — |
| Started (local) | — |
| Ended (local) | — |
| Build | — |
| Scenario | — |
| Facilitator | — |
| Closing failure observed | — |
| Withdrawn | — |

---

## Field Guidance

- **Participant code**: `P1` through `P6`. Exactly 6 distinct codes in the completed round.
- **Assigned play style**: The card given to the participant (`Card 1` through `Card 6`).
- **Intended path**: The path targeted by the card (`YANDERE`, `SPLIT`, `TSUN`, `HOLLOW`, `AWAKE`, `ANCHOR`).
- **GameState path at end**: The path recorded by the engine at session end (`GameState.path`).
- **Consent**: `yes` only if the paper consent form was signed prior to play.
- **Consent version**: `consent-v2` (from `consent.md`).
- **Closing failure observed**: `no` normally. Any trapped close or freeze on exit is a failure (`yes`).
- **Withdrawn**: `no` normally. If participant requested withdrawal, delete bundle and note offline.

---

## What Happened

<!-- Two or three sentences: how the session progressed, what the conversation revolved around,
     and how the 10-minute session concluded. -->

> 

---

## Path Landing Summary

<!-- Note whether the participant adhered to the play style card, what path GameState reached,
     and what the participant self-reported on their survey. -->

- Assigned Style & Intended Path: 
- GameState.path at session end: 
- Player self-reported path: 
- Agreement confirmed? (yes/no): 

---

## Meta Events Summary

<!-- List any meta events triggered (M01–M12, M21–M26, M31–M38), whether they were natural
     or triggered via F3 debug fallback, and how the participant reacted. -->

> 

---

## Deviations from the Runbook

<!-- "None" or any specific adjustment made (e.g. photosensitive toggle enabled, F3 debug fallback used for M12). -->

> 

---

## Teardown Checklist

- [ ] Game window closed cleanly without error or force-kill.
- [ ] Esc pause verified functional during play.
- [ ] Closing verified working within one extra press/click.
- [ ] `tools/playtest/collect.sh <session-id>` ran and printed `OK`.
- [ ] `survey.md`, `obs_sheet.md`, and this file completely filled.
- [ ] No real names anywhere in the bundle.
- [ ] Paper consent copy stored offline.
