extends GdUnitTestSuite
## P3.10 — the MetaDirector seam the docs/05 §1.3 scripted events ride on: the
## module is mounted from EFFECTS_PATHS, a due event is polled once per turn and
## pays the same docs/05 §3 budget as an offer (scene cap, quiet turn,
## once-per-save ledger), and its EVENT note rides the turn it happened in
## (docs/05 §2) instead of arriving a turn late.

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const DebugOverlayScene := preload("res://scenes/debug/DebugOverlay.tscn")
const TMP_DIR := "user://meta_scripted_test/"
const LEDGER := TMP_DIR + "log_edits.json"

var _snapshot := {}
var _module: Node = null


func before_test() -> void:
	_snapshot = GameState.to_dict()
	GameState.reset()
	GameState.stage = 4
	GameState.path = &"YANDERE"
	GameState.turn = 5
	_remove_dir(TMP_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	MetaLogEdits.use_path(LEDGER)
	MetaDirector.load_catalog()
	MetaDirector.reset_session()
	MetaDirector.note_scene("test_scene")
	_module = MetaDirector.get_node_or_null("MetaEventsM21")
	if _module != null:
		_module.call("_load_data")
		_module.set_seed_base(0)
		# Deterministic: any stage ≥ 3 and any path; the shipped table's chance
		# stays untouched for every other task's tests.
		(
			_module
			. set_data(
				{
					"m23": {"stage": 3, "paths": [], "chance": 1.0},
					"m24": {"stage": 3, "paths": [], "chance": 0.0},
					"m26": {"stage": 3, "paths": [], "chance": 0.0},
				}
			)
		)
	PauseMenu.close()


func after_test() -> void:
	await get_tree().process_frame
	PauseMenu.close()
	if _module != null:
		_module.call("_load_data")
	MetaDirector.load_catalog()
	MetaDirector.reset_session()
	MetaDirector.note_scene("")
	MetaLogEdits.use_path("")
	_remove_dir(TMP_DIR)
	if not _snapshot.is_empty():
		GameState.from_dict(_snapshot)
	_snapshot = {}
	_module = null


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _new_chat() -> Control:
	var ui: Control = ChatUIScene.instantiate()
	add_child(auto_free(ui))
	await get_tree().process_frame
	return ui


func _log_player_line(ui: Control) -> void:
	ui.chat_log.append_entry("player", "Senpai", "I like you")


## ── Mounting ──────────────────────────────────────────────────────────────


func test_the_effect_module_is_mounted_from_the_path_list() -> void:
	assert_array(MetaDirector.EFFECTS_PATHS).contains("res://llm/meta/MetaEventsM21.gd")
	assert_object(_module).is_not_null()
	assert_str(String(_module.name)).is_equal("MetaEventsM21")
	assert_bool(_module.has_method("fire")).is_true()
	assert_bool(_module.has_method("poll_scripted")).is_true()
	assert_bool(_module.has_method("debug_fire")).is_true()


## ── Polling, caps and the note ────────────────────────────────────────────


func test_a_due_scripted_event_fires_at_the_scene_boundary_and_pays_the_scene_budget() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	assert_bool(MetaDirector.events_seen().has("M23")).is_false()
	MetaDirector.note_scene("test_scene")
	assert_bool(MetaDirector.events_seen().has("M23")).is_true()
	var view: Dictionary = MetaDirector.state()
	assert_int(int(view.get("scene_events", 0))).is_equal(1)
	# The effect landed on the chat log (docs/05 §1.3 M23).
	assert_str(MetaLogEdits.shown("player", "I like you", 1)).is_equal("I love you")


## One poll per turn: a second scene boundary in the same turn cannot repeat it.
func test_a_scripted_event_fires_once_per_turn() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	MetaDirector.note_scene("test_scene")
	MetaDirector.note_scene("test_scene")
	# The second boundary lands in the same turn: the quiet-turn guard suppresses
	# the repeat, so M23 is charged exactly once even though the new scene's own
	# budget is fresh.
	var seen := 0
	for id: String in MetaDirector.events_seen():
		if id == "M23":
			seen += 1
	assert_int(seen).is_equal(1)
	assert_int(int(MetaDirector.state().get("scene_events", 0))).is_equal(0)


## docs/05 §2: the note reaches the SAME submit (docs/02 §4 step 1), not the next
## one — the clock greeting a turn late is not "her greeting matches the time".
func test_the_event_note_rides_the_turn_it_happened_in() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	MetaDirector.note_scene("test_scene")
	var events: Array = MetaDirector.turn_events([], 4)
	var found := false
	for line: String in events:
		if line.begins_with("EVENT:") and line.contains("chat log"):
			found = true
	assert_bool(found).is_true()


## docs/05 §3 "never two in a row": the turn after a scripted event is quiet.
func test_the_turn_after_a_scripted_event_is_quiet() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	MetaDirector.note_scene("test_scene")
	GameState.advance_turn()
	MetaDirector.note_scene("next_scene")
	assert_array(MetaDirector.offers(4)).is_empty()


## Once per save: the `meta_seen` ledger that Extras shows is also the cap.
func test_a_scripted_event_is_once_per_save() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	MetaDirector.note_scene("test_scene")
	GameState.advance_turn()
	GameState.advance_turn()
	MetaDirector.note_scene("next_scene")
	assert_bool(bool(MetaDirector.call("_scripted_allowed", "M23", 4))).is_false()


## CODE-1/DES-1: spent M23 must not starve M24 or M26.
func test_spent_m23_does_not_starve_m24() -> void:
	var ui := await _new_chat()
	for index in 6:
		var key := "player" if index % 2 == 0 else "her"
		ui.chat_log.append_entry(key, "Senpai" if key == "player" else "Leila", "line %d" % index)
	GameState.set_flag(&"meta_seen", ["M23"])
	(
		_module
		. set_data(
			{
				"m23": {"stage": 3, "paths": [], "chance": 1.0},
				"m24": {"stage": 3, "paths": [], "chance": 1.0},
				"m26": {"stage": 3, "paths": [], "chance": 0.0},
			}
		)
	)
	assert_bool(MetaDirector.events_seen().has("M23")).is_true()
	assert_bool(MetaDirector.events_seen().has("M24")).is_false()
	MetaDirector.note_scene("test_scene")
	assert_bool(MetaDirector.events_seen().has("M24")).is_true()


## The per-scene budget is the same one offers pay: a spent cap-1 scene buys no
## scripted event either.
func test_a_spent_scene_buys_no_scripted_event() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	MetaDirector.note_scene("test_scene")
	assert_int(MetaDirector.scene_cap(4)).is_equal(2)
	assert_int(int(MetaDirector.state().get("scene_events", 0))).is_equal(1)
	# A stage-3 scene has room for one event; make this one stage 3.
	GameState.stage = 3
	assert_bool(bool(MetaDirector.call("_scripted_allowed", "M24", 3))).is_false()


## A parked scheduler (an empty catalogue — every suite that wants the lottery
## out of the way) runs no meta events at all, scripted ones included.
func test_a_parked_scheduler_runs_no_scripted_events() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	MetaDirector.set_catalog({"events": {}})
	MetaDirector.note_scene("test_scene")
	assert_bool(MetaDirector.events_seen().has("M23")).is_false()
	assert_int(int(MetaDirector.state().get("scene_events", 0))).is_equal(0)


## ── The F3 path ───────────────────────────────────────────────────────────


## The overlay's generic block calls `debug_ids()` on every mounted module and
## `debug_fire()` for the button — the same call the suites use here.
func test_debug_fire_reaches_the_scripted_events_from_the_mounted_module() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	var ids: Array = _module.debug_ids()
	assert_array(ids).contains(["M23", "M24", "M26"])
	assert_bool(bool(_module.debug_fire("M23"))).is_true()
	assert_bool(MetaDirector.events_seen().has("M23")).is_true()


## The F3 seam itself (role checklist): the overlay's generic block dispatches
## a button click to the mounted module, and the demo line reports what ran.
func test_the_overlay_button_path_fires_the_scripted_event() -> void:
	var ui := await _new_chat()
	_log_player_line(ui)
	var overlay: CanvasLayer = DebugOverlayScene.instantiate() as CanvasLayer
	add_child(auto_free(overlay))
	await get_tree().process_frame
	assert_bool(overlay.fire_meta_demo("M23")).is_true()
	assert_str(MetaLogEdits.shown("player", "I like you", 1)).is_equal("I love you")
	assert_str(overlay.get_meta_demo_text()).contains("M23")
