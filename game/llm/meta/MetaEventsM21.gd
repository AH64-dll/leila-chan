class_name MetaEventsM21
extends Node
## docs/05 §1.3 M21–M26 — the text, input and UI events. Mounted by
## MetaDirector (`EFFECTS_PATHS`) as a child, so it shares the meta-event
## scheduler, its docs/05 §3 caps and its `meta_seen` ledger.
##
##   M21 deleted draft   R  St 1  Telemetry owns detection + the quote (its
##                              `draft_deleted` event, stage ≥ 3 quotes the exact
##                              words). This module only records the event in the
##                              Extras ledger when she is cleared to react — the
##                              draft itself never leaves Telemetry's memory.
##   M22 she types for you O mimic_player St 4  the input box fills with her
##                              suggestion and the player can always delete it.
##   M23 edited message  S  St 4 SPLIT/YANDERE  a sent line reads differently in
##                              the log; the original stays in the entry.
##   M24 rewritten history S St 4 SPLIT  the oldest lines of the log become her
##                              version of events.
##   M25 hide the UI     O hide_ui St 4  boxes vanish for one turn; any click or
##                              key restores them (docs/05 §0: Esc is untouched).
##   M26 settings sabotage S St 3  the volume slider shows +10% — a display lie,
##                              never a write: docs/05 §0 / D20 forbid touching a
##                              player's mix, text speed, reduced motion or
##                              photosensitive flag.
##
## Everything an event *shows* is resolved through `MetaLogEdits` or
## `ChatUI.apply_meta_ui`; this module owns the gates and the content, the UI
## owns the pixels. Docs/07 §2: the strings live in data/meta_events_m21.json,
## the constants below are the documented fallback.

## docs/05 §1.3: the ids this module answers to. `fire()` receives every landed
## meta event, so anything outside this list is somebody else's.
const IDS: Array[String] = ["M21", "M22", "M23", "M24", "M25", "M26"]
## docs/05 §3 "Never two in a row" is the scheduler's, not ours: S events go
## through poll_scripted() so MetaDirector charges the scene budget and the
## quiet turn exactly as it does for an offer.
const SCRIPTED_ORDER: Array[String] = ["M23", "M24", "M26"]
const DATA_PATH := "res://data/meta_events_m21.json"
## PauseMenu records that the player has seen the settings page at least once
## (`meta_settings_seen`); M26's lie only lands on someone who has a slider to
## remember, and the flag keeps the event out of a run that never opened it.
const SETTINGS_SEEN_FLAG := &"meta_settings_seen"
## Fallback mirroring the data file (docs/07 §2), so a missing or partial table
## still gates every event at its docs/05 stage with authored, safe text.
const DEFAULTS := {
	"m22":
	{
		"suggestions":
		["I'll never leave you.", "I love you.", "You're the only one.", "I'm staying."],
	},
	"m23":
	{
		"stage": 4,
		"paths": ["SPLIT", "YANDERE"],
		"chance": 0.35,
		"swaps": [["like", "love"], ["guess", "know"], ["maybe", "always"]],
		"prefix": "I love you. ",
		"note_line":
		"EVENT: A message the player sent earlier now reads differently in the chat log.",
	},
	"m24":
	{
		"stage": 4,
		"paths": ["SPLIT"],
		"chance": 0.25,
		"window": 4,
		"player_lines": ["I'll stay with you tonight.", "I'm not going anywhere."],
		"her_lines": ["You said you'd never leave.", "I told you I'd wait, and I did."],
		"note_line": "EVENT: You rewrote the beginning of the chat log.",
	},
	"m26":
	{
		"stage": 3,
		"paths": [],
		"chance": 0.4,
		"bus": "Music",
		"offset": 0.1,
		"note_line": "EVENT: The volume slider on the settings page moved up by itself.",
	},
}
const REGEX_SPECIAL := ".^$*+?()[]{}|\\"

var _data := {}
var _seed := 0
var _scene := ""
## One scripted roll per turn: the host polls `poll_scripted()` while it builds
## a turn, and the fallback path below must not roll the same turn twice.
var _polled_turn := -1
## "id:turn" → applied. A host that both polls and calls `fire()` (or a seam
## that connects the signal AND hooks `_fire`) can never double-apply an effect.
var _applied := {}
## UI effects that land when her line is fully on screen (input unlocked), not
## mid-stream: [{effect, text, turn}].
var _pending_ui: Array = []
## A sabotage the player has not opened the settings page to see yet.
var _sabotage := {}


