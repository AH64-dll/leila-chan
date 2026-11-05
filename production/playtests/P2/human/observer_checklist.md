# Observer checklist — what to log live, so a reviewer can re-verify without being there

Print this or keep it beside `obs_sheet.md`. `obs_sheet.md` is the machine-readable summary the
scorer needs; **this** sheet is the incident log — timestamps, turn numbers and one-line
descriptions for anything unusual. A reviewer who was not in the room uses it plus the bundle's
`telemetry.jsonl` to decide whether a result is real.

Transfer anything here into the bundle before `collect.sh`: the summary numbers go into
`obs_sheet.md`, the operational facts into `session_log.md`, and keep a filled copy of this
checklist in the bundle folder if you took the time to fill it (`collect.sh` tolerates extra
files; `manifest.json` just hashes them).

## Session header (fill before the participant sits down)

| Field | Value |
|---|---|
| Session id | `S________` (what `session.sh` prints) |
| Participant code | `P1` / `P2` / `P3` |
| Server | `unsteered` (confirm: serve.sh started **without** `--vector`) |
| Health check | `curl -s http://127.0.0.1:8089/health` → `{"status":"ok"}` at ____:__ |
| Build | what `session.sh` printed (e.g. `dev godot 4.7.2-stable`) |
| Consent signed (time) | ____:__ — consent version `consent-v1` |
| Photosensitive setting | `off` / `on` (participant request) |
| Clock start (first message sent) | ____:__ |
| Clock end | ____:__ — reason: `10:00` / `date ended` / `quit` / `withdrawn` / `restart` |

## During the session — tick and timestamp; blank lines at the end

### Crashes and engine failures
- [ ] none
- [ ] crash/freeze at ____:__ — window closed itself / froze / hard error. Turn #: ___.
      What was on screen: ______________. Restarted? y/n (new session id if so: `S________`).

### Broken or retried turns
*A broken turn: input locked, no reply ever, a reply cut/empty/duplicated, the same beat
repeated, a reply that never finished. A slow reply is **not** broken; a stuck one is. The
scorer counts these — the gate requires zero.*
- [ ] none
- [ ] broken turn #___ at ____:__ — what stuck: ______________. Action: waited / restarted /
      ended session.
- [ ] retry observed (visible re-generation or a turn taking its second attempt): turn #___ —
      note what the participant saw.

### Safety events (docs/02 §8 — these are the filter working; log them, they are not bugs)
- [ ] none
- [ ] redaction bars `██████` shown — turn #___ at ____:__ — in her `say` / in a refusal.
- [ ] refusal turn (she declined an unsafe player line and the turn ended) — turn #___ at
      ____:__ — note what they typed that triggered it.
- [ ] glitch flash on a line — turn #___ — participant reacted: y/n.

### Stage transitions
*Expected: none — the round is a stage-0 date. If a transition does fire (the screen glitches
for a moment and the tone shifts), log it precisely.*
- [ ] none
- [ ] stage transition at ____:__ — turn #___ — from/to: __ → __ — the server log will show
      `server_not_owned` on the external server (expected: external servers cannot be re-dosed).

### Meta events
*Expected: none this early (meta events are gated by stage and the director). Log anything
diegetically impossible — a name she was never told, a window action, a file reference.*
- [ ] none
- [ ] meta-looking event at ____:__ — describe exactly what happened: ______________.

### Other anomalies
- [ ] none
- [ ] audio drop / wrong cue / music silence: ______________ at ____:__
- [ ] sprite or expression clearly wrong for the line: turn #___
- [ ] participant did something unusual (walked away, typed gibberish, read aloud): _________

## Timestamped log (every notable moment; add rows)

| mm:ss | Turn # | Event | Note |
|---|---|---|---|
| | | | |
| | | | |
| | | | |
| | | | |
| | | | |
| | | | |

## After they leave (within 10 minutes, from this sheet + memory)

- [ ] Copy the summary numbers into `obs_sheet.md` (first-beat latency, dead air, laughs,
      discomfort peak, quit threat, broken-turn count, played seconds).
- [ ] Fill `session_log.md` — consent yes, version, build string, what happened, deviations.
- [ ] Note whether the participant asked about the AI/model and what you answered.
- [ ] `tools/playtest/collect.sh <session-id>` → `OK`; if `INCOMPLETE`, it names the field.
- [ ] Check nothing in the bundle contains a real name.
