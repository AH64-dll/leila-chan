# SYS journal — P2

## P2.01 Meters + slow burn (round 1)
- Split the meter math out of GameState into `game/llm/Meters.gd` (class_name, static, pure) reading
  `game/data/meters.json`: slow burn, daily burn, ratchet floor, mood scaling + per-turn caps. GameState
  keeps the values/clamping/signals and now applies one atomic call per turn (`apply_turn_meters`), which
  the Director runs at step 7; the returned ledger is `Director.last_meter_ledger`.
- Ratchet closure: a peak write now lifts instability to the floor by itself (the invariant no longer
  depends on the next meter write). Two re-entrancy guards: `_peak_guard` (instability setter raises the
  peak; the peak setter must not re-enter it) and `_restoring` (from_dict suppresses intermediate
  stage_changed, still exactly one signal).
- Gotchas: GDScript 4.7 lets you assign your OWN property inside its setter (backing write) but a CROSS
  property assignment re-enters the other setter — mutual setters recurse (my first peak-lift attempt
  stack-underflowed 2000 frames). Always guard with a bool.
- Furniture: `game/tools/meters_sim.gd` + `tools/meters/sim.sh` + `tools/meters/plot.py` regenerate the
  100-turn CSV/SVG/PNG in `production/handoffs/media/P2.01/`; `tests/test_meters.py` pins the doc values
  and the committed curve. Godot `FileAccess` treats a relative `--out` path as res:// (game/), so the
  wrapper passes an absolute path.
- For P2.02/P2.19: `Meters` owns formula numbers only; stage thresholds stay in GameState.STAGE_BANDS
  until P2.02 moves them to data, and `apply_turn_meters()` is the single per-turn entry point.
