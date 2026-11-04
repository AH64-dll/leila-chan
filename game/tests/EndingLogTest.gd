extends GdUnitTestSuite
## P3.16 — the ending log: what the player has reached across runs.
##
## Acceptance "persisted across saves" is this suite's core: the log is a profile
## beside the saves, so a New Game, a save wipe or a fresh process cannot take a
## reached ending away, and a resumed save cannot count the same ending twice (the
## once-per-run guard lives in the run's own flags — EndingSceneTest proves the
## scene side). A corrupt file is a value, never a crash: a gallery may lose its
## history, it may not stop the game.

const TEST_DIR := "user://ending_log_test/"
const LOG_PATH := TEST_DIR + "endings.json"

var _clock_tick := 0


func before_test() -> void:
	_remove_dir(TEST_DIR)
	_clock_tick = 0
	EndingLog.use_path(LOG_PATH)
	EndingLog.set_clock(_clock)
	EndingLog.clear_cache()


func after_test() -> void:
	EndingLog.use_path("")
	EndingLog.set_clock(Callable())
	EndingLog.clear_cache()
	_remove_dir(TEST_DIR)


func test_recording_counts_runs_and_keeps_the_first_visit() -> void:
	var row := Endings.get_ending("E01")
	var first := EndingLog.record(row, {"day": 14, "stage": 5})
	assert_int(int(first.get("count", 0))).is_equal(1)
	var second := EndingLog.record(row, {"day": 14, "stage": 5})
	assert_int(int(second.get("count", 0))).is_equal(2)
	assert_str(String(second.get("first_seen", ""))).is_equal(String(first.get("first_seen", "")))
	assert_str(String(second.get("last_seen", ""))).is_not_equal(String(first.get("last_seen", "")))
	assert_str(String(second.get("path", ""))).is_equal("YANDERE")
	assert_int(EndingLog.count("E01")).is_equal(2)


## A fresh process reads the same answer: the cache is an optimisation, not the
## store.
func test_the_log_survives_a_restart() -> void:
	EndingLog.record(Endings.get_ending("E04"), {"day": 14, "stage": 5})
	EndingLog.clear_cache()
	assert_bool(EndingLog.seen("E04")).is_true()
	assert_int(EndingLog.seen_ids().size()).is_equal(1)
	var paths := EndingLog.seen_paths()
	assert_int(paths.size()).is_equal(1)
	assert_str(String(paths[0])).is_equal("SPLIT")


## Acceptance "persisted across saves": wiping the run must not touch the profile.
func test_a_new_run_keeps_the_log() -> void:
	EndingLog.record(Endings.get_ending("E01"), {"day": 14, "stage": 5})
	GameState.reset()
	assert_int(GameState.day).is_equal(1)
	assert_bool(EndingLog.seen("E01")).is_true()
	assert_bool(EndingLog.any_seen()).is_true()


## Only an ending that belongs to a path completes that path — E14 is "any path",
## so a burnout is not a reason to unlock the secret.
func test_only_a_path_ending_completes_a_path() -> void:
	EndingLog.record(Endings.get_ending("E14"), {"day": 6, "stage": 5})
	assert_bool(EndingLog.seen("E14")).is_true()
	assert_array(EndingLog.seen_paths()).is_empty()


func test_a_corrupt_log_starts_fresh_without_crashing() -> void:
	_write("{ this is not json")
	EndingLog.clear_cache()
	assert_bool(EndingLog.any_seen()).is_false()
	var written := EndingLog.record(Endings.get_ending("E06"), {"day": 14, "stage": 5})
	assert_int(int(written.get("count", 0))).is_equal(1)
	assert_bool(EndingLog.seen("E06")).is_true()


## An unknown record (a newer build, or a hand edit) is preserved on rewrite: this
## build must not truncate a log it does not fully understand.
func test_unknown_records_are_preserved() -> void:
	var stored := {
		"version": 1,
		"endings":
		{
			"E99":
			{
				"count": 3,
				"first_seen": "earlier",
				"last_seen": "earlier",
				"path": "",
				"day": 2,
				"stage": 1
			}
		},
	}
	_write(JSON.stringify(stored))
	EndingLog.clear_cache()
	assert_int(EndingLog.seen_ids().size()).is_equal(1)
	EndingLog.record(Endings.get_ending("E01"), {"day": 14, "stage": 5})
	EndingLog.clear_cache()
	var entries := _dict(EndingLog.data().get("endings", {}))
	assert_bool(entries.has("E99")).is_true()
	assert_bool(entries.has("E01")).is_true()
	assert_int(int(_dict(entries["E99"]).get("count", 0))).is_equal(3)


func test_wipe_removes_the_file_and_the_cache() -> void:
	EndingLog.record(Endings.get_ending("E10"), {"day": 14, "stage": 5})
	assert_bool(FileAccess.file_exists(LOG_PATH)).is_true()
	assert_bool(EndingLog.wipe()).is_true()
	assert_bool(FileAccess.file_exists(LOG_PATH)).is_false()
	assert_bool(EndingLog.any_seen()).is_false()
	assert_bool(EndingLog.wipe()).is_false()


func test_missing_file_is_an_empty_log() -> void:
	assert_bool(EndingLog.any_seen()).is_false()
	assert_dict(EndingLog.record_of("E01")).is_empty()
	assert_int(EndingLog.count("E01")).is_zero()


func _write(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clock() -> String:
	_clock_tick += 1
	return "2026-11-04T13:%02d:00" % _clock_tick


func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
