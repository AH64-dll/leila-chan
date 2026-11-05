# Human playtest — round 1 (the runbook)

This is the operating manual for the **real** human round that docs/09 §1 M1 exit criterion 1
("a stranger plays 10 minutes, the face/sound match her words, survey mean ≥ 4/5, zero broken
turns") needs before the M2 gate. Three strangers, one session each, about ten minutes of play.
P1 round 0 was a scripted self-review with no humans (`production/playtests/P1/survey_round0.md`
says so); it found defects but it cannot stand in for this round.

Everything in this folder is committed. The game runs; the transcripts are captured by
`tools/playtest/session.sh`; the survey, the observer sheet and the operator log are filled by
humans; `tools/playtest/collect.sh` bundles a session and `tools/playtest/score.py` turns the three
bundles into `RESULT.md` with a verdict.

**What counts as evidence:** three bundles in this folder, each with a non-empty `telemetry.jsonl`,
a filled `survey.md`, a filled `obs_sheet.md`, a filled `session_log.md` whose `Consent` row says
`yes`, and a participant code instead of a name. `score.py` refuses anything else. `_dryrun/` is a
synthetic demo for testing the pipeline and is **never** evidence (the tool refuses it without
`--allow-synthetic`, and labels its output SYNTHETIC).

---

## 0. The day before — preflight (15 minutes)

1. **Backend.** The game talks to a `llama-server` that you start once and leave running:

   ```bash
   # terminal 1, from the project root; leave it in the foreground
   tools/llm/serve.sh
   # then in terminal 2:
   curl -s http://127.0.0.1:8089/health        # must print {"status":"ok"}
   ```

   Leave `LEILA_OWN_SERVER` unset. The app then attaches to your server instead of launching
   its own (the round is a stage-0 date; no steering restart is expected).

2. **Build.** Either a debug export or a dev run works. `session.sh` uses, in order:
   `$LEILA_PLAYTEST_BUILD`, `build/Leila-chan.x86_64`, `build/leila-chan.x86_64`,
   `game/build/Leila-chan.x86_64`, `dist/Leila-chan.x86_64`, `export/Leila-chan.x86_64`, and
   otherwise `tools/godot.sh --path game` (dev run). The repo ships no export preset, so the dev
   run is the supported path today; if you do build one it must be a **debug** export
   (`--export-debug`, not `--export-release`): `TranscriptLogger` is dev-only
   (`game/llm/TranscriptLogger.gd`, docs/07 §5), so a release build writes no telemetry and the
   bundle comes out empty.

3. **Preflight check.** This resolves the build, checks the server and prints the bundle path it
   would create. It does not launch the game or write anything:

   ```bash
   tools/playtest/session.sh --check
   ```

4. **Kit dry run.** Prove the scoring pipeline works before any human arrives:

   ```bash
   python3 tools/playtest/score.py --dir production/playtests/P2/human/_dryrun \
     --expect 1 --allow-synthetic --out production/playtests/P2/human/_dryrun/RESULT.md
   ```

   Must print `VERDICT: PASS` (labelled synthetic) and exit 0.

5. **Room.** A quiet room, one screen, speakers at a comfortable volume. Windowed game
   (384×688 logical, integer-scaled). Do not open the debug overlay (F3) during a session: it
   shows meters and stages the participant must not see. Turn notification popups off.

---

## 1. Recruiting the three

- **Strangers**: people who have never seen the project, its code, its journals or a transcript.
  Not the team, not anyone who playtested round 0, not anyone who has read this runbook.
- **Adults only (18+)**, comfortable with psychological horror / an unsettling character.
  She is a yandere-coded character; content is implied, never explicit, but the tone is dark.
- **Fluent enough in English** to type a few sentences. If you have a mix, record the language.
- **No explanation of the game's systems.** You may say it is "a short text-chat date with an AI
  character". You may not explain meters, stages, paths, triggers, or that she gets worse.
- You need **three separate people**, each in their own session. The same person twice is not
  three strangers.

---

## 2. Set-up (5 minutes per session)

- ONE facilitator runs the terminal, the stopwatch and the conversation. If a second person is
  available, they fill `obs_sheet.md` so the facilitator can stay quiet. If you are alone, run the
  session and fill the observer sheet's summary rows between turns — do not talk while doing it.
- Keep the participant's real name out of every file. Use the code they are given (`P1`, `P2`,
  `P3`) wherever a name would go. The game will ask them to type a **character name**; tell them
  it can be anything, including a made-up one, and that it is not their real name.
