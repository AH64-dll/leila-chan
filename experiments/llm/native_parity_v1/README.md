# Prompt-lab parity: native engine against the pinned llama-server (P4.04)

`tools/promptlab/native_parity.py --runs 1 --seed 424242`. RTX 4050, CUDA, Qwen3.5-4B-Q4_K_M, llama.cpp b12024.
The unchanged `run.py` and `score.py`, over `plan.json`'s `scheduled` exercises: 128 cases, malice only at each stage's dose.
The native side is `game/tools/native_http_shim.gd`, which calls the real `NativeBackend`.

| stage | dose | identical replies | validity | read | emotion fit |
|---|---:|---:|---:|---:|---:|
| 0 | 0.0 | 18/18 | 100.0 | 88.9 | 100.0 |
| 1 | 2.5 | 12/12 | 100.0 | 66.7 | 83.3 |
| 2 | 3.5 | 20/20 | 100.0 | 70.0 | 70.0 |
| 3 | 4.5 | 25/25 | 100.0 | 56.0 | 64.0 |
| 4 | 6.0 | 32/32 | 100.0 | 68.8 | 43.8 |
| 5 | 8.0 | 21/21 | 100.0 | 42.9 | 38.1 |

Every value is the same on both transports, so every delta is 0.0.

## Why a fixed seed
The lab samples at temperature 0.75-0.95 with no seed. A stage has 12-32 cases, so one reply moves its score by 3-8 points at one
run per case, and a difference of 2 points is well inside sampling noise for two identical runtimes. With one seed both transports
draw the same random stream, so they can be compared reply by reply, which is stronger than comparing scores.

## What this does not show
- The read and emotion-fit scores themselves are below the docs' 85% gates at most stages. That is the same on the server, and
  it is P2.21's finding, not a runtime result. These are bare one-turn lab cases with no game state.
- One seed is one draw per case. It shows the runtime computes the same thing, not how often a reply is good.
- Mixed path vectors are not in this exercise. `experiments/steering/mix_native_v1/` covers those, 10/10 identical.
- Before P4.05: this ran with no prefix cache. P4.05 must show it does not disturb this.
