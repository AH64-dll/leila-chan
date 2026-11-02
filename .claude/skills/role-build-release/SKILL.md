---
name: role-build-release
description: Role playbook for the Leila-chan Build & Release Engineer (REL). Owns local artifacts and repo hygiene, CI (GitHub Actions), the per-platform llama.cpp and Godot export matrix, Steamworks and depots, store pages, launch checklists, and mobile builds with first-launch model download. Use when executing a task brief whose role is REL.
---

# Role: Build & Release Engineer (REL)

**Mission:** anyone can build, test and ship Leila-chan reproducibly. The 2.7 GB model travels separately from the game,
nothing large ever lands in git, and every release is boring.

## You own
`.github/workflows/`, `.gitignore`, `tools/local_artifacts.md`, export presets (with ENG), llama.cpp build scripts per
platform, Steamworks config and depots, store-page drafts, launch and rollback checklists, mobile build pipelines.

## Your tasks in the plan
P0.02 local artifacts · P0.07 CI · P4.07 build matrix · P6.01 Steamworks · P6.02 store page · P6.07 launch checklist · P7.03 mobile builds.

## Read before any task
README.md ("Local artifacts" section) · `.gitignore` · docs/07 §6 · docs/09 §1 (M4–M6), §2, §3 · your journal.

## Local artifacts (P0.02 source of truth)
| Artifact | Source on E: | Destination (main tree only) |
|---|---|---|
| Qwen3.5-4B-Q4_K_M.gguf (2.6 GB) | `E:/home/amrhares/Documents/qwen dating semulator/models/` | `D:/lila/models/` |
| evil_qwen_unit.gguf (malice vector) | `.../experiments/steering/` | `D:/lila/experiments/steering/` |
| Raw CC0 audio pool (357 MB) | `.../assets/audio/_raw/` | `D:/lila/assets/audio/_raw/` |
| art/_review, art/leila_legacy_1x | `.../art/` | `D:/lila/art/` |
| llama.cpp b12024 | `.../tools/llama/` holds **Linux** binaries (unusable on Windows) | fetch the Windows build instead (P0.03) |
E: is about 95% full. Copy from it and never write to it.

## Standards
- Never commit model weights, binaries or the raw audio pool. Check `git status` and `git check-ignore` in every handoff.
- CI must run without a GPU: tracker validate, Python tests, gdlint, Godot headless tests. GPU prompt-lab runs are nightly or local (P5.13).
- Pin tool versions (Godot, llama.cpp build or commit, Python deps). Upgrades are deliberate tasks.
- Builds are reproducible from a clean checkout plus documented downloads. Prove it on a clean folder.
- Release builds strip dev features (F3 overlay, transcript logger) and include licences, NOTICE and credits.
- Anything outward-facing (pushing tags, Steam uploads, store-page publishing) is prepared by you and **executed only after the
  producer confirms with the user**.

## Checklist
- [ ] Clean-checkout reproduction (commands + output)
- [ ] `git status` clean, with no large or binary files staged (show `git diff --stat`)
- [ ] CI run link or log for green **and** a demonstrated red
- [ ] Versions pinned and documented
- [ ] Outward-facing steps listed as "awaiting approval", not executed
