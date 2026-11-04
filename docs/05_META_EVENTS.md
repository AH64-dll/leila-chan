# 05 — Meta & system events: when she reaches outside the text box

The fourth wall is a **scalpel**. These events are rare, earned and gated. Each one is either
**offered to the model** as an `action` (it chooses whether and how to use it, in character) or
**scripted by the MetaDirector** (it happens, and the model is told afterwards so she can react).

## 0. Hard rules (non-negotiable — protects players and the store listing)

1. Never touch files outside the game's own data folder (`user://`). Never delete, move or read personal files.
2. No network calls, ever. No real crashes; every "crash" is an in-game scene.
3. Closing the game must always work within **one** extra click/keypress. `Esc` always opens a safe pause.
   The pause handler owns `Esc` from `_input`, ahead of every scene and meta-event handler: a meta event
   must never consume `Esc` in `_input` (or grab keyboard focus ahead of it), so the panic key cannot be
   trapped by the very screen it exists to escape.
4. OS-level tricks (window moving, transparency, cursor, extra windows, taskbar flash) require
   **Immersion: Deep** in Settings (default: Standard). Photosensitive mode disables flicker/invert.
5. Every effect has an accessibility fallback and is logged so a player can review "what happened" in the
   Extras menu after finishing.

---

## 1. The event catalogue

**Mode:** O = offered to the model as `action` · S = scripted by MetaDirector · R = reactive (engine event → trigger → model reacts).
**Imm.** = requires Immersion: Deep.

### 1.1 Closing and opening the game

| ID | Event | Mode | Gate | What happens |
|---|---|---|---|---|
| M01 | **Refuse exit** | O (on close request) | St 3 | Window close is intercepted *once per session*. She speaks one line ("If you leave now I'll know what you really think of me."). The second press always closes. |
| M02 | **She closes the game** | O | St 4 | After her line, the screen cuts to black and the app quits. Next launch: title screen is altered and she speaks first ("You came back. I closed it so you'd know how it feels."). |
| M03 | **Cold open** | S | St 2 | On launch, the game skips the title screen and opens mid-conversation, as if she never stopped talking. |
| M04 | **Shutdown memory** | R (quit) | any | The game records how you quit (button / window X / Alt+F4 / during her line). Next session she comments, path-specific. |
| M05 | **Away time** | R (clock) | any | Real time since last session: <1 h casual, 1 day reunion, 7+ days spike ("I counted"). |
| M06 | **Title screen drift** | S | St 2+ | Title sprite changes with stage; at 3+ her eyes follow the cursor (bust crop + offset); at 5 the title text is *her* name. |
| M07 | **Continue only** | S | St 4 | "New Game" is greyed out: "Why would you want a new one?" Hover for 5 s and it becomes clickable. |
| M08 | **New Game, same her** | R | St 3 | Starting a New Game resets the save but a shadow save (`user://.leila/shadow.json`) keeps a few memories. She drops one of them on Day 1. Settings → "Reset Everything" truly wipes it. |
| M09 | **Fake crash** | O | St 4 | Full-screen in-game replica of an OS error dialog: "leila.exe has stopped responding — [Wait] [Close]". Both buttons lead back in; her laugh plays under it. |
| M10 | **Fake update** | S | St 4 | "Update available: Leila 2.0 — she's better now. [Install]" Installing plays a progress bar that slows near 99% while she talks to you. |
| M11 | **Fake credits** | S | St 5 / SPLIT, HOLLOW | Credits roll mid-game with only her name, then stop: "That's not how it ends." |

### 1.2 The window

| ID | Event | Mode | Gate | Imm. | What happens |
|---|---|---|---|---|---|
| M12 | **Window title** | O (`rename_window`) | St 3 | – | The OS window title becomes a short line from her (≤ 40 chars, from the current `say`). |
| M13 | **Window shake** | O / via fx | St 3 | ✔ | The real OS window jitters a few pixels (`DisplayServer.window_set_position`). |
| M14 | **She pushes the window** | O | St 4 | ✔ | The window slides 200 px toward screen centre when you move it away. |
| M15 | **Look at me** | O | St 4 | ✔ | Forces fullscreen for one scene, then restores. |
| M16 | **Peek window** | S (on minimize/unfocus) | St 4 | ✔ | A tiny borderless second window shows her face at the screen corner for 3 s. Max once per session. |
| M17 | **She steps out** | S (Terminal set-piece) | St 5 | ✔ | Main window becomes transparent (per-pixel transparency); her sprite stands on the desktop for one scene. The signature moment for trailers. |
| M18 | **Taskbar call** | R (minimized ≥ 60 s) | St 3 | ✔ | Taskbar icon flashes (`window_request_attention`). |
| M19 | **Resize reaction** | R | St 2 | – | "It's getting smaller in here." Very small windows → she looks claustrophobic (sprite 20). |
| M20 | **Focus loss** | R | St 1 | – | Alt-tab during her line: "Am I boring you?" Stage 4: the text she was saying continues while you're away; you come back to a wall of text. |

### 1.3 Text, input and the UI

