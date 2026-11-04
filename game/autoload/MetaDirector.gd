extends Node
## MetaDirector — docs/05 meta/system events: what she may do outside the text
## box. Two parts share this node:
##
##   1. The docs/05 §1.1 M01 **refuse exit** seam (P2.10): the window close is
##      intercepted ONCE per session from the T10 row's stage gate upwards, she
##      gets the docs/05 §2 OPPORTUNITY that offers `refuse_exit`, and the
##      second press always closes.
##   2. The docs/05 §3 **offer scheduler** (P3.08): every turn it may open 0–2
##      offered actions from `data/meta_events.json`, each with the data's
##      OPPORTUNITY line (docs/02 §2.4: the model never picks a meta action on
##      its own, so the offer — and its reason — is the whole mechanism).
##
## docs/05 §0 hard rules — the reason every request this node does not hold
## quits immediately, and why the scheduler gates offers instead of running
## effects itself:
##   1. closing works within ONE extra press. Taking over `auto_accept_quit` is
##      what makes an intercept possible at all; an unheld request calls the
##      quit on the same press, so the default path is still one press.
##   2. `Esc` is untouched: this node reads no input, and `ChatUI`'s pause path
##      is unchanged.
##   3. The quit goes through one injected Callable, so a scripted test can
##      press close without ending the test run.
##   4. OS-level tricks are only ever *offered* while Settings says Immersion:
##      Deep. The class is `ACTION_CLASS` in code, not a row's self-description,
##      so dropping a declaration cannot exempt an effect; the offer is the gate
##      P3.09's effects will later check again.
##
## docs/05 §3 caps live in data/meta_events.json ("rules"): per-scene maxima,
## never two meta events in a row, and per-event `once_per_session` /
## `once_per_save` / `repeatable(cooldown_turns)`. once_per_save rides
## GameState's `meta_seen` flag so a resumed save cannot replay it; the seen
## list is also the Extras-menu record docs/05 §3 promises.

signal close_held  ## The session's first close request was held (M01).
signal offer_changed  ## An offer opened or was consumed.
signal event_fired(id: String, action: String)  ## A meta event landed (model took an offer).

const CLOSE_TRIGGER := "T10"
const EXIT_OFFER := "refuse_exit"
const DATA_PATH := "res://data/meta_events.json"
const SEEN_FLAG := &"meta_seen"
## docs/05 §2, verbatim: the reason the action is available. Testing showed the
## model never picks a meta action on its own (0%), so the offer is the whole
## mechanism (docs/02 §2.4). The gates data holds the line ("prompts live in
## data", docs/07 §2); this constant is the documented fallback, like
## Telemetry's event lines.
const OPPORTUNITY_LINE := (
	"OPPORTUNITY (optional): The player just tried to close the window. "
	+ 'You may set action to "refuse_exit". If you do, your reply is the last thing '
	+ "they hear before the game decides."
)
## docs/05 §1.1 M01 "Gate: St 3" — only for a catalogue that lost its T10 row.
const CLOSE_GATE_FALLBACK := 3
## docs/05 §3 "Never two in a row" is a hard rule: it is the fallback and the
## floor even if the data's `rules` block is unreadable.
const DEFAULT_RULES := {
	"max_offers_per_turn": 2,
	"per_scene_caps": {"3": 1, "4": 2, "5": 3},
	"default_scene_cap": 1,
	"never_two_in_a_row": true,
}
## docs/05 §0 rule 4: Deep-immersion tricks default to OFF. Settings owns the
## player-facing switch (P3.13); until then the scheduler reads it when present
## and treats "no setting" as Standard.
const IMMERSION_DEEP := "deep"
## docs/05 §0 rules 1–2, as data no catalogue row may carry: "never touch files
## outside user://", "no network calls, ever", "no real crashes". A row that
## sets one of these keys is malformed and is never offered, whatever its stage
## or caps say — the guard is here so a future event task cannot add a row that
## reaches outside the game, and so a reviewer can see the rule in code.
const FORBIDDEN_EFFECTS := {
	"network": "R2: no network calls, ever",
	"real_crash": "R2: no real crashes; every crash is an in-game scene",
	"delete_files": "R1: never delete the player's files",
	"move_files": "R1: never move the player's files",
	"read_personal_files": "R1: never read personal files",
}
## docs/05 §0: the effect class of every action the scheduler may offer, owned by
## CODE and not by the row. This is the authority for rules 1 and 4, so a row
## cannot leave a class by dropping a key (r1 SAF-1: deleting `immersion_deep`
## from M13 must not make an OS-level trick eligible under Standard) and a new
## action is refused until someone classes it here (r1 SAF-2: unclassified is a
## data error, never an in-window default). The Python contract pins the data's
## `immersion_deep` declarations to this table.
##   "os_deep"   a §0 rule-4 OS-level trick — window move/shake, fullscreen,
##               transparency, extra windows, taskbar flash, cursor. docs/05 §1.2
##               marks each of these "Imm. ✔".
##   "window"    the OS title bar only; docs/05 gives M12 no "Imm.", so rule 4
##               does not apply to it.
##   "write"     writes a file: §0 rule 1 — the row must declare `writes` inside
##               user://.
##   "quit"      quits the app on purpose after her line (docs/05 §1.1 M02); the
##               class is here so the behaviour is reviewed, not inferred.
##   "in_window" everything it does happens inside the game's own window.
const ACTION_CLASS := {
	"refuse_exit": ["in_window"],
	"rename_window": ["window"],
	"window_shake": ["os_deep"],
	"she_closes_game": ["quit"],
	"fake_crash": ["in_window"],
	"push_window": ["os_deep"],
	"look_at_me": ["os_deep"],
	"call_player_name": ["in_window"],
	"write_note": ["write"],
	"mimic_player": ["in_window"],
	"hide_ui": ["in_window"],
}
## The complete catalogue row vocabulary (docs/07 §2: the row is data, its shape
## is code). Any OTHER key is a hard failure: rules 1–2 must not be opt-in, so an
## effect the gate does not understand (`cursor_warp`, `reads`, a future
## `network_v2`) can never ride a row through on silence (r1 SAF-2).
const ROW_KEYS := [
	"meta",
	"stage",
	"repeat",
	"weights",
	"fallback",
	"note_line",
	"writes",
	"immersion_deep",
]
## docs/05 §0 rule 1: the only writable root the game has.
const USER_DIR := "user://"
## ── P3.09 meta-effect modules ─────────────────────────────────────────────
## The scheduler decides WHAT fires; a mounted module decides what the player
## sees for the events it owns (docs/05 §1.1–§1.2 M01–M12 live in the first
## entry). A path that does not exist mounts nothing, so a branch without that
## task's file keeps working; every hook is duck-typed, so a module implements
## only what it needs:
##   fire(id, action)                  after every cap is charged (O and S)
##   on_scene(scene_key)               date boundary, after the budget reset
##   poll_scripted(stage)              {} or {id, action, note} — charged here
##   set_scripted_hooks(allowed, fire) a module that schedules its own S events
##   set_quit_callable(cb)             M02's on-purpose quit, stubbable
##   debug_ids() / debug_fire(id)      the F3 overlay's demo buttons
const EFFECTS_PATHS: Array[String] = [
	"res://llm/meta/MetaEventsM01.gd",
	"res://llm/meta/MetaEventsM21.gd",  # P3.10 M21–M26
]

