# prefix_cache_v1: LeilaLLM prompt-prefix cache on the game's real prompts (P4.05b)

## What was measured

`LeilaLLM` can reuse the common prompt prefix between turns by restoring a saved state checkpoint. This run measures what that does to latency and to the generated text, using the game's own prompt builder and turn schema.

- A scripted 8-turn scene is built through `PromptBuilder.build` and `TurnSchema.build_turn_schema`, then sent through `NativeBackend.generate`, one turn at a time.
- 16 configurations, one process per configuration, run sequentially on one GPU.
- The scene is identical in every configuration. History replies come from a fixed list of 8 canned lines, not from the model, so the cache=0 and cache=1 runs of a pair see the same messages.

### Fixed scene inputs

- Stage 3, path `yandere`, player name `Ren`, one fixed `scene` string.
- `memories`: 4 fixed lines.
- `events`: a different line on turns 3 and 6, empty on other turns.
- `offered` (turn 5 only): `{"music": ["quiet_piano"], "fx": ["rain_loop"], "cue": [], "action": []}`.
- 8 fixed player lines, one per turn.
- Sampling: `temp=0` uses `{temperature: 0, top_k: 1}`. `temp=game` uses `TurnContext.request_sampling(3)` with seed 20261105.
- Dose: `{"malice": dose}` when dose > 0, otherwise `{}`. With `dose-from`, turns 1-4 use the dose-from value and turns 5-8 use `--dose`.

### Matrix (16 rows, run in this order)

| row | cache | ubatch | dose | dose-from | temp |
|---|---|---|---|---|---|
| r01 / r02 | 0 / 1 | 512 | 0 | - | 0 |
| r03 / r04 | 0 / 1 | 512 | 4.5 | - | 0 |
| r05 / r06 | 0 / 1 | 128 | 4.5 | - | 0 |
| r07 / r08 | 0 / 1 | 64 | 4.5 | - | 0 |
| r09 / r10 | 0 / 1 | 512 | 4.5 | - | game |
| r11 / r12 | 0 / 1 | 128 | 4.5 | - | game |
| r13 / r14 | 0 / 1 | 512 | 4.5 | 0 | 0 |
| r15 / r16 | 0 / 1 | 128 | 4.5 | 0 | 0 |

The last four pairs change the dose mid-scene (dose 0 on turns 1-4, dose 4.5 on turns 5-8). Cached early words keep the dose they were decoded with, so text differences after turn 4 are expected there.

### Metrics

Each JSONL row holds: `cache, ubatch, dose, dose_from, temp, turn, prompt_tokens, cache_reused_tokens, cache_save_ms, cache_restore_ms, cache_state_bytes, prompt_ms, ttft_ms, first_say_ms, total_ms, tok_s, text`.

- Turn 1 of every process is cold. It is reported separately and is not in any mean.
- Means and p90 (nearest-rank) are over turns 2-8.
- `cache_compare.py` compares each cache=1 run with the cache=0 run that has the same ubatch, dose, dose-from and temp, and reports how many of the 8 turns have byte-identical text.

## Hardware and software

- GPU: NVIDIA GeForce RTX 4050 Laptop GPU, 6141 MiB, driver 615.71.09. VRAM use before each load was 62 MiB.
- CPU: AMD Ryzen 5 8645HS. RAM: 22 GB.
- OS: Linux 6.19.10-300.fc44.x86_64. Godot 4.7.2 headless via `tools/godot.sh`.
- Model: `/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf`, 2740937888 bytes, sha256 `00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4` (from `.orchestrator/p4-native-20261105/w1/results/model_hash.txt`).
- Engine library: `game/addons/leila_llm/bin/linux/libleila_llm.so`, sha256 `d56cf2070e748adfbbe94c3d049ebd878e4158877bb58f46c9807841554428fd`, mtime 2026-11-05 08:05:52. Source `native/src/leila_llm.cpp`, sha256 `187c7695806f20273fc8e47bb49493b6fe7a92e8061314d6822d8bd8b42254cb`. Neither was rebuilt for this run.

## Files

- `r01_*.jsonl` to `r16_*.jsonl`: one JSONL row per turn (8 rows each), copied unchanged from `/home/amrhares/.cache/leila-native/cache_scene/`. Hashes match the source files.
- `cache_compare.txt`: output of `python3 -I tools/promptlab/cache_compare.py --dir experiments/llm/prefix_cache_v1` (re-run and identical to the saved file).

Not copied here: the per-row `.log` files (VRAM and load lines), kept in `/home/amrhares/.cache/leila-native/cache_scene/`. The VRAM figures are in the results file.

## Scripts (outside this directory)

- Measurement script: `native/tests/cache_scene.gd` (untracked in the P4 worktree; sha256 `2024833bc8eab70cb5835ae7e47e90d4203d68c513a34deb02f562b6a051582d`). Args after `--`: `--out= --ubatch= --cache= --dose= --dose-from= --temp=`.
- Comparison: `tools/promptlab/cache_compare.py` (untracked; sha256 `ccc6cd7e569eab822025cb59ebe7341833341ca557a8140229f8e3869aaff0ba`).
- Driver: `/home/amrhares/.cache/leila-native/cache_scene/run_all.sh` (outside the repo; sha256 `6d104622f65e588085a0345a64e6b69e8e692a129412975396de2db53356d67d`). Usage: `run_all.sh [FIRST] [LAST]`. Each row has `timeout 240`.

## Engine configuration used

The measurement script overrides `NativeBackend._attempt_load` so that `n_ubatch` and `prompt_cache` reach `LeilaLLM.load_model`. The production `_load_engine` path passes neither key, so the game itself runs engine defaults (`n_ubatch` 512, `prompt_cache` 1). See the results file for detail.

## Timing caveats

- `prompt_ms` is the engine's host-side window around the `llama_decode` calls. It appears to under-count GPU work on some chunks: on cache=1 ubatch=512 turn 2, `prompt_ms` is 6 for a decode of 352 new tokens, while `ttft_ms` on the same turn is 124. Prefer `ttft_ms` and `total_ms` for latency; `first_say_ms` is end-to-end to the first say.
- `cache_save_ms` is inside `prompt_ms`. On miss turns (3, 4, 6) at ubatch 512, cache=1 `ttft_ms` is within about 10 ms of cache=0 `ttft_ms`, so the end-to-end checkpoint cost looks small. A save at ubatch 512 measures about 155 ms per checkpoint; per-turn means are 111-186 ms across ubatch values. The save figure probably includes GPU work drained at the sync point. Not isolated by this run.
- The 512 turn 6 to 7 step in `prompt_ms` (about 170 to 345 ms on cache=0) coincides with the prompt crossing 1024 tokens. `ttft_ms` rises only about 30 ms there. Treat the step as likely a timer artifact, not confirmed.
