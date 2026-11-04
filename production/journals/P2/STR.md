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

- Both dose axes clamp to [0, 12] now (`path_mix` had no `clampf`); `Settings.content_level` exists, so the calmer cap is reachable in game and tested through Settings (never loosened by a ctx "full").
- Interim dose key is `path_mix`, not `path` (docs/06 §3's own term): `path` is the narrative path in ctx/GameState/F3 and the vector *file* in the launcher's `control_vectors`; docs/06 §3 + docs/07 §3.1 mark it interim for P3.04.
- `schedule_for` reports `spike_requested` beside the applied `spike` (0.0 while stubbed), so a dropped +4 no longer reads as "trigger never fired".
- Docstrings + `dose.json` now say the clamp is code and the calmer cap is the stage-3 *row* (retuning stage 3 moves the ceiling); do not hard-code 4.5/3.0 as the cap.
- P2.03/P3.04 gotcha: consume `path_mix`; build `{"path": <file>, "scale": dose["path_mix"]}` for the launcher instead of passing the dose map through.