## M01 is once per session; the flags are cleared by GameState.reset().
var _held := false
var _refused := false
var _quit: Callable = Callable()

## Scheduler state (docs/05 §3). `_open_offers` is insertion-ordered
## {action: opportunity_line}; it holds at most `max_offers_per_turn` entries.
var _rules: Dictionary = DEFAULT_RULES.duplicate(true)
var _events: Dictionary = {}
var _open_offers := {}
var _rolled_turn := -1
var _rolled_offers: Array[String] = []
var _last_offered := {}  ## action → last turn it was offered (re-offer cooldown)
var _session_counts := {}
var _last_fired := {}
var _last_event_turn := -1
var _scene_key := ""
var _scene_events := 0
var _session_log: Array = []
var _seed_base := 0
## Mounted docs/05 §1.3 effect modules, in EFFECTS_PATHS order.
var _effects: Array = []
## Scripted S events are polled once per turn (the same turn boundary the offer
## lottery uses), so a run of `offers()` calls in one turn cannot roll twice.
var _polled_turn := -1
## docs/05 §2 event notes for SCRIPTED events: [{note, turn}]. They are merged
## by `turn_events()` while that turn is being built, because the clock greeting
## that arrives a turn late is not "her greeting matches the time of day". A
## note whose turn is behind the counter (an aborted turn) is pruned.
var _notes: Array = []


func _ready() -> void:
	load_catalog()
	_mount_effects()
	if GameState != null and not GameState.state_reset.is_connected(reset_session):
		GameState.state_reset.connect(reset_session)
	_take_over_close()
	_mount_effects()
	if get_tree() != null:
		_quit = Callable(get_tree(), "quit")


## docs/05 §1.1 M01: may THIS close request be held? Sets the state and queues
## the offer when it may. Pure with respect to the trigger engine: Telemetry's
## own close listener records the event and fires T10 in the same dispatch, and
## the row's `once` cap must not be what decides the first press.
func hold_close_requested() -> bool:
	if _held:
		return false  # the second press always closes (docs/05 §1.1 M01)
	if int(GameState.stage) < close_gate():
		return false
	# docs/05 §3: the close request is a meta event too, so a scene that already
	# spent its budget buys no intercept. The press then closes the game, which
	# is the one outcome docs/05 §0 rule 3 always allows — the cap can never
	# trap the player (r1 CODE-4 / DES-5 / SAF-3).
	if _scene_events >= scene_cap(int(GameState.stage)):
		return false
	_held = true
	_open_offer(EXIT_OFFER, _opportunity_line(EXIT_OFFER))
	close_held.emit()
	return true


