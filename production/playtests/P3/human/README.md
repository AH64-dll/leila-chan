# P3 Human Playtest — Round 1 Kit

Complete facilitator kit for the **P3.20 human playtest round** (docs/09 §1 M3 exit criteria):
**6 players, each told a play style; record which path they land on; meta events felt earned?**  
Gate thresholds: **≥ 4/6 land on the intended path; pooled survey mean ≥ 4/5; zero close-failures; zero broken turns.**

`<main tree>` = repository root containing `models/` and `tools/llama/`.  
`<wt>` = worktree containing this kit and `tools/playtest/`.

---

## File Catalogue

| File | Audience | Purpose |
|---|---|---|
| `RUNBOOK.md` | Facilitator | Complete operator manual: recruiting, setup, execution, scoring criteria, and rules. **Start here.** |
| `play_style_cards.md` | Participants | The six play-style cards (one per path). Describes behaviors and conversational posture; never names the path. |
| `session_script.md` | Facilitator | Verbatim 10-minute session protocol: setup, consent, briefing, cold open, meta-events protocol, closing. |
| `consent.md` | Participant | Participant information and consent form (version `consent-v2`). Covers AI disclosure, horror themes, meta events, Esc pause, close safety, and 14-day deletion. |
| `survey.md` | Participant | Survey with 1–5 ratings (Face, Sound, Charm, Creepiness, Play again, Meta events earned, Content comfort) + path self-report + close failure check. |
| `obs_sheet.md` | Observer | Summary sheet capturing latencies, dead air, path detection, meta events count, close failures, and broken turns. |
| `session_log_template.md` | Facilitator | Factual session record template seeded into each bundle as `session_log.md`. |
| `observer_checklist.md` | Observer | Real-time incident tracking sheet for meta events, close verification, broken turns, and safety filter events. |
| `analysis_template.md` | Reviewer | Layout of session bundles, step-by-step arithmetic to re-derive scores by hand, and verdict format. |
| `.gitignore` | System | Ignores `**/_userdata/` so isolated Godot directories are never committed. |
| `_dryrun/` | Automation | Synthetic 6-bundle fixture proving the scoring pipeline end-to-end. Refused without `--allow-synthetic`. |

---

## Tooling

Located in `<wt>/tools/playtest/`:
- `session.sh`: Launches the game in an isolated profile, seeds bundle templates, and tails telemetry. Pass `--phase P3`.
- `collect.sh`: Merges raw transcripts, renders `transcript.md`, writes `manifest.json`, and validates bundle completeness.
- `score_p3.py`: Evaluates the 6 bundles against the P3.20 gate criteria, writes `RESULT.md`, and exits 0 on PASS, 1 on FAIL, 2 on INCOMPLETE.
- `tests/test_score_p3.py`: Pytest suite exercising all scoring logic and gate edge cases.

---

## End-to-End Workflow

```bash
# 1. Start local LLM backend (terminal 1, from main tree):
cd <main tree>
tools/llm/serve.sh
curl -s http://127.0.0.1:8089/health

# 2. Preflight and dry run scoring pipeline (terminal 2, from worktree):
cd <wt>
tools/playtest/session.sh --check --phase P3
python3 tools/playtest/score_p3.py --dir production/playtests/P3/human/_dryrun \
  --expect 6 --allow-synthetic --out production/playtests/P3/human/_dryrun/RESULT.md

# 3. For each of the 6 participants:
#    - Sign paper consent.md
#    - Hand them their single assigned card from play_style_cards.md
tools/playtest/session.sh --phase P3 --name "<character name>"
#    - Follow session_script.md for the 10-minute session
#    - Participant fills survey.md; team fills obs_sheet.md and session_log.md
tools/playtest/collect.sh <session-id>    # repeats until OK

# 4. Score the entire 6-session round:
python3 tools/playtest/score_p3.py
# Writes production/playtests/P3/human/RESULT.md and exits 0 on PASS.
```
