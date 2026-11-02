# P7: Mobile (weight 5%)

**Goal:** docs/09 M6, mobile half. Android and iOS versions run on a smaller model with re-derived steering vectors.
The model downloads on first launch, there is an in-app "report output" button, and the build passes store policy review.

## Entry criteria
- P6 gate passed (Steam live).

## Role roster for this phase
| Role | Mission in P7 |
|---|---|
| STR | Smaller model choice, re-derived vectors |
| REL | Mobile builds, model download, store submission |
| META | Touch UI, meta-event adaptation |
| SAFE | Report-output flow, store policy |
| QA | Device performance and thermals |

## Tasks
| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |
|---|---|---|---|---|---|---|---|
| P7.01 | Choose the mobile model: prompt-lab candidates (≤ 2B class), latency on reference phones | STR | M | — | design | docs/06_STEERING.md§5, docs/07_TECH_ARCHITECTURE.md§6 | Comparison table; chosen model meets ≥ 97/80/80 prompt-lab thresholds |
| P7.02 | Re-derive malice + path vectors for the mobile model; re-tune dose table | STR | M | P7.01 | code, design | docs/06_STEERING.md§2, docs/06_STEERING.md§5 | Vectors committed; blind-read check per stage |
| P7.03 | Android + iOS exports, llama.cpp mobile builds (Vulkan/Metal), first-launch model download with resume | REL | L | P7.01 | code | docs/07_TECH_ARCHITECTURE.md§6 | Both builds boot to a date on reference devices; interrupted download resumes |
| P7.04 | Touch UI + mobile meta-event adaptation (no OS window tricks; in-app equivalents) | META | M | — | code, design, safety | docs/05_META_EVENTS.md§4 | Every meta event either adapted or disabled on mobile (table); safe areas respected |
| P7.05 | In-app "report output" + store policy review (AI-generated content) | SAFE | M | — | safety | docs/09_PRODUCTION_PLAN.md§1 | Report flow works offline-first; policy checklist for both stores |
| P7.06 | Device performance + thermal tests; store submissions | QA | M | P7.02, P7.03, P7.04, P7.05 | code, design | docs/07_TECH_ARCHITECTURE.md§4 | 30-min session without thermal throttling below playable; both stores accept the build |

## Exit criteria (gate)
1. Both mobile builds accepted by their stores.
2. Prompt-lab thresholds met on the mobile model; safety 0 leaks.

## Risks
- Smaller model breaks character more → more few-shots + stricter fallbacks; consider a cloud-free larger model on high-end devices only.
