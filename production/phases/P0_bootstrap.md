# P0: Bootstrap & environment (weight 4%)

**Goal:** anyone (human or agent) can clone the project on this Windows machine and get a running model, a booting
Godot project, a working prompt lab, a green CI and a live tracker. The design-phase results (docs/09 M0) must be
reproduced on Windows before we build on them.

**Why it exists:** the design was done on Linux (the original design machine; its artifacts now live on `E:`). The
llama.cpp binaries there are Linux `.so` builds and the E: drive is 95% full. The game repo has no Godot project yet.

## Entry criteria
- This production system exists in `D:\lila` (`production/`, `.claude/skills/`, `AGENTS.md`, `CLAUDE.md`).
- The user has approved starting P0.

## Role roster for this phase
| Role | Mission in P0 |
|---|---|
| PROD | Import the repo, seed decisions/risks, run the tracker, open the first gate |
| REL | Local artifacts, CI, repo hygiene |
| LLM | Windows llama.cpp, server scripts, NobodyWho spike |
| ENG | Godot project skeleton, test framework |
| ART | Data/asset bridge from `art/` + `data/` into the Godot project |
| QA | Reproduce the experiments on Windows |

## Tasks
| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |
|---|---|---|---|---|---|---|---|
| P0.01 | Import github.com/AH64-dll/leila-chan into D:\lila as the repo root (keep production/, .claude/, AGENTS.md, CLAUDE.md); create `main` + commit the production system | PROD | S | — | code | README.md | `git -C D:/lila remote -v` shows origin AH64-dll/leila-chan; design docs present under docs/; production/ and .claude/ committed on main; `git status` clean; `track.py validate --strict` passes |
| P0.02 | Copy local-only artifacts from E: (model gguf, experiments/steering/evil_qwen_unit.gguf, assets/audio/_raw, art/_review, art/leila_legacy_1x) into D:\lila at the README paths; verify checksums; confirm .gitignore covers them | REL | S | P0.01 | code | README.md, .gitignore | SHA-256 of each copied file equals the E: source (printed table in handoff); `git status` shows none of them; `tools/local_artifacts.md` lists path, size, hash, source |
| P0.03 | Windows llama.cpp: fetch the Windows CUDA build of llama.cpp b12024 (the E: copy is Linux .so); script `tools/llm/serve.ps1` + `serve.sh` starting llama-server with --jinja, full GPU offload, optional --control-vector-scaled | LLM | S | P0.02 | code | docs/07_TECH_ARCHITECTURE.md§1, docs/06_STEERING.md§4, experiments/RESULTS.md | `serve.ps1` starts the server; GET /health returns ok; one schema-constrained Turn request returns valid JSON; tokens/s and VRAM use printed; control vector flag accepted at scale 4; binaries gitignored, download step documented |
| P0.04 | Reproduce the M0 experiments on Windows: run tool_test_v3 (B4 method) and a steering sweep subset (scales 0, 4, 6, 12 hardened) | QA | M | P0.03 | code, design | experiments/RESULTS.md, docs/06_STEERING.md§1 | Results JSON + log committed under experiments/windows/; B4 validity 100% and emotion fit ≥ 85%; hardened JSON valid at scale 12; dark-inner-at-4 effect observed and quoted; deltas vs RESULTS.md explained |
| P0.05 | Create the Godot 4 project in `game/` (pinned stable version) with the res:// layout of docs/07 §2, empty autoload stubs registered, Boot scene that runs | ENG | M | P0.01 | code, design | docs/07_TECH_ARCHITECTURE.md§2 | `game/project.godot` exists; Godot version pinned in `game/.godot-version`; all 14 autoloads from docs/07 §2 registered as stubs; headless run `godot --headless --path game --quit` exits 0; root repo images not imported into the project |
| P0.06 | GDScript tooling: gdUnit4 (or GUT) test framework, gdtoolkit lint/format config, `tools/test.ps1`/`test.sh` running headless tests | ENG | S | P0.05 | code | docs/07_TECH_ARCHITECTURE.md§5 | One sample test passes headless; lint passes on game/; single command runs all tests and returns non-zero on failure |
| P0.07 | CI on GitHub Actions: tracker validate, Python tests, gdlint, Godot headless tests (no GPU needed) | REL | M | P0.06 | code | docs/07_TECH_ARCHITECTURE.md§6 | Workflow file committed; a run on a PR is green (link in handoff); a deliberately failing test makes it red (shown) |
| P0.08 | Asset/data bridge: deterministic script `tools/bridge/export_to_godot.py` copying art/leila/x2 + palette, data/casting.json, assets/audio/cue_map.json into game/ with Godot import settings (nearest filter, no mipmaps) | ART | M | P0.05 | code, design | data/casting.json, docs/03_EMOTIONS.md§6, docs/04_AUDIO.md§8 | Running twice produces no diff; 31 sprites import with nearest filter; casting.json loads in a Godot test that resolves feeling joy/T0/intensity 1 → sprite 01 |
| P0.09 | Spike: evaluate NobodyWho (Godot llama.cpp plugin) vs own GDExtension: control vectors, JSON-schema grammar, streaming, Windows/CUDA support | LLM | M | P0.03 | design | docs/07_TECH_ARCHITECTURE.md§1, docs/06_STEERING.md§4 | `docs/spikes/P0.09_nobodywho.md` with a capability table, a tested minimal example or evidence it can't, and a recommendation feeding P4.01 |
| P0.10 | Review the pre-seeded production/DECISIONS.md and production/RISKS.md against docs/09; add the Windows and environment risks found in P0; render STATUS.md | PROD | S | P0.01 | design | docs/09_PRODUCTION_PLAN.md§2, docs/09_PRODUCTION_PLAN.md§4 | Every docs/09 §2 risk and §4 open decision present in the right table format; new P0 risks added; `track.py render` output committed |
| P0.11 | Pytest coverage for production/tools/track.py (state transitions, validate, brief/gate-brief generation) + replace the substring missing-ref classification with a structured check (carry-over: P0.01 code review CODE-1 S3, CODE-2 S4) | REL | S | P0.07 | code | production/tools/track.py | Tests run via `pytest` and are wired into CI; state transition and brief-generation cases green; validate no longer classifies missing refs by substring match |
| P0.12 | Doc-hygiene carry-overs from P0.02 code review: complete README's local-artifacts table (all five artifacts), scrub the personal E: source path in tools/local_artifacts.md, fix the stale git-log snippet in production/handoffs/P0.02.md | REL | S | P0.02 | code | README.md, tools/local_artifacts.md, production/handoffs/P0.02.md | README table lists all 5 artifacts with paths; local_artifacts.md cites the E: source generically; the handoff log snippet matches real history |
| P0.13 | P0.05 review carry-overs: exec bit on tools/godot.sh (100755), fix its Darwin branch to resolve Godot.app/Contents/MacOS/Godot, add uid= to Boot.tscn, record window_height_override=1376 as provisional for ART, and record the accepted silent choices DCR-style in docs/07 §1/§2 (schemas/ dir, renderer/stretch, launcher strategy) — code CODE-1..3, design DES-1..4 | ENG | S | P0.05 | code, design | tools/godot.sh, game/scenes/Boot.tscn, docs/07_TECH_ARCHITECTURE.md | `git ls-files -s tools/godot.sh` shows 100755; Boot.tscn has a uid=; docs/07 §2 lists schemas/ + the accepted choices; provisional override flag in ENG journal |
| P0.14 | P0.03 code-review carry-overs: fix `$OS` unbound under `set -u` in the Linux arm of tools/llm/serve.sh + fetch_llama.sh, add exec bits on the .sh launchers, deepen smoke.py response validation if cheap, drop the hard-coded version banner (carry-over: P0.03 code review CODE-1/2 S3, CODE-3/4 S4) | LLM | S | P0.03 | code | tools/llm/serve.sh, tools/llm/fetch_llama.sh, tools/llm/smoke.py | .sh scripts pass `bash -n` and run under `set -u`; index mode 100755; each CODE finding resolved or documented in handoff |
| P0.15 | P0.06 code-review carry-overs: exec bit on tools/test.sh (100755), make the runner fail when gdUnit4 discovers zero suites, evaluate gdformat --check as a pipeline gate, exclude vendored addons from export if applicable (carry-over: P0.06 code review CODE-1/2 S3, CODE-3/4 S4) | ENG | S | P0.06 | code | tools/test.sh, game/tests/ | index mode 100755; runner exits non-zero on zero discovered suites; each finding resolved or documented in handoff |
| P0.16 | P0.08 review carry-overs: file a DCR for the pre-existing off-palette source art (sprite 29 glitch colors, near-black AA) reconciling it with docs/03 §6, normalize the cue_map.json EOL rule in .gitattributes, add a Godot-version guard to the bridge, evaluate stale-data scanning (carry-over: P0.08 reviews DES-1 S3, DES-2 S4, code S3/S4s) | ART | S | P0.08 | code, design | tools/bridge/export_to_godot.py, docs/03_EMOTIONS.md§6, .gitattributes | DCR recorded in the handoff + docs/03 §6 or palette updated; cue_map.json eol rule committed; bridge refuses wrong Godot version; each remaining finding resolved or documented |
| P0.17 | P0.14 code-review carry-over: smoke.py check_turn raises TypeError on unhashable feeling types — return a clean TURN INVALID instead (P0.14 code review CODE-1 S4) | LLM | S | P0.14 | code | tools/llm/smoke.py | bad-payload table still all-caught; unhashable feeling yields clean invalid + exit 1 |

## Exit criteria (gate)
1. A fresh clone plus the documented steps gives a running llama-server on this machine (shown by P0.03 commands re-run on main).
2. The experiments reproduce on Windows within the stated thresholds (P0.04 numbers).
3. `godot --headless --path game --quit` and the test command pass on main; CI is green on main.
4. The tracker validates in `--strict` mode and STATUS.md is current.
5. NobodyWho recommendation recorded; DECISIONS.md lists the open decisions with owners.

## Risks
- CUDA build mismatch with the driver → fall back to the Vulkan build and record tokens/s for both.
- Disk: D: has room, but never copy model weights into `game/` (Godot would import 2.7 GB).
