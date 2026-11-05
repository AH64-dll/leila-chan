# Analysis template — where session outputs land and how the verdict is written

## 1. Where everything lands

Each `tools/playtest/session.sh` run creates one bundle folder, named by the session id it
prints (`S<yyyymmdd>-<hhmmss>` — "session 1 / 2 / 3" in the task description are simply the three
bundles in run order; name them session_1/2/3 when writing the round up):

```
production/playtests/P2/human/<session-id>/
  session.meta.json     machine facts: id, participant code, build, server, status (ended/aborted)
  telemetry.jsonl       the live transcript tail — TranscriptLogger turn/event records
  raw/                  pristine turns_*.jsonl copied out of the isolated user://
  transcript.md         readable chat log, rendered by collect.sh
  survey.md             the participant's filled survey          (the task's "survey_<n>")
  obs_sheet.md          the observer's filled summary sheet
  session_log.md        the facilitator's operator log           (the task's "session_<n>" record)
  manifest.json         sizes + sha256 of every file above + completeness flag
  _userdata/            Godot user dir — gitignored, never evidence
```

Everything above is committed except `_userdata/`. The round-level output:

```
production/playtests/P2/human/RESULT.md   written by python3 tools/playtest/score.py
```

`score.py` is the source of truth: it refuses to write `RESULT.md` at all if a bundle is
incomplete (`exit 2`, every missing field named). Never write a verdict by hand **instead of**
running it. The manual template in §3 exists for two cases: drafting the handoff summary before
the third session lands, and re-verifying a `RESULT.md` a reviewer doesn't trust.

### Re-deriving the numbers by hand (what the scorer does)

- **Survey mean** — from each bundle's `survey.md`: the `Face` and `Sound` rows only
  (1–5 each; `score.py` reads the first `| Question | Score |` table). Pool all six values:
  `(F1+S1+F2+S2+F3+S3) / 6`. `Charm`, `Creepiness`, `Play again` are reported, not gated.
- **Broken turns** — per bundle, the worse of: `obs_sheet.md` → `Broken turns` row, and the
  count of turn records in `telemetry.jsonl`/`raw/` whose status is not `completed`
  (`failed`, `cancelled`). `grep -c '"status": *"completed"' raw/turns_*.jsonl` vs total lines
  is the quick check; `manifest.json` already counts turns per file.
- **Sessions** — exactly 3 bundles, each `session.meta.json` → `"status": "ended"`, distinct
  participant codes, `Consent: yes` in `session_log.md`.

## 2. The gate rule (docs/09 §1 M1 exit criterion 1)

| Check | Rule | Source |
|---|---|---|
| Survey mean | pooled Face+Sound over the 3 sessions ≥ **4.00** | the task's "word/survey ≥ 4/5" |
| Broken turns | **0** across all three sessions | M1 "no broken turns" |
| Bundles | exactly **3**, all complete (score.py's field list) | brief: 3 strangers |

PASS needs all three. A FAIL is a result — report it with the reasons and quotes; do not re-run
a participant to move the mean.

## 3. Verdict template (copy into the handoff / round notes)

```markdown
## P2.24 human round 1 — verdict

- Sessions: <n> of 3 complete (S______, S______, S______)
- Builds: <what session.meta.json says> · Server: unsteered llama.cpp b12024, port 8089

| Session | Participant | Turns | Face | Sound | Broken (obs/telemetry) | First beat (s) |
|---|---|---|---|---|---|---|
| S______ | P_ | __ | _ | _ | _ / _ | __._ |
| S______ | P_ | __ | _ | _ | _ / _ | __._ |
| S______ | P_ | __ | _ | _ | _ / _ | __._ |

| Check | Result | Threshold | Pass? |
|---|---|---|---|
| Survey mean (pooled Face+Sound) | __.__ | ≥ 4.00 | PASS/FAIL |
| Broken turns (observer and telemetry, worst of) | _ | 0 | PASS/FAIL |
| Sessions | _ | 3 | PASS/FAIL |

**VERDICT: PASS|FAIL** — <reason line, e.g. "every M1 criterion 1 check passed" /
"survey mean 3.83 < 4.00; 1 broken turn (session 2, turn 7 — input never re-unlocked)">

### Notable quotes (verbatim from free text / obs sheets)
- S______: "…"
- S______: "…"

### Findings to ticket (severity, title, role)
- S_ — <what broke or felt wrong, evidence pointer> — proposed task: <title, role, size>
```

## 4. Reporting etiquette

- Read the free text before quoting the mean: the number is the gate, the sentences are why.
- Quote the game transcript and the survey, never the participant; participant codes only.
- If a session is withdrawn or declined, it is absent — not scored, not a failure.
- `_dryrun/` is a synthetic pipeline fixture, permanently labelled NOT EVIDENCE; exclude it.
