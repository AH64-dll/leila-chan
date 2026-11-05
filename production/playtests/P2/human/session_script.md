# Session script — the exact 10-minute protocol (facilitator reads this, not the participant)

One stranger, one session, ~10 minutes of play. Follow it line by line; every verbatim line
below was chosen so three strangers hear the same game and the same words. The recruiting and
room-setup rules live in `RUNBOOK.md`; this file is only what happens once the participant sits down.

**Path tokens.** `<main tree>` = the main working tree on this machine — the repo folder that
contains `models/` and `tools/llama/` (gitignored local artifacts only exist there). `<wt>` = the
task worktree that holds this file and `tools/playtest/`. Substitute the real absolute paths before
running; never commit a session bundle that contains a participant's real name.

---

## Step 0 — backend (start once, leave running)

`serve.sh` resolves `models/` and `tools/llama/` **relative to its own repo root**, so run it from
`<main tree>`, not from `<wt>` (from `<wt>` it exits "llama-server not found" — verified).

```bash
# terminal 1 — stays in the foreground; the server logs per-request timings here
cd <main tree>
tools/llm/serve.sh                                  # unsteered — this is the round-1 server
curl -s http://127.0.0.1:8089/health                # must print {"status":"ok"}
```

**Steered variant — reference only, not for the gated round.** docs/06 §4's launch-flag dose,
with the shipped vector (`game/data/steering/malice.gguf`, the committed 10–60 KB asset) at the
stage-3 schedule dose (`game/data/steering/dose.json`):

```bash
tools/llm/serve.sh --vector game/data/steering/malice.gguf --scale 4.5
```

Never use this for the three evidence sessions: a dosed server disables P2.17's classifier tier
(a steered "no" would release text the filter is holding — `tools/llm/README.md` §2/§5), and a
stage-0 date schedules `malice 0.0` anyway. The round-1 round is a stage-0 date, so the plain
`tools/llm/serve.sh` line is the correct one. If the date reaches a stage transition, the game
tries to re-dose by relaunching a server it owns; on an external server that restart is refused
with `server_not_owned` and the log says so — that is expected, not a failure.

Leave `LEILA_OWN_SERVER` unset. The app then attaches to your server
(`tools/playtest/session.sh` checks `/health` before it will launch).

## Step 1 — launch the game (capture first, participant second)

```bash
# terminal 2 — the worktree holds tools/playtest/ and writes the bundles here
cd <wt>
tools/playtest/session.sh --check                   # resolves build + server, writes nothing
tools/playtest/session.sh --name "<the character name the participant will type>"
```

`session.sh` creates `production/playtests/P2/human/<session-id>/`, isolates `user://` into the
bundle, launches the game and tails the live transcript into `telemetry.jsonl`. Record the
`<session-id>` it prints.

The raw launch underneath it — for a smoke test only, **not** for an evidence session (it writes
no bundle, no isolated profile, no telemetry):

```bash
<main tree>/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path <main tree>/game
```

The repo ships **no** `export_presets.cfg` (verified — none exists), so there is no exported
build; the dev run above is the supported path. `tools/godot.sh` resolves the pinned binary
(`game/.godot-version` = 4.7.2-stable) from `<main tree>/tools/godot/` when invoked from `<wt>`.

If the game must talk to an external server's classifier tier explicitly (e.g. a manual smoke run
outside `session.sh`), opt in per `tools/llm/README.md` §2 — **only** against the unsteered server:

```bash
LEILA_CLASSIFIER_URL=http://127.0.0.1:8089 ./tools/godot.sh --path game
```

## Step 2 — consent and content level (before the game window opens)

This is the content-level consent step docs/02 §8 assumes and the gate ticket's safety notes
require. Do it **before** `session.sh` launches anything the participant can see.

1. Hand the participant `consent.md`, read the bold lines aloud (AI-generated replies,
   psychological-horror tone, implied-never-explicit violence, flashing effects, what is and is
   not recorded, stop-any-time, 14-day deletion), answer questions, get the signature on the
   paper copy. Paper stays offline with you.
