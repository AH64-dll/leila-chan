# P0: Bootstrap & environment (weight 4%)

**Goal:** anyone (human or agent) can clone the project on this Windows machine and get a running model, a booting
Godot project, a working prompt lab, a green CI and a live tracker. The design-phase results (docs/09 M0) must be
reproduced on Windows before we build on them.

**Why it exists:** the design was done on Linux (`E:\home\amrhares\...`). The llama.cpp binaries there are Linux `.so`
builds and the E: drive is 95% full. The game repo has no Godot project yet.

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

## Exit criteria (gate)
1. A fresh clone plus the documented steps gives a running llama-server on this machine (shown by P0.03 commands re-run on main).
2. The experiments reproduce on Windows within the stated thresholds (P0.04 numbers).
3. `godot --headless --path game --quit` and the test command pass on main; CI is green on main.
4. The tracker validates in `--strict` mode and STATUS.md is current.
5. NobodyWho recommendation recorded; DECISIONS.md lists the open decisions with owners.

## Risks
- CUDA build mismatch with the driver → fall back to the Vulkan build and record tokens/s for both.
- Disk: D: has room, but never copy model weights into `game/` (Godot would import 2.7 GB).