## docs/05 §2: the offer sentence, from the gates data (TurnSchema reads
## data/stage_gates.json) with the documented fallback for M01, so a broken
## gates file still offers the action instead of silently dropping its line.
func _opportunity_line(action: String) -> String:
	var line := TurnSchema.opportunity_line(action)
	if not line.is_empty():
		return line
	return OPPORTUNITY_LINE if action == EXIT_OFFER else ""


## docs/05 §1.1 M01's gate, read from the T10 row (docs/07 §2: data, not code).
func close_gate() -> int:
	if Triggers != null and Triggers.has_method("stage_min_of"):
		var gate := int(Triggers.stage_min_of(CLOSE_TRIGGER))
		if gate >= 0:
			return gate
	return CLOSE_GATE_FALLBACK


## docs/02 §2.4: meta actions are offered, never free — 0–2 per turn. The enum
## is `["none"]` unless this returns action names. Rolling is the only side
## effect; the offer's reason is delivered separately by `turn_events()` so the
## sentence can never outlive the enum it explains.
func offers(stage: int) -> Array:
	if stage >= scheduler_stage_min():
		_poll_scripted(stage)
		_roll_schedule(stage)
	return _visible_offers(stage)


## docs/02 §2.4 / docs/05 §2: an offer's reason must ride the SAME turn as the
## enum that carries it. The Director merges these into the submit's `events`
## snapshot while building the turn (`build_turn_context`), because the
## pending-event queue drains at step 0 — before this turn's offers exist — so a
## queued line rode the NEXT submit with a different enum and was erased when
## the offer was taken (P3.08 r1 CODE-1/DES-1). Duplicates are dropped: an
## empty-say retry snapshots the same turn twice.
func turn_events(events: Array, stage: int) -> Array:
	var merged := events.duplicate()
	for action: String in _visible_offers(stage):
		var line := String(_open_offers[action])
		if not merged.has(line):
			merged.append(line)
	# Scripted (S) events have no offer sentence — their docs/05 §2 note is held
	# with the turn it happened in and rides this submit while it is current.
	for item: Variant in _notes:
		var note := str((item as Dictionary).get("note", ""))
		if not note.is_empty() and not merged.has(note):
			merged.append(note)
	return merged


## The offers the enum may carry right now, in open order. M01's offer only
## exists above the close gate, so a stage that lost the gate never sees a
## `refuse_exit` the schema's own gate would reject.
func _visible_offers(stage: int) -> Array:
	var out: Array = []
	for action: String in _open_offers:
		if action == EXIT_OFFER and stage < close_gate():
			continue
		out.append(action)
	return out


## docs/02 §4 step 7 / docs/05 §2: the model used an offer. One close request
## buys one refusal and one line; a scheduled action counts once toward the
## docs/05 §3 caps — the scene cap, the "never two in a row" turn, and the
## event's own session/save/cooldown counter. The docs/05 §2 event note is
## queued so the next prompt tells her what happened. Unknown actions are not
## consumed: `end_date` (and anything the catalogue does not own) stays free.
## `answered_turn` is the index of the turn the player answered (the Director's
## `_turn_index`, read BEFORE `apply_turn_meters()` advances the counter), so
## every cap counts PLAYER turns: an event that lands at the end of turn N makes
## turn N+1 the one quiet turn, not N+1 and N+2 (P3.08 r1 CODE-2/DES-2). A caller
## outside a turn (F3, a suite) passes nothing and means the current counter.
func execute_after_text(action: String, answered_turn: int = -1) -> void:
	if not _open_offers.has(action):
		return
	var turn := answered_turn if answered_turn >= 0 else int(GameState.turn)
	_rolled_offers.erase(action)
	_close_offer(action)
	# docs/05 §3: the scene budget is re-checked HERE and not only when the
	# roller offers. M01's offer outlives the scene it was opened in, so without
	# this a cap-1 stage-3 scene could fire a scheduled event and a `refuse_exit`
	# (r1 CODE-4/DES-5/SAF-3). The offer is consumed either way — the model
	# already said the line — but a spent scene gains no second event.
	if _scene_events >= scene_cap(int(GameState.stage)):
		push_warning("MetaDirector: %s not fired — the scene budget is spent" % action)
		return
	if action == EXIT_OFFER:
		_refused = true
	# M01 IS the meta event here (docs/05 §1.1): a taken offer counts against
	# the scene cap and starts the "never two in a row" quiet turn, like any
	# scheduled row.
	_fire(_event_id_for(action), action, turn)


## A scene (Date) is starting: the docs/05 §3 per-scene budget resets. Anything
## an offer promised before the scene boundary still counts against the scene
## it was *executed* in, which is the turn the player actually sees it.
func note_scene(scene_key: String = "") -> void:
	_scene_key = scene_key
	_scene_events = 0
	for module: Node in _effects:
		if module.has_method("on_scene"):
			module.call("on_scene", scene_key)


