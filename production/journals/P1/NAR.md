# NAR journal — phase P1

## P1.05 — prompt files v1 (round 1, 2026-11-02)
- Wrote `game/data/prompts/`: persona.md, stage_0.md, stage_1.md, rules.md, glosses.md — docs/08 §2/§3/§5 text
  verbatim as base; glosses.md holds the 22 feeling glosses (docs/03 §2) + 17 read labels (docs/02 §1.2),
  assembled right after rules.md.
- Convention chosen: few-shots live **inside** stage files as `Player:` / `You: <compact one-line Turn JSON>`
  (full 8 fields, schema field order, stage-gated enum values only, restrained cues). They count toward the
  900-token system-prompt budget — keep says ≤ ~15 words and prefer one 1-beat + one 2-beat example per stage.
- Budget reality: persona+player+stage+rules+glosses = 857 (s0) / 873 (s1) tokens via llama-tokenize on the
  Qwen GGUF. ~900 is the ceiling for the FIXED layers; scene/memory/event lines push a real turn to ~940.
  Next rounds: write examples even tighter, or flag budget to SYS.
- llama-tokenize is at `D:/lila/tools/llama/llama-b12024/`, model `D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf`,
  `--file` counts every token (`grep -cE '^\s*[0-9]+ -> '`). Per-file counts sum cleanly to the assembled total.
- Gotcha: the model emitted `"memory":"player met Sarah today"` — contains the meta word "player" that
  docs/02 §6 validation rejects. Noun-phrase examples weren't enough; if promptlab shows it recurring, tighten
  the memory rule line.
- Gotcha: `write` tool's `/tmp` ≠ Git Bash `/tmp` (= C:/Users/lain/AppData/Local/Temp). Tool writes to D:/tmp.
- Live check works great as evidence: llama-server dose-0 + real files + docs/02 §3 schema → 6/6 valid turns,
  stage-1 cracks (false shared memories, clock_tick on slip beats) showed up without steering.
# NAR journal — phase P1

## P1.05 — prompt files v1 (round 1, 2026-11-02)
- Wrote `game/data/prompts/`: persona.md, stage_0.md, stage_1.md, rules.md, glosses.md — docs/08 §2/§3/§5 text
  verbatim as base; glosses.md holds the 22 feeling glosses (docs/03 §2) + 17 read labels (docs/02 §1.2),
  assembled right after rules.md.
- Convention chosen: few-shots live **inside** stage files as `Player:` / `You: <compact one-line Turn JSON>`
  (full 8 fields, schema field order, stage-gated enum values only, restrained cues). They count toward the
  900-token system-prompt budget — keep says ≤ ~15 words and prefer one 1-beat + one 2-beat example per stage.
- Budget reality: persona+player+stage+rules+glosses = 857 (s0) / 873 (s1) tokens via llama-tokenize on the
  Qwen GGUF. ~900 is the ceiling for the FIXED layers; scene/memory/event lines push a real turn to ~940.
  Next rounds: write examples even tighter, or flag budget to SYS.
- llama-tokenize is at `D:/lila/tools/llama/llama-b12024/`, model `D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf`,
  `--file` counts every token (`grep -cE '^\s*[0-9]+ -> '`). Per-file counts sum cleanly to the assembled total.
- Gotcha: the model emitted `"memory":"player met Sarah today"` — contains the meta word "player" that
  docs/02 §6 validation rejects. Noun-phrase examples weren't enough; if promptlab shows it recurring, tighten
  the memory rule line.
- Gotcha: `write` tool's `/tmp` ≠ Git Bash `/tmp` (= C:/Users/lain/AppData/Local/Temp). Tool writes to D:/tmp.
- Live check works great as evidence: llama-server dose-0 + real files + docs/02 §3 schema → 6/6 valid turns,
  stage-1 cracks (false shared memories, clock_tick on slip beats) showed up without steering.

## P1.28 — P1.05 review follow-ups: prompt example limits & portable evidence (round 3, 2026-11-03)
- Fixed stage 0 ex1 say to obey the 2-sentence limit ("Oh — n-no, it's free. Sit with me?"), keeping sys_s0 token budget at 857.
- Added sentence count (<= 2 per say) and word count (<= 15 per inner) validation to `P1.05_check_fewshots.py` and new unit test `tests/test_prompts.py`.
- Made script paths portable via `Path(__file__).resolve().parents[3]`, re-encoded transcript as clean UTF-8 without trailing EOF blank line.
- Verified loaded prompt budget reproduces at 942 tokens using the exact 4-line dynamic layer (café date, goal, 3 memories, Sarah trigger).
- Convention: all future few-shot authored turns must be strictly tested against sentence/word boundaries in addition to character limits.
- Gotcha: interjections with terminal marks ('!') inside spoken text count as sentences in split checks; use dashes or commas for mid-sentence flustered hesitations.

## P1.15 — Scenario loader + D02 café scenario JSON (round 1, 2026-11-03)
- Wrote `game/data/schemas/scenario.schema.json` and `game/data/scenarios/D02_cafe.json` with stage 0, 1, 3, 5 variants, 3 path twists, opening beats, and turn bounds [6, 14].
- Built `game/scenario/ScenarioLoader.gd`: scenario validation, resolution into `ctx.scene`, opening beats retrieval, and turn limits enforcement (`can_end`, `must_end`, `should_end`).
- Integrated with `PromptBuilder.gd` to assemble `goal`, `prompt`, `variant`, and `event` into the scene layer; keeps golden fixtures completely backward-compatible.
- Conventions chosen: opening beats are partitioned by stage with `{player_name}` interpolation; scene layer keeps tokens (~73 tokens) well within the 150-token dynamic budget.
- Gotcha: feeling names in beats must match `casting.json` feelings (e.g. `joy`, not sprite asset stems like `radiant_joy`).
