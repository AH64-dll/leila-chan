# NAR — phase P3 journal

## P3.15 — 14 more scenarios (round 1)

- Shipped `D05_library`, `D07_aquarium`, `D08_summer_festival`, `D09_beach_sunset`, `D10_ferris_wheel`,
  `D12_cooking_together`, `I02_love_letter`, `I03_quiz_about_her`, `I05_poem`, `I08_rival_appears`,
  `I13_lucid_moment`, `I15_promise`, plus the path set-pieces `SP_YANDERE_the_list` and `SP_AWAKE_her_prompt`
  (`kind: "setpiece"`, `paths: [<own path>]`, `stages: [3,5]` — the path lock point).
- Convention: D/I scenes carry stage variants 0–5 and three twists each, with YANDERE + AWAKE pinned on all twelve
  and a scene-fitting third; set-pieces carry 3–5 variants and their own path + two alternates. Opening beats are
  authored for every playable stage, never only 0/1/3/5.
- `tests/test_scenarios.py` gained the P3.15 block: docs/01 §6.1/§6.2/§6.4 anchors, set-piece path locks,
  per-available-stage opening-beat coverage, and an "ambience is `none` or a real `cue_map.system` id" rule (only
  `ambience.paper` and `ambience.dishes` exist today). The engine loader floor is 21 files.
- Budget: the scene layer is the constraint. `scenario_playthrough.gd --stats=1` on 42 combos gave worst fixed
  868/900 and scene 126/150 on the real tokenizer. Keep a stage variant ≤ ~45 tokens and a twist ≤ ~25, or stage 5 +
  YANDERE crosses the builder's 150 estimate (SP_AWAKE needed trimming).
- Opening-beat `say` lines are limited to **two `[.!?]+` segments**, not two sentences as a human counts them:
  three short sentences fail the test even when they read naturally. Set-piece beats start at stage 3.
- Gotcha: a fresh worktree needs `./tools/godot.sh --headless --path game --import` before
  `scenario_playthrough.gd` runs (`class_name ScenarioLoader` not in the cache → parse error at `_print_stats`).
- Gotcha: the shared :8089 server was OOM-restarted mid-batch several times. A health gate before each run plus a
  retry cap (3) salvaged all 14; always verify the transcript's `invalid turns: 0` line rather than the exit code
  alone, and never start a second server.
