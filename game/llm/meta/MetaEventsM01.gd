class_name MetaEventsM01
extends Node
## MetaEventsM01 — docs/05 §1.1–§1.2 meta events **M01–M12**: what the player
## actually sees when one of them lands. `MetaDirector` owns the rules (offers,
## caps, docs/05 §0); this module owns the effect, the text and the one bit of
## state that has to outlive a session.
##
## docs/05 §1.1–§1.2 is the catalogue; every effect is one `match` arm in
## `fire()` or one decision below (M01 is MetaDirector's close seam, M06/M07 are
## `title_state()`, M04/M05 are the session-boundary note).
##
## docs/05 §0, one line per rule as the role checklist asks:
##   R1 writes: exactly one file, `user://.leila/meta_state.json` (below); no
##      read of any personal file, no delete or move of anything.
##   R2 no network call, no real crash: M09 is a `Control` drawn by this game.
##   R3 closing always works: nothing here reads input in `_input`, holds the
##      close request, or takes focus ahead of `PauseMenu`; M02 quits on purpose.
##   R4 no OS-level trick: the only window call is M12's title (docs/05 gives
##      M12 no "Imm."); nothing moves, resizes, hides or flashes the window.
##   R5 every effect has its documented fallback, and reduced motion is honoured
##      here: no fade (M02), no jolt (M09), still credits page (M11).
##
## PRIVACY — the only file any of this writes is `user://.leila/meta_state.json`,
## owned by MetaStateM01: the last-seen stamp (M05), how the player left (M04)
## and M02's "she closed it" marker. Its whole contents are documented there.
## Nothing else is stored, and nothing is ever read from outside `user://`.

## docs/05 §2: she is told what happened, addressed to her, never shown.
const NOTE_PREFIX := "EVENT: "
const MESSAGES_PATH := "res://data/meta_messages.json"
const DIALOGS_SCRIPT := "res://llm/meta/MetaDialogsM01.gd"
const SEEN_FLAG := &"meta_seen"
const META_IDS: Array[String] = [
	"M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "M09", "M10", "M11", "M12"
]
## docs/05 §1.1 gates that are not a catalogue row (S/R events).
const COLD_OPEN_STAGE := 2
const TITLE_DRIFT_STAGE := 2
const SHADOW_MEMORY_STAGE := 3
const UPDATE_STAGE := 4
const CREDITS_STAGE := 5
## docs/05 §1.1 M11 "St 5 / SPLIT, HOLLOW".
const CREDITS_PATHS: Array[String] = ["SPLIT", "HOLLOW"]
const HOUR_SECONDS := 3600
const DAY_SECONDS := 86400
## A gap longer than this is a moved clock, not a message from her.
const MAX_AWAY_SECONDS := 3650 * DAY_SECONDS
const BLACK_FADE_SECONDS := 0.8

## Test seams, the ShadowStore/SaveSystem convention: a suite points
## `store.path` at a scratch file and injects the clock, so one case can prove
## "8 days later" without waiting.
var store := MetaStateM01.new()
var clock: Callable = Callable()
## Whether an OS title bar exists on this platform (M12's fallback). Headless
## has none; a test flips it to prove the in-window fallback.
var title_bar_available := true
## How often a due scripted event (M10/M11) fires at a scene boundary. The roll
## is deterministic per (day, event, scene index) — the F3 demo bypasses it and
## a suite sets it to 1.0.
var scripted_chance := 0.34

var _messages := {}
var _state := {}
var _away_seconds := -1
var _last_quit := {}
var _quit_recorded := false
var _pending_method := ""
var _session_started := false
var _session_notes_done := false
var _scene_index := 0
var _cold_open := false
var _cold_open_fired := false
var _she_closed_pending := false
var _closing := false
var _pending_line := ""
var _due := {}
var _last_window_title := ""
var _last_demo := {}
var _dialogs: CanvasLayer = null
var _quit: Callable = Callable()
var _fire_scripted_hook: Callable = Callable()
var _allowed_hook: Callable = Callable()