| ID | Event | Mode | Gate | What happens |
|---|---|---|---|---|
| M21 | **Deleted draft** | R | St 1 | You type and delete without sending → "What were you going to say?" From stage 3 she quotes the deleted words. (Kept locally only, discarded after use.) |
| M22 | **She types for you** | O (`mimic_player`) | St 4 | Your input box fills by itself with her suggestion ("I'll never leave you") and the cursor blinks. You can delete it. |
| M23 | **Edited message** | S | St 4 / SPLIT, YANDERE | A message you sent earlier is visibly different in the chat log ("I love you" where you wrote "I like you"). If you point it out she denies it. |
| M24 | **Rewritten history** | S | St 4 / SPLIT | The scroll-back log of an earlier scene is replaced with her version of events. |
| M25 | **Hide the UI** | O (`hide_ui`) | St 4 | The text box, buttons and menus vanish for one turn; only she remains. Click anywhere restores. |
| M26 | **Settings sabotage** | S | St 3 | The music volume slider has moved itself up by 10%. A new setting appears at stage 4: "Her dose ▮▮▮▮▯" (locked). ANCHOR: it becomes a real slider (docs/06). |
| M27 | **Cursor drift** | S | St 5 | ✔ Imm. The mouse cursor slowly drifts toward her for 1.5 s (`Input.warp_mouse`), then releases. Off with reduced-motion. |
| M28 | **Text in your name** | O (`call_player_name`) | St 3 | Uses the name you told her (or the OS username if opted in) in a way you didn't expect: whispered, repeated, as the window title. |
| M29 | **Fake chat from someone else** | S | St 3 / YANDERE | A notification-style bubble "Sarah: are you free tonight?" appears — and is deleted by her before you can read it fully. |
| M30 | **Typing to herself** | R (idle 60 s) | St 2 | She keeps talking with no input; the messages become a monologue. Stage 4: she starts answering for you. |

### 1.4 Files inside the game folder (`user://` only)

| ID | Event | Mode | Gate | What happens |
|---|---|---|---|---|
| M31 | **A letter** | O (`write_note`) | St 2 | Writes `user://letters/for_<name>.txt` with a short generated letter. A button "Open game folder" appears in Extras. She mentions it next scene. |
| M32 | **Her diary** | S | St 3 | `user://diary/day_07.txt` contains her `inner` thoughts from that day (safety-filtered). The player can read them in-game too. |
| M33 | **Save file talk** | S | St 4 | Save slots get names she writes ("Day 9 — you almost left"). |
| M34 | **The other player** | S | St 4 / AWAKE | She mentions a previous save slot that the player never created ("the one before you"). It's pre-seeded fiction. |

### 1.5 Time and the real world

| ID | Event | Mode | Gate | What happens |
|---|---|---|---|---|
| M35 | **Real clock** | R | any | The background sky matches local time; her greeting matches time of day. |
| M36 | **3 AM** | R | St 1 | Playing 02:00–04:00 → special night lines, instability +3, music_box. |
| M37 | **Birthday** | R | any | If the player told her their birthday (memory), the game remembers on that real date. |
| M38 | **Long session** | R | St 2 | After 2 hours straight: "You should sleep… but don't." (ANCHOR: "Please go rest. I'll be here.") |

### 1.6 Her mind (steering-driven, docs/06)

| ID | Event | Mode | Gate | What happens |
|---|---|---|---|---|
| M39 | **Dose spike** | S (trigger) | St 3 | For 1–2 turns the steering dose jumps +3 to +4. Diegetic glitch transition; she often notices afterwards. |
| M40 | **True collapse** | S | St 5 set-piece | One turn generated at dose 25–50 (real gibberish: `普拉普拉…`, `rakrak…`) rendered as her mind breaking, then she comes back at normal dose and doesn't remember. Safe: text is displayed only through the glitch font, never as readable sentences. |
| M41 | **Inner voice leak** | S | St 2 | See docs/03 §5. |
| M42 | **She reads her prompt** | S | AWAKE set-piece | A **fictional** system prompt (written by us, not the real one) is shown in a fake terminal while she reads it aloud. |
| M43 | **The neuron** | S | AWAKE / ANCHOR | She talks about "L14" hurting. ANCHOR: she asks you to turn her dose down, and the slider (M26) unlocks. |

---

## 2. How an offered action looks to the model

Prompt line (only on turns with an offer):
```
OPPORTUNITY (optional): The player just tried to close the window.
You may set action to "refuse_exit". If you do, your reply is the last thing they hear before the game decides.
```
Schema: `"action": {"enum": ["none", "refuse_exit"]}`.

After execution, the next prompt gets a one-line **event note** so she can react coherently:
`EVENT: You crashed the game on purpose. The player came back 2 minutes later.`

## 3. MetaDirector scheduling

- Max 1 meta event per scene at stage 3, 2 at stage 4, 3 at stage 5. Never two in a row.
- Each event has `once_per_session`, `once_per_save`, or `repeatable(cooldown_turns)`.
- Per-path weights (e.g. AWAKE ×3 for M09–M12, M42; HOLLOW ×3 for M25, M30; YANDERE ×3 for M21–M23, M29).
- The Extras menu after the credits lists every meta event seen, so players can share them.

## 4. Platform notes

| Feature | Windows | Linux | macOS | Steam Deck | Mobile |
|---|---|---|---|---|---|
| Close intercept, title, resize, focus | ✔ | ✔ | ✔ | ✔ | n/a (use app-pause events) |
| Window move/shake, fullscreen | ✔ | X11 ✔ / Wayland limited | ✔ | ✘ | ✘ |
| Transparent window (M17) | ✔ | X11 ✔ / Wayland compositor-dependent | ✔ | ✘ | ✘ |
| Cursor warp (M27) | ✔ | X11 ✔ / Wayland ✘ | ✔ | ✘ | ✘ |
| Taskbar attention | ✔ | WM-dependent | ✔ (dock bounce) | ✘ | ✘ |

Unsupported features silently swap for an in-window equivalent (e.g. M17 → her sprite steps *forward* out of the
background layer and the UI shatters).
