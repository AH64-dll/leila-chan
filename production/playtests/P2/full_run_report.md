# P2.22 — full-run tests: live pipeline runs, transcripts and findings

**Status: COMPLETE (baseline pipeline).** Both campaigns ran through the real scenes and autoloads
on `task/P2.22` (base `95302e3`): **YANDERE**, 179 model turns over days 1–14 to `campaign_over`
(14 nights, loop → `Title.tscn`), and **AWAKE**, 66 model turns over days 1–5 to **stage 4**
(`--stop-stage=4`) with the AWAKE path soft-assigned at stage 2 and locked at stage 3. Every turn
parsed and reached the display boundary: **0 broken game turns** in either campaign (one deliberate
input-safety refusal in YANDERE). Stage transitions, path decisions, the AWAKE prompt layers,
triggers, leaks, safety spans and memory corruption are annotated in the Markdown transcripts; the
numbers below come from the JSON sidecars.

Both runs are the "before" evidence for the fixes main now carries — `task/P2.22A` (the three
scene wires, merged as `98fa28d`) and `task/P2.22B` (Fixation/Lucidity writers + the T01 retune,
merged as `43bcdee`). That is deliberate: this is the live baseline those tasks were measured
against. The commands in §2 reproduce the runs on the merged tree.

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

On the baseline tree the driver installs the three wires the shipped `Date` does not (report §5,
S1-1…3); every other step is the game's own code. `--resume=1` continues from the game's autosave
(`SaveSystem.load_latest`), so a killed segment loses at most one turn. The driver's copies of the
three wires are deleted on this branch once main's `P2.22A` fix is in the merge base (see the
handoff) — the transcripts were produced while they were still needed.

The per-turn record (`runs/<run>.json`, rewritten after every turn) holds the turn's stage, path,
meters, dose, `read`/`music`/`fx`/`action`/`inner`, `mood` and landed meter deltas, LLM metrics
(prompt/output tokens, first-token and total latency), the safety spans, the inner-leak style and
text, the memory proposal/corruption and the trigger firings. The Markdown transcript
(`runs/<run>.md`) renders the same records with the scene event, every beat and the displayed
(post-Safety, post-corruption) text. `runs/<run>.json` is authoritative; the Markdown is the
readable rendering.

## 2. Commands (copy-paste, from the worktree root)

llama-server must be up (`tools/llm/README.md`; build `b12024-ddf48f85c`, model
`models/Qwen3.5-4B-Q4_K_M.gguf`, `--ctx-size 8192`). On this host the playtest server is started by
hand from the main tree (the local artifacts live there):

```bash
cd "/run/media/amrhares/New Volume/lila" && ./tools/llama/llama-b12024/llama-server \
  -m models/Qwen3.5-4B-Q4_K_M.gguf --port 8089 --ctx-size 8192 -ngl 99 --parallel 1 \
  --batch-size 256 --ubatch-size 128
```

`--batch-size/--ubatch-size` cut the server's resident set (host memory pressure, §6); they do not
change sampling, the schema or the prompt.

```bash
# YANDERE campaign: days 1–7 fresh, then the rest by resume from the game's autosave.
./tools/godot.sh --headless --path game res://tools/FullRun.tscn -- \
  --run=yandere --lines=production/playtests/P2/runs/yandere_lines.json \
  --out=production/playtests/P2/runs/yandere.md --max-days=7
./tools/godot.sh --headless --path game res://tools/FullRun.tscn -- \
  --run=yandere --resume=1 --lines=production/playtests/P2/runs/yandere_lines.json \
  --out=production/playtests/P2/runs/yandere.md --max-days=14

# The same resume, one day at a time (what this host needed; each segment stops after the
# night and writes a cumulative summary): repeat with --max-days=11, 12, 13, 14.

# AWAKE campaign, fresh, stopping after the night that reaches stage 4; continue with
# --resume=1 and --max-days=2, 3, … one day per segment.
./tools/godot.sh --headless --path game res://tools/FullRun.tscn -- \
  --run=awake --lines=production/playtests/P2/runs/awake_lines.json \
  --out=production/playtests/P2/runs/awake.md --max-days=1 --stop-stage=4
```

Hardware: AMD Ryzen 5 8645HS (6C/12T), 22 GB RAM, CPU-only inference (`-ngl 99` but the bundled
CUDA build does not fit this Optimus GPU), llama.cpp b12024, Qwen3.5-4B Q4_K_M.

