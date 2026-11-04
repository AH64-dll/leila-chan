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

### Round 2 (rework after design-r1 + code-r1)

- The `hardened` block now separates the **measured** docs/06 §1 legs (`say` 160, temperature 0.7) from the
  **adopted** numbers (docs/02 §3's 90/200, docs/02 §9's temperature ladder). The docs conflict is real and is
  filed as DCR-1 in the handoff — do not fold docs/06's measured values into the shipped table without the
  producer/user deciding; the stage-5 row stays 0.95.
- Deleted the "legacy stage-agnostic" flat row entirely: it never shipped (`git log -- game/data/sampling.json`
  → `4a46b3d` added the file already as `{"stages": …}`), and its flat overlay wrongly copied `dose` everywhere.
- `parse_sampling()` warns when a document yields no usable stage rows (`{}`, misspelled `stages`,
  `{"stages": []}`, only out-of-range keys). Do **not** ship a test for it — gdUnit4 logs the warning and the DoD
  forbids new warnings in the gate; probe it with a throwaway suite and paste the transcript instead.
- Envelope gate now uses the highest reachable dose (`base + 4`, docs/06 §3 spike band, clamp 12), so stages 3
  and 4 are gated too, plus `assert_int(checked).is_greater(0)` so a retune cannot empty the check silently.
- `TurnContext` reads `GameState.STAGE_MAX` (no local copy). Gotcha: `--script` cannot `preload` *any*
  autoload-dependent script (`Director.gd` fails identically) and a `class_name` script is compiled before
  autoloads exist, so verify loader behaviour through a gdUnit suite, not a standalone probe.
- Gotcha: `Director.reset()` reinstalls the real `Safety` filter — every test that writes a loop must re-arm the
  fake seam after each reset (`_reset_director()`), or the sampling assertions run against the real corpus.