func _ready() -> void:
	_messages = _load_messages()
	_state = store.load_state()
	_away_seconds = _measure_away()
	_last_quit = _dict_at(_state, "last_quit")
	_she_closed_pending = not _dict_at(_state, "she_closed").is_empty()
	title_bar_available = DisplayServer.get_name() != "headless"
	# Headless is CI/tests territory (the game ships as a windowed desktop app):
	# keep M10/M11's roll deterministic-off unless a suite opts in — a random
	# scripted replica would flake any suite that happens to call note_scene.
	if DisplayServer.get_name() == "headless":
		scripted_chance = 0.0
	var root := get_tree().root if get_tree() != null else null
	if root != null and not root.close_requested.is_connected(_on_close_requested):
		root.close_requested.connect(_on_close_requested)


## Any quit (M04): a window close, Alt+F4, the pause menu's Quit or the title's
## Quit all land here before the tree goes down, so the method is remembered
## while the menus are still readable. `MetaDirector` owns the actual quit.
func _on_close_requested() -> void:
	_pending_method = _infer_quit_method()


func _exit_tree() -> void:
	if _quit_recorded or _closing:
		return
	var method := _pending_method if not _pending_method.is_empty() else _infer_quit_method()
	_write_quit(method)


## ── The host contract (MetaDirector mounts this node as its child) ────────


## M02 quits on purpose after her line. The callable is `MetaDirector`'s own
## quit path, so a suite that stubs the close handler never ends the test run.
func set_quit_callable(quit_callable: Callable) -> void:
	_quit = quit_callable


## docs/05 §3: a scripted (S) event costs the same per-scene budget as an
## offered one, so the host passes its private guard and charging fire rather
## than this module keeping a second copy of the cap arithmetic.
func set_scripted_hooks(allowed: Callable, fire_scripted: Callable) -> void:
	_allowed_hook = allowed
	_fire_scripted_hook = fire_scripted


## Every landed meta event, after `MetaDirector` has charged its caps. Ids this
## module does not own are ignored, so the three meta modules can share a host.
func fire(id: String, _action: String) -> void:
	if not META_IDS.has(id):
		return
	match id:
		"M02":
			_effect_she_closes()
		"M03":
			_speak_when_idle(String(_msg("cold_open").get("line", "")))
		"M08":
			_effect_shadow_memory()
		"M09":
			_effect_fake_crash()
		"M10":
			_effect_fake_update()
		"M11":
			_effect_fake_credits()
		"M12":
			_effect_window_title()
		_:
			# M01's line is the model's own; M04/M05 are session notes delivered
			# at the boundary; M06/M07 live on the Title screen.
			pass


## A date scene began (docs/05 §3 scene budget already reset). Everything
## session-scoped happens exactly here: M04/M05's note, M03's cold open, M08's
## shadow memory and the M10/M11 roll.
func on_scene(_scene_key: String) -> void:
	_scene_index += 1
	_begin_session()
	_touch_last_seen()
	_fire_cold_open()
	_deliver_session_notes()
	_fire_shadow_memory()
	_fire_scripted_candidates()


## The host polls this once per turn; a due S event is charged and fired by the
## host. Normally `on_scene` already fired it directly through the hooks — this
## is the fallback for a host that only polls.
func poll_scripted(_stage: int) -> Dictionary:
	if _due.is_empty():
		return {}
	var due := _due.duplicate()
	_due = {}
	return due


## The F3 overlay's demo buttons: one per docs/05 §1.1–§1.2 event this task owns.
func debug_ids() -> Array:
	return META_IDS.duplicate()


## Demo one event from the F3 overlay (dev builds only, like
## `MetaDirector.debug_offer`): the effect is shown without charging the scene
## budget, so a reviewer can walk all twelve in one scene. Cross-session effects
## (M02's marker, M04's record) are performed, because they *are* the effect.
## The result string is exposed through `state()["last_demo"]`.
func debug_fire(id: String) -> bool:
	if OS.has_feature("release") or not META_IDS.has(id):
		return false
	var result := MetaDemoM01.run(self, id)
	_last_demo = {"id": id, "detail": String(result.get("detail", ""))}
	return bool(result.get("ok", false))


## ── Title screen (M02 / M06 / M07) ────────────────────────────────────────