func _ready() -> void:
	_load_data()
	# Autoload order puts Telemetry after MetaDirector, so the engine-event seam
	# is connected once the whole autoload ring exists (P2.09 owns the detector;
	# this module only listens).
	call_deferred(&"_connect_telemetry")


## docs/05 §1.3 M21: the deleted draft is the one event this module cannot fire
## itself — Telemetry detected it and already holds the words in memory. This
## only records the event for the Extras ledger, and only from the stage where
## she is cleared to react (docs/05 gate St 1); the quote at stage ≥ 3 stays
## Telemetry's (`draft_quote_stage`), so the words are never copied here.
func _connect_telemetry() -> void:
	var telemetry := _autoload("Telemetry")
	if telemetry == null or not telemetry.has_signal(&"engine_event"):
		return
	if telemetry.is_connected(&"engine_event", _on_engine_event):
		return
	telemetry.connect(&"engine_event", _on_engine_event)


func _on_engine_event(event: Dictionary) -> void:
	if String(event.get("event", "")) != "draft_deleted":
		return
	if int(GameState.stage) < int(event.get("stage_min", 1)):
		return
	_mark_seen("M21")


## Every landed meta event (offered or scripted), after MetaDirector charged its
## docs/05 §3 caps. Ids outside M21–M26 are ignored.
func fire(id: String, _action: String) -> void:
	if not IDS.has(id):
		return
	match id:
		"M22":
			_apply_once(id)
		"M25":
			_apply_once(id)
		_:
			# Scripted events are charged by the host, which then announces the
			# landing here — the effect is the same single call either way.
			_apply_once(id)


## A date scene started: MetaDirector already reset the scene budget. The live
## ChatUI is hooked here (it is created by the Date scene) so M22/M25 land when
## the input unlocks, and so a seam that never polls still gets its scripted
## rolls (the fallback checks `_polled_turn`).
func on_scene(scene_key: String) -> void:
	_scene = scene_key
	_polled_turn = -1
	call_deferred(&"_hook_chat_ui")


## docs/05 §1.3 S events: returns {} or {id, action, note}. MetaDirector charges
## the scene budget, the quiet turn and `meta_seen` before firing it, so this
## only decides *whether* a scripted event is due this turn. Deterministic per
## (seed, turn), like the offer lottery, so a replay of the same turns replays
## the same lies; `chance` is the data's per-turn draw.
func poll_scripted(stage: int) -> Dictionary:
	_polled_turn = int(GameState.turn)
	var due := _due_scripted(stage)
	if due.is_empty():
		return {}
	return {
		"id": String(due["id"]), "action": String(due["id"]).to_lower(), "note": _note(due["id"])
	}


## F3 (role checklist: every meta event reachable from the overlay). The shared
## generic block in DebugOverlay lists these ids and calls `debug_fire()`, which
## bypasses gates and caps like Telemetry.debug_fire — and never bypasses Safety:
## every string shown here is game-authored data, not model text.
func debug_ids() -> Array:
	return IDS.duplicate()


func debug_fire(id: String) -> bool:
	if OS.has_feature("release"):
		return false
	if id == "M21":
		var telemetry := _autoload("Telemetry")
		if telemetry == null or not telemetry.has_method("debug_fire"):
			return false
		return bool(telemetry.call("debug_fire", "draft_deleted"))
	if not IDS.has(id):
		return false
	var applied := _apply_now(id)
	if applied:
		_applied[_key(id)] = true
		_mark_seen(id)
	return applied


## Test/F3 view of the module's own state (the scheduler's budget belongs to
## MetaDirector.state()).
func state() -> Dictionary:
	return {
		"scene": _scene,
		"applied": _applied.keys(),
		"pending": _pending_ui.duplicate(true),
		"sabotage": _sabotage.duplicate(),
		"polled_turn": _polled_turn,
		"gate": _scripted_gate(),
	}


## Tests pin the lottery (MetaDirector.set_seed_base drives the offers; this is
## the S-event equivalent).
func set_seed_base(seed: int) -> void:
	_seed = seed


## ── Scripted events (docs/05 §1.3 mode S) ─────────────────────────────────


## The docs/05 §3 gate: stage, the doc's path condition, then the draw. A row
## whose effect cannot show anything (`_can_apply`) is skipped, so a wasted roll
## never costs the scene budget.
func _due_scripted(stage: int) -> Dictionary:
	for id: String in SCRIPTED_ORDER:
		var spec := _spec(id)
		if stage < int(spec.get("stage", 99)):
			continue
		if not _path_matches(spec):
			continue
		if not _roll(id, spec):
			continue
		if not _can_apply(id):
			continue
		return {"id": id}
	return {}