## Reads data/meta_events.json (docs/07 §2: content is data). A missing or
## broken file keeps the documented defaults — the M01 seam does not need the
## file, and an empty `events` block simply means the scheduler never offers.
func load_catalog() -> bool:
	_rules = DEFAULT_RULES.duplicate(true)
	_events = {}
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("MetaDirector: %s missing; scheduled offers disabled" % DATA_PATH)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		push_warning("MetaDirector: %s is not a JSON object; offers disabled" % DATA_PATH)
		return false
	var document: Dictionary = parsed
	var rules: Variant = document.get("rules")
	if rules is Dictionary:
		for key: Variant in rules:
			_rules[str(key)] = rules[key]
	var events: Variant = document.get("events")
	if events is Dictionary:
		for action: Variant in events:
			var spec: Variant = events[action]
			if spec is Dictionary:
				_events[str(action)] = (spec as Dictionary).duplicate(true)
	return true


## Test seam (docs/07 §2): replace the catalogue the way Triggers.set_catalog
## does, so a suite can retune caps without touching the shipped data. Same
## merge rules as `load_catalog()`.
func set_catalog(document: Variant) -> bool:
	if not (document is Dictionary):
		return false
	_rules = DEFAULT_RULES.duplicate(true)
	_events = {}
	var doc: Dictionary = document
	var rules: Variant = doc.get("rules")
	if rules is Dictionary:
		for key: Variant in rules:
			_rules[str(key)] = rules[key]
	var events: Variant = doc.get("events")
	if events is Dictionary:
		for action: Variant in events:
			var spec: Variant = events[action]
			if spec is Dictionary:
				_events[str(action)] = (spec as Dictionary).duplicate(true)
	return true


## docs/05 §1/§3: the scheduler's floor is the LOWEST gate in the catalogue, read
## from the rows themselves (`stage`, pinned to `stage_gates.offered_actions` by
## the data contract). One authority, so no row can be gated above its own entry
## — r1 CODE-5/DES-4: `gates.meta_min_stage`, the row gate and a separate
## `rules.scheduler_stage_min` disagreed and left M31's documented St 2
## unreachable. An empty catalogue offers nothing at any stage.
func scheduler_stage_min() -> int:
	var floor := -1
	for action: String in _events:
		var gate := int((_events[action] as Dictionary).get("stage", 0))
		floor = gate if floor < 0 else mini(floor, gate)
	return maxi(floor, 0)


## docs/05 §3: the most actions one prompt may offer.
func max_offers_per_turn() -> int:
	return maxi(0, int(_rules.get("max_offers_per_turn", 2)))


## docs/05 §3 "Max 1 meta event per scene at stage 3, 2 at stage 4, 3 at
## stage 5": the cap for THIS stage (clamped to the data's keys).
func scene_cap(stage: int) -> int:
	var caps: Variant = _rules.get("per_scene_caps", {})
	if caps is Dictionary:
		var table: Dictionary = caps
		for s: int in range(mini(stage, 5), -1, -1):
			var key := str(s)
			if table.has(key):
				return int(table[key])
	return int(_rules.get("default_scene_cap", 1))


## Whether THIS action may be scheduled at `stage` right now — the docs/05 §0
## and §3 gates in one place, so the roller and the F3 overlay agree.
func eligible(action: String, stage: int) -> bool:
	var spec: Variant = _events.get(action)
	if not (spec is Dictionary):
		return false
	var row: Dictionary = spec
	if stage < int(row.get("stage", 0)):
		return false
	if _opportunity_line(action).is_empty():
		return false  # docs/05 §2: no authored reason → never offered
	if not _hard_rule_violation(action).is_empty():
		return false  # docs/05 §0: the row asks for something forbidden
	if str(row.get("note_line", "")).strip_edges().is_empty():
		return false  # docs/05 §2: she is told afterwards, or it never ran
	return _cap_allows(action, row, stage)