## Everything `Title.gd` needs in one read: stage to drift at, sprite, eye
## follow, her-name title, M02's line and M07's lock. Reading the M02 line is
## what shows it, so the marker is consumed here — the title shows once.
func title_state() -> Dictionary:
	return _title_state(true)


## M03 (Boot): may this launch skip the title screen? Needs a readable save at
## docs/05's St 2 gate, and it happens once per save (`meta_seen`).
func cold_open_requested() -> bool:
	if _cold_open or _cold_open_fired or _seen().has("M03"):
		return false
	if _latest_save_stage() < COLD_OPEN_STAGE:
		return false
	_cold_open = true
	return true


## M04's store. Public because the Title's Quit is not a window close (it calls
## `get_tree().quit()` directly) and has to say how the player left; tests call
## it too. Writes `last_quit` + `last_seen` and never anything else.
func record_quit(method: String) -> void:
	_write_quit(method)


## The whole module's live state in one call (the F3 overlay and the suites).
func state() -> Dictionary:
	return {
		"ids": META_IDS,
		"away_seconds": _away_seconds,
		"last_quit": _last_quit.duplicate(),
		"she_closed_pending": _she_closed_pending,
		"cold_open": _cold_open,
		"cold_open_fired": _cold_open_fired,
		"title": _title_state(false),
		"last_window_title": _last_window_title,
		"dialog": _dialog_id(),
		"last_demo": _last_demo.duplicate(),
		"seen": _seen(),
	}


## A fresh save or session (`GameState.reset()`, a New Game, a suite): forget
## the in-memory session facts and re-read the state file. The file itself is
## kept — M02/M04's memory is cross-session by design.
func reset_session() -> void:
	dismiss()
	_state = store.load_state()
	_away_seconds = _measure_away()
	_last_quit = _dict_at(_state, "last_quit")
	_she_closed_pending = not _dict_at(_state, "she_closed").is_empty()
	_session_started = false
	_session_notes_done = false
	_cold_open = false
	_cold_open_fired = false
	_quit_recorded = false
	_closing = false
	_pending_line = ""
	_due = {}
	_scene_index = 0
	_last_demo = {}


## Takes whatever replica is on screen away (tests, and a scene change).
func dismiss() -> void:
	if _dialogs != null and is_instance_valid(_dialogs):
		_dialogs.dismiss()


## The M05 sentence for a measured gap (the F3 demo shows it without waiting),
## so the three buckets stay in one place.
func describe_away(seconds: int) -> String:
	return _away_fact(seconds)


## The F3 / suite lookup: the mounted module under a MetaDirector host. Static
## so a scene (Title, Boot) can find it without a second autoload.
static func find(host: Node) -> Node:
	if host == null:
		return null
	for child: Node in host.get_children():
		if child.has_method("title_state") and child.has_method("fire"):
			return child
	return null


## docs/05 §1.1 M04's four documented ways to leave, as a pure decision so the
## priority is testable without a window: a line in flight outranks the menu,
## the menu outranks the shortcut, and a bare close is the X.
static func quit_method(turn_open: bool, menu_open: bool, alt_held: bool) -> String:
	if turn_open:
		return "during_line"
	if menu_open:
		return "button"
	if alt_held:
		return "alt_f4"
	return "window_x"


## ── Effects ───────────────────────────────────────────────────────────────


## M02: "after her line, the screen cuts to black and the app quits. Next
## launch: title screen altered and she speaks first." The marker is written
## before the quit, so a hard kill still leaves her a memory to open with.
func _effect_she_closes() -> void:
	if _closing:
		return
	_closing = true
	_write_she_closed()
	var dialogs := _dialogs_node()
	if dialogs == null or DisplayServer.get_name() == "headless":
		_request_quit()
		return
	if not dialogs.black_out_finished.is_connected(_on_black_out):
		dialogs.black_out_finished.connect(_on_black_out, CONNECT_ONE_SHOT)
	dialogs.fade_to_black(BLACK_FADE_SECONDS, _reduced_motion())


func _on_black_out() -> void:
	_request_quit()


