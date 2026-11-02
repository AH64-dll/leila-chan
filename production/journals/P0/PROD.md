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