## docs/05 §0, one check per rule, in the order the doc writes them. Returns ""
## when the row is legal at this moment, otherwise the rule and the reason — the
## F3 overlay shows it, `eligible()` refuses the offer, and a test can prove
## each rule against a deliberately broken row.
##   R0  the action is classed in `ACTION_CLASS` and the row speaks the
##       `ROW_KEYS` vocabulary — an unknown or unclassed effect is a hard
##       failure, never an in-window default (r1 SAF-2)
##   R1  files only under `user://`, never delete/move/read the player's own,
##       and a write-class action must declare its target
##   R2  no network, no real crash (a crash is an in-game replica)
##   R3  closing always works — structural: the close handler lives above and
##       `offers()`/`execute_after_text()` never touch it
##   R4  the OS-level class needs Immersion: Deep, and any non-"deep" value fails
##       closed to Standard. The class comes from `ACTION_CLASS`, so deleting a
##       row's `immersion_deep` cannot exempt it; the declaration can only ADD
##       the requirement (r1 SAF-1)
##   R5  every effect carries an accessibility fallback string (its in-window
##       swap, docs/05 §4); being logged for Extras is structural — `_fire()`
##   Rules the row itself cannot satisfy are data errors, so the row is never
##   offered rather than fixed up at runtime.
func _hard_rule_violation(action: String) -> String:
	var spec: Variant = _events.get(action)
	if not (spec is Dictionary):
		return "R0: not a catalogue row"
	var row: Dictionary = spec
	var classes: Variant = ACTION_CLASS.get(action)
	if not (classes is Array):
		return "R0: unclassified action (docs/05 §0)"
	var problem := ""
	for key: String in FORBIDDEN_EFFECTS:
		if bool(row.get(key, false)):
			problem = str(FORBIDDEN_EFFECTS[key])
			break
	if problem.is_empty():
		for key: Variant in row:
			if not ROW_KEYS.has(str(key)):
				problem = 'R0: unknown effect key "%s"' % str(key)
				break
	var writes := str(row.get("writes", "")).strip_edges()
	var writes_required := (classes as Array).has("write")
	if problem.is_empty() and writes_required and writes.is_empty():
		problem = "R1: a write effect must declare writes inside user://"
	if problem.is_empty() and not writes.is_empty() and not _inside_user_dir(writes):
		problem = "R1: %s writes outside user://" % writes
	var deep := (classes as Array).has("os_deep") or bool(row.get("immersion_deep", false))
	if problem.is_empty() and deep and not _immersion_is_deep():
		problem = "R4: an OS-level trick needs Immersion: Deep"
	if problem.is_empty():
		var fallback: Variant = row.get("fallback")
		if not (fallback is String) or (fallback as String).strip_edges().is_empty():
			problem = "R5: no accessibility fallback"
	return problem


## docs/05 §0 rule 1: a path is inside the game's own data folder when it uses
## the `user://` scheme and climbs nowhere. `res://` is readable data, never a
## write target, so it is not enough here.
func _inside_user_dir(path: String) -> bool:
	var normalised := path.strip_edges().replace("\\", "/").to_lower()
	if not normalised.begins_with(USER_DIR):
		return false
	for part: String in normalised.split("/"):
		if part == "..":
			return false
	return true


## F3 overlay seam (role checklist: every meta event is triggerable from F3).
## Opens the offer directly — gates/caps bypassed like Telemetry.debug_fire —
## so the reviewer can watch the enum, the line and execute_after_text without
## waiting for the lottery. The enum still caps at `max_offers_per_turn`.
func debug_offer(action: String) -> bool:
	if OS.has_feature("release"):
		return false
	var line := _opportunity_line(action)
	if line.is_empty():
		return false
	_open_offer(action, line)
	return _open_offers.has(action)


## The docs/05 §1 catalogue ids MetaDirector knows (F3 labels, Extras list).
func action_ids() -> Array[String]:
	var ids: Array[String] = []
	for action: String in _events:
		ids.append(action)
	ids.sort()
	return ids


## docs/05 §3: every meta event seen this save — the Extras "what happened"
## list and the once_per_save ledger. Read straight from the flag so a resumed
## save reports what the earlier session saw.
func events_seen() -> Array:
	var seen: Variant = GameState.get_flag(SEEN_FLAG, [])
	return (seen as Array).duplicate() if seen is Array else []


## The session log for the F3 overlay: [{id, action, turn, scene}].
func session_log() -> Array:
	return _session_log.duplicate(true)


## The F3 overlay and the tests read the whole event state in one call.
func state() -> Dictionary:
	return {
		"close_held": _held,
		"offer_open": not _open_offers.is_empty(),
		"open_offers": _open_offers.keys(),
		"exit_refused": _refused,
		"gate": close_gate(),
		"scene": _scene_key,
		"scene_events": _scene_events,
		"scene_cap": scene_cap(int(GameState.stage)),
		"last_event_turn": _last_event_turn,
		"session_counts": _session_counts.duplicate(),
		"events_seen": events_seen(),
		# docs/05 §0: rows the hard-rule gate refuses right now, so the overlay
		# shows "hide_ui → R5: no accessibility fallback" instead of silence.
		"hard_rule_violations": _all_hard_rule_violations(),
	}


## Every row with a docs/05 §0 violation at this moment ({action: reason}); an
## empty dict means the whole catalogue is legal as shipped.
func _all_hard_rule_violations() -> Dictionary:
	var out := {}
	for action: String in _events:
		var reason := _hard_rule_violation(action)
		if not reason.is_empty():
			out[action] = reason
	return out


