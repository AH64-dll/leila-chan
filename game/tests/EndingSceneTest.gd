extends GdUnitTestSuite
## P3.16 — the ending screen: the run's last beat, its log write, and the save
## that makes Continue land back on it.
##
## The clock is advance_time(), never the wall clock, so the reveal cannot flake
## under load. The log and the save dir are scratch paths; nothing here touches
## the player's user://.

const EndingPacked := preload("res://scenes/Ending.tscn")
const TEST_DIR := "user://ending_scene_saves/"
const LOG_DIR := "user://ending_scene_log/"

var _previous_dir := ""
var _snapshot := {}


func before_test() -> void:
	_previous_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.autosave_enabled = true
	SaveSystem.set_clock(func() -> int: return 1_700_000_000)
	SaveSystem.consume_pending_scene()
	_remove_dir(LOG_DIR)
	EndingLog.use_path(LOG_DIR + "endings.json")
	EndingLog.set_clock(func() -> String: return "2026-11-04T12:00:00")
	EndingLog.clear_cache()
	Endings.clear_cache()
	_snapshot = GameState.to_dict()
	GameState.reset()


func after_test() -> void:
	await get_tree().process_frame
	_remove_dir(TEST_DIR)
	_remove_dir(LOG_DIR)
	SaveSystem.save_dir = _previous_dir
	SaveSystem.autosave_enabled = DisplayServer.get_name() != "headless"
	SaveSystem.set_clock(Callable())
	SaveSystem.consume_pending_scene()
	EndingLog.use_path("")
	EndingLog.set_clock(Callable())
	EndingLog.clear_cache()
	Endings.clear_cache()
	if not _snapshot.is_empty():
		GameState.from_dict(_snapshot)
	_snapshot = {}


## The ending screen renders what the data says the run reached: the row's name,
## the path/day/stage the run ended on, and this visit's place in the log.
func test_the_screen_renders_the_ending_the_run_reached() -> void:
	assert_bool(bool(Endings.force("E01").get("ok", false))).is_true()
	var screen := _open()
	screen.advance_time(5.0)
	var lines: Array = screen.visible_lines()
	assert_int(lines.size()).is_equal(3)
	assert_str(String(lines[0])).is_equal("Forever Together")
	assert_bool(String(lines[1]).contains("YANDERE")).is_true()
	assert_bool(String(lines[1]).contains("Day 14")).is_true()
	assert_bool(String(lines[1]).contains("Terminal")).is_true()
	assert_str(String(lines[2])).is_equal("First time")
	assert_str(String(screen.ending_row().get("id", ""))).is_equal("E01")
	assert_int(int(screen.log_record().get("count", 0))).is_equal(1)


## docs/01 §7 rows are the screen's content, so every row names itself.
func test_every_row_renders_its_own_title() -> void:
	for id: String in ["E02", "E07", "E14"]:
		assert_bool(bool(Endings.force(id).get("ok", false))).is_true()
		var screen := _open()
		var lines: Array = screen.visible_lines()
		assert_str(String(lines[0])).is_equal(String(Endings.get_ending(id).get("name", "")))
		assert_str(String(screen.ending_row().get("id", ""))).is_equal(id)


## The log counts runs, not visits: quitting on the ending and resuming the save
## must not inflate it, while a fresh run of the same ending must.
func test_the_log_is_written_once_per_run() -> void:
	assert_bool(bool(Endings.force("E04").get("ok", false))).is_true()
	var first := _open()
	assert_int(EndingLog.count("E04")).is_equal(1)
	first.queue_free()
	await get_tree().process_frame
	var second := _open()
	assert_int(EndingLog.count("E04")).is_equal(1)
	assert_int(int(second.log_record().get("count", 0))).is_equal(1)
	# A new run clears the run-scoped guard, so the same ending counts again.
	GameState.reset()
	assert_bool(bool(Endings.force("E04").get("ok", false))).is_true()
	_open()
	assert_int(EndingLog.count("E04")).is_equal(2)


