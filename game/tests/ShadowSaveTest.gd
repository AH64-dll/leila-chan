extends GdUnitTestSuite
## P3.12 — shadow save `user://.leila/shadow.json` + Settings → "Reset
## Everything" (docs/05 M08, docs/07 §3.5).
##
## Acceptance 1 (survives New Game): a stage-3+ run's name/first_name and a
## few of its memories are still in the shadow file AFTER GameState+Director
## reset wiped the run — NewGame calls `SaveSystem.begin_new_game` before the
## reset, so "she remembers" is file-backed, not a live-state leak.
##
## Acceptance 2 (Reset Everything deletes it): `Settings.reset_everything()`
## removes every file under the user root — slots, the shadow save, letters,
## diary, debug — except the settings file itself.
##
## Acceptance 3 (contents documented): the file IS the docs — ShadowStore.gd's
## PRIVACY block lists every key; a test asserts the written envelope carries
## only those keys and nothing else.

const TEST_ROOT := "user://shadow_test/"
const SHADOW_PATH := TEST_ROOT + ".leila/shadow.json"
const SETTINGS_PATH := TEST_ROOT + "settings.cfg"

var _previous_dir := ""
var _previous_shadow := ""
var _previous_root := ""
var _previous_settings := ""


func before_test() -> void:
	_previous_dir = SaveSystem.save_dir
	_previous_shadow = SaveSystem.shadow_path
	_previous_root = SaveSystem.user_root
	_previous_settings = Settings.settings_path
	SaveSystem.save_dir = TEST_ROOT + "saves"
	SaveSystem.shadow_path = SHADOW_PATH
	SaveSystem.user_root = TEST_ROOT
	Settings.settings_path = SETTINGS_PATH
	SaveSystem.consume_pending_scene()
	_reset_game()


func after_test() -> void:
	_remove_tree(TEST_ROOT)
	SaveSystem.save_dir = _previous_dir
	SaveSystem.shadow_path = _previous_shadow
	SaveSystem.user_root = _previous_root
	Settings.settings_path = _previous_settings
	SaveSystem.consume_pending_scene()
	_reset_game()


## Acceptance 1: first_name, names, runs and the kept memories all survive a
## full New Game reset — and the file carried them (re-read after the wipe).
func test_shadow_survives_new_game_and_keeps_stage3_memories() -> void:
	assert_bool(bool(SaveSystem.begin_new_game("Ren")["ok"])).is_true()
	_play_stage3_run("Ren")
	var written := SaveSystem.begin_new_game("Aya")
	assert_bool(bool(written["ok"])).is_true()
	# The New Game wipe: nothing live may carry the old run.
	GameState.reset()
	Director.reset()
	assert_array(Memory.facts()).is_empty()

	var shadow := SaveSystem.shadow_data()
	assert_str(String(shadow["first_name"])).is_equal("Ren")
	assert_array(shadow["names"]).contains_exactly(["Ren", "Aya"])
	assert_array(shadow["runs"]).contains_exactly(["Ren"])
	# memory.json shadow.limit = 3 → a few memories: the quoted fact first,
	# then the newest of the equal-importance rest.
	assert_array(shadow["memories"]).contains_exactly(
		["gave me a music box", "hates loud people", "fears the aquarium"]
	)


## M08's gate: a run that never reached stage 3 seals its name and the run —
## but NO memories ("she remembers" is the deteriorated-her trick).
func test_new_game_below_meta_gate_keeps_names_but_no_memories() -> void:
	assert_bool(bool(SaveSystem.begin_new_game("Ren")["ok"])).is_true()
	GameState.player_name = "Ren"
	GameState.turn = 3
	GameState.day = 2
	GameState.set_meter(&"instability", 10.0)  # still stage 0
	Memory.consider("likes film alpha", ["I like film alpha"])
	assert_bool(bool(SaveSystem.begin_new_game("Aya")["ok"])).is_true()
	var shadow := SaveSystem.shadow_data()
	assert_array(shadow["names"]).contains_exactly(["Ren", "Aya"])
	assert_array(shadow["runs"]).contains_exactly(["Ren"])
	assert_array(shadow["memories"]).is_empty()


## docs/08 §1.5: the FIRST name ever typed is fixed; repeats dedupe.
func test_first_name_never_overwritten_and_names_dedupe() -> void:
	assert_bool(bool(SaveSystem.begin_new_game("Ren")["ok"])).is_true()
	GameState.player_name = "Ren"
	GameState.turn = 1  # a real run so it seals
	assert_bool(bool(SaveSystem.begin_new_game("Aya")["ok"])).is_true()
	GameState.player_name = "Aya"
	GameState.turn = 1
	assert_bool(bool(SaveSystem.begin_new_game("Ren")["ok"])).is_true()
	var shadow := SaveSystem.shadow_data()
	assert_str(String(shadow["first_name"])).is_equal("Ren")
	assert_array(shadow["names"]).contains_exactly(["Ren", "Aya"])
	assert_array(shadow["runs"]).contains_exactly(["Ren", "Aya"])
	assert_str(SaveSystem.shadow_first_name()).is_equal("Ren")
	assert_array(SaveSystem.shadow_memories()).is_empty()


