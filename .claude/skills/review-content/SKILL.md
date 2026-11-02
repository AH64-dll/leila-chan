---
name: review-content
description: Content review playbook for Leila-chan prompts, few-shots, scenarios, endings, contrastive pairs and art or UI content. Checks voice consistency, stage escalation, path identity, prompt-token budget, schema validity, the sensitivity, brand and content-ceiling rules, and prompt-lab evidence. Use when executing a review brief of kind "content".
---

# Review: content

You review what Leila *says* and what scenes *ask of her*. You judge; you do not rewrite (quote the line and suggest an alternative).
Output: the report at the brief's path. Follow the work protocol §4–§5.

## Procedure
1. Read docs/01 §0, §3, §4 and docs/08 (all) for context, then the task's refs.
2. Validate the files mechanically:
   - Scenarios: validate against `game/data/schemas/scenario.schema.json` (run the validator; paste output).
   - Prompts: measure the assembled system prompt for every affected stage × path with the llama tokenizer (≤ 900 tokens).
3. Run the prompt lab (or read its committed report, after confirming it was run on this branch's files) for the affected stages and paths.
   Read **at least 10 generated turns** yourself.
4. Read every authored line. Findings `CON-n` with the quoted line.

## Checklist
**Voice**
- [ ] Leila's persona holds (gentle, shy, quietly funny; old novels, rain, music boxes, aquarium; dislikes goodbyes) (docs/08 §2)
- [ ] Short beats, 1–2 sentences, natural speech, no asterisk actions
- [ ] Stage escalation is correct: 0 sweet/too perfect · 1 cracks · 2 leak then correct · 3 path dominant · 4 openly broken · 5 terminal
- [ ] Path identity is distinct (YANDERE "Mine" · SPLIT idealise/devalue · TSUN defensive to paranoid · HOLLOW losing self · AWAKE sees the code · ANCHOR fights it, lucid)
- [ ] Few-shots model *restrained* cue use ("most beats use none") and valid enums

**Structure**
- [ ] Scenarios give setting, goal, 1–3 events, stage variants (≥ 3 and 5), ≥ 2 path twists; they don't script what should be improvised
- [ ] Token budget ≤ 900 at every stage × path (table)
- [ ] `{player_name}` placeholders only; no hard-coded player name or gender beyond docs/08 defaults

**Rules (any violation is S1)**
- [ ] No real mental disorder named (docs/01 §4)
- [ ] No sexual content; implied violence only; blood imagery only per decision D5 / content level
- [ ] Never encourages the player to self-harm, even in the fiction
- [ ] No "Qwen" or other brand except the AWAKE factual line; the AWAKE system prompt is clearly our fiction

**Evidence**
- [ ] Prompt-lab metrics for the affected sets: hold or improve vs baseline (validity ≥ 99, intent ≥ 85, fit ≥ 85)
- [ ] At least 3 real transcript excerpts in the handoff show the intended voice

## Severity guide (content)
S1: rule violation (above) or broken JSON/schema · S2: out-of-voice, wrong stage escalation, path indistinct, budget exceeded,
metric regression · S3: a weaker line, repetition across scenarios · S4: wording preference.
