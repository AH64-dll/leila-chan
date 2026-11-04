# Session log — operator record

<!-- Filled by the FACILITATOR after the participant leaves. No real names: participant code only. -->
<!-- score.py reads the first table: keep the `| Field | value |` shape; `Consent` must be `yes`. -->

## Session facts

| Field | Value |
|---|---|
| Session id | — |
| Participant code | — |
| Consent | — |
| Consent version | — |
| Date | — |
| Started (local) | — |
| Ended (local) | — |
| Build | — |
| Scenario | — |
| Facilitator | — |
| Withdrawn | — |

- **Consent**: `yes` only if the participant signed the paper form. `no` means this session can
  never be evidence.
- **Consent version**: the line at the top of `consent.md` (`consent-v1`).
- **Build**: what `session.sh` printed (e.g. `dev godot 4.7.2` or the export path). Do not guess.
- **Scenario**: what the scene showed (`D01_classroom`, `D02_cafe`, …), or `unknown` if you did not
  see the setting. It is for reading the results, not for the gate.
- **Withdrawn**: `no` normally. `yes` means the participant asked to delete the data: delete the
  bundle and do not commit it.

## What happened

<!-- Two or three lines: how they started, what they typed about, how it ended (date end, 10:00,
     quit). Note anything unusual about the room, the machine or the audio. -->

> 

## Deviations from the runbook

<!-- "None" or what you had to do differently (e.g. restarted after a stuck turn, turned off the
     photosensitive effects at the participant's request, a second observer joined). -->

> 

## Teardown

- [ ] Game window closed normally (not force-killed mid-turn).
- [ ] `tools/playtest/collect.sh <session-id>` ran and printed `OK`.
- [ ] `survey.md` filled by the participant, `obs_sheet.md` and this file filled by the team.
- [ ] No real names in the bundle.
- [ ] Consent paper copy filed offline.
