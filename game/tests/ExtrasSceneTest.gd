extends GdUnitTestSuite
## P3.16 — Extras: the after-the-run gallery (docs/05 §0 rule 5, docs/05 §3).
##
## The screen is a view of the ending log: one row per docs/01 §7 ending, its name
## only once it was reached, and the secret row whose unlock rule is its own data.
## The log is a scratch file; nothing here touches the player's user://.

const ExtrasPacked := preload("res://scenes/Extras.tscn")
const LOG_DIR := "user://extras_scene_log/"

var _snapshot := {}


func before_test() -> void:
	_remove_dir(LOG_DIR)
	EndingLog.use_path(LOG_DIR + "endings.json")
	EndingLog.set_clock(func() -> String: return "2026-11-04T12:00:00")
	EndingLog.clear_cache()
	Endings.clear_cache()
	_snapshot = GameState.to_dict()
	GameState.reset()


func after_test() -> void:
	await get_tree().process_frame
	_remove_dir(LOG_DIR)
	EndingLog.use_path("")
	EndingLog.set_clock(Callable())
	EndingLog.clear_cache()
	Endings.clear_cache()
	if not _snapshot.is_empty():
		GameState.from_dict(_snapshot)
	_snapshot = {}


## Before the first ending there is nothing to show, and every row is locked —
## including the names, so the gallery cannot spoil what has not happened.
func test_extras_is_locked_before_the_first_ending() -> void:
	var extras := _open()
	assert_str(extras.progress_text()).is_equal("No ending yet. Finish a run.")
	var entries: Array = extras.entries()
	assert_int(entries.size()).is_equal(15)  # docs/01 §7's 14 + the secret
	for entry: Dictionary in entries:
		assert_bool(bool(entry.get("unlocked", true))).is_false()
	assert_str(String(entries[0].get("name", ""))).is_equal("???")


func test_a_reached_ending_is_listed_with_its_run() -> void:
	EndingLog.record(Endings.get_ending("E01"), {"day": 14, "stage": 5})
	var extras := _open()
	var entry := _entry(extras, "E01")
	assert_bool(bool(entry.get("unlocked", false))).is_true()
	assert_str(String(entry.get("name", ""))).is_equal("Forever Together")
	assert_bool(String(entry.get("detail", "")).contains("Day 14")).is_true()
	assert_bool(String(entry.get("detail", "")).contains("YANDERE")).is_true()
	assert_str(extras.progress_text()).is_equal("1 / 14 endings")
	# A locked sibling still hides its name.
	assert_str(String(_entry(extras, "E02").get("name", ""))).is_equal("???")


## docs/01 §7's secret: "play all 6 paths". The rule is the row's data; the fact
## is the log's path history.
func test_the_secret_unlocks_after_six_paths() -> void:
	for id: String in ["E01", "E04", "E06", "E08", "E10", "E12"]:
		EndingLog.record(Endings.get_ending(id), {"day": 14, "stage": 5})
	var extras := _open()
	var secret := _entry(extras, Endings.SECRET_ID)
	assert_bool(bool(secret.get("unlocked", false))).is_true()
	assert_str(String(secret.get("name", ""))).is_equal("Weights")
	assert_str(String(secret.get("detail", ""))).is_equal("She remembers every version of herself.")


func test_the_secret_stays_locked_at_five_paths() -> void:
	for id: String in ["E01", "E04", "E06", "E08", "E10"]:
		EndingLog.record(Endings.get_ending(id), {"day": 14, "stage": 5})
	var extras := _open()
	var secret := _entry(extras, Endings.SECRET_ID)
	assert_bool(bool(secret.get("unlocked", true))).is_false()
	assert_str(String(secret.get("detail", ""))).is_equal("Play all six paths.")


## The secret's requirement is visible (it is the one unlock a player can chase);
## a path ending's detail carries the run's own day and path.
func test_an_ending_reached_twice_shows_the_count() -> void:
	var row := Endings.get_ending("E12")
	EndingLog.record(row, {"day": 14, "stage": 3})
	EndingLog.record(row, {"day": 14, "stage": 3})
	var extras := _open()
	var entry := _entry(extras, "E12")
	assert_bool(String(entry.get("detail", "")).contains("2×")).is_true()
	assert_str(extras.progress_text()).is_equal("1 / 14 endings")


func test_back_returns_to_the_title() -> void:
	var extras := _open()
	var backs := [false]
	extras.back_requested.connect(func() -> void: backs[0] = true)
	extras.back_button.pressed.emit()
	assert_bool(backs[0]).is_true()
	assert_bool(extras.scene_change_enabled).is_false()


func test_esc_goes_back() -> void:
	var extras := _open()
	var backs := [false]
	extras.back_requested.connect(func() -> void: backs[0] = true)
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	extras._unhandled_key_input(event)
	assert_bool(backs[0]).is_true()


func _open() -> Control:
	var extras: Control = auto_free(ExtrasPacked.instantiate())
	extras.scene_change_enabled = false
	add_child(extras)
	return extras


func _entry(extras: Control, id: String) -> Dictionary:
	for entry: Dictionary in extras.entries():
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