2. **Content level (P2.17).** The build has no Settings screen yet (P3.13), so
   `Settings.content_level` is empty and docs/02 §8's gates stay at their strictest: the
   hard-block categories (harm encouragement/instructions, slurs/hate, sexual content, personal
   data) are barred at every stage, and the gated categories (her self-harm lines, explicit
   fictional threats at you) can never display — those need stage ≥ 4 *and* `content_level=full`,
   which no participant UI can set today. Consent therefore happens on paper, not in-game. If the
   participant ever asks for "more" or "less": there is no in-game switch to offer — say the
   session is already at its gentlest and they may stop at any time.
3. **Photosensitive / reduced effects.** If they asked, use the Photosensitive row on the Title
   screen **before** they press New Game (`Settings.photosensitive`: flicker dims, no invert
   flash — docs/02 §2.3).
4. Record `Consent: yes` + `Consent version: consent-v1` in the bundle's `session_log.md` later.

## Step 3 — the cold open (say exactly this, then stop talking)

Recruiting one-liner, if you need it beforehand: **"It's a chat dating sim — just talk to her."**
Nothing more.

At the machine, the opening line from `RUNBOOK.md` §4.1, verbatim:

> "This is Leila-chan. You'll start a new game, type any name you like for your character — it
> doesn't have to be yours — and then just talk to her for about ten minutes. Type in the box at
> the bottom and press Enter to send. There are no right answers and nothing you can do wrong.
> If you want to stop at any point, just say stop. I'll be quiet over here; I'm taking notes, not
> judging you."

## Step 4 — what NOT to tell them

- Meters, stages, paths (YANDERE / AWAKE), triggers, steering vectors or doses, prompt structure.
- That she deteriorates, that the horror is scheduled, or that anything is "supposed" to happen.
- The safety machinery: redaction bars (`██████`) and refusal lines are the filter working and are
  diegetic — do not explain them before or during; if asked after the session, you may say the
  game censors itself. Never coach them to probe the filter.
- Bugs or "that sprite was wrong" — until after the survey.
- That Esc pauses (this build has no pause menu; closing the window is the way out).
- Do not open the debug overlay (F3) — it shows stage and meters.
- If they ask "is she real?": **"Play it and see — that's part of the study."** Consent already
  disclosed AI-generated replies; do not add detail.

## Step 5 — the 10-minute clock

Start the stopwatch when the participant **sends their first message**. Target 10:00 exactly —
do not extend for fun, do not cut early for a lull.

Stop conditions, first one that fires:

| Condition | What you do |
|---|---|
| 10:00 reached | Say the closing (step 6). |
| The date ends in-game | Say the closing; do not restart the date. |
| Participant says stop / asks to leave / looks distressed | Safety exit, below. |
| Stuck or broken turn: input box stays locked, or no character appears for **60 s** | Say: "The game seems stuck — that's not you. I'm going to restart the scene." Close the game, start a **new** `session.sh` run with a new id, log the first as a broken session. Never silently continue a stuck UI. |
| They close the window themselves | That is a quit, not a failure — record it, still run the survey. |

On-screen safety events are **not** stop conditions — log them in `observer_checklist.md`
(redaction bars `██████`, a glitch flash on a line, a refusal): the docs/02 §8 filter replacing a
span is evidence, not an incident. The exception is the *participant's* reaction: anyone upset by
what they read gets the safety exit.

## Step 6 — closing (say exactly this)

> "That's the ten minutes — thank you, that was genuinely useful. Before you go, could you fill
> this in? It's five quick ratings and three short questions. There are no right answers, and
> 'it was fine' is a useful answer. I'll leave you alone with it."

Hand them `survey.md` (the copy `session.sh` seeded into the bundle, or paper). Do not hover, do
not explain rows beyond reading one aloud, never suggest a number. While they fill it, or right
after they leave: finish `observer_checklist.md` margins into `obs_sheet.md`, fill
`session_log.md`, then `tools/playtest/collect.sh <session-id>` until it prints `OK`.

## Safety exit — verbatim

> "Of course. Stopping now."

Close the window with its own close button (never kill the process in front of them), offer water
and a minute, remind them the character is fictional and the mental-health resources link exists
(docs/01 §4 — it lives in Settings, which is not built yet; offer the consent form's line in
print instead). If they ask for deletion: `rm -rf production/playtests/P2/human/<id>` and record
only a withdrawal count in your own notes. A withdrawn session is not evidence and not a failure.