## M08: one fact from the shadow save, said out loud on Day 1 (docs/05 §1.1).
## Stored model text goes through Safety before it is displayed (docs/02 §8).
func _effect_shadow_memory() -> void:
	var memories := _shadow_memories()
	if memories.is_empty():
		return
	var line := str(_msg("shadow_memory").get("line", ""))
	if line.is_empty():
		return
	_speak_when_idle(line.format({"memory": String(memories[0])}))


## M09: the replica. Every button leads back in; her laugh plays under it.
func _effect_fake_crash() -> void:
	var texts := _msg("fake_crash")
	_play_engine_cue(str(texts.get("cue", "")))
	var dialogs := _dialogs_node()
	if dialogs != null:
		dialogs.show_crash(texts, _reduced_motion())


func _effect_fake_update() -> void:
	var dialogs := _dialogs_node()
	if dialogs != null:
		dialogs.show_update(_msg("fake_update"), _reduced_motion())


func _effect_fake_credits() -> void:
	var dialogs := _dialogs_node()
	if dialogs != null:
		dialogs.show_credits(_msg("fake_credits"), _reduced_motion())


## M12: the OS window title becomes a short line from her current `say`
## (docs/05 §1.2, ≤ 40 chars). Model text, so Safety first (docs/02 §8); no
## title bar (mobile, kiosk) takes the documented in-window fallback.
func _effect_window_title() -> void:
	var row := _msg("window_title")
	var line := _current_say()
	if line.strip_edges().is_empty():
		return
	var limit := maxi(8, int(row.get("max_chars", 40)))
	var short := _shorten(_scan(line), limit)
	if short.strip_edges().is_empty():
		return
	if title_bar_available:
		DisplayServer.window_set_title(short)
		_last_window_title = short
		return
	var format := str(row.get("fallback_format", "{line}"))
	var text := format.format({"line": short})
	_post_system_line(str(row.get("fallback_speaker", "system")), text)
	_last_window_title = short


## ── Scripted (S) events ───────────────────────────────────────────────────


func _fire_cold_open() -> void:
	if not _cold_open or _cold_open_fired:
		return
	_cold_open_fired = true
	# She "never stopped talking": a cold open is not a reunion, so M04/M05's
	# gap lines stay unsaid for this launch (one event at a time).
	_session_notes_done = true
	_request_scripted("M03", String(_msg("cold_open").get("note", "")))


func _fire_shadow_memory() -> void:
	if int(GameState.day) != 1 or int(GameState.turn) != 0:
		return
	if int(GameState.stage) < SHADOW_MEMORY_STAGE or _seen().has("M08"):
		return
	if _shadow_memories().is_empty():
		return
	_request_scripted("M08", String(_msg("shadow_memory").get("note", "")))


func _fire_scripted_candidates() -> void:
	var stage := int(GameState.stage)
	if stage >= UPDATE_STAGE and not _seen().has("M10") and _roll_allows("M10"):
		if _request_scripted("M10", String(_msg("fake_update").get("note", ""))):
			return
	if _seen().has("M11"):
		return
	var credits_gate := stage >= CREDITS_STAGE or CREDITS_PATHS.has(String(GameState.path))
	if credits_gate and _roll_allows("M11"):
		_request_scripted("M11", String(_msg("fake_credits").get("note", "")))


## M10/M11 are scripted, not offered, and the docs call them rare: the roll is
## deterministic per (day, event, scene) instead of firing at every boundary.
func _roll_allows(id: String) -> bool:
	if scripted_chance >= 1.0:
		return true
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("%d:%s:%d" % [int(GameState.day), id, _scene_index]))
	return rng.randf() < scripted_chance


## Charge and fire one S event through the host. Without the hooks the fallback
## reads the public budget and `meta_seen`, so an S event still cannot exceed
## docs/05 §3 — it just cannot close the scene counter itself.
func _request_scripted(id: String, note: String) -> bool:
	if _fire_scripted_hook.is_valid():
		var fired := bool(_fire_scripted_hook.call(id, note, int(GameState.stage)))
		if not fired:
			_due = {"id": id, "action": id, "note": note}
		return fired
	if _seen().has(id):
		return false
	if _allowed_hook.is_valid() and not bool(_allowed_hook.call(id, int(GameState.stage))):
		_due = {"id": id, "action": id, "note": note}
		return false
	var host := get_parent()
	if host != null and host.has_method("state"):
		var view: Dictionary = host.call("state")
		if int(view.get("scene_events", 0)) >= int(view.get("scene_cap", 0)):
			_due = {"id": id, "action": id, "note": note}
			return false
	_mark_seen([id])
	if not note.strip_edges().is_empty():
		GameState.queue_event(NOTE_PREFIX + note.strip_edges())
	fire(id, id)
	return true