## No run behind it: a first-ever New Game seals nothing but the name.
func test_first_ever_new_game_records_no_run() -> void:
	assert_bool(bool(SaveSystem.begin_new_game("Ren")["ok"])).is_true()
	var shadow := SaveSystem.shadow_data()
	assert_str(String(shadow["first_name"])).is_equal("Ren")
	assert_array(shadow["names"]).contains_exactly(["Ren"])
	assert_array(shadow["runs"]).is_empty()


## Corruption is a value: a present-but-broken shadow file reads as an error,
## readers see the blank shape, and the next New Game rewrites it cleanly.
func test_corrupt_shadow_reads_safe_and_is_replaced() -> void:
	_write_raw(SHADOW_PATH, "{not json")
	var read := SaveSystem.shadow.load_shadow()
	assert_bool(bool(read["ok"])).is_false()
	assert_str(String(read["error"])).is_equal("corrupt")
	assert_str(SaveSystem.shadow_first_name()).is_equal("")
	assert_array(SaveSystem.shadow_memories()).is_empty()
	assert_bool(bool(SaveSystem.begin_new_game("Ren")["ok"])).is_true()
	assert_str(SaveSystem.shadow_first_name()).is_equal("Ren")


## Acceptance 3: the envelope contains exactly the documented keys — a player
## (or reviewer) verifying the privacy promise finds nothing else in the file.
func test_shadow_file_contains_only_the_documented_keys() -> void:
	assert_bool(bool(SaveSystem.begin_new_game("Ren")["ok"])).is_true()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHADOW_PATH))
	assert_object(parsed).is_not_null()
	var envelope := parsed as Dictionary
	assert_str(String(envelope["format"])).is_equal("leila.shadow")
	assert_dict(envelope).contains_keys(["format", "version", "checksum", "payload"])
	assert_int(envelope.keys().size()).is_equal(4)
	var payload := envelope["payload"] as Dictionary
	assert_dict(payload).contains_keys(["first_name", "names", "runs", "memories"])
	assert_int(payload.keys().size()).is_equal(4)


## Acceptance 2: Reset Everything removes the shadow save, every slot and any
## other user files — the settings file alone survives.
func test_reset_everything_deletes_shadow_and_slots_but_keeps_settings() -> void:
	_play_stage3_run("Ren")
	assert_bool(bool(SaveSystem.begin_new_game("Aya")["ok"])).is_true()
	assert_bool(FileAccess.file_exists(SHADOW_PATH)).is_true()
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	assert_bool(bool(SaveSystem.save_to_slot("auto")["ok"])).is_true()
	Settings.save_settings()  # a real settings.cfg in the wiped tree
	_write_raw(TEST_ROOT + "letters/for_Ren.txt", "for you")
	_write_raw(TEST_ROOT + "debug/turns_x.jsonl", "{}")

	var result := Settings.reset_everything()

	assert_bool(bool(result["ok"])).is_true()
	assert_bool(FileAccess.file_exists(SHADOW_PATH)).is_false()
	assert_array(SaveSystem.list_slots()).is_empty()
	assert_bool(DirAccess.dir_exists_absolute(TEST_ROOT + "letters")).is_false()
	assert_bool(DirAccess.dir_exists_absolute(TEST_ROOT + "debug")).is_false()
	assert_bool(DirAccess.dir_exists_absolute(TEST_ROOT + "saves")).is_false()
	# The one survivor: settings.cfg (docs/07 §3.5 keeps it).
	assert_bool(FileAccess.file_exists(SETTINGS_PATH)).is_true()
	# And readers agree the shadow is gone, not merely hidden.
	assert_str(SaveSystem.shadow_first_name()).is_equal("")
	assert_bool(SaveSystem.shadow.erase()).is_false()


# ------------------------------------------------------------------ fixtures


## A stage-3+ run as Ren with three memories where "gave me a music box" was
## quoted once — importance 2 beats importance 1, so the keep order is pinned.
func _play_stage3_run(run_name: String) -> void:
	GameState.reset()
	Director.reset()
	GameState.player_name = run_name
	GameState.day = 5
	GameState.turn = 9
	GameState.set_meter(&"instability", 55.0)  # stage 3 band
	Memory.consider("likes film alpha", ["I like film alpha"])
	Memory.consider("fears the aquarium", ["the aquarium scares me"])
	Memory.consider("gave me a music box", ["I got you a music box"])
	Memory.consider("hates loud people", ["loud people bother me"])
	Memory.note_quotes("I still have the music box.")


func _reset_game() -> void:
	Director.reset()
	GameState.reset()
	Memory.reset()


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _remove_tree(path: String) -> void:
	# A trailing "/" makes DirAccess.remove_absolute refuse the root itself —
	# normalize before recursing or the scratch tree leaks into the next test.
	var root := path.trim_suffix("/")
	if not DirAccess.dir_exists_absolute(root):
		return
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.set_include_hidden(true)  # .leila/ is hidden; the scratch must not leak
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := root.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(child)
		DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(root)