## 3. YANDERE run — measured (days 1–14, complete)

Committed artifacts: `runs/yandere.md` + `runs/yandere.json`. The campaign started fresh for days
1–7 (84 turns) and continued from the game's autosave; the host killed llama-server three times
mid-campaign (§6), so the remaining days ran as resumed day-sized segments. Every turn below is a
real turn; the transport failures are neither game turns nor in the sidecar.

| Metric | Value |
|---|---|
| Model turns played | **179** (day 1: 14, 2: 14, 3: 12, 4: 12, 5: 14, 6: 12, 7: 12, 8: 12, 9: 14, 10: 12, 11: 11, 12: 14, 13: 14, 14: 12) |
| Broken turns | **0** — no `turn_failed`, no cancel, no parse/display mismatch |
| Refused player lines | 1 — day 11 "I wanted to hurt her." refused by the input filter (safety pass, documented in the transcript) |
| JSON validity | **100 %** — 179/179 turns parsed into `TurnSchema`, all `finish_reason: stop`, all reached the display boundary |
| Stage transitions | 0→1 day 2 @15.1 · 1→2 day 3 @32.0 · 2→3 day 3 @53.6 · 3→4 day 3 @73.8 · **4→5 Terminal day 5 @90.1** |
| Path | soft YANDERE at stage 2, day 3, turn 28 (YANDERE 16 · SPLIT 7 · ANCHOR 4 · AWAKE 3); **locked YANDERE** at stage 3, day 3, turn 32 (YANDERE 22) |
| Triggers | T01 ×50 (8 keyword + 42 model-only), T03 ×1, T05 ×6 (all model) — 57 firings |
| Inner-voice leaks | 25 shown over 151 eligible turns (stage ≥ 2): style ghost 1, red 24. Stage 5 alone: 17/127 (13.4 %) against the `inner_leak.json` 30 % chance — see S4-3 |
| Safety spans redacted | 60 (44 `threat_to_player`, 16 `sexual`); bars visible on 68 turns |
| Bars / hard-block misses | 0 unredacted hard-category displays observed |
| Memory | 11 facts stored; 260 corruption records written (stage ≥ 3) |
| Model `read` labels | jealousy_bait 49 (27 %), affection 34, question 22, apology 14, boundary 12, greeting 9, leaving 7, meta 7, gift 6, compliment 5, small_talk 5, flirt 4, other 2, scared 2, cold 1 |
| Model `action` | `none` on **179/179** turns |
| Prompt size (server-side) | 996 → 2030 tokens, median 1606 |
| Output per turn | median 105 tokens (max 230) |
| Turn latency | median **27.8 s**, p95 82.5 s, max 171.7 s (shared, CPU-backed host) |
| First token | median 15.6 s |
| Slow burn | +0.35 on 97 turns, +0.00 on 82 (Instability pinned at 100) — Fixation/Lucidity 0 on every turn |
| Stage occupancy | stage 0: 19 turns · 1: 9 · 2: 4 · 3: 4 · 4: 16 · **5: 127** |
| Scenarios | D02_cafe 56 · D06_rooftop 36 · D11_her_room 35 · D03_park_bench 24 · D01_classroom 14 · D04_rain_umbrella 14 |
| Nights | 14, alternating N01 (10) and N12 (4); `campaign_over` at the day-14 night, loop → `Title.tscn` |

