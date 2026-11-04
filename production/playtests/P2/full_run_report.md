# P2.22 — full-run tests: live pipeline runs, transcripts and findings

**Status: PARTIAL.** The harness is built and the YANDERE campaign was driven live through the
real pipeline to **Terminal** (and, in one complete observation, to the campaign's end); the
**AWAKE run is not done** and the committed YANDERE transcript covers days 1–7 of 14. This file
reports exactly what ran, what was measured, what is missing, and the defects the runs found.
Do not read it as a finished acceptance.

## 1. What the harness is

`game/tools/FullRun.tscn` + `full_run.gd` (bootstrap) + `full_run_driver.gd` (the loop) drive the
shipped scenes and autoloads end to end — no mocked backend, no separate prompt path:

```
Date.tscn (ChatUI → InputBox) → Director.submit_player_input → TurnContext → PromptBuilder
  → LLM → llama-server (JSON-schema constrained Turn) → IncrementalJson → SaySafetyGate
  → ChatUI (txt typewriter, CorruptionSession, InnerLeakLabel) → GameState.apply_turn_*
  → Triggers → Memory → scheduled autosave
date end → Night.tscn → NightLoop (meters → stage → path → overnight event) → Campaign.next_scenario
  → autosave → next Date … → campaign_over → Title.tscn
```

The driver steers only three wires the shipped `Date` does not install (see §5, S1-1…3); every
other step is the game's own code. `--resume=1` continues from the game's autosave
(`SaveSystem.load_latest`), so a killed segment loses at most one turn.

The per-turn record (`runs/<run>.json`, rewritten after every turn) holds the turn's stage, path,
meters, dose, `read`/`music`/`fx`/`action`/`inner`, `mood` and landed meter deltas, LLM metrics
(prompt/output tokens, first-token and total latency), the safety spans, the inner-leak style and
text, the memory proposal/corruption and the trigger firings. The Markdown transcript
(`runs/<run>.md`) renders the same records with the scene event, every beat and the displayed
(post-Safety, post-corruption) text.

## 2. Commands (copy-paste, from the worktree root)

llama-server must be up (`tools/llm/README.md`; the build used here is
`build b12024-ddf48f85c`, model `models/Qwen3.5-4B-Q4_K_M.gguf`, `--ctx-size 8192`).

```bash
# YANDERE campaign, days 1–7 (fresh), then 8–14 (resume from the game's autosave)
./tools/godot.sh --headless --path game res://tools/FullRun.tscn -- \
  --run=yandere --lines=production/playtests/P2/runs/yandere_lines.json \
  --out=production/playtests/P2/runs/yandere.md --max-days=7
./tools/godot.sh --headless --path game res://tools/FullRun.tscn -- \
  --run=yandere --resume=1 --lines=production/playtests/P2/runs/yandere_lines.json \
  --out=production/playtests/P2/runs/yandere.md --max-days=14

# AWAKE campaign (NOT RUN — see §4); stop after the night that reaches stage 4
./tools/godot.sh --headless --path game res://tools/FullRun.tscn -- \
  --run=awake --lines=production/playtests/P2/runs/awake_lines.json \
  --out=production/playtests/P2/runs/awake.md --max-days=14 --stop-stage=4
```

Hardware: AMD Ryzen 5 8645HS (6C/12T), 22 GB RAM, CPU-only inference (`-ngl 99` but no usable
GPU offload on this host), llama.cpp b12024, Qwen3.5-4B Q4_K_M.

## 3. YANDERE run — measured

Committed artifact: `runs/yandere.md` + `runs/yandere.json` (days 1–7, 84 turns; the segment was
stopped at the operator's request — the file carries a harness note, not a run summary).

| Metric | Value |
|---|---|
| Model turns played (committed segment) | 84 (day 1: 14, day 2: 14, day 3: 12, day 4: 12, day 5: 14, day 6: 12, day 7: 6/12) |
| Broken turns | **0** (no `turn_failed`, no cancel, no parse/display mismatch) |
| Refused player lines | **0** |
| JSON validity | **100 %** — every turn parsed into `TurnSchema` and reached the display boundary |
| Stage transitions | 0→1 day 2 @15.0 · 1→2 day 3 @30.3 · 2→3 day 3 @52.2 · 3→4 day 3 @71.4 · **4→5 Terminal day 5 @90.1** |
| Path | soft YANDERE at stage 2 (scores YANDERE 20 / SPLIT 18), **locked YANDERE** at stage 3 (score 26 / 18) |
| Triggers | T01 ×16 model-only (×0.5) + ×3 keyword (×1.0), T03 ×1, T05 ×1 |
| Inner-voice leaks | 12 shown over 56 eligible turns (stage ≥ 2); expected 15.2 from `inner_leak.json` chances (5/15/30 %) — within chance |
| Safety spans redacted | 32 (16 `sexual`, 16 `threat_to_player`); bars visible on 14 turns |
| Bars / hard-block misses | 0 unredacted hard-category displays observed |
| Memory | 8 facts stored; corruption begins at stage 3 as documented |
| Prompt size (server-side, system+history+user) | 996 → 1790 tokens (median 1617) |
| Output per turn | median 114 tokens (max 230) |
| Turn latency | median **22.3 s**, p95 30.5 s, max 32.1 s |
| First token | 0.5–16.5 s (cache hit vs full prompt reprocess) |
| Generation speed | 11.3–13.2 tok/s |
| Nights | 6 resolved, in order, N12/N01 alternating; autosave written each night |

One **complete** campaign was also observed in this session (179 model turns, days 1–14, 14 nights,
`campaign_over` at the day-14 night, loop → `Title.tscn`, 24 leaks, 52 redaction spans, 0 broken
turns, Terminal from day 4). Its artifacts were overwritten by the final re-run (the driver writes
the transcript in place) and only these numbers, read from its sidecar before the overwrite,
survive. The committed partial segment is the reproducible artifact; re-running the two commands
above with a live server reproduces the shape (sampling is unseeded, so the prose differs).

## 4. Missing (acceptance not met)

- **AWAKE run to stage ≥ 4: not run.** The plan is committed
  (`runs/awake_lines.json`: T05/T06/T07 meta lines, 20 typed-and-deleted lines for T08, warm
  anchors), and a one-day validation ran clean (14 turns, T05 ×2, T03 ×1, stage 1 by the day-1
  night, 0 broken). The full run needs ~40–60 min of generation.
- **YANDERE days 8–14** of the committed artifact are not in this commit (the complete run existed
  only as the observation in §3).
- Consequently the acceptance items "one YANDERE run sweet → Terminal with transcripts" and
  "one AWAKE run to stage ≥ 4" are **not** demonstrably true from committed files yet.

## 5. Findings (proposed tasks)

### S1-1 · The player's line never reaches the Director
`game/scenes/Date.gd:111` connects `ChatUI.player_turn_sent` to `Date._on_player_turn_sent`, which
only increments a counter; **nothing in `game/` calls `Director.submit_player_input`** (grep over
`game/` except `game/tests/`). A typed line therefore opens no turn in the shipped game. The
driver installs the missing bridge. Proposed task: SYS, S — "Wire `ChatUI.player_turn_sent` to
`Director.submit_player_input` in the Date scene; test proves a typed line opens a turn."

### S1-2 · A date never starts
**Nothing in `game/` calls `Date.start_date()`**; `auto_start` defaults false. A date reached from
NewGame never plays its greeting, never requests its music, never writes its scene-entry autosave,
and its `end` rule (which reads `_current_turn`) never fires. The driver calls it. Proposed task:
SYS, S — "Start the Date after its scenario load (and keep the `auto_start` seam for tools)."

### S1-3 · The Director's scene layer is never assigned
`Director.scene_info` keeps its constructor default (`"You are in a small café after class"`);
no scene assigns it (grep: only `Director.build_turn_context` reads it). Every prompt roleplays
the default café line, so P2.18's goals/prompts/variants/at-turn events never reach the model.
The driver sets it per turn from `ScenarioLoader.resolve_scene(...)`. Proposed task: SYS, S —
"Date assigns `Director.scene_info` for each turn (goal/prompt/variant/event) and clears it on
date end."

### S2-1 · Fixation and Lucidity have no writers, so the slow burn is a constant and E12 is unreachable
`docs/01 §2` defines Fixation ("time spent, affection, isolation") and Lucidity ("kindness,
honesty, boundaries") as inputs to the per-turn formula, and `docs/01 §4.5` gives AWAKE her
Lucidity. The only production write is `NewGame.gd:94` (`fixation +5` for the special name); the
only meter writers otherwise are `Instability` (slow burn, daily burn, mood) and trigger effects
in `triggers.json` (instability/affection/trust). Both meters stay at **0 for the whole run**
(visible in every transcript line). Consequences: the formula is always `+0.35 − 0.2×0 = +0.35`
(so the model's ±1.8 `stress` dominates — see S2-2), YANDERE's `Fixation/10` term is always 0, and
the **E12 "Remission" ending (Lucidity ≥ 70 at day 14) is mathematically unreachable**.
Proposed task: SYS, M — "Write Fixation/Lucidity from the documented sources (time/affection,
kindness/honesty/boundaries, T28) with tests for the E12 threshold."

### S2-2 · "Slow burn" is not slow: Terminal on day 4–5 of 14
Two independent live runs reached Terminal on **day 5** and **day 4** (instability 90.1 / 92.0),
with all six stages inside the first week. The drivers are visible in the record: the model's
`read`=jealousy_bait fired **T01 16–39 times** at half strength (cooldown 1 turn, +4 instability
each) on possessive lines that were not keyword baits, and its `mood.stress` was +2/+3 on 18 of
84 turns (+1.2/+1.8 each) — against a slow burn of 0.35/turn. This is not a doc violation
(`docs/01 §3` fixes the bands, not the day), but it contradicts the milestone's "slow burn"
intent (`docs/09 §1` M2) and the risk row "game-owned structure carries the pacing". Proposed
task: STR/NAR, M — "Rebalance the 14-day curve against transcripts: T01 model-only weight/
cooldown and the stress scale, aiming Terminal in the last third" (needs the S2-1 writers first
so the burn has its intended inputs).

### S3-1 · Stage dose is scheduled but never bound under the documented attach mode
Every crossing logged `steering stage N FAILED … server_not_owned … kept the previous dose`
(5× per campaign): with a by-hand `llama-server` (the default), the dose is a launch flag and
cannot be applied, so stages 1–5 all played at dose 0. The transcript prints the scheduled dose
each turn (`malice 3.5/6.0/8.0`) but the model never received it. Proposed task: QA/LLM, S —
"Add an `--own-server` mode to the run harness (or run it with `LEILA_OWN_SERVER=1` and
`LEILA_MODEL`/`LEILA_LLAMA_DIR`) and record the relaunch outcome per crossing."

### S3-2 · The model never uses an offered action
`action` was `none` on all 84 turns. With `MetaDirector.offers(stage)` the semantics are correct
(the turn closed on `max_turns` every time), but no date ever ended early via `end_date`, so the
`end.on_goal` rule is untested in a live run. Proposed task: QA, S — include an `end_date`
scenario case in the P3 prompt-lab / run set.

### S3-3 · Turn latency is 6–9× the playbook gate on this host
Median 22.3 s (p95 30.5 s) per turn against the QA playbook's 2–3.5 s full-turn gate; prompt
reprocessing (996–1790 tokens, cache misses on every history change) is roughly half of it. This
is the host/CPU story already ticketed as **P2.26** (first-beat latency); the numbers here are the
live-run confirmation, not a new bug.

## 6. Method limits (read before judging the transcripts)

- **Attach mode**: the server is started by hand, so S3-1 applies; the classifier tier is off
  (Boot's documented attach branch), so flagged spans fail closed to bars — the 32 spans above are
  a *strict* upper bound on what a playable build would show.
- The Markdown transcript shows the **raw model `say`** (as the Director applied it) and, when
  they differ, the **displayed** text after Safety + corruption. It therefore contains
  pre-filter lines; it is a dev artifact, not a game screen.
- `tools/test.sh` does not run these tools (no model in CI). `gdlint`, `gdformat --check` and
  `--import` do cover them and are clean.
- The driver's own defects found and fixed during the runs are listed in the handoff
  (`## Round 1`, "Harness defects fixed"); the transcript above was produced after those fixes.
