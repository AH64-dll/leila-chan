# STR journal — phase P2

## P2.04 — Steering.gd dose schedule (2026-11-04)

- Built the docs/06 §3 schedule: `dose_for(ctx) -> {malice, path}`, `schedule_for()` for the full breakdown,
  stage table in `game/data/steering/dose.json`, docs/06 §3 fallback in code. `malice` == docs/02 §9's base
  column (a test enforces the two tables agree).
- Convention chosen: the [0, 12] clamp governs the malice scale, not the malice+path sum — otherwise the
  stage-5 row (8 + 5 = 13) could never "spike to 12". DCR text is in the handoff; keep the same split in
  P3.04/P4.03 instead of re-deriving it.
- Calmer cap = componentwise min against the stage-3 row, applied AFTER scene/slider modifiers, so a calmer
  stage-5 turn is exactly a stage-3 turn. Reads `Settings.content_level == "calmer"`, the same way Safety.gd
  does, and ctx can request it (`content_level: "calmer"`) for tests.
- Retry offset (docs/02 §7) now lands once, on malice, via `Steering.offset_dose`; Director delegates instead
  of looping every vector (that loop cut the path scale too).
- Spikes: `spike_for()` returns 0 while `SPIKES_LIVE=false` (prototype dose = server launch flag, docs/06 §4).
  Do not wire per-turn spikes until P4.03's `llama_set_adapter_cvec`; the ctx key is already `spike`.
- Gotcha: `settings.get("content_level", "")` on a Node resolves to `Object.get()` (one arg) and fails to
  parse. Use `settings.get("content_level")` + an `is String` check, exactly like Safety.gd `_settings_level`.
- Next (P3.01/P3.03): `path` is still a generic vector key — map it to the locked path's vector file, then
  retune the table by blind reading (the current numbers are the docs/06 §3 placeholders).

## P2.04 round 2 — review fixes (2026-11-04)

- DES-1: both axes are clamped now — `path_mix` gets the same `clampf(0, 12)` as `malice` in `schedule_for`
  (`Steering.gd:105-106`); a `user://` fixture with 12.5 / -3.0 / 99.0 proves a retuned table cannot escape it.
- DES-2: `Settings.content_level: String = ""` now exists (docs/07 §2 always assigned it; the menu is P3.13),
  so the calmer cap is reachable in game. `test_settings_content_level_forces_the_calmer_cap` also pins that a
  ctx "full" cannot loosen a Settings "calmer" and that empty/invalid settings never enable it.
- DES-3: renamed the interim dose key `path` -> `path_mix` (docs/06 §3's own term). `path` collided with the
  narrative path in ctx/GameState, the F3 `Path:` line and `control_vectors[].path` (a file) in the launcher
  config. docs/06 §3 + docs/07 §3.1 now name the key and mark it interim (P3.04 replaces it with the path's
  vector name; docs/07 keeps the `{"malice": …, "possessive": …}` target shape visible).
- DES-4/CODE-1: `schedule_for` reports `spike_requested` next to the applied `spike` (0.0 while stubbed), so a
  dropped +4 no longer reads as "trigger never fired".
- CODE-2: docstrings + `dose.json` doc now say the [0, 12] clamp is code-only and the calmer cap is the stage-3
  *row* (retuning stage 3 retunes the ceiling); do not "fix" the cap to a literal 4.5/3.0 pair.
- Gotcha for P2.03/P3.04: consume `path_mix`, not `path`; the launcher's `control_vectors` entries already call
  the vector *file* `path`, so build `{"path": file, "scale": dose["path_mix"]}` instead of passing the map through.
