extends GdUnitTestSuite
## P2.20 — the save experience in the real scenes: the Date autosaves itself
## (scene start + every completed turn), a loaded log lands back in the ChatLog
## and in the Director's prompt history, and the Title's Continue resumes the
## newest save (or stays disabled when there is none).

const TEST_DIR := "user://save_flow_test/"
const DatePacked := preload("res://scenes/Date.tscn")
const TitleScene := preload("res://scenes/Title.tscn")
const FakeChatLogScript := preload("res://tests/helpers/FakeChatLog.gd")
const SCENARIO := "res://data/scenarios/D02_cafe.json"

var _previous_dir := ""
var _date: Node2D = null
var _title: Control = null


func before_test() -> void:
	_previous_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.autosave_enabled = true
	SaveSystem.set_clock(func() -> int: return 1_700_000_000)
	SaveSystem.consume_pending_scene()
	Director.reset()
	GameState.reset()
	GameState.player_name = "Ren"


func after_test() -> void:
	for node: Node in [_date, _title]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_date = null
	_title = null
	await get_tree().process_frame
	SaveSystem.clear_log_seam(null)
	_remove_dir(TEST_DIR)
	SaveSystem.save_dir = _previous_dir
	SaveSystem.autosave_enabled = DisplayServer.get_name() != "headless"
	SaveSystem.set_clock(Callable())
	SaveSystem.consume_pending_scene()
	Director.reset()
	GameState.reset()


## Acceptance: the Date scene autosaves on entry and after a completed turn,
## and the autosave carries the scene and the scroll-back log.
func test_date_scene_autosaves_its_scene_and_log() -> void:
	_date = DatePacked.instantiate()
	_date.auto_start = false
	get_tree().root.add_child(_date)
	await get_tree().process_frame
	_date.start_date()
	await get_tree().process_frame
	var on_entry := _autosave_payload()
	assert_str(String(_dict(on_entry["scene"])["id"])).is_equal("date")
	assert_str(String(_dict(on_entry["scene"])["scenario"])).is_equal(SCENARIO)

	# A displayed turn is the next autosave point, and its log rides along.
	_date.chat_ui.chat_log.append_entry("player", "Ren", "Good evening.")
	_date.chat_ui.chat_log.append_entry("her", "Leila", "You came.")
	_date.chat_ui.turn_displayed.emit()
	var after_turn := _autosave_payload()
	var entries: Array = _dict(after_turn["log"])["entries"]
	assert_int(entries.size()).is_equal(2)
	assert_str(String(entries[0]["speaker_key"])).is_equal("player")
	assert_str(String(entries[0]["text"])).is_equal("Good evening.")
	assert_str(String(entries[1]["text"])).is_equal("You came.")


## Acceptance: a load restores the log into the ChatLog and the prompt history
## rebuilt from it (docs/08 §1: assistant side as spoken text).
func test_loaded_log_is_restored_into_the_chat_log_and_history() -> void:
	var source := FakeChatLogScript.new()
	source.entries = [
		{"speaker_key": "her", "speaker": "Leila", "text": "I kept your seat."},
		{"speaker_key": "player", "speaker": "Ren", "text": "You remembered."},
	]
	SaveSystem.register_log_seam(
		source, Callable(source, "get_entries"), Callable(source, "restore_entries")
	)
	var saved := SaveSystem.save_to_slot(1, "date", {"scenario": SCENARIO, "turn": 3})
	assert_bool(bool(saved["ok"])).is_true()
	SaveSystem.clear_log_seam(source)

	# A fresh launch: no log node registered, then the Date scene comes up.
	assert_bool(bool(SaveSystem.load_from_slot(1)["ok"])).is_true()
	(
		assert_array(Director.history)
		. is_equal(
			[
				{"role": "assistant", "text": "I kept your seat."},
				{"role": "user", "text": "You remembered."},
			]
		)
	)
	_date = DatePacked.instantiate()
	get_tree().root.add_child(_date)
	await get_tree().process_frame
	var entries: Array = _date.chat_ui.chat_log.get_entries()
	assert_int(entries.size()).is_equal(2)
	assert_str(String(entries[0]["text"])).is_equal("I kept your seat.")
	assert_str(String(entries[1]["speaker_key"])).is_equal("player")
	# the scene the load named was consumed, and its turn counter restored
	assert_dict(SaveSystem.pending_scene()).is_empty()
	_date.start_date()
	assert_int(_date._current_turn).is_equal(3)


## Acceptance: Continue resumes the newest save (meters included).
func test_title_continue_resumes_the_newest_save() -> void:
	GameState.set_meter(&"affection", 44.0)
	GameState.set_meter(&"instability", 51.0)
	GameState.day = 6
	var saved := SaveSystem.save_to_slot(2, "date", {"scenario": SCENARIO, "turn": 5})
	assert_bool(bool(saved["ok"])).is_true()
	GameState.reset()
	GameState.player_name = "Senpai"
	assert_int(GameState.day).is_equal(1)

	_title = TitleScene.instantiate()
	_title.scene_change_enabled = false
	add_child(_title)
	await get_tree().process_frame
	assert_bool(_title.continue_button.disabled).is_false()
	_title.continue_button.pressed.emit()
	assert_str(GameState.player_name).is_equal("Ren")
	assert_int(GameState.day).is_equal(6)
	assert_float(GameState.affection).is_equal_approx(44.0, 0.001)
	assert_str(String(SaveSystem.pending_scene()["scenario"])).is_equal(SCENARIO)


## Acceptance: with nothing to load, Continue is disabled and a click is a
## safe no-op instead of a crash or a scene change.
func test_title_continue_is_disabled_without_a_save() -> void:
	assert_bool(SaveSystem.has_save()).is_false()
	_title = TitleScene.instantiate()
	_title.scene_change_enabled = false
	add_child(_title)
	await get_tree().process_frame
	assert_bool(_title.continue_button.disabled).is_true()
	_title.continue_button.pressed.emit()
	assert_str(GameState.player_name).is_equal("Ren")


func _autosave_payload() -> Dictionary:
	var text := FileAccess.get_file_as_string(TEST_DIR + "autosave.json")
	var decoded: Dictionary = SaveSystem.slots.decode(text)
	return _dict(decoded.get("payload"))


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}