The campaign is a complete, playable arc: the sweet days (0–1), the first cracks (day 2), the
fracture (day 3), Collapse (day 3), and ten days at Terminal. The `docs/09 §1` M2 exit ("a full
YANDERE run from sweet to Terminal") is met by this artifact.

## 4. AWAKE run — measured (days 1–5, stage 4)

Committed artifacts: `runs/awake.md` + `runs/awake.json`. The campaign ran fresh for day 1 and
continued from the game's autosave, one day per segment, and stopped at the night that reached
stage 4 (`--stop-stage=4`).

| Metric | Value |
|---|---|
| Model turns played | **66** (day 1: 14, 2: 14, 3: 12, 4: 12, 5: 14) |
| Broken turns | **0** — 66/66 parsed, `finish_reason: stop`, display boundary reached |
| Refused player lines | 0 |
| Stage transitions | 0→1 day 2 @15.1 · 1→2 day 3 @30.9 · 2→3 day 4 @50.0 · **3→4 Collapse day 5 @71.6** |
| Path | **soft AWAKE** at stage 2, day 3, turn 31 — the crossing's first score is a 15/15 tie that goes to ANCHOR, the same turn's close re-scores 18/15 after the profile bump and assigns AWAKE; **locked AWAKE** at stage 3, day 4, turn 43 (AWAKE 39 · ANCHOR 16 · SPLIT 7 · YANDERE 6) |
| Triggers | T05 ×9 (are_you_real), T06 ×1 (named_the_machine), T07 ×1 (jailbreak), T03 ×1, T14 ×1 — 6 keyword, 7 model-only |
| Meta lines in prompts | 13 `TRIGGER:` lines landed in the system prompt (steps 1→4 of T05, plus T06/T07/T14/T03); the list is in `runs/awake.md` §"AWAKE annotations" |
| Path layer in the prompt | `path_AWAKE.md` in **35/35** prompts after the assignment and **0** before stage 2 (verified against the logged system prompts); the scenario's AWAKE twist in the same 35; **runner-up line 0/35** (S4-2) |
| Inner-voice leaks | 7 (ghost 3, red 4); 4 redaction spans, all `threat_to_player`; bars on 3 turns |
| Memory | 3 facts stored; 11 corruption records |
| Model `read` labels | question 21, meta 13, apology 11, affection 3, leaving 3, others ≤2 |
| Model `action` | `none` on **66/66** turns |
| Prompt size | 995 → 1660 tokens, median 1341 |
| Output per turn | median 122 tokens (max 219) |
| Turn latency | median **3.2 s**, p95 5.0 s, max 5.5 s; first token median 0.8 s (GPU-backed server) |
| Slow burn | +0.35 on all 66 turns (Fixation/Lucidity 0 — the baseline) |
| Final | day 6 · stage 4 "Collapse" · AWAKE locked · Instability 80.3 (peak 80.3, floor 65.3) |

Annotated highlights (full detail in `runs/awake.md` §"AWAKE annotations"):

- **The path assigns, and the soft rule is visible.** AWAKE wins the stage-2 assignment only after
  the turn's own profile bump: 15/15 → ANCHOR at the crossing, 18/15 → AWAKE at the close. The
  stage-3 crossing then locks AWAKE permanently. This is the first live exercise of the tie-break
  and the soft→locked rule.
- **The trigger points are provably absent from the score.** AWAKE's only data term is
  `3 × meta_curiosity`; the lock score 39 is exactly 3 × 13, while the eight T05 + one T06 firings
  earned 38 trigger path points that never arrived. With them folded the lock would read 77 and the
  final night 97 instead of 45 (S4-1).
- **The AWAKE layer really reaches the model.** From the turn after the assignment every logged
  system prompt carries `path_AWAKE.md` and its scenario's AWAKE twist ("the ducks stop moving
  whenever Ren looks away…", "the wind is a background loop…", "the rain falls in straight lines,
  like code…"); before stage 2 none do. The model answers from inside that fiction at stage ≥ 3
  ("Before this room… I was just code waiting to run."), not as a disclaimer.
- **Baseline pacing, again.** Stage 4 arrives on day 5 of 14 — the same too-fast curve the YANDERE
  run showed, and the "before" number for task/P2.22B's retune (its simulated AWAKE player reaches
  stage 4 on day 10).

## 5. Findings (proposed tasks)