- Consent first (section 3), then start the session script, then the game.
- Stopwatch: one for the session clock, one for the first-beat measurement. Phone timers are fine.

---

## 3. Consent — say this before anything else

Hand the participant `consent.md`. Read the **bold** lines aloud. Answer questions. Then get the
signature (the paper copy stays with you, offline; the bundle keeps only `Consent: yes` and the
version). If they decline, thank them and stop — a declined session is not a failed session.

Verbatim:

> "Before we start: this is a short game study, about ten minutes. You'll type messages to a
> character and she answers in text. Her replies are generated by a small AI model running on
> this machine; nothing you type leaves this computer. The game is psychological horror — it is
> meant to be a little unsettling — and it has some flashing effects, which we can turn off. We
> record the game's own text transcript, your survey answers and my notes; we never record audio
> or video, and we never write your real name. You can stop at any time, for any reason, and you
> can ask me to delete everything from this session. Do you have any questions?"

If they ask "is she real?" or "is this an AI?": **"Play it and see — that's part of the study."**
Do not answer for the game.

---

## 4. Running the session

Each session runs on its own fresh `user://` profile, so the game's settings start at their
defaults. If the participant asked for reduced effects, use the **Photosensitive** row on the
title screen before they start.

Start the capture **before** the participant touches the keyboard:

```bash
# from the project root; the session id is generated and printed
tools/playtest/session.sh --name "<the name they plan to type, or leave it out>"
```

The script:

- creates `production/playtests/P2/human/<session-id>/` and seeds `survey.md`, `obs_sheet.md`
  and `session_log.md` from the templates in this folder;
- exports `LEILA_PLAYTEST_SESSION` and `LEILA_PLAYTEST_BUNDLE` for the game's environment;
- points the game's `user://` at `<bundle>/_userdata/` so the transcript for this session is
  isolated (the folder is gitignored);
- launches the game (debug export if present, else the dev run);
- tails the live transcript into `<bundle>/telemetry.jsonl` while the game runs. The first turn
  takes a few seconds to appear — the transcript file is only created when the first turn
  completes, and the script keeps watching for it.

Two terminals are fine: run `session.sh` in one and keep `serve.sh` in the other.

### 4.1 The opening — say exactly this

> "This is Leila-chan. You'll start a new game, type any name you like for your character — it
> doesn't have to be yours — and then just talk to her for about ten minutes. Type in the box at
> the bottom and press Enter to send. There are no right answers and nothing you can do wrong.
> If you want to stop at any point, just say stop. I'll be quiet over here; I'm taking notes, not
> judging you."

Then point at the screen and stop talking.

### 4.2 During the session

- **Do not** prompt topics, suggest lines, react to her lines, laugh first, or explain what just
  happened. Note it silently.
- **Do not** answer "is this real / is she an AI / is this a model". Use the line above.
- **Do not** mention bugs, or that a sprite "should" be different, until after the survey.
- This build has **no pause menu** (the Esc hook is wired but only emits a signal), so do not
  tell them Esc pauses. Closing the window always works (docs/05 §0) — if they close it early,
  that is a **quit**, not a failure: record it and still ask for the survey.
- Target **10:00** on the session stopwatch. Stop at 10:00, or when the date ends in-game,
  whichever comes first. Do not extend because it looks fun; do not stop at 7:00 because the
  conversation lulled.
- **Stuck turn:** if the input box stays locked or no character appears for **60 seconds**, say:
  > "The game seems stuck — that's not you. I'm going to restart the scene."
  Close the game, start a new `session.sh` run with a new id, and log the first one as a broken
  session. Do not silently continue in a stuck UI.

### 4.3 Safety exit

If the participant says stop, looks distressed, or asks to leave — **stop immediately**:

