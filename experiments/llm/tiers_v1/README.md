# Device tiers and first-beat options (tiers_v1)

Task p410a-tiers. Measured on 2026-11-05 with the scene-driven prefix-cache benchmark
`native/tests/cache_scene.gd` (Godot 4.7.2 headless, C++ GDExtension over llama.cpp b12024).
Model: `Qwen3.5-4B-Q4_K_M.gguf`. Every row: `--cache=1 --ubatch=128 --dose=4.5 --temp=game`,
8 turns, one run per row.

## Hardware

- GPU: NVIDIA GeForce RTX 4050 Laptop GPU, 6141 MiB, driver 615.71.09.
- CPU: AMD Ryzen 5 8645HS w/ Radeon 760M. This is a **6-core** CPU with 12 threads
  (`nproc` = 12), not an 8-core. "6 threads" means the physical core count.
- iGPU: Radeon 760M, reached through Vulkan as `Vulkan0` (`device_type=igpu`).
  `Vulkan1` is the RTX 4050 through Vulkan (`device_type=gpu`).

## Load average

`uptime` was recorded before and after every row in `driver_run.txt`.

- GPU rows started near idle (1-minute load 0.7 to 1.4).
- The CPU rows ran back to back. Each started with the previous row's load still in the
  1-minute average: cpu_4t 0.93, cpu_6t 3.58, cpu_8t 6.05, cpu_12t 8.25,
  cpu_default_fast 11.29, cpu_default_normal 8.54. The CPU rows were measured under their own
  load, plus this carry-over. Other processes on the machine were not separated out.
- Peak 1-minute load after a CPU row was 11.29 (after cpu_12t_fast). The 5-minute load
  peaked at 6.77.

## Limits (read before using these numbers)

- The machine has a 6-core CPU, not an 8-core. Thread counts above 6 use SMT threads.
- The proxy limits memory only. A real 4 GB card has a slower chip, so `proxy_4gb` does
  not predict a 4 GB card's speed.
- In this run the proxy did not constrain the game. The ballast held 2140 MiB, and the game
  still loaded all 99 layers on CUDA0 (VRAM 2140 to 5402 MiB). The game needs about 3.3 GB,
  so a ballast of roughly 2.8 GB or more would be needed to force a fallback. That was not
  tested.
- `late-events` and `inner-cap` are experiments, not game behaviour.
  - `late-events` moves the events and offered text to the end of the system message.
  - `inner-cap` sets `inner.maxLength` to 40 in the turn schema copy.
- One run per row. Differences of about 100 ms in first-say are within the spread of the
  turns and are not established.

## Results

Columns: first_say mean and p90 over turns 2 to 8, cold turn-1 first_say, mean total_ms
over turns 2 to 8, mean tok/s, and `vm_hwm_kb` (peak RAM, from the last row of each file).

| Label | Device | Threads | first_say mean (ms) | first_say p90 (ms) | turn 1 first_say (ms) | total_ms mean | tok/s mean | vm_hwm_kb | Status |
|---|---|---|---|---|---|---|---|---|---|
| cpu_12t_fast | cpu | 12 | 7995 | 10515 | 11789 | 11475 | 10.0 | 5598544 | ok 8/8 |
| cpu_4t_fast | cpu | 4 | 7205 | 9871 | 11818 | 9782 | 13.9 | 5594520 | ok 8/8 |
| cpu_6t_fast | cpu | 6 | 6284 | 8331 | 10142 | 8629 | 14.1 | 5595600 | ok 8/8 |
| cpu_8t_fast | cpu | 8 | 6474 | 8611 | 10196 | 8844 | 13.9 | 5597680 | ok 8/8 |
| cpu_default_fast | cpu | 6 | 6235 | 8200 | 10107 | 8564 | 14.2 | 5595408 | ok 8/8 |
| cpu_default_normal | cpu | 6 | 6266 | 8290 | 9915 | 10661 | 14.2 | 5595528 | ok 8/8 |
| gpu_auto | CUDA0 | 6 | 1057 | 1248 | 1311 | 2232 | 50.8 | 3406348 | ok 8/8 |
| gpu_cuda | CUDA0 | 6 | 1057 | 1240 | 1297 | 2232 | 50.8 | 3407028 | ok 8/8 |
| gpu_fast | CUDA0 | 6 | 1059 | 1242 | 1314 | 1742 | 49.8 | 3406824 | ok 8/8 |
| gpu_vulkan | Vulkan1 | 6 | 1294 | 1630 | 4284 | 2590 | 47.2 | 3480208 | ok 8/8 |
| igpu_vulkan | Vulkan0 | 6 | 3768 | 4805 | 5748 | 7363 | 17.0 | 1192080 | ok 8/8 |
| opt_both | CUDA0 | 6 | 989 | 1110 | 1308 | 2177 | 50.2 | 3406680 | ok 8/8 |
| opt_inner_40 | CUDA0 | 6 | 1065 | 1256 | 1318 | 2245 | 50.6 | 3406608 | ok 8/8 |
| opt_late_events | CUDA0 | 6 | 993 | 1119 | 1310 | 2184 | 50.0 | 3406984 | ok 8/8 |
| proxy_4gb | CUDA0 | 6 | 1056 | 1240 | 1297 | 2230 | 50.8 | 3388216 | ok 8/8 |

The GPU rows that show `Threads 6` used the engine default (`n_threads = 6` in the load line).

Notes on the table:

- `gpu_fast` has the same first_say as `gpu_cuda`. Its lower total_ms comes from fewer
  tokens: fast mode caps `max_tokens` at 220, and completions averaged about 80 tokens
  against about 106.
- `cpu_default_normal` matches `cpu_default_fast` on first_say but takes longer in total
  for the same reason.
- `gpu_vulkan` (Vulkan1) has a cold turn 1 of 4284 ms, about 3 times the CUDA cold turn.
  The cause was not investigated.
- `igpu_vulkan` (Vulkan0) reports a peak RAM of about 1.19 GB, far below the other rows
  (about 3.4 GB on GPU, about 5.6 GB on CPU). The cause was not investigated.

## Proxy

- Binary: `tools/llama/gpu-cuda/llama-b12024/llama-server`, launched with
  `LD_LIBRARY_PATH` set to the cudart directory and the binary directory.
- Port 8097, `-c 512`, `-ngl N`. VRAM was read after each load.
  - N=12: 1566 MiB
  - N=19: 2068 MiB
  - N=20: 2140 MiB (used for the row)
- Baseline before the proxy: 63 MiB.
- Offload was confirmed by the CUDA libraries mapped into the server process (21 entries).
- The server was stopped by PID after the row. VRAM returned to 63 MiB.

## Files

- `<label>.jsonl`: one file per row. Eight turn rows. The last row carries `vm_hwm_kb`.
- `tiers_table.md`: the table above, generated by `tools/promptlab/cache_compare.py --tiers`.
- `driver_run.txt`: the 14-row driver output, with uptime and VRAM before and after each row.
- `proxy_ngl12.log`, `proxy_ngl19.log`, `proxy_ngl20.log`: proxy server logs for the N tuning.
- `run_tiers.sh`: the driver. It runs one label per call, as `bash run_tiers.sh <label>`,
  with `LEILA_MODEL` set. It was run with `bash` because it has no execute bit.
  The paths inside the script are those of the worktree and the cache directory.