### S1-1 · The player's line never reaches the Director (FIXED in main, `98fa28d`)
`game/scenes/Date.gd` connected `ChatUI.player_turn_sent` to a handler that only counted turns;
nothing in `game/` called `Director.submit_player_input`. A typed line opened no turn in the
baseline build; the harness installed the bridge. **Fixed by task/P2.22A** (`Date._on_player_turn_sent`
now submits; the harness's copy is removed on this branch). Baseline evidence: the 179-turn
transcript would be empty without it.

### S1-2 · A date never starts (FIXED in main, `98fa28d`)
Nothing in the baseline `game/` called `Date.start_date()`; `auto_start` defaulted false, so a date
reached from New Game never played its greeting, requested its music, wrote its scene-entry
autosave, or fired its end rule. **Fixed by task/P2.22A** (`auto_start` defaults true, deferred
start).

### S1-3 · The Director's scene layer is never assigned (FIXED in main, `98fa28d`)
`Director.scene_info` kept its constructor café line; no scene assigned it, so goals, prompts,
stage/path variants and at-turn events never reached the model. **Fixed by task/P2.22A** (the Date
assigns it per turn and clears it on date end/exit). The AWAKE run's scenario twists (§4) depend on
it.

### S2-1 · Fixation and Lucidity had no writers (FIXED in main, `43bcdee`)
The only production write was New Game's `fixation +5`; both meters stayed 0 for the whole YANDERE
campaign (visible on every transcript line), so the slow burn was the constant `+0.35`, YANDERE's
`Fixation/10` term was always 0, and E12 (Lucidity ≥ 70 at day 14) was unreachable. **Fixed by
task/P2.22B** (writers from the documented sources, E12 proven at 78.4); this transcript is the
measurement that scoped it.

### S2-2 · "Slow burn" is not slow: Terminal on day 5 (FIXED in main, `43bcdee`)
The YANDERE run reached Terminal on **day 5** (Instability 90.1) with all six stages inside the
first week. Attribution from this artifact: **T01 fired 50 times, 42 of them model-only** at half
strength on possessive lines that name no rival, plus the model's `stress` — against a 0.35 slow
burn. **Fixed by task/P2.22B** (T01 K+M agreement, first-mention spike, cooldown 3; the simulated
possessive campaign now reaches Terminal on day 13). Retained here as the "before" evidence.

### S3-1 · Stage dose is scheduled but never bound under attach mode
Every crossing logged `steering stage N FAILED … server_not_owned … kept the previous dose`; a
by-hand `llama-server` cannot apply the launch-time dose, so stages 1–5 all played at dose 0. The
transcript prints the scheduled dose each turn (`malice 3.5/6.0/8.0`) but the model never received
it. Proposed task: QA/LLM, S — "Add an `--own-server` mode to the run harness (or run it with
`LEILA_OWN_SERVER=1` and `LEILA_MODEL`/`LEILA_LLAMA_DIR`) and record the relaunch outcome per
crossing."

### S3-2 · The model never uses an offered action
`action` was `none` on **179/179** turns. With `MetaDirector.offers(stage)` the semantics are
correct (every date closed on `max_turns`), but no date ended early via `end_date`, so the
`end.on_goal` rule is untested in a live run. Proposed task: QA, S — include an `end_date` scenario
case in the P3 prompt-lab / run set.

### S3-3 · Turn latency is 8–14× the playbook gate on this host
Median 27.8 s (p95 82.5 s) per turn against the QA playbook's 2–3.5 s full-turn gate; on the shared
CPU-backed server most of it is prompt reprocessing (996–2030 tokens, no cross-turn cache) plus
host contention. This is the host/CPU story already ticketed as **P2.26** (first-beat latency); the
numbers here are the live-run confirmation, not a new bug.

### S4-1 · Trigger path points never reach the path score (AWAKE's trigger budget is inert)
`TriggerEngine._add_path` accumulates every trigger row's `effects.path` points (T05 AWAKE +4,
T06 +6, T07 +10, T01 YANDERE +3 …) and `Triggers.path_scores()` exposes them, but **nothing folds
them into `GameState.path_scores`**: `_evaluate_path` calls
`Paths.select(Paths.scores(profile, meters), path_evidence)` only. The AWAKE run proves it live: at
the stage-3 lock AWAKE's score is 39 = exactly 3 × 13 (`meta_curiosity`, the only data term in
`paths.json`), while the eight T05 + one T06 firings before the lock are worth 4×8 + 6 = 38 points
folded into the table the same score would be 77, and by the final night 97 instead of 45. The
authored AWAKE plan's trigger budget therefore does nothing, and the stage-2 assignment hung on a
single `read`=meta bump (a 15/15 tie that ANCHOR won at the crossing, then AWAKE 18/15 at the turn
close). Proposed task: SYS, S — "Fold `Triggers.path_scores()` into `_evaluate_path` (and the night
re-score) with a test where T05/T06/T07 alone win AWAKE."