## ── M04 / M05: the session boundary ───────────────────────────────────────


## Once per session, on the first date: one docs/05 §2 note carrying the clock
## (M05), how they left (M04) and the current path's clause — M04's comment is
## path-specific (docs/05 §1.1), so the clause rides the same sentence.
func _deliver_session_notes() -> void:
	if _session_notes_done:
		return
	_session_notes_done = true
	var method := str(_last_quit.get("method", ""))
	var note := session_note_preview(_away_seconds, method)
	if note.is_empty():
		return
	GameState.queue_event(NOTE_PREFIX + note)
	var ids: Array[String] = []
	if _away_seconds >= 0 and not _away_fact(_away_seconds).is_empty():
		ids.append("M05")
	if not method.is_empty() and not _quit_clause(method).is_empty():
		ids.append("M04")
	_mark_seen(ids)


## The preview the F3 demo shows for M04/M05 and the sentence the next
## session's note carries: one composer, so a demo can never describe something
## the game would not actually say. `away` < 0 means "no measured gap".
func session_note_preview(away: int, method: String) -> String:
	var parts: Array[String] = []
	if away >= 0:
		var fact := _away_fact(away)
		if not fact.is_empty():
			parts.append(fact)
	var clause := _quit_clause(method)
	if not clause.is_empty():
		parts.append(clause)
	if parts.is_empty():
		return ""
	var path_clause := _path_clause()
	if not path_clause.is_empty():
		parts.append(path_clause)
	return " ".join(parts)


func _away_fact(away: int) -> String:
	var bucket := _away_bucket(away)
	var row := _dict_at(_dict_at(_msg("away_time"), "buckets"), bucket)
	var note := str(row.get("note", "")).strip_edges()
	if note.is_empty():
		return ""
	return note.format({"duration": human_duration(away), "days": _days_of(away)})


## docs/05 §1.1 M05's three buckets: "<1 h casual, 1 day reunion, 7+ days
## spike". The last bucket is the catch-all, so a broken file still answers.
func _away_bucket(away: int) -> String:
	var buckets := _dict_at(_msg("away_time"), "buckets")
	for key: String in ["casual", "reunion", "spike"]:
		var row := _dict_at(buckets, key)
		var under := int(row.get("under_seconds", 0))
		if under > 0 and away < under:
			return key
	return "spike"


func _quit_clause(method: String) -> String:
	return str(_dict_at(_msg("shutdown_memory"), "methods").get(method, ""))


func _path_clause() -> String:
	return str(_dict_at(_msg("shutdown_memory"), "paths").get(String(GameState.path), ""))


func _days_of(away: int) -> String:
	return str(maxi(1, away / DAY_SECONDS))


## "40 minutes" / "3 hours" / "2 days" — the gap in the words the note uses.
static func human_duration(seconds: int) -> String:
	if seconds < 60:
		return "%d seconds" % maxi(1, seconds)
	if seconds < HOUR_SECONDS:
		return "%d minutes" % maxi(1, seconds / 60)
	if seconds < DAY_SECONDS:
		var hours := seconds / HOUR_SECONDS
		return "%d hour%s" % [hours, "" if hours == 1 else "s"]
	var days := seconds / DAY_SECONDS
	return "%d day%s" % [days, "" if days == 1 else "s"]


## ── Title decisions ───────────────────────────────────────────────────────


