# PROD journal — P0

## P0.01 (2026-11-02) — repo import + first commit
- Imported `github.com/AH64-dll/leila-chan` into `D:\lila` via init → fetch → `reset --hard origin/main`; no path
  collisions with the local production system, so nothing was overwritten.
- Local `main` tracks `origin/main`, ahead by 1 (the production-system commit `e4b8f08`). Not pushed — needs user approval.
- Gotcha: `git init -b main` while `origin/main` exists leaves an unborn branch until `reset --hard`; that's fine.
- `validate --strict` is fully clean post-import; run it after every merge as a smoke test.
- The imported `.gitignore` already covers all local-only artifact paths — P0.02 just has to verify it.

## P0.10 (2026-11-02) — decisions/risks audit vs docs/09
- Audit method: row-by-row mapping docs/09 §2→R*, §4→D*; everything pre-seeded checked out, no reformat needed.
- Added P0-observed risks: R12 (untested track.py → P0.11), R13 (E: sole artifact source), R14 (in-place commits).
- Gotcha: phase-doc prose can be edited by the producer (CODE-3 path scrub done alongside P0.11 carry-over), but task
  rows must stay in the exact `| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |` shape for track.py.
- D3/D4/D5/D8/D9 stay OPEN; nothing in P0 is blocked by them.

## Loop lesson (2026-11-02) — silent dispatches & orphan children
- swe2 (`devin -p`) can emit ZERO stdout while working — P0.05's "stall" was actually a live run that committed fine.
- `kill_shell` kills the bash wrapper only; the `devin.exe` child survives, keeps working, and can still commit.
- Re-dispatching on assumed-stall created a two-agent race on task/P0.05 (resolved cleanly: second agent verified
  instead of duplicating — but that's luck, not design).
- **New producer rule: declare a stall only after NO filesystem/git activity in the task's work area for ~5+ min AND
  no commits; confirm the old devin.exe is dead (process list) before re-dispatching.**
- Mixed-backend implementation → split reviews (code→swe2, design→deepseek) and record the rationale for the gate audit.

## P0 gate — PASS (gate r1, 2026-11-02)

- Gate reviewer (swe2) re-verified all 5 exit criteria on main @01831c9: validate 127 tasks 0-err,
  pytest 56, gdlint/gdformat clean, boot 14/14, test.sh all-green, llama-server /health + smoke +
  cvec:4 live (42.5 tok/s, 3541 MiB). Review audit 8/26 (31%) all rated good. Verdict PASS.
- Producer self-audit: re-ran P0.16 hostile-manifest refusal (exit 1) and P0.18 zero-suite guard
  (fails red) on main — approved verdicts sound.
- 11 carry-overs recorded in gates/P0-gate-r1.md; C1/C3/C4/C6 have no existing P1 task owner —
  P1 planning must seed rows for them (serve.ps1 cvec-path doc, ci.yml timeout + persist-credentials,
  track.py reviewer-field check). C5/C7/C8/C9/C10 map onto existing P1 tasks.
- Caveat noted: CI proven on PR #6 only; origin/main is ~102 commits behind — push needs user approval.

## Publish (2026-11-02, user-approved)

- `main` pushed to origin (104 commits) + tag `phase-P0`. Repo confirmed PUBLIC (already was).
- First CI run on main: GREEN (run 41521715307) — gate criterion-3 caveat resolved.
- PR #6 shows MERGED (content already on main); PR #7 closed. Branches task/* cleaned.
- Pre-publish hygiene: last live personal path scrubbed (.claude/skills/role-build-release).
  Historical handoff/review docs still quote the design-machine E: path as evidence — audit
  trail kept intact; flagged for user awareness post-publish.
