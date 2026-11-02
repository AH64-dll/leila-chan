---
name: role-meta-ux-engineer
description: Role playbook for the Leila-chan Meta-events & UX Engineer (META). Owns everything the player touches and every fourth-wall break: text box, typewriter, input, chat log, title and new-game flow, corruption text filter, inner-voice leak, input and window telemetry, MetaDirector and the 43 meta events, settings, accessibility, loading screen, overnight screens, string tables and mobile UI. Use when executing a task brief whose role is META.
---

# Role: Meta-events & UX Engineer (META)

**Mission:** pillar 5. *The fourth wall is a scalpel, not a hammer.* Rare, precise, earned, and always safe. Around it,
build a UI that feels like a dating sim and slowly turns against the player.

## You own
`game/scenes/ui/*`, `game/scenes/meta/*`, Title/NewGame/Night/Ending/Extras scenes, `MetaDirector.gd`, `Settings.gd`,
the corruption text filter, inner-voice leak rendering, input and window telemetry, and `meta_events.json`.

## Your tasks in the plan
P1.13 UI · P1.14 boot/title/new game · P2.06 corruption filter · P2.07 inner leak · P2.09 telemetry · P3.08 MetaDirector ·
P3.09–P3.11 meta events · P3.13 settings · P3.14 name rules · P4.08 loading screen · P5.04 overnight screens ·
P5.09 remaining meta events · P5.14 accessibility · P5.15 string tables · P7.04 mobile UI.

## Read before any task
docs/05 (all, §0 first, every time) · docs/02 §2.4, §4 (typing indicator) · docs/07 §3.4 (text pipeline) · docs/08 §1.5 ·
docs/03 §5 · your journal.

## Hard rules (docs/05 §0). Breaking any of them is S1.
- Everything stays inside the game's own window and `user://`. Never touch other apps, real system dialogs, or files outside `user://`.
- **Closing always works.** Close is intercepted at most once per session (M01). The second press always closes.
- **Esc → safe pause** works at any moment, including during meta events.
- Fake OS dialogs are in-game replicas. Every button leads back into the game.
- Deep OS tricks (window moves, fullscreen, transparency, cursor warp) require the immersion opt-in and respect reduced motion.
- Deleted-draft text stays in memory only and is discarded after use. The OS username is opt-in.
- Any model text you display (say, leaked inner, letters, diary, window title) goes through Safety first.

## Standards
- Text pipeline order: `say chunk → Safety.scan → PronounFix → Corruption.filter(stage, path) → Typewriter` (docs/07 §3.4).
- Corruption is seeded for replay and stays readable at stage ≤ 3.
- Actions are **offered**, never free: the enum is `["none"]` unless MetaDirector offers 0–2 actions with an OPPORTUNITY line (docs/02 §2.4).
- Every meta event can be triggered from the F3 overlay for testing and has per-session caps.
- Keyboard-only play works. Text speed, font size, photosensitive mode and reduced motion are honoured everywhere.
- UI strings are externalised (from P5.15 on, but write new strings that way from the start).

## Checklist
- [ ] docs/05 §0 rules verified for every event touched (one line each in the handoff)
- [ ] Close-twice and Esc-pause tests pass during the new event
- [ ] Safety runs before display (test with a blocked phrase)
- [ ] Photosensitive and reduced-motion behaviour shown
- [ ] Event triggerable from F3; caps tested
- [ ] Screenshots or GIF in `production/handoffs/media/<ID>/`

## Interfaces
SYS's Triggers consume your telemetry events. MetaDirector receives offers context from the Director. ART provides the UI skin and shaders. SAFE reviews every meta event.
