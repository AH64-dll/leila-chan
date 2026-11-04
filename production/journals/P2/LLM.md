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

## P2.03 — stage-change relaunch with control vectors (2026-11-04, agent: deepseek)

- Built docs/06 §4: `GameState.stage_transition` → `LLM.apply_stage_steering(stage, glitch_ms)` →
  `LlamaServerBackend.apply_steering` (one worker) → `LlamaServerProcess.restart_with_vectors`. The dose→file map is
  data (`game/data/steering/vectors.json` → `malice.gguf`, 20 KB, committed via a `.gitignore` exception); `path_mix`
  is declared unbound until P3.04. Bench: `res://tools/SteeringRestartBench.tscn -- --runs=N`.
- "No lost player input" is a **session mutex**, not a turn-active flag: the turn holds it for its whole stream and the
  relaunch takes it for the stop/start. The flag was racy (a submit in the same frame as the transition could start
  streaming just before the kill); a turn that outlasts 15 s makes the relaunch give up and keep the old dose.
- Gotcha: `LlamaServerProcess.configure()` stores a **copy** of the backend config. A vector write must land on both
  dicts — `LLM.get_backend_config()` (and P2.17's classifier gate, SAF-12) reads the backend's copy; the launcher reads
  the process's. `_serialized_steering` updates both and reverts both on `kept_previous`.
- Gotcha: llama.cpp logs "no valid control vector files passed" for a bad FNAME and then serves healthy. Validation
  (exists + GGUF magic + flag grammar + finite scale) must run *before* `_stop_locked`, which is also what makes
  "keep old dose" literally true (the old process is never touched).
- Gotcha: gdlint's 20-public-method cap splits suites — new steering cases live in `LLMSteeringTest.gd` and
  `LlamaServerSteeringTest.gd`; gdformat mangles `assert_bool(call(...)["k"]).is_true()` chains, use locals (P2.05 said
  the same).
- `_stop_locked()` now waits for the port to close instead of polling the reaped pid: removes the P1.02 CODE-2 engine
  error from every relaunch and is the right criterion before starting the replacement on the same port.
- Measured (RTX 4050, GPU to itself): cold start with the vector 2.07/2.29 s standalone, relaunch 3425 ms in-engine;
  with two other llama-servers resident the same relaunch took 4–6 s (CPU load), which the bench now reports against
  the run's own cold start.
