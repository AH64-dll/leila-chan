# P6: Steam launch (weight 7%)

**Goal:** docs/09 M6, desktop half. Leila-chan is live on Steam with a store page, a trailer, achievements,
a release candidate tested on clean machines, bundled licences and a day-0 plan.

## Entry criteria
- P5 gate passed (content complete, legal checklist done).

## Role roster for this phase
| Role | Mission in P6 |
|---|---|
| REL | Steamworks, depots, store page, launch checklist |
| ART | Capsule art, screenshots, trailer |
| QA | Release-candidate testing |
| SAFE | Credits, licences, EULA/privacy, content survey |
| PROD | Go/no-go and release |

## Tasks
| ID | Task | Role | Size | Deps | Review | Refs | Acceptance |
|---|---|---|---|---|---|---|---|
| P6.01 | Steamworks: app setup, depots (game + separate 2.7 GB model depot), achievements per ending, cloud saves policy (exclude shadow save or not, decide) | REL | M | — | code, design | docs/07_TECH_ARCHITECTURE.md§6 | Test branch installs from Steam; achievements unlock in a test run; cloud policy decision in DECISIONS.md |
| P6.02 | Store page: description, content warnings, mature content survey, min spec, tags | REL | M | — | design, safety | docs/09_PRODUCTION_PLAN.md§3, docs/01_GAME_DESIGN.md§0 | Page draft approved by the user; AI-content disclosure filled honestly |
| P6.03 | Capsule art + screenshots set | ART | M | — | design | docs/03_EMOTIONS.md§6 | All Steam asset sizes delivered; no third-party logos |
| P6.04 | Trailer featuring the M17 "she steps out" shot | ART | M | — | design, safety | docs/05_META_EVENTS.md§1.2 | 60–90 s cut; captions; no photosensitive violations |
| P6.05 | Credits, licences bundled (Qwen NOTICE, CC0 credits, tweet inspiration), EULA + privacy statement in game | SAFE | S | — | safety | docs/09_PRODUCTION_PLAN.md§3 | Files present in the install folder and in the Credits screen |
| P6.06 | Release candidate: clean-machine install/uninstall on Windows/Linux/macOS, upgrade from beta save, crash-free 3-hour run | QA | M | P6.01, P6.05 | code, design | docs/07_TECH_ARCHITECTURE.md§6 | RC checklist all green; 0 S1/S2 bugs |
| P6.07 | Launch checklist, opt-in crash reporting, day-0 patch plan | REL | S | P6.06 | design | docs/09_PRODUCTION_PLAN.md§2 | Checklist reviewed; rollback steps documented |
| P6.08 | Go/no-go with the user and press release on Steam | PROD | S | P6.02, P6.03, P6.04, P6.07 | design | docs/09_PRODUCTION_PLAN.md§1 | User's explicit go recorded in DECISIONS.md; game live; store link in STATUS.md |

## Exit criteria (gate)
1. The game is purchasable and installable on Steam.
2. RC checklist green; no S1/S2 bugs open.
3. Licences, credits and privacy statement shipped.

## Risks
- Store rejection (AI content / mature) → honest disclosure, content warnings, Steam first (docs/09 risk register).
