extends GdUnitTestSuite
## P2.20 — the save experience in the real scenes: the Date autosaves itself
## (scene start + every completed turn), a loaded log lands back in the ChatLog
## and in the Director's prompt history, and the Title's Continue resumes the
## newest save (or stays disabled when there is none).

const TEST_DIR := "user://save_flow_test/"
const DatePacked := preload("res://scenes/Date.tscn")
const TitleScene := preload("res://scenes/Title.tscn")
const FakeChatLogScript := preload("res://tests/helpers/FakeChatLog.gd")
const GatedBackendScript := preload("res://tests/helpers/GatedLLMBackend.gd")
const SCENARIO := "res://data/scenarios/D02_cafe.json"
## One complete turn as the model streams it (IncrementalJson order). The say is
## the only line that reaches the ChatLog, so it is pinned by the turn test.
const TURN_JSON := (
	'{"read":"small_talk","inner":"He came back.","music":"keep","fx":"none",'
	+ '"beats":[{"feeling":"warmth","intensity":1,"cue":"none","say":"I saved you a seat."}],'
	+ '"mood":{"affection":1,"trust":1,"stress":0},"memory":"","action":"none"}'
)
const TURN_SAY := "I saved you a seat."

var _previous_dir := ""
var _previous_backend: LLMBackend = null
var _backend: Variant = null
var _date: Node2D = null
var _title: Control = null


func before_test() -> void:
	_previous_dir = SaveSystem.save_dir
	_previous_backend = LLM.get_backend()
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.autosave_enabled = true
	SaveSystem.set_clock(func() -> int: return 1_700_000_000)
	SaveSystem.consume_pending_scene()
	Director.reset()
	GameState.reset()
	GameState.player_name = "Ren"


func after_test() -> void:
	# A failed assertion must not leave the gated worker parked, or the next
	# suite's first turn would be answered by it.
	if _backend != null:
		_backend.release = true
	if LLM.is_busy():
		LLM.cancel()
	for node: Node in [_date, _title]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_date = null
	_title = null
	_backend = null
	await get_tree().process_frame
	LLM.set_backend(_previous_backend)
	_previous_backend = null
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
	# The after-turn write is deferred past the Director's in-flight window
	# (CODE-1), so the file only changes on the next idle frame.
	await get_tree().process_frame
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
	# P2.22 S1-2: Continue's Date starts itself on the next idle frame. The resume
	# facts land in `_ready`, so they are readable before that start — and must
	# survive it.
	assert_bool(_date._resumed).is_true()
	var entries: Array = _date.chat_ui.chat_log.get_entries()
	assert_int(entries.size()).is_equal(2)
	assert_str(String(entries[0]["text"])).is_equal("I kept your seat.")
	assert_str(String(entries[1]["speaker_key"])).is_equal("player")
	# the scene the load named was consumed, and its turn counter restored
	assert_dict(SaveSystem.pending_scene()).is_empty()

	await get_tree().process_frame  # the date starts itself here
	# A log with entries carries the greeting: the resumed date skips replaying it.
	assert_bool(_date.is_opening_finished()).is_true()
	assert_int(_date._current_turn).is_equal(3)
	assert_int(_date.chat_ui.chat_log.entry_count()).is_equal(2)


## CODE-2: the scene-entry autosave lands before her opening beats reach the
## ChatLog, so a save taken during the greeting carries an empty log. Resuming
## it must play the greeting, not suppress it into a silent blank scroll-back.
func test_resume_plays_the_greeting_when_the_saved_log_is_empty() -> void:
	var saved := SaveSystem.save_to_slot(1, "date", {"scenario": SCENARIO, "turn": 0})
	assert_bool(bool(saved["ok"])).is_true()
	assert_bool(bool(SaveSystem.load_from_slot(1)["ok"])).is_true()

	_date = DatePacked.instantiate()
	var finished := [false]
	_date.opening_beats_finished.connect(func() -> void: finished[0] = true)
	get_tree().root.add_child(_date)
	_date.set_reduced_motion(true)  # instant reveal: no typewriter wall-clock wait
	# P2.22 S1-2: the scene starts itself now, so CODE-2 is asserted through that
	# start — an empty saved log must not suppress the greeting.
	assert_bool(_date._resumed).is_false()
	assert_bool(finished[0]).is_false()  # nothing has played yet

	await _await_until(func() -> bool: return finished[0])
	assert_bool(finished[0]).is_true()
	assert_int(_date.chat_ui.chat_log.entry_count()).is_equal(1)  # the greeting played


## CODE-1: the per-turn autosave must survive the Director's in-flight window. A
## turn whose typewriter already drained when `end_turn()` arrives emits
## `turn_displayed` from inside the turn close, while `is_busy()` is still true —
## the window in which a synchronous write is refused as "busy" and the turn is
## silently lost.
func test_completed_director_turn_autosaves_after_the_in_flight_window() -> void:
	_date = DatePacked.instantiate()
	_date.auto_start = false
	get_tree().root.add_child(_date)
	await get_tree().process_frame
	_date.set_reduced_motion(true)  # instant reveal: the writer is drained first
	_date.start_date()
	await _await_until(func() -> bool: return _date.is_opening_finished())
	assert_int(_date.chat_ui.chat_log.entry_count()).is_equal(1)  # the greeting

	# A turn the test can hold open: the reply is fully on screen, the stream is
	# not closed yet, and the Director still reports busy.
	_backend = GatedBackendScript.new()
	_backend.chunks = PackedStringArray([TURN_JSON])
	LLM.set_backend(_backend)
	# P2.22 S1-1: the Date is the bridge now (Date._on_player_turn_sent), so this
	# suite must not submit a second time — the reply's autosave is what is under
	# test here, not the wiring.
	var busy_at_close := [false]
	_date.chat_ui.turn_displayed.connect(func() -> void: busy_at_close[0] = Director.is_busy())
	var line := "Good evening, Leila."
	_date.chat_ui.input_box.text = line
	_date.chat_ui.input_box.text_submitted.emit(line)
	# greeting + the player's line are already logged; the reply lands as her beat
	# drains, while the stream is still open.
	await _await_until(func() -> bool: return _date.chat_ui.chat_log.entry_count() >= 3)
	assert_bool(Director.is_busy()).is_true()
	# Nothing has been written since the greeting: the log the turn produced is
	# not in the autosave yet, so the write really is still to come.
	assert_int(_entries_of(_autosave_payload()).size()).is_equal(1)
	_backend.release = true

	await _await_until(func() -> bool: return not Director.is_busy())
	await get_tree().process_frame  # the deferred write lands here
	assert_bool(busy_at_close[0]).is_true()  # `turn_displayed` fired inside the window
	var after_turn := _autosave_payload()
	var entries := _entries_of(after_turn)
	assert_int(entries.size()).is_equal(3)  # greeting, player line, her reply
	assert_str(String(entries[1]["speaker_key"])).is_equal("player")
	assert_str(String(entries[1]["text"])).is_equal(line)
	assert_str(String(entries[2]["speaker_key"])).is_equal("her")
	assert_str(String(entries[2]["text"])).is_equal(TURN_SAY)
	assert_int(int(_dict(after_turn["scene"])["turn"])).is_equal(1)


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


func _entries_of(payload: Dictionary) -> Array:
	var log_block: Variant = _dict(payload.get("log")).get("entries", [])
	return log_block if log_block is Array else []


## Wait until predicate.call() is true or the deadline passes (no sleeps: the
## frame itself is the clock).
func _await_until(predicate: Callable, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


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