## "Persisted across saves": the ending is a scene id, so the save it writes at
## the ending resumes on the ending screen with the same ending.
func test_the_ending_save_resumes_on_the_ending_screen() -> void:
	assert_bool(bool(Endings.force("E06").get("ok", false))).is_true()
	var screen := _open()
	screen.advance_time(10.0)
	assert_bool(screen.skip()).is_true()
	await get_tree().process_frame
	var loaded := SaveSystem.load_from_slot("auto")
	assert_bool(bool(loaded.get("ok", false))).is_true()
	assert_str(String(SaveSystem.pending_scene().get("id", ""))).is_equal(SaveSystem.SCENE_ENDING)
	assert_str(String(GameState.get_flag(Endings.FLAG_ENDING, ""))).is_equal("E06")
	assert_bool(bool(GameState.get_flag(Endings.FLAG_RECORDED, false))).is_true()


## The skip window is data (ui.json's `ending` block): an ending is never skipped
## by the click that opened it.
func test_skip_waits_for_the_data_window() -> void:
	assert_bool(bool(Endings.force("E02").get("ok", false))).is_true()
	var screen := _open()
	assert_bool(screen.skip()).is_false()
	screen.advance_time(1.0)
	assert_bool(screen.skip()).is_false()
	# The window alone is not enough: the last line still has to be on screen.
	screen.advance_time(0.6)
	assert_bool(screen.skip()).is_false()
	screen.advance_time(0.3)
	assert_bool(screen.skip()).is_true()
	assert_bool(screen.is_finished()).is_true()


func test_the_reveal_timing_comes_from_ui_data() -> void:
	assert_bool(bool(Endings.force("E05").get("ok", false))).is_true()
	var screen := _open()
	assert_int(screen.visible_lines().size()).is_equal(1)
	screen.advance_time(0.9)
	assert_int(screen.visible_lines().size()).is_equal(2)
	screen.advance_time(0.9)
	assert_int(screen.visible_lines().size()).is_equal(3)


## docs/05 §0 rule 3: Esc always works. There is no pause menu yet (P3.13), so it
## leaves for the Title — never a screen that ignores the player.
func test_esc_leaves_and_reports_the_pause() -> void:
	assert_bool(bool(Endings.force("E03").get("ok", false))).is_true()
	var screen := _open()
	var paused := [false]
	screen.pause_requested.connect(func() -> void: paused[0] = true)
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	screen._unhandled_key_input(event)
	assert_bool(paused[0]).is_true()
	assert_bool(screen.is_finished()).is_true()


## P3.17's content slot: a row that carries a `frame` renders it, with no code
## change — the ending screen is the consumer of that prose.
func test_a_row_frame_renders_when_the_data_has_one() -> void:
	var document := Endings.table().duplicate(true)
	for row: Dictionary in document["endings"]:
		if String(row.get("id", "")) == "E01":
			row["frame"] = "You stay. She closes the door."
	assert_array(Endings.use_document(document)).is_empty()
	assert_bool(bool(Endings.force("E01").get("ok", false))).is_true()
	var screen := _open()
	screen.advance_time(5.0)
	assert_bool(screen.visible_lines().has("You stay. She closes the door.")).is_true()


## A table that lost every row still ends on a screen instead of a black one: the
## fallback title is data (ui.json), and no bogus ending is invented or logged.
func test_a_table_with_no_rows_renders_the_fallback() -> void:
	Endings.use_document({"endings": [], "defaults": {}})
	var screen := _open()
	assert_str(String(screen.ending_row().get("id", ""))).is_empty()
	assert_str(String(screen.visible_lines()[0])).is_equal("The End")
	assert_dict(screen.log_record()).is_empty()
	assert_int(EndingLog.seen_ids().size()).is_zero()


func _open() -> Control:
	var screen: Control = auto_free(EndingPacked.instantiate())
	screen.scene_change_enabled = false
	screen.auto_advance = false
	add_child(screen)
	screen.start_ending()
	return screen


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