func _path_matches(spec: Dictionary) -> bool:
	var paths: Variant = spec.get("paths", [])
	if not (paths is Array) or (paths as Array).is_empty():
		return true
	return (paths as Array).has(String(GameState.path))


## Deterministic draw per (seed, turn, id): the same turn in a replay makes the
## same choice, and a suite that pins the seed pins the event.
func _roll(id: String, spec: Dictionary) -> bool:
	var chance := float(spec.get("chance", 0.0))
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("%d:%d:%s" % [_seed, int(GameState.turn), id]))
	return rng.randf() <= chance


## Whether the effect would show anything at all right now: nothing here may be
## charged (or told to her) when the log is empty or the settings page does not
## exist on this build.
func _can_apply(id: String) -> bool:
	match id:
		"M23":
			return _last_player_entry() != null
		"M24":
			var log_node := _chat_log()
			return log_node != null and int(log_node.call("entry_count")) >= _window()
		"M26":
			if not bool(GameState.get_flag(SETTINGS_SEEN_FLAG, false)):
				return false
			return _pause_menu() != null
		_:
			return true


## Fallback seam: if the host polls (the contract), this never runs ahead of it
## because `_polled_turn` proves the poll happened this turn. If a future
## MetaDirector seam has no poll, the roll happens when her line is on screen —
## the only moment the log is guaranteed settled.
func _on_turn_displayed() -> void:
	_apply_pending_ui()
	if _polled_turn == int(GameState.turn):
		return
	var stage := int(GameState.stage)
	var due := _due_scripted(stage)
	if due.is_empty():
		return
	var id := String(due["id"])
	if not _allowed_here(id, stage):
		return
	if not _apply_once(id):
		return
	_charge_fallback(id)


## The host's own cap gate when it exposes one (P3.09's seam); otherwise the
## `meta_seen` ledger is the only cap a scripted event carries here.
func _allowed_here(id: String, stage: int) -> bool:
	var host := get_parent()
	if host != null and host.has_method("_scripted_allowed"):
		return bool(host.call("_scripted_allowed", id, stage))
	return not MetaDirector.events_seen().has(id)


func _charge_fallback(id: String) -> void:
	var host := get_parent()
	if host != null and host.has_method("_fire_scripted"):
		host.call("_fire_scripted", id, _note(id), int(GameState.stage))
		return
	_mark_seen(id)
	var note := _note(id)
	if not note.is_empty():
		GameState.queue_event(note)


## ── M22 / M25: the UI half, queued for the end of her line ────────────────


## Both effects belong *after* her text: the docs/05 §1.3 wording is "your input
## box fills by itself" and "one turn with nothing between her and the player",
## and the input is locked until every beat is on screen. `fire()` therefore
## queues; `_on_turn_displayed` applies. `_apply_now` is the F3 path, which has
## no turn to wait for.
func _apply_once(id: String) -> bool:
	var key := _key(id)
	if _applied.has(key):
		return false
	var applied := false
	match id:
		"M22":
			applied = _queue_mimic()
		"M25":
			applied = _queue_hide()
		_:
			applied = _apply_now(id)
	if applied:
		_applied[key] = true
	return applied


func _apply_now(id: String) -> bool:
	var ui := _chat_ui()
	match id:
		"M22":
			return ui != null and bool(ui.call("apply_meta_ui", "mimic", _suggestion()))
		"M25":
			return ui != null and bool(ui.call("apply_meta_ui", "hide"))
		"M23":
			return _apply_m23()
		"M24":
			return _apply_m24()
		"M26":
			return _apply_m26()
	return false


func _queue_mimic() -> bool:
	var text := _suggestion()
	if text.is_empty():
		return false
	_pending_ui.append({"effect": "mimic", "text": text, "turn": int(GameState.turn)})
	_hook_chat_ui()
	return true


func _queue_hide() -> bool:
	_pending_ui.append({"effect": "hide", "text": "", "turn": int(GameState.turn)})
	_hook_chat_ui()
	return true


## Applies the queued UI effects once, and drops anything a broken turn left
## behind: an effect whose turn is more than one behind the live counter is
## stale (her line is long gone, and dropping it is the only safe outcome).
func _apply_pending_ui() -> void:
	var ui := _chat_ui()
	var turn := int(GameState.turn)
	for item: Variant in _pending_ui:
		var entry: Dictionary = item
		if turn - int(entry.get("turn", -1)) > 1:
			continue
		if ui != null:
			ui.call("apply_meta_ui", String(entry.get("effect", "")), String(entry.get("text", "")))
	_pending_ui.clear()


