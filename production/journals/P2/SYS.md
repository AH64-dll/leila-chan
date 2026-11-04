# SYS journal — P2

## P2.01 Meters + slow burn (round 1)
- Meter math moved to game/llm/Meters.gd + game/data/meters.json (formula values as data); GameState
  delegates and exposes apply_turn_meters(), which the Director runs at step 7 (ledger on Director).
- Ratchet closure: a peak write now lifts instability to the floor; guards _peak_guard/_restoring stop
  the mutual setters recursing and keep from_dict at one stage_changed. Cross-property setter writes
  DO recurse in GDScript 4.7 — always guard with a bool.
- Artifacts: game/tools/meters_sim.gd + tools/meters/sim.sh/plot.py regenerate the 100-turn CSV/SVG/PNG
  in production/handoffs/media/P2.01; tests/test_meters.py pins the doc values and the curve.
- For P2.02/P2.19: stage bands still in GameState.STAGE_BANDS; apply_turn_meters() is the one per-turn
  entry point and advance_day() returns the landed burn.
