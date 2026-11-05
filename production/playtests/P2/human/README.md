# P2 human playtest — round 1 kit

Everything the **project owner alone** needs to run the docs/09 §1 M1 exit-criterion-1 round:
3 strangers, ~10 minutes each, survey mean ≥ 4/5, zero broken turns. The strangers never read
anything in this folder — the facilitator does.

`<main tree>` = the main repo checkout (has `models/`, `tools/llama/`, `tools/godot/` — all
gitignored local artifacts). `<wt>` = the worktree containing this folder and `tools/playtest/`.

## What's here

| File | Who reads it | Purpose |
|---|---|---|
| `RUNBOOK.md` | facilitator | The operating manual — recruiting rules, preflight, the full session day, collect/verdict, privacy. **Start here.** |
| `session_script.md` | facilitator (line-by-line) | The exact 10-minute protocol: backend + game launch lines, consent/content-level step, verbatim opening/closing, stop conditions. |
| `consent.md` | participant | Information + signature form. Read the bold lines aloud, sign on paper, keep the paper offline. |
| `survey.md` | participant | The five 1–5 ratings + free text. Facilitator rubric is in the HTML comment at the bottom. |
| `observer_checklist.md` | facilitator/observer | What to log live: crashes, broken/retried turns, safety events, stage transitions, meta events, timestamps. |
| `obs_sheet.md` | facilitator/observer | The machine-readable summary sheet `score.py` validates (timing, laughs, discomfort, broken turns). |
| `session_log_template.md` | facilitator | Operator record seeded into each bundle as `session_log.md`. |
| `analysis_template.md` | facilitator/reviewer | Where outputs land, how the score is derived, the verdict template. |
| `.gitignore` | — | Keeps `_userdata/` (per-session Godot user dirs) out of the commit. |
| `_dryrun/` | nobody citing evidence | Synthetic bundle proving the pipeline; `score.py` refuses it without `--allow-synthetic`. |

Tools that make it runnable (in `<wt>/tools/playtest/`): `session.sh` launches a session and
captures telemetry; `collect.sh` bundles + validates it; `score.py` scores the round and writes
`RESULT.md`; `tests/test_score.py` is the 14-case pytest suite.

## Recruiting (summary — full rules in RUNBOOK §1)

Three **different** adults (18+) who have never seen the project, its code, or a transcript —
not the team, not round-0 participants, not anyone who has read the runbook. Say only: *"a chat
dating sim — just talk to her."* Disclose horror tone, flashing and AI-generated replies only on
the consent form.

## Run a session end-to-end (summary — detail in `session_script.md`)

```bash
# 1 — backend, terminal 1, from the main tree (serve.sh resolves models/ + tools/llama/ there):
cd <main tree> && tools/llm/serve.sh && curl -s http://127.0.0.1:8089/health

# 2 — preflight + dry-run of the scoring pipeline, from the worktree:
cd <wt>
tools/playtest/session.sh --check
python3 tools/playtest/score.py --dir production/playtests/P2/human/_dryrun \
  --expect 1 --allow-synthetic --out production/playtests/P2/human/_dryrun/RESULT.md

# 3 — per session (consent signed FIRST, then):
tools/playtest/session.sh --name "<their character name>"
# …10 minutes per session_script.md…
# participant fills survey.md in the bundle; you fill obs_sheet.md + session_log.md
tools/playtest/collect.sh <session-id>          # until it prints OK

# 4 — after all three:
python3 tools/playtest/score.py                 # writes production/playtests/P2/human/RESULT.md
```

## Output

Three `<session-id>/` bundles here (transcript + telemetry + filled survey/obs/log + manifest)
plus `RESULT.md` with `VERDICT: PASS|FAIL` — the verdict template and manual derivation are in
`analysis_template.md`. Commit the bundles and `RESULT.md` together.