## docs/05 §1.3 M22: her suggestion, chosen deterministically per turn from the
## data. Game-authored on purpose — the sentence the player is invited to send
## must be reviewed content, never a fresh model line.
func _suggestion() -> String:
	var spec := _spec("M22")
	var list: Variant = spec.get("suggestions", [])
	if not (list is Array) or (list as Array).is_empty():
		return ""
	var items: Array = list
	var index := posmod(int(hash("%d:%d" % [_seed, int(GameState.turn)])), items.size())
	return str(items[index])


## ── M23 / M24: the log edits (original stays in the entry) ────────────────


## docs/05 §1.3 M23: the newest player line reads as her version. The rule table
## is data (word swaps first, then her prefix when nothing matched), and the row
## is a *display* override in MetaLogEdits — the entry keeps what the player
## typed, so Extras can restore it and the save never stores the lie.
func _apply_m23() -> bool:
	var log_node := _chat_log()
	if log_node == null:
		return false
	var entries: Array = log_node.call("get_entries")
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		if String(entry.get("speaker_key", "")) != "player":
			continue
		var original := String(entry.get("text", ""))
		if original.is_empty():
			continue
		var edited := _her_version(original)
		if edited == original:
			continue
		var recorded := MetaLogEdits.record(
			"M23", "player", original, int(entry.get("occurrence", 1)), edited
		)
		if recorded:
			log_node.call("rerender")
			return true
	return false


## The docs/05 §1.3 M23 content: "I love you" where you wrote "I like you".
## Whole-word, case-insensitive swaps from the data; when no word applies she
## still cannot resist, so her authored prefix goes in front of the line.
func _her_version(text: String) -> String:
	var spec := _spec("M23")
	var out := text
	var swaps: Variant = spec.get("swaps", [])
	if swaps is Array:
		for pair: Variant in swaps:
			if not (pair is Array) or (pair as Array).size() < 2:
				continue
			var pattern := "(?i)\\b%s\\b" % _escape_regex(str((pair as Array)[0]))
			var regex := RegEx.create_from_string(pattern)
			if regex == null:
				continue
			out = regex.sub(out, str((pair as Array)[1]), true)
	if out == text:
		out = String(spec.get("prefix", "")) + text
	return out


## docs/05 §1.3 M24: the beginning of the scroll-back becomes her version of
## events. The window is the oldest `window` entries — a scene the player has
## already read past — and both speakers are rewritten, because in her memory
## nobody said anything she did not like.
func _apply_m24() -> bool:
	var log_node := _chat_log()
	if log_node == null:
		return false
	var window := _window()
	var entries: Array = log_node.call("get_entries")
	if entries.size() < window:
		return false
	var spec := _spec("M24")
	var player_lines: Variant = spec.get("player_lines", [])
	var her_lines: Variant = spec.get("her_lines", [])
	if not (player_lines is Array) or not (her_lines is Array):
		return false
	var player_pool: Array = player_lines
	var her_pool: Array = her_lines
	if player_pool.is_empty() or her_pool.is_empty():
		return false
	var player_cursor := 0
	var her_cursor := 0
	var changed := 0
	for index in range(window):
		var entry: Dictionary = entries[index]
		var key := String(entry.get("speaker_key", "her"))
		var replacement := ""
		if key == "player":
			replacement = str(player_pool[player_cursor % player_pool.size()])
			player_cursor += 1
		else:
			replacement = str(her_pool[her_cursor % her_pool.size()])
			her_cursor += 1
		var original := String(entry.get("text", ""))
		if original.is_empty() or replacement == original:
			continue
		if MetaLogEdits.record("M24", key, original, int(entry.get("occurrence", 1)), replacement):
			changed += 1
	if changed > 0:
		log_node.call("rerender")
	return changed > 0


## ── M26: settings sabotage, display only ──────────────────────────────────


## docs/05 §1.3 M26 with docs/05 §0 + D20's limit: the slider *shows* +10%, and
## nothing is written. No accessibility value is touched — not the mix, not text
## speed, not reduced motion, not photosensitive — and the lie dies the moment
## the player touches the slider or reopens the page (PauseMenu owns that).
func _apply_m26() -> bool:
	var pause_menu := _pause_menu()
	if pause_menu == null:
		return false
	var spec := _spec("M26")
	var bus := StringName(str(spec.get("bus", "Music")))
	var offset := float(spec.get("offset", 0.1))
	if bool(pause_menu.call("showing_settings")):
		return bool(pause_menu.call("show_sabotaged_bus", bus, offset))
	_sabotage = {"bus": String(bus), "offset": offset}
	_hook_settings(pause_menu)
	return true