func _title_state(mark_as_seen: bool) -> Dictionary:
	var stage := _title_stage()
	var drift := _msg("title_drift")
	var sprite := str(_dict_at(drift, "sprites").get(str(stage), ""))
	var closed := _she_closed_pending
	var line := str(_msg("she_closed").get("line", "")) if closed else ""
	var lock := _msg("continue_only")
	var locked := stage >= int(lock.get("from_stage", 4))
	var view := {
		"stage": stage,
		"sprite": sprite,
		"eyes_follow": stage >= int(drift.get("eyes_follow_from", 3)) and not sprite.is_empty(),
		"eyes_offset_px": int(drift.get("eyes_offset_px", 2)),
		"title_text":
		str(drift.get("her_name_title", "")) if stage >= int(drift.get("her_name_from", 5)) else "",
		"she_closed": closed,
		"line": line,
		"subtitle": str(_msg("she_closed").get("subtitle", "")) if closed else "",
		"new_game_locked": locked,
		"lock_line": str(lock.get("line", "")),
		"unlock_seconds": float(lock.get("unlock_seconds", 5.0)),
	}
	if mark_as_seen:
		if stage >= TITLE_DRIFT_STAGE and not sprite.is_empty():
			_mark_seen(["M06"])
		if locked:
			_mark_seen(["M07"])
		if closed:
			_consume_she_closed()
	return view


## M06/M07 are St 2+/St 4 on a screen that outlives the run: `GameState.stage`
## is 0 after a relaunch, so the gate falls back to the shadow's `last_stage`
## when no run is in progress — P3.14's shadow-name rule (live if running,
## stored otherwise).
func _title_stage() -> int:
	var live := int(GameState.stage)
	if ShadowStore.has_run(GameState.day, GameState.turn, live):
		return live
	var save := get_node_or_null("/root/SaveSystem")
	if save != null and save.has_method("shadow_data"):
		var shadow: Variant = save.call("shadow_data")
		if shadow is Dictionary:
			return maxi(live, int((shadow as Dictionary).get("last_stage", 0)))
	return live


func _latest_save_stage() -> int:
	var save := get_node_or_null("/root/SaveSystem")
	if save == null or not save.has_method("latest_slot") or not save.has_method("list_slots"):
		return 0
	var latest := str(save.call("latest_slot"))
	if latest.is_empty():
		return 0
	var rows: Variant = save.call("list_slots")
	if not rows is Array:
		return 0
	for row: Variant in rows as Array:
		if not row is Dictionary:
			continue
		var entry := row as Dictionary
		if str(entry.get("slot", "")) == latest and bool(entry.get("ok", false)):
			return int(entry.get("stage", 0))
	return 0


## ── Speaking, scanning, cues ──────────────────────────────────────────────