## A fresh session (`GameState.reset()`, or a test): M01 may be held again and
## session-scoped caps reset. once_per_save rows stay spent — they live in the
## save's `meta_seen` flag, which a reset clears only on New Game. Effect
## modules get the same boundary: a replica on screen, a due scripted event or
## a cold-open flag is session state too, and a New Game (or a suite) must not
## inherit it — a leftover dialog swallows every click the next scene makes.
func reset_session() -> void:
	_held = false
	_refused = false
	_session_counts.clear()
	_last_fired.clear()
	_last_event_turn = -1
	_scene_key = ""
	_scene_events = 0
	_rolled_turn = -1
	_rolled_offers.clear()
	_last_offered.clear()
	_session_log.clear()
	_polled_turn = -1
	_notes.clear()
	for action: String in _open_offers.keys():
		_close_offer(action)
	for module: Object in _effects:
		if is_instance_valid(module) and module.has_method("reset_session"):
			module.call("reset_session")


## Test seam (docs/05 §0 rule 3): `quit_callable` runs instead of the tree's
## quit, so a scripted close request never terminates the test run.
func set_quit_callable(quit_callable: Callable) -> void:
	_quit = quit_callable


## Test seam: pin the lottery (Campaign's convention is per-(seed, turn) rng;
## this overrides the base for a deterministic suite).
func set_seed_base(seed: int) -> void:
	_seed_base = seed


func _take_over_close() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	if not tree.root.close_requested.is_connected(_on_close_requested):
		tree.root.close_requested.connect(_on_close_requested)
	# Only after the handler is connected: a window whose close nobody handles
	# would never close, which is the one thing docs/05 §0 forbids.
	tree.auto_accept_quit = false


func _on_close_requested() -> void:
	# Telemetry's listener may run before or after this one; the decision does
	# not depend on the order, only on this node's own once-per-session flag.
	if hold_close_requested():
		return
	_request_quit()


func _request_quit() -> void:
	if _quit.is_valid():
		_quit.call()
		return
	var tree := get_tree()
	if tree != null:
		tree.quit()


## Opens an offer and records its docs/05 §2 sentence; `turn_events()` delivers
## it on the turn whose enum carries it, so nothing is queued here. Two never
## means three: when the enum is full a scheduled offer waits for a free slot —
## EXCEPT M01's, which evicts the oldest scheduled offer instead. The close was
## already held (the player is owed her one line), and a dropped scheduled
## offer only ever means the lottery may pick again next turn.
func _open_offer(action: String, line: String) -> void:
	if _open_offers.has(action):
		return
	while _open_offers.size() >= max_offers_per_turn():
		if action != EXIT_OFFER:
			return
		var evicted := false
		for open: String in _open_offers.keys():
			if open != EXIT_OFFER:
				_close_offer(open)
				evicted = true
				break
		if not evicted:
			return
	_open_offers[action] = line
	offer_changed.emit()


## Consumes the offer, taking its docs/05 §2 sentence with it: the sentence is
## only ever delivered while the enum carries the action (`turn_events()`), so a
## taken, expired or reset offer can never leave a reason behind for a later
## prompt or the next session.
func _close_offer(action: String) -> void:
	if not _open_offers.has(action):
		return
	_open_offers.erase(action)
	offer_changed.emit()


## ── docs/05 §3 scheduling ─────────────────────────────────────────────────


## One roll per turn (keyed on GameState.turn — the same counter the meter
## budget uses, so tests that bump `turn` directly see the same boundary).
## A scheduled offer rides exactly the turn it was rolled for — an OPPORTUNITY
## is a "this turn" thing (docs/08 §6) — so the last turn's unused picks close
## here and wait one more turn before the lottery may offer them again; M01's
## offer stays open until used, because the held close is still held.
## "Never two in a row" blocks the roll entirely on the turn after an event:
## the offered action IS the event here, so the quiet turn applies to offers.
## `_last_event_turn` is the turn the player ANSWERED (see
## `execute_after_text()`), never the post-advance counter, so exactly one turn
## is quiet — "turn - last <= 1" is true for N+1 only, not N+1 and N+2 (r1
## CODE-2/DES-2).
func _roll_schedule(stage: int) -> void:
	var turn := int(GameState.turn)
	if _rolled_turn == turn:
		return
	var expired := _rolled_offers.duplicate()
	_rolled_turn = turn
	_rolled_offers = []
	for action: String in expired:
		if _open_offers.has(action):
			_close_offer(action)
			# It was offered on the previous turn; the candidate filter below
			# then skips it exactly once — an ignored offer never repeats on
			# the very next turn.
			_last_offered[action] = turn - 1
	if bool(_rules.get("never_two_in_a_row", true)):
		if _last_event_turn >= 0 and turn - _last_event_turn <= 1:
			return
	_poll_scripted(stage)
	var slots := max_offers_per_turn() - _open_offers.size()
	if slots <= 0:
		return
	var candidates: Array = []
	for action: String in _events:
		if _open_offers.has(action) or not eligible(action, stage):
			continue
		# docs/05 §3's scalpel, not a hammer: an offer the model ignored is not
		# repeated on the very next turn.
		if _last_offered.has(action) and turn - int(_last_offered[action]) <= 1:
			continue
		candidates.append({"action": action, "weight": _weight(action, stage)})
	# Deterministic per (campaign seed, turn), like Campaign._rng(): replaying
	# the day replays the same offers; tests pin it via set_seed_base().
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("%d:%d" % [_seed_base, turn]))
	while slots > 0 and not candidates.is_empty():
		# docs/05 §3, re-checked per offer: candidates are vetted before any
		# offer opens, so without this a cap-1 scene could reserve two (r1
		# CODE-4/DES-5). Reservations count; the execution check is the backstop.
		if _scene_events + _open_offers.size() >= scene_cap(stage):
			break
		var picked := _draw_weighted(candidates, rng)
		if picked.is_empty():
			break
		candidates.erase(picked)
		var action := String(picked["action"])
		_rolled_offers.append(action)
		_open_offer(action, _opportunity_line(action))
		slots -= 1