## The page may be closed when the event lands; the moved slider then waits for
## the next time the player opens Settings — which is exactly when they would
## notice. The request is one-shot: seeing it once is the whole beat.
func _hook_settings(pause_menu: Node) -> void:
	if not pause_menu.has_signal(&"settings_opened"):
		return
	if pause_menu.is_connected(&"settings_opened", _on_settings_opened):
		return
	pause_menu.connect(&"settings_opened", _on_settings_opened)


func _on_settings_opened() -> void:
	if _sabotage.is_empty():
		return
	var pause_menu := _pause_menu()
	if pause_menu == null:
		return
	var bus := StringName(str(_sabotage.get("bus", "Music")))
	var offset := float(_sabotage.get("offset", 0.1))
	_sabotage.clear()
	pause_menu.call("show_sabotaged_bus", bus, offset)


## ── Plumbing ──────────────────────────────────────────────────────────────


func _hook_chat_ui() -> void:
	var ui := _chat_ui()
	if ui == null or not ui.has_signal(&"turn_displayed"):
		return
	if ui.is_connected(&"turn_displayed", _on_turn_displayed):
		return
	ui.connect(&"turn_displayed", _on_turn_displayed)


func _chat_ui() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).get_first_node_in_group(&"chat_ui")


func _chat_log() -> Node:
	var ui := _chat_ui()
	if ui == null:
		return null
	var log_node: Variant = ui.get("chat_log")
	return log_node if log_node is Node else null


func _pause_menu() -> Node:
	return _autoload("PauseMenu")


func _autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree) or (loop as SceneTree).root == null:
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath(node_name))


func _last_player_entry() -> Variant:
	var log_node := _chat_log()
	if log_node == null:
		return null
	var entries: Array = log_node.call("get_entries")
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		if String(entry.get("speaker_key", "")) != "player":
			continue
		if not String(entry.get("text", "")).is_empty():
			return entry
	return null


func _window() -> int:
	return maxi(2, int(_spec("M24").get("window", 4)))


func _key(id: String) -> String:
	return "%s:%d" % [id, int(GameState.turn)]


func _mark_seen(id: String) -> void:
	var seen := MetaDirector.events_seen()
	if seen.has(id):
		return
	seen.append(id)
	GameState.set_flag(MetaDirector.SEEN_FLAG, seen)


func _note(id: String) -> String:
	return String(_spec(id).get("note_line", "")).strip_edges()


func _scripted_gate() -> Dictionary:
	var out := {}
	for id: String in SCRIPTED_ORDER:
		var spec := _spec(id)
		out[id] = {"stage": int(spec.get("stage", 99)), "chance": float(spec.get("chance", 0.0))}
	return out


func _spec(id: String) -> Dictionary:
	var section: Variant = _data.get(id.to_lower(), {})
	return section if section is Dictionary else {}


func _escape_regex(text: String) -> String:
	var out := ""
	for index in text.length():
		var character := text[index]
		if REGEX_SPECIAL.contains(character):
			out += "\\" + character
		else:
			out += character
	return out


## A fresh session (`GameState.reset()`): the per-turn dedupe, the queued UI
## effects and the un-seen sabotage belong to the session that ended.
func reset_session() -> void:
	_applied.clear()
	_pending_ui.clear()
	_polled_turn = -1
	_sabotage.clear()


## Test seam (MetaDirector.set_catalog's convention): pin gates, paths and text
## for a suite without touching the shipped table — a deterministic fire needs
## `chance: 1.0`, which no shipped row may carry (docs/05 §3 "rare, earned").
func set_data(document: Dictionary) -> void:
	_data = DEFAULTS.duplicate(true)
	_merge_data(document)


## The data file is content (docs/07 §2) and the constants are the fallback: a
## section missing from the file keeps its documented gate and text.
func _load_data() -> void:
	_data = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("MetaEventsM21: %s missing; using documented fallbacks" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		push_warning("MetaEventsM21: %s is not a JSON object; using fallbacks" % DATA_PATH)
		return
	_merge_data(parsed)


func _merge_data(document: Dictionary) -> void:
	for key: Variant in document:
		if str(key).begins_with("_"):
			continue
		var value: Variant = document[key]
		if value is Dictionary and (_data.get(str(key)) is Dictionary):
			var merged: Dictionary = (_data[str(key)] as Dictionary).duplicate(true)
			for inner: Variant in value:
				merged[str(inner)] = (value as Dictionary)[inner]
			_data[str(key)] = merged
		elif value is Dictionary:
			_data[str(key)] = (value as Dictionary).duplicate(true)