## Her line, once the conversation is idle: the ChatUI's own beat API
## (`begin_turn_wait` → beats → `end_turn`), the path the Date's opening beats
## take, so input locking and the typewriter stay consistent.
func _speak_when_idle(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	var chat := _chat_ui()
	if chat == null:
		return
	# A scene's own greeting comes first: `note_scene()` runs before
	# `play_opening_beats()`, and speaking now would be wiped by that call's
	# `begin_turn_wait()` (it resets the text box). The Date's public
	# `is_opening_finished()` is the same boundary its own beats use.
	var scene := get_tree().current_scene if get_tree() != null else null
	var opening := scene != null and scene.has_method("is_opening_finished")
	if opening and not bool(scene.call("is_opening_finished")):
		_pending_line = clean
		_connect_idle(chat)
		return
	if _chat_idle(chat):
		_speak_now(chat, clean)
		return
	_pending_line = clean
	_connect_idle(chat)


func _speak_now(chat: Node, text: String) -> void:
	var scanned := _scan(text)
	if scanned.strip_edges().is_empty():
		return
	chat.call("begin_turn_wait")
	chat.call("begin_beat", 0)
	chat.call("say_chunk", 0, scanned)
	chat.call("end_beat", 0)
	chat.call("end_turn")


## Wait for the conversation to go quiet: the opening beats, then her streamed
## reply, then the typewriter. Every boundary is an existing public signal, so
## no scene has to know this module exists.
func _connect_idle(chat: Node) -> void:
	var tree := get_tree()
	var scene := tree.current_scene if tree != null else null
	if scene != null and scene.has_signal("opening_beats_finished"):
		if not scene.is_connected("opening_beats_finished", _on_idle):
			scene.connect("opening_beats_finished", _on_idle)
	if chat != null and chat.has_signal("turn_displayed"):
		if not chat.is_connected("turn_displayed", _on_idle):
			chat.connect("turn_displayed", _on_idle)
	if not Director.is_connected("turn_completed", _on_turn_completed):
		Director.turn_completed.connect(_on_turn_completed)


func _on_idle() -> void:
	_try_speak_pending()


func _on_turn_completed(_turn_index: int, _turn_data: Dictionary) -> void:
	_try_speak_pending()


func _try_speak_pending() -> void:
	if _pending_line.is_empty():
		return
	var chat := _chat_ui()
	if chat == null or not _chat_idle(chat):
		return
	var text := _pending_line
	_pending_line = ""
	_speak_now(chat, text)
	var tree := get_tree()
	var scene := tree.current_scene if tree != null else null
	if scene != null and scene.is_connected("opening_beats_finished", _on_idle):
		scene.disconnect("opening_beats_finished", _on_idle)
	if chat.is_connected("turn_displayed", _on_idle):
		chat.disconnect("turn_displayed", _on_idle)
	if Director.is_connected("turn_completed", _on_turn_completed):
		Director.turn_completed.disconnect(_on_turn_completed)


func _chat_idle(chat: Node) -> bool:
	if chat.has_method("is_turn_open") and bool(chat.call("is_turn_open")):
		return false
	return not Director.is_busy()


func _chat_ui() -> Node:
	var node: Variant = Director.get("chat_ui_node")
	if not node is Node:
		return null
	var chat := node as Node
	if not is_instance_valid(chat) or not chat.has_method("begin_turn_wait"):
		return null
	return chat


## docs/07 §3.4: any model text that will be displayed passes Safety first.
## Fail closed — a build without the scan API shows bars, never raw text.
func _scan(text: String) -> String:
	var safety := get_node_or_null("/root/Safety")
	if safety == null or not safety.has_method("filter_text"):
		return SaySafetyGate.redact(text)
	var res: Variant = safety.call("filter_text", text, {"stage": int(GameState.stage)})
	if res is Dictionary and (res as Dictionary).has("text"):
		return str((res as Dictionary)["text"])
	if res is String:
		return res
	return SaySafetyGate.redact(text)


func _current_say() -> String:
	return TurnContext.spoken_text(Director.last_turn_data)


func _post_system_line(speaker: String, text: String) -> void:
	var chat := _chat_ui()
	if chat == null:
		return
	var log: Variant = chat.get("chat_log")
	if log == null or not (log as Node).has_method("append_entry"):
		return
	(log as Node).call("append_entry", "system", speaker, text)


static func _shorten(text: String, limit: int) -> String:
	var clean := text.strip_edges().replace("\n", " ").replace("\t", " ")
	while clean.find("  ") >= 0:
		clean = clean.replace("  ", " ")
	if clean.length() <= limit:
		return clean
	var cut := clean.substr(0, limit)
	var space := cut.rfind(" ")
	if space > limit / 2:
		cut = cut.substr(0, space)
	return cut.strip_edges().rstrip(" ,.;:-")


func _play_engine_cue(cue: String) -> void:
	if cue.strip_edges().is_empty() or AudioDirector == null:
		return
	if AudioDirector.has_method("play_engine_cue"):
		AudioDirector.play_engine_cue(StringName(cue))


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return false
	return bool(settings.get("reduced_motion"))


func _request_quit() -> void:
	if _quit.is_valid():
		_quit.call()
		return
	if get_tree() != null:
		get_tree().quit()


## The id of the replica on screen, "" when there is none. A freed dialog node
## must read as "none": a dangling reference would crash the F3 refresh.
func _dialog_id() -> String:
	if _dialogs == null or not is_instance_valid(_dialogs):
		return ""
	return str(_dialogs.current_id())


func _dialogs_node() -> CanvasLayer:
	if _dialogs != null and is_instance_valid(_dialogs):
		return _dialogs
	var script := load(DIALOGS_SCRIPT) as Script
	if script == null or not script.can_instantiate():
		return null
	var node: Variant = script.new()
	if not node is CanvasLayer:
		return null
	_dialogs = node as CanvasLayer
	_dialogs.name = "MetaDialogsM01"
	add_child(_dialogs)
	return _dialogs


## ── Session and state file ────────────────────────────────────────────────


func _begin_session() -> void:
	if _session_started:
		return
	_session_started = true
	var now := _now()
	_state["session"] = {"start": now}
	_state["last_seen"] = now
	_persist()


## Refresh "the last moment they were here" at every scene boundary, so a hard
## kill costs at most one scene of away-time accuracy. M05 reads it next launch.
func _touch_last_seen() -> void:
	var now := _now()
	if int(_state.get("last_seen", 0)) <= 0:
		return
	_state["last_seen"] = now
	_persist()


func _measure_away() -> int:
	var last_seen := int(_state.get("last_seen", 0))
	if last_seen <= 0:
		return -1
	var away := _now() - last_seen
	if away < 0 or away > MAX_AWAY_SECONDS:
		return -1
	return away


func _now() -> int:
	if clock.is_valid():
		var stamp: Variant = clock.call()
		if stamp is float or stamp is int:
			return int(stamp)
	return int(Time.get_unix_time_from_system())


func _write_quit(method: String) -> void:
	var clean := method.strip_edges()
	if clean.is_empty():
		clean = "window_x"
	var now := _now()
	_last_quit = {"method": clean, "at": now}
	_quit_recorded = true
	_state["last_quit"] = _last_quit.duplicate()
	_state["last_seen"] = now
	_persist()


func _write_she_closed() -> void:
	_state["she_closed"] = {"at": _now()}
	_state["last_seen"] = _now()
	_she_closed_pending = true
	_persist()


func _consume_she_closed() -> void:
	_she_closed_pending = false
	_state.erase("she_closed")
	_persist()


func _infer_quit_method() -> String:
	var turn_open := false
	var chat := _chat_ui()
	if chat != null and chat.has_method("is_turn_open"):
		turn_open = bool(chat.call("is_turn_open"))
	if not turn_open and Director != null and Director.has_method("is_busy"):
		turn_open = Director.is_busy()
	var menu_open := false
	var pause := get_node_or_null("/root/PauseMenu")
	if pause != null and pause.has_method("is_open"):
		menu_open = bool(pause.call("is_open"))
	return quit_method(turn_open, menu_open, Input.is_key_pressed(KEY_ALT))


func _shadow_memories() -> Array:
	var save := get_node_or_null("/root/SaveSystem")
	if save == null or not save.has_method("shadow_memories"):
		return []
	var memories: Variant = save.call("shadow_memories")
	return (memories as Array) if memories is Array else []


func _seen() -> Array:
	var seen: Variant = GameState.get_flag(SEEN_FLAG, [])
	return (seen as Array).duplicate() if seen is Array else []


## The Extras "what happened" ledger and the once-per-save guard share one flag
## with MetaDirector (`meta_seen`), so nothing double-books an event.
func _mark_seen(ids: Array) -> void:
	if ids.is_empty():
		return
	var seen := _seen()
	var changed := false
	for id: Variant in ids:
		var key := str(id)
		if key.is_empty() or seen.has(key):
			continue
		seen.append(key)
		changed = true
	if changed:
		GameState.set_flag(SEEN_FLAG, seen)


## ── Data ─────────────────────────────────────────────────────────────────


func _load_messages() -> Dictionary:
	if not FileAccess.file_exists(MESSAGES_PATH):
		push_warning("MetaEventsM01: %s missing; M01–M12 have no text" % MESSAGES_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MESSAGES_PATH))
	if not parsed is Dictionary:
		push_warning("MetaEventsM01: %s is not a JSON object" % MESSAGES_PATH)
		return {}
	return parsed as Dictionary


func _msg(section: String) -> Dictionary:
	return _dict_at(_messages, section)


func _persist() -> void:
	store.store(_state)


static func _dict_at(row: Dictionary, key: String) -> Dictionary:
	var value: Variant = row.get(key, {})
	return (value as Dictionary) if value is Dictionary else {}
