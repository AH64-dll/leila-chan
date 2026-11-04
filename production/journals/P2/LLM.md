# LLM journal — phase P2

## P2.05 — sampling per stage + hardened schema limits (2026-11-04, agent: commandcode)

- The per-stage table was already data-owned (`game/data/sampling.json`, since P1.08); this round made the
  loader explicit: `TurnContext.parse_sampling()` is pure and accepts both `{"stages": {...}}` and the legacy
  flat stage-agnostic row (applied to every stage), with missing keys falling back to the docs/02 §9 row.
- `TurnContext.request_sampling(stage)` is now the only place a `TurnRequest` gets its three sampling columns;
  `Director` keeps no copy of the numbers/defaults. `dose` stays out of `request.sampling` (steering owns it).
- `sampling.json` v2 adds a `hardened` block (docs/06 §1: repeat_penalty floor 1.15, inner 90, say 200). It is a
  declarative contract gated by `SamplingPerStageTest`, not a runtime clamp — the data file stays authoritative.
- `TurnSchema` limits are now constants shared by grammar and validator; tests assert 90/200/80 at every stage
  and that 91/201 are rejected.
- Gotcha: gdformat will dedent a parenthesised assertion continuation out of a `for` body; assign the values to
  locals and keep the chain on one line instead. The test drives 6 Director turns in one case — 72 ms, fine.
- For P2.21 (QA): `tools/promptlab/lab.py` still mirrors stages 0–1 sampling + limits in Python; read the JSON
  (`stages` + `hardened`) when extending the lab to stages 0–5 instead of adding a third copy.