## Weighted draw without replacement: `weight` 0 rows stay in the candidate
## list but can only be drawn when nothing else can (never silently dropped —
## a zero base weight is a data error the F3 view should still show).
func _draw_weighted(candidates: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for c: Variant in candidates:
		total += float((c as Dictionary).get("weight", 0.0))
	if total <= 0.0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var roll := rng.randf() * total
	for c: Variant in candidates:
		roll -= float((c as Dictionary).get("weight", 0.0))
		if roll <= 0.0:
			return c
	return candidates.back()


## docs/05 §3: base weight 1 × the row's path multiplier (AWAKE ×3 for M09–M12
## & M42, HOLLOW ×3 for M25/M30, YANDERE ×3 for M21–M23/M29 — the shipped rows
## carry only what their entry documents).
func _weight(action: String, _stage: int) -> float:
	var spec: Dictionary = _events.get(action, {})
	var weight := 1.0
	var weights: Variant = spec.get("weights", {})
	if weights is Dictionary:
		weight *= float((weights as Dictionary).get(String(GameState.path), 1.0))
	return weight


## The docs/05 §3 cap kinds. `once_per_save` reads the persisted flag so a
## mid-save reload cannot replay the event; `once_per_session` and cooldowns
## are session state (cleared by reset_session).
func _cap_allows(action: String, row: Dictionary, stage: int) -> bool:
	var repeat: Variant = row.get("repeat", ["repeatable", 0])
	var kind := (
		str((repeat as Array)[0]) if repeat is Array and not repeat.is_empty() else "repeatable"
	)
	match kind:
		"once_per_save":
			if events_seen().has(_id_of(row, action)):
				return false
		"once_per_session":
			if int(_session_counts.get(action, 0)) > 0:
				return false
		_:
			var cooldown := (
				int((repeat as Array)[1]) if repeat is Array and repeat.size() > 1 else 0
			)
			if cooldown > 0 and _last_fired.has(action):
				if int(GameState.turn) - int(_last_fired[action]) < cooldown:
					return false
	# The scene cap governs EXECUTIONS: an offer is only made while the scene
	# still has room for it — open offers (M01's included) already count, since
	# the player may take every one of them this same turn.
	if _scene_events + _open_offers.size() >= scene_cap(stage):
		return false
	return true


func _event_id_for(action: String) -> String:
	if action == EXIT_OFFER:
		return "M01"  # the request-opened offer's catalogue id (docs/05 §1.1)
	var spec: Dictionary = _events.get(action, {})
	return _id_of(spec, action)


func _id_of(spec: Dictionary, action: String) -> String:
	return str(spec.get("meta", action))


## The event landed: charge every docs/05 §3 counter, log it for F3/Extras,
## and queue its docs/05 §2 note so she can react next turn. Every turn stamp
## here is `answered_turn` — the turn the player answered — so the cooldown and
## the quiet turn are measured in the same player turns the model sees (r1
## CODE-2: the post-`apply_turn_meters()` counter made "never two in a row"
## block two turns).
func _fire(id: String, action: String, answered_turn: int, note := "") -> void:
	_scene_events += 1
	_session_counts[action] = int(_session_counts.get(action, 0)) + 1
	_last_fired[action] = answered_turn
	_last_event_turn = answered_turn
	(
		_session_log
		. append(
			{
				"id": id,
				"action": action,
				"turn": answered_turn,
				"scene": _scene_key,
			}
		)
	)
	var seen := events_seen()
	if not seen.has(id):
		seen.append(id)
		GameState.set_flag(SEEN_FLAG, seen)
	# docs/05 §2: she is told afterwards. A scripted event passes its own note
	# (it has no catalogue row) and that note must ride the SAME turn — the
	# submit is already being built when `_poll_scripted()` fires it — so it is
	# held with its turn for `turn_events()` instead of the pending queue, which
	# the Director drained at step 0. Offered actions keep the queue.
	if not note.strip_edges().is_empty():
		_notes.append({"note": note.strip_edges(), "turn": int(GameState.turn)})
	else:
		var row_note := str(_events.get(action, {}).get("note_line", "")).strip_edges()
		if not row_note.is_empty():
			GameState.queue_event(row_note)
	event_fired.emit(id, action)
	for module: Node in _effects:
		if module.has_method("fire"):
			module.call("fire", id, action)


## docs/05 §1.3/§1.4 SCRIPTED events (mode S: "it happens"): once per turn the
## mounted modules may each propose one. The caps are the same ones an offer
## pays — the per-scene budget, "never two in a row" and the once-per-save
## ledger — so a scripted event can never exceed what the doc allows. A module
## may return `{"budget": false}` for ambient context (docs/05 M35's clock line):
## that is not a fourth-wall beat, so it lands without spending the scene's slot.
func _poll_scripted(stage: int) -> void:
	_prune_notes()
	if _events.is_empty():
		return  # a parked scheduler (a suite, an empty catalogue) runs no events
	var turn := int(GameState.turn)
	if _polled_turn == turn:
		return
	_polled_turn = turn
	for module: Node in _effects:
		if not module.has_method("poll_scripted"):
			continue
		var request: Variant = module.call("poll_scripted", stage)
		if not (request is Dictionary) or (request as Dictionary).is_empty():
			continue
		var req: Dictionary = request
		var id := str(req.get("id", "")).strip_edges()
		if id.is_empty():
			continue
		var action := str(req.get("action", id.to_lower()))
		var note := str(req.get("note", ""))
		if not bool(req.get("budget", true)):
			_fire(id, action, turn, note)
			return
		if _fire_scripted(id, note, stage):
			return  # one scripted event per turn; the quiet turn starts here


## docs/05 §3 gate for a scripted event: the scene budget is re-checked (offers
## already reserve their slots), the quiet turn applies exactly as it does to an
## offer, and the scripted ids are once per save (they have no catalogue row to
## declare a cap, and `meta_seen` is the ledger Extras shows).
func _scripted_allowed(id: String, stage: int) -> bool:
	if _scene_events + _open_offers.size() >= scene_cap(stage):
		return false
	if bool(_rules.get("never_two_in_a_row", true)) and _last_event_turn >= 0:
		if int(GameState.turn) - _last_event_turn <= 1:
			return false
	return not events_seen().has(id)


## Charges and lands a scripted event through `_fire()` — the one place every
## cap is incremented — and reports whether it landed (so a module can roll back
## an effect it applied optimistically).
func _fire_scripted(id: String, note: String, stage: int) -> bool:
	if not _scripted_allowed(id, stage):
		return false
	_fire(id, id.to_lower(), int(GameState.turn), note)
	return true


## Drops notes whose turn is behind the live counter: the submit they belonged
## to never happened (an aborted turn), and replaying them later would tell her
## about an event the player never saw.
func _prune_notes() -> void:
	var turn := int(GameState.turn)
	for index in range(_notes.size() - 1, -1, -1):
		if int((_notes[index] as Dictionary).get("turn", -1)) < turn:
			_notes.remove_at(index)


## docs/05 §0 rule 4: reads Settings when it carries an immersion level; any
## missing or non-"deep" value is Standard, so the default path never moves a
## window.
func _immersion_is_deep() -> bool:
	var settings := get_node_or_null("/root/Settings")
	if settings == null or not ("immersion" in settings):
		return false
	return str(settings.immersion).to_lower() == IMMERSION_DEEP


## ── P3.09 meta-effect modules ─────────────────────────────────────────────
## Mounted once, from `EFFECTS_PATHS`: a missing file mounts nothing, so this
## autoload never hard-depends on a task branch. Each module is a plain child
## Node named after its file; the hooks are duck-typed (see the const's list).
func _mount_effects() -> void:
	for path: String in EFFECTS_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			continue
		var module: Variant = script.new()
		if not module is Node:
			continue
		var node := module as Node
		node.name = path.get_file().get_basename()
		add_child(node)
		_effects.append(node)
		_wire_effect(node)


## The one host-side seam a module needs beyond fire/on_scene: M02's quit must
## go through this node's injected Callable (a suite stubs it), and a module
## that schedules its own S events gets the cap guard and the charging fire.
func _wire_effect(module: Node) -> void:
	if module.has_method("set_quit_callable"):
		module.call("set_quit_callable", Callable(self, "_request_quit"))
	if module.has_method("set_scripted_hooks"):
		module.call(
			"set_scripted_hooks",
			Callable(self, "_scripted_allowed"),
			Callable(self, "_fire_scripted")
		)

## docs/05 §3: a scripted (S) event costs the same budget as an offered one —
## the scene cap, the quiet turn and its own once-per-save ledger. A module
## cannot exceed the documented cap by firing on a scene boundary.

## Charges and fires one scripted event: `id` is both the catalogue id and the
## cap key, and `note` is its docs/05 §2 EVENT line (a scripted event has no
## catalogue row to take one from).

## One module poll per turn, before the offer roll: the first due S event wins
## and is charged here, so the offers that follow see the spent budget.
