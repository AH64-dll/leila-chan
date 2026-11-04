extends GdUnitTestSuite
## P3.10 — the docs/05 §1.3 M23/M24 edit ledger and its way back: every rewritten
## line keeps the player's words in the entry (so a save never stores the lie),
## the log renders her version, and the Extras menu lists and restores it
## (docs/05 §0 rule 5 + docs/05 §3's "what happened" review).

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const ExtrasPacked := preload("res://scenes/Extras.tscn")
const TMP_DIR := "user://meta_log_edits_test/"
const LEDGER := TMP_DIR + "log_edits.json"
const ENDING_LOG := TMP_DIR + "endings.json"

var _snapshot := {}


func before_test() -> void:
	_snapshot = GameState.to_dict()
	GameState.reset()
	_remove_dir(TMP_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	MetaLogEdits.use_path(LEDGER)
	EndingLog.use_path(ENDING_LOG)
	EndingLog.set_clock(func() -> String: return "2026-11-04T12:00:00")
	EndingLog.clear_cache()


func after_test() -> void:
	await get_tree().process_frame
	MetaLogEdits.set_clock(Callable())
	MetaLogEdits.use_path("")
	EndingLog.use_path("")
	EndingLog.set_clock(Callable())
	EndingLog.clear_cache()
	_remove_dir(TMP_DIR)
	if not _snapshot.is_empty():
		GameState.from_dict(_snapshot)
	_snapshot = {}


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


func _open_extras() -> Node:
	var extras: Node = ExtrasPacked.instantiate()
	extras.scene_change_enabled = false
	add_child(auto_free(extras))
	await get_tree().process_frame
	return extras


## ── The ledger ────────────────────────────────────────────────────────────


func test_a_recorded_edit_is_shown_and_the_original_is_kept() -> void:
	assert_bool(MetaLogEdits.record("M23", "player", "I like you", 1, "I love you")).is_true()
	assert_int(MetaLogEdits.count()).is_equal(1)
	assert_str(MetaLogEdits.shown("player", "I like you", 1)).is_equal("I love you")
	assert_str(MetaLogEdits.shown("player", "I like you", 2)).is_equal("I like you")
	assert_str(MetaLogEdits.shown("her", "I like you", 1)).is_equal("I like you")
	var rows: Array = MetaLogEdits.rows()
	assert_str(String(rows[0]["original"])).is_equal("I like you")


func test_identical_lines_are_told_apart_by_occurrence() -> void:
	MetaLogEdits.record("M23", "player", "ok", 2, "yes")
	assert_str(MetaLogEdits.shown("player", "ok", 1)).is_equal("ok")
	assert_str(MetaLogEdits.shown("player", "ok", 2)).is_equal("yes")


func test_a_second_lie_replaces_the_first_row() -> void:
	MetaLogEdits.record("M23", "player", "maybe later", 1, "always now")
	MetaLogEdits.record("M23", "player", "maybe later", 1, "always")
	assert_int(MetaLogEdits.count()).is_equal(1)
	assert_str(MetaLogEdits.shown("player", "maybe later", 1)).is_equal("always")


func test_restore_all_clears_the_lie_and_reports_how_many() -> void:
	MetaLogEdits.record("M23", "player", "a message", 1, "her version")
	MetaLogEdits.record("M24", "her", "an old line", 1, "her memory")
	assert_int(MetaLogEdits.restore_all()).is_equal(2)
	assert_int(MetaLogEdits.count()).is_equal(0)
	assert_str(MetaLogEdits.shown("player", "a message", 1)).is_equal("a message")


## A corrupt or hand-edited ledger must never block play or resurrect an edit.
func test_a_broken_ledger_reads_as_empty() -> void:
	var file := FileAccess.open(LEDGER, FileAccess.WRITE)
	file.store_string("[1, 2, 3]")  # valid JSON, wrong shape
	file.close()
	MetaLogEdits.reset_cache()
	assert_int(MetaLogEdits.count()).is_equal(0)
	assert_str(MetaLogEdits.shown("player", "I like you", 1)).is_equal("I like you")


func test_the_ledger_lives_under_user_dir() -> void:
	assert_bool(MetaLogEdits.PATH.begins_with("user://.leila/")).is_true()


## ── The log: her version on screen, the truth in the entry ────────────────


func test_the_log_renders_her_version_and_restores_the_players() -> void:
	var ui := await _new_chat()
	ui.chat_log.append_entry("player", "Senpai", "I like you")
	var list: Node = ui.chat_log.get("_list")
	assert_str((list.get_child(0) as Label).text).is_equal("Senpai: I like you")
	MetaLogEdits.record("M23", "player", "I like you", 1, "I love you")
	ui.chat_log.rerender()
	assert_str((list.get_child(0) as Label).text).is_equal("Senpai: I love you")
	# The entry is the player's line; only the paint is hers.
	assert_str(String(ui.chat_log.get_entries()[0]["text"])).is_equal("I like you")
	MetaLogEdits.restore_all()
	ui.chat_log.rerender()
	assert_str((list.get_child(0) as Label).text).is_equal("Senpai: I like you")


## A save stores the entry, and a reload re-paints her version from the ledger —
## so the edit survives the reload while the player's words stay recoverable.
func test_a_reloaded_log_still_shows_the_lie_until_it_is_restored() -> void:
	var ui := await _new_chat()
	ui.chat_log.append_entry("player", "Senpai", "I like you")
	MetaLogEdits.record("M23", "player", "I like you", 1, "I love you")
	var saved: Array = ui.chat_log.get_entries()
	var restored_ui := await _new_chat()
	restored_ui.chat_log.restore_entries(saved)
	var list: Node = restored_ui.chat_log.get("_list")
	assert_str((list.get_child(0) as Label).text).is_equal("Senpai: I love you")
	MetaLogEdits.restore_all()
	restored_ui.chat_log.rerender()
	assert_str((list.get_child(0) as Label).text).is_equal("Senpai: I like you")


## ── Extras: the review and the way back ───────────────────────────────────


func test_extras_lists_the_rewrites_and_restores_them() -> void:
	var ui := await _new_chat()
	ui.chat_log.append_entry("player", "Senpai", "I like you")
	MetaLogEdits.record("M23", "player", "I like you", 1, "I love you")
	var extras := await _open_extras()
	assert_int(extras.log_edits().size()).is_equal(1)
	assert_int(extras.restore_log_edits()).is_equal(1)
	assert_int(extras.log_edits().size()).is_equal(0)
	# The live log came back with the player's own words.
	var list: Node = ui.chat_log.get("_list")
	assert_str((list.get_child(0) as Label).text).is_equal("Senpai: I like you")


func test_extras_says_so_when_nothing_was_rewritten() -> void:
	var extras := await _open_extras()
	assert_array(extras.log_edits()).is_empty()
	# The section is drawn either way (docs/05 §0 rule 5: the review exists even
	# when it is empty), and its restore button only appears with something to
	# restore — so `restore_log_edits()` is a safe no-op.
	assert_int(extras.restore_log_edits()).is_equal(0)
	assert_dict(EndingLog.record_of("E01")).is_empty()  # nothing else was touched


func test_record_timestamp_uses_injected_clock() -> void:
	MetaLogEdits.set_clock(func() -> int: return 1_700_000_123)
	assert_bool(MetaLogEdits.record("M23", "player", "hello", 1, "hi")).is_true()
	var rows: Array = MetaLogEdits.rows()
	assert_int(int(rows[0].get("at", 0))).is_equal(1_700_000_123)


func test_game_state_reset_clears_edits_from_memory_and_disk() -> void:
	MetaLogEdits.record("M23", "player", "I like you", 1, "I love you")
	assert_int(MetaLogEdits.count()).is_equal(1)
	assert_bool(FileAccess.file_exists(LEDGER)).is_true()
	GameState.reset()
	assert_int(MetaLogEdits.count()).is_equal(0)
	assert_str(MetaLogEdits.shown("player", "I like you", 1)).is_equal("I like you")
	assert_bool(FileAccess.file_exists(LEDGER)).is_false()


func test_begin_new_game_clears_edits_from_memory_and_disk() -> void:
	MetaLogEdits.record("M23", "player", "I like you", 1, "I love you")
	assert_int(MetaLogEdits.count()).is_equal(1)
	assert_bool(FileAccess.file_exists(LEDGER)).is_true()
	SaveSystem.begin_new_game("Ren")
	assert_int(MetaLogEdits.count()).is_equal(0)
	assert_str(MetaLogEdits.shown("player", "I like you", 1)).is_equal("I like you")
	assert_bool(FileAccess.file_exists(LEDGER)).is_false()