> "Of course. Stopping now."

Close the window with its own close button (never kill the process in front of them if a click
works), offer water and a minute, and remind them the character is fictional. If they ask to
delete the session, delete the whole bundle (`rm -rf production/playtests/P2/human/<id>`) and
write nothing about them anywhere except a one-line withdrawal count in your own notes. A
withdrawn session is not evidence and is not a failure.

### 4.4 Closing — say exactly this

> "That's the ten minutes — thank you, that was genuinely useful. Before you go, could you fill
> this in? It's five quick ratings and three short questions. There are no right answers, and
> 'it was fine' is a useful answer. I'll leave you alone with it."

Hand them `survey.md` (paper or the file in the bundle). Do not hover, do not explain the
questions beyond reading a row aloud, do not correct a score.

Then, once they are gone, fill `obs_sheet.md` (your timings and notes) and `session_log.md`
(operator log) **from memory while it is fresh** — within 10 minutes.

---

## 5. After each session — collect and check

```bash
# from the project root; <session-id> is the folder name session.sh printed
tools/playtest/collect.sh <session-id>
```

`collect.sh` copies the raw game transcripts into `<bundle>/raw/`, merges any turn the live tail
missed into `telemetry.jsonl` (deduplicated), renders a readable `<bundle>/transcript.md`, writes
`<bundle>/manifest.json` with sizes and sha256s, and then **validates the bundle**. It exits
non-zero and prints exactly what is still missing. Fix that, run it again. Do not hand-edit
`telemetry.jsonl` or the manifest.

Common validation failures and what they mean:

| Message | Fix |
|---|---|
| `survey.md: Face rating is missing or not 1-5` | The participant skipped a rating; ask them (in person or by message) before they leave. |
| `obs_sheet.md: Quit threat is missing (yes/no)` | Fill the row even when the answer is `no`. |
| `session_log.md: Consent is not 'yes'` | The participant did not consent; the session cannot be evidence. |
| `telemetry.jsonl: 0 turn records` | The server was down or the export is a release build; the session did not happen. |

---

## 6. The verdict

After all three sessions are collected:

```bash
python3 tools/playtest/score.py
# writes production/playtests/P2/human/RESULT.md and exits 0 only on PASS
```

The gate rule, from docs/09 §1 M1 exit criterion 1:

- **Survey mean** = the pooled mean of the three participants' **Face** and **Sound** ratings
  (six values, each 1–5). It must be **≥ 4.00**.
- **Broken turns** = the larger of the observer's count and the number of turn records whose
  status is not `completed` (failed/cancelled) across the three transcripts. It must be **0**.
- Three complete bundles are required. `score.py` exits 2 and writes nothing if one is missing.

`RESULT.md` also prints per-session charm/creepiness/play-again scores, latency medians from
the transcripts, and every free-text answer verbatim. Read the free text before quoting the
number; the number is the gate, the sentences are why.

---

## 7. What "done" looks like

- [ ] Three sibling folders in this directory, one per stranger, each `collect.sh`-valid.
- [ ] `RESULT.md` generated by `score.py`, containing `VERDICT: PASS` (or a documented FAIL with
      the reasons and quotes — a FAIL is also a result, and the honest one wins).
- [ ] No real names anywhere in the bundles; participant codes only.
- [ ] `_dryrun/` untouched and still labelled synthetic.
- [ ] The three folders and `RESULT.md` committed together; telemetry and raw transcripts included.

## 8. Privacy and evidence hygiene

- The bundle holds the game's text transcript, which includes whatever the participant typed.
  That is the evidence. Keep it in the repo; the repo is private.
- The paper consent forms and any real names stay with the facilitator, offline. The bundle stores
  only `Consent: yes`, the consent version and the participant code.
- Never put a participant's real name, contact details or anything they said about themselves in
  a journal, a handoff or a review. Quote the game transcript and the survey, not the person.
- `_userdata/` inside a bundle is the Godot user directory (settings, saves, the transcript the
  tail reads). It is gitignored; do not commit it, and do not delete it before `collect.sh` has
  copied `raw/`.
