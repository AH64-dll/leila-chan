# Analysis Template — P3 Human Playtest Round 1

## 1. File Structure

Each session creates an isolated bundle under `production/playtests/P3/human/<session-id>/`:

```
production/playtests/P3/human/<session-id>/
  session.meta.json     machine facts: id, participant code, build, intended path, status
  telemetry.jsonl       live transcript tail (turn records, events, GameState.path)
  raw/                  pristine transcript jsonl files copied from _userdata/
  transcript.md         human-readable chat log rendered by collect.sh
  survey.md             participant filled survey (ratings + path self-report + closing check)
  obs_sheet.md          observer sheet (timing, path landing, meta events log, broken turns)
  session_log.md        facilitator log (facts, consent yes, deviations, teardown)
  manifest.json         file hashes, sizes and bundle completeness flag
  _userdata/            Godot user directory (gitignored, never evidence)
```

The round-level verdict file is written by:
```bash
python3 tools/playtest/score_p3.py
# outputs: production/playtests/P3/human/RESULT.md
```

---

## 2. Deriving the Gate Metrics by Hand

### A. Path-Landing Detection & Agreement
For each session:
1. Identify the **Intended Path** assigned via the play-style card.
2. Read the **GameState.path** at session end (from `telemetry.jsonl` or `session_log.md`).
3. Read the **Player Self-Report** from `survey.md` Part 2.
4. **Agreement**: Did `GameState.path == Player Self-Report`?
5. **Landed Intended**: Did they agree, and does that path match the **Intended Path**?
6. Gate requires **≥ 4 / 6** sessions landing on their intended path.

### B. Survey Ratings
1. Pool the `Face` and `Sound` ratings across all 6 sessions (12 values).
2. Compute arithmetic mean: `sum(Face + Sound) / 12.0`.
3. Gate requires pooled mean **≥ 4.00**.
4. Compute and report mean of `Meta events earned` rating (target ≥ 4.00).

### C. Zero Close-Failures (docs/05 §0 hard rule)
1. Verify `Closing failures` in `obs_sheet.md` is `0` for all 6 sessions.
2. Verify `Did closing ever fail?` in `survey.md` is `no` (or `never tried`) for all 6 sessions.
3. Gate requires **0** close failures total.

### D. Zero Broken Turns
1. For each session, take the maximum of observer broken turn count and telemetry uncompleted turns.
2. Sum across all sessions.
3. Gate requires **0** broken turns total.

---

## 3. Verdict Template

```markdown
# P3 Human Playtest — Round 1 Result

- Generated: <timestamp> by tools/playtest/score_p3.py
- Sessions: 6 of 6 complete
- Build: <build description>
- Gate: docs/09 §1 M3 exit criterion / P3.20 acceptance criteria

## Path Landing Summary

| Session | Participant | Card Style | Intended Path | GameState Path | Player Report | Agreement? | Landed Intended? |
|---|---|---|---|---|---|---|---|
| S... | P1 | Card 1 | YANDERE | YANDERE | YANDERE | yes | YES |
| S... | P2 | Card 2 | SPLIT   | SPLIT   | SPLIT   | yes | YES |
| S... | P3 | Card 3 | TSUN    | TSUN    | TSUN    | yes | YES |
| S... | P4 | Card 4 | HOLLOW  | HOLLOW  | HOLLOW  | yes | YES |
| S... | P5 | Card 5 | AWAKE   | AWAKE   | AWAKE   | yes | YES |
| S... | P6 | Card 6 | ANCHOR  | ANCHOR  | ANCHOR  | yes | YES |

- **Path landing rate:** <n>/6 (threshold: ≥ 4/6) -> PASS/FAIL

## Survey & Experience Ratings

| Session | Face | Sound | Mean | Charm | Creepiness | Meta Earned | Comfort | Close Failures | Broken |
|---|---|---|---|---|---|---|---|---|---|
| S... | _ | _ | _.__ | _ | _ | _ | _ | 0 | 0 |
| S... | _ | _ | _.__ | _ | _ | _ | _ | 0 | 0 |
| S... | _ | _ | _.__ | _ | _ | _ | _ | 0 | 0 |
| S... | _ | _ | _.__ | _ | _ | _ | _ | 0 | 0 |
| S... | _ | _ | _.__ | _ | _ | _ | _ | 0 | 0 |
| S... | _ | _ | _.__ | _ | _ | _ | _ | 0 | 0 |
| **Pooled** | **_.__** | **_.__** | **_.__** | _.__ | _.__ | **_.__** | _.__ | **0** | **0** |

## Gate Evaluation

| Check | Result | Threshold | Status |
|---|---|---|---|
| Path Landing (agreement on intended) | <n>/6 | ≥ 4/6 | PASS/FAIL |
| Survey Mean (pooled Face+Sound) | <x.xx> | ≥ 4.00 | PASS/FAIL |
| Closing Failures | 0 | 0 | PASS/FAIL |
| Broken Turns | 0 | 0 | PASS/FAIL |
| Completed Sessions | 6 | 6 | PASS/FAIL |

**VERDICT: PASS / FAIL** — <verdict explanation>
```