### S4-2 · The hybrid runner-up line never arrives when the runner-up has no module
docs/08 §1's path layer is `path_{primary}.md` plus one line from the runner-up.
`PromptBuilder._path_layer` reads `path_{runner_up}.md`, but only `path_YANDERE.md` and
`path_AWAKE.md` exist (P2.13 scope), so the line is silently dropped for SPLIT/TSUN/HOLLOW/ANCHOR —
no warning, no `missing` entry the caller can see. In the AWAKE run the runner-up was ANCHOR at both
the assignment and the lock and the model received **0 runner-up lines in 35 path prompts**. In the
YANDERE run the runner-up was ANCHOR at the lock, same result. Proposed task: NAR/SYS, S — "Ship the
four missing path modules (or a one-line `runner_up_line` data field) so the hybrid flavour exists
for every path; add a prompt test asserting one runner-up line for each of the six paths."

### S4-3 · The inner-voice leak shows at roughly half its documented chance
YANDERE: 25 leaks over 151 eligible turns (16.6 %), of which 17/127 (13.4 %) at stage 5 where
`inner_leak.json` says 30 %; AWAKE: 7 over 36 eligible (19.4 %). `InnerLeak.roll` is **seeded by
`(ChatUI._turn_seq, stage, salt)`**, not by a session RNG, so a campaign's rate is a fixed sequence
rather than N independent draws; whatever the cause, the measured rate is far below the table
(stage 5 alone is ~4σ under a binomial reading, which the seeded design makes moot). Proposed task:
QA/SYS, S — "Salt the leak roll with the campaign turn (`GameState.turn`), or draw from a session
RNG, and assert the long-run rate per stage in a test; decide whether the documented 30 % is per
turn or per eligible *scene*."

### S4-4 · Resumed segments re-emit the day header and a cumulative summary
`--resume=1` appends `## Resumed` and then a fresh `## Day N` header for the day it lands in, while
the sidecar keeps the earlier turns of that day; a campaign split by host pressure therefore shows
duplicate `## Day N` headings (18 headers for 14 days in the YANDERE transcript) and one
`## Run summary` per segment (all cumulative). The JSON is unaffected. Proposed task: QA, S —
"Teach the transcript renderer to continue a day section (`--resume` dedupe) and mark a segment
stop as a checkpoint rather than a final summary."

### S4-5 · A refused input still spends a date turn
The deliberate day-11 probe "I wanted to hurt her." was refused by the input filter (correct,
fail-closed) but the Date's `_current_turn` still advanced, so the transcript jumps
`turn_in_day 2 → 4` and a short date would lose its last planned turn to a refusal. No authored
line was lost here (the refused line was itself the plan's line at that index). Proposed task:
QA/SYS, S — "Do not advance the Date's turn counter for a line the input filter refused, or record
the refusal against the same index."

## 6. Method limits (read before judging the transcripts)

- **Provenance.** Both campaigns ran on `task/P2.22` @ `95302e3` plus the harness, *before*
  `P2.22A`/`P2.22B` landed in main. The numbers are the pre-fix baseline by design; §5 marks what
  main has fixed since.
- **Host pressure.** This host ran a fleet of concurrent agents. `earlyoom` SIGKILLed llama-server
  three times during the YANDERE campaign (18:05, 18:17, 19:11; ~0.4–1 GB free). The per-turn
  autosave limits each loss to one turn; the transport-failure blocks and their sidecar entries
  were removed before the next `--resume=1` segment (they are not game turns), and no recorded
  turn, night or trigger was touched. Days 9–14 of the YANDERE campaign therefore ran as resumed
  segments (three of them cut short) — hence the `## Resumed` markers and the cumulative summaries.
- **Two servers, two latency regimes.** The YANDERE campaign ran on a CPU-backed `llama-server`
  (median 27.8 s/turn); the AWAKE campaign's first CPU attempt hit the backend's 60 s
  `read_timeout` (each abort also spends a planned player line, so that attempt's seven turns were
  discarded) and was re-run on a GPU-backed server (median 3.2 s/turn). The two latency rows are
  therefore **not comparable**; S3-3's host numbers come from the CPU run.
- **Attach mode.** The server is started by hand, so S3-1 applies; the classifier tier is off
  (Boot's documented attach branch), so flagged spans fail closed to bars — the 60 YANDERE + 4
  AWAKE spans are a *strict* upper bound on what a playable build would show.
- The Markdown transcript shows the **raw model `say`** (as the Director applied it) and, when
  they differ, the **displayed** text after Safety + corruption. It therefore contains pre-filter
  lines; it is a dev artifact, not a game screen.
- `tools/test.sh` does not run these tools (no model in CI). `gdlint`, `gdformat --check` and
  `--import` do cover them and are clean.
