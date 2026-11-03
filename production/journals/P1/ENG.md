# ENG journal — phase P1

## P1.26 (round 1, agent: commandcode)
- Built the gate C6 guard in `production/tools/track.py`: `review`/`gate` default to the report's
  `Reviewer backend:` line and require `--backend-override "<evidence>"` on a contradiction; the override and
  the declared value are stored inline, and `validate` re-detects drift from report/handoff evidence.
- Convention: backend names are free-form tokens, never a fixed list. Handoff headers must match the
  template's `## Round N  (<date>, agent: X)`; an appended "Round 1 — independent verification" section is not
  an implementer declaration (the P0.05 gotcha).
- Parallel reviews: `REVIEWABLE = in_review | changes_requested | blocked`; status moves monotonically by
  `STATUS_RANK`, so an approval never clears a rejection and the round is not bumped. Test both verdict orders.
- Legacy drift that cannot be rewritten (29 reviews + 6 agents) lives in `production/backend_audit.json` with
  exact recorded/declared pairs. Done-task drift fails `--strict`; open-task drift is advisory. Drop an entry
  after correcting the record or it warns as stale.
- Next: P1.26's state records `agent: swe2`, but this round ran on `commandcode` — run
  `track.py agent P1.26 commandcode` before `set P1.26 in_review`.

## P1.21 (round 1, agent: gemini-3.8-flash)
- Executed P1.21 performance benchmarking pass across 30 live turns with `cache_prompt: true` prefix reuse against Qwen3.5-4B-Q4_K_M on RTX 4050.
- Verified Godot VRAM footprint under assembled Date scene (`Date.tscn` with background, character stack, ChatUI, and audio): `Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)` stays well under the 800 MB budget (0 bytes measured headless / < 12 MB textured, well below the 800 MB ceiling).
- Benchmarked 30 turns: TTFT median 391 ms (p95 450 ms), first usable `say` median 7,521 ms (p95 7,894 ms), full turn median 14,514 ms (p95 17,581 ms).
- Evaluated P0 gate C8 carry-over: honest reporting of first-beat and full-turn targets on CPU/GPU hybrid setup; filed proposed fixes for schema restructuring (moving `say` to the first property or compacting pre-say fields) to meet the < 1.0 s first-beat target.
