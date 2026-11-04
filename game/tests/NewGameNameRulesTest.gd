extends GdUnitTestSuite
## P3.14 — New Game name rules: special names (OS username behind the opt-in,
## "Leila") and shadow name memory at the New Game screen (docs/08 §1.5).
## Split from NameRulesTest.gd (max-public-methods).

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const NewGameScene := preload("res://scenes/NewGame.tscn")
const TEST_ROOT := "user://name_rules_test/"
const SETTINGS_PATH := TEST_ROOT + "settings.cfg"

var _previous_settings := ""
var _previous_flag := false
var _previous_shadow := ""
var _previous_user := ""
var _previous_username := ""


func before_test() -> void:
	_previous_settings = Settings.settings_path
	_previous_flag = Settings.use_os_username
	_previous_shadow = SaveSystem.shadow_path
	# The opt-in tests mutate the process environment; capture it first so a
	# failing assert cannot leak USER/USERNAME into a later suite (CODE-5).
	_previous_user = OS.get_environment("USER")
	_previous_username = OS.get_environment("USERNAME")
	Settings.settings_path = SETTINGS_PATH
	SaveSystem.shadow_path = TEST_ROOT + ".leila/shadow.json"
	# The settings store writes the file, it never creates the folder (the
	# game's own `user://` root always exists), so the fixture must.
	DirAccess.make_dir_recursive_absolute(TEST_ROOT)
	Settings.use_os_username = false
	Corruption.clear_cache()
	GameState.reset()
	Director.reset()


func after_test() -> void:
	OS.set_environment("USER", _previous_user)
	OS.set_environment("USERNAME", _previous_username)
	Settings.settings_path = _previous_settings
	Settings.use_os_username = _previous_flag
	SaveSystem.shadow_path = _previous_shadow
	Corruption.clear_cache()
	GameState.reset()
	Director.reset()
	_remove_tree(TEST_ROOT)


func test_tag_swap_happens_once_per_chat_log() -> void:
	var ui: Control = auto_free(ChatUIScene.instantiate())
	add_child(ui)
	await get_tree().process_frame
	ui.set_stage(5)
	ui.set_player_name("Renji")
	# find a turn index where the roll fires, then jump there
	var target := -1
	for t: int in range(1, 60):
		if Corruption.should_swap_name_tag(5, t, 0):
			target = t
			break
	assert_int(target).is_greater(0)
	ui._turn_seq = target - 1
	assert_str(ui.player_tag_for(target)).is_equal("Leila")
	# one line: the tag is hers exactly once, then back to his name
	assert_str(ui.player_tag_for(target + 1)).is_equal("Renji")
	assert_str(ui.player_tag_for(target + 2)).is_equal("Renji")


func test_tag_swap_below_stage_5_keeps_player_tag() -> void:
	var ui: Control = auto_free(ChatUIScene.instantiate())
	add_child(ui)
	await get_tree().process_frame
	ui.set_stage(4)
	ui.set_player_name("Renji")
	for t: int in range(1, 30):
		assert_str(ui.player_tag_for(t)).is_equal("Renji")


func test_submit_swapped_tag_lands_in_chat_log() -> void:
	var ui: Control = auto_free(ChatUIScene.instantiate())
	add_child(ui)
	await get_tree().process_frame
	ui.set_stage(5)
	ui.set_player_name("Renji")
	var target := -1
	for t: int in range(1, 60):
		if Corruption.should_swap_name_tag(5, t, 0):
			target = t
			break
	ui._turn_seq = target - 1
	ui.input_box.submitted.emit("hello")
	await get_tree().process_frame
	var entries: Array = ui.chat_log.get_entries()
	assert_int(entries.size()).is_equal(1)
	assert_str(str(entries[0]["speaker"])).is_equal("Leila")
	assert_str(str(entries[0]["text"])).is_equal("hello")


## ── 6. the opt-in gate ──────────────────────────────────────────────────────


func test_settings_os_username_opt_in_gate() -> void:
	# Opt-in off: the env IS readable, yet the game must see "" — the gate is
	# the flag, not the match, so the assertion has to run with the flag OFF.
	OS.set_environment("USER", "ci_test_player")
	OS.set_environment("USERNAME", "")
	Settings.use_os_username = false
	assert_str(Settings.os_username()).is_equal("")
	# Opt-in on: USERNAME is preferred, USER is the fallback.
	Settings.use_os_username = true
	assert_str(Settings.os_username()).is_equal("ci_test_player")
	OS.set_environment("USER", "")
	OS.set_environment("USERNAME", "windows_name")
	assert_str(Settings.os_username()).is_equal("windows_name")
	# Both set: USERNAME wins (Windows carries both).
	OS.set_environment("USER", "ci_test_player")
	assert_str(Settings.os_username()).is_equal("windows_name")


func test_settings_use_os_username_persists() -> void:
	Settings.settings_path = SETTINGS_PATH
	Settings.set_use_os_username(true)
	var cfg := ConfigFile.new()
	assert_int(cfg.load(SETTINGS_PATH)).is_equal(OK)
	assert_bool(bool(cfg.get_value("privacy", "use_os_username", false))).is_true()
	Settings.use_os_username = false
	Settings.load_settings()
	assert_bool(Settings.use_os_username).is_true()


## ── 7. shadow name memory ─────────────────────────────────────────────────


func test_shadow_name_message_fires_after_stage3_run_with_new_name() -> void:
	assert_str(PlayerNameRules.shadow_name_message("Haru", "Ren", 3)).is_equal(
		"That's not what you were called last time."
	)
	assert_str(PlayerNameRules.shadow_name_message("Haru", "Ren", 5)).is_equal(
		"That's not what you were called last time."
	)


func test_shadow_name_message_silent_below_stage3_or_same_name() -> void:
	assert_str(PlayerNameRules.shadow_name_message("Haru", "Ren", 2)).is_empty()
	assert_str(PlayerNameRules.shadow_name_message("Ren", "Ren", 4)).is_empty()
	# case-insensitive: "ren" after "Ren" is the same name
	assert_str(PlayerNameRules.shadow_name_message("ren", "Ren", 4)).is_empty()
	# no first name on file (first-ever run) → nothing to compare
	assert_str(PlayerNameRules.shadow_name_message("Haru", "", 4)).is_empty()


func test_shadow_name_message_silent_for_a_name_she_already_knows() -> void:
	# The shadow's `names` list: "Haru" was used before, so it is not news and
	# the line fires once per name, not every run.
	assert_str(PlayerNameRules.shadow_name_message("Haru", "Ren", 3, ["Ren", "Haru"])).is_empty()
	# A brand-new name still earns the line.
	assert_str(PlayerNameRules.shadow_name_message("Sora", "Ren", 3, ["Ren", "Haru"])).is_equal(
		"That's not what you were called last time."
	)


func test_new_game_no_shadow_line_for_a_name_she_already_knows() -> void:
	# A run as "Ren", then a full run as "Haru" (P3.12 appends every confirmed
	# name to `names`). The next New Game under "Haru" must be silent.
	SaveSystem.begin_new_game("Ren")
	SaveSystem.begin_new_game("Haru")
	var known: Array = SaveSystem.shadow_data().get("names", [])
	assert_int(known.size()).is_equal(2)
	assert_bool(known.has("Ren")).is_true()
	assert_bool(known.has("Haru")).is_true()
	GameState.reset()
	GameState.player_name = "Haru"
	GameState.set_meter(&"instability", 55.0)
	assert_int(GameState.stage).is_equal(3)
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Haru"
	scene.confirm_name()
	await get_tree().process_frame
	assert_str(scene.feedback_label.text).is_equal("")


func test_new_game_shows_shadow_line_after_stage3_run_with_different_name() -> void:
	# First-ever New Game recorded "Ren" in the shadow save (P3.12), and that
	# run ended at stage 3. A new game under "Haru": she notices the change.
	SaveSystem.begin_new_game("Ren")
	GameState.reset()
	GameState.player_name = "Ren"
	GameState.day = 4
	GameState.turn = 7
	GameState.set_meter(&"instability", 55.0)  # stage 3 band (50–69)
	assert_int(GameState.stage).is_equal(3)
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Haru"
	scene.confirm_name()
	await get_tree().process_frame

	assert_str(scene.feedback_label.text).is_equal("That's not what you were called last time.")


func test_new_game_no_shadow_line_below_stage3() -> void:
	SaveSystem.begin_new_game("Ren")
	GameState.reset()
	GameState.player_name = "Ren"
	GameState.set_meter(&"instability", 10.0)  # stage 0
	assert_int(GameState.stage).is_equal(0)
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Haru"
	scene.confirm_name()
	await get_tree().process_frame

	assert_str(scene.feedback_label.text).is_equal("")


func test_new_game_os_username_shows_truth_line() -> void:
	# A real account name is typable, so the match is the case-insensitive one
	# the docs describe.
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	scene.os_username_override = "amr"
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Amr"
	scene.confirm_name()
	await get_tree().process_frame
	assert_str(scene.feedback_label.text).is_equal("You told me the truth. Good.")


func test_new_game_truth_line_for_an_underscore_account_name() -> void:
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	scene.os_username_override = "john_doe"
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "John Doe"
	scene.confirm_name()
	await get_tree().process_frame
	assert_str(scene.feedback_label.text).is_equal("You told me the truth. Good.")


func test_new_game_flag_off_with_env_set_shows_no_truth_line() -> void:
	# The production path end to end: the environment carries the account name
	# and the player types exactly that name, but the opt-in is off, so the
	# field sees "" and nothing is revealed (CODE-5).
	OS.set_environment("USER", "envplayer")
	OS.set_environment("USERNAME", "")
	Settings.use_os_username = false
	assert_str(Settings.os_username()).is_equal("")
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "envplayer"
	scene.confirm_name()
	await get_tree().process_frame
	assert_str(scene.feedback_label.text).is_equal("")
	assert_str(GameState.player_name).is_equal("envplayer")


func test_new_game_same_name_no_shadow_line() -> void:
	SaveSystem.begin_new_game("Ren")
	GameState.reset()
	GameState.player_name = "Ren"
	GameState.set_meter(&"instability", 55.0)
	assert_int(GameState.stage).is_equal(3)
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Ren"
	scene.confirm_name()
	await get_tree().process_frame
	assert_str(scene.feedback_label.text).is_equal("")


func test_new_game_shadow_line_survives_a_relaunch() -> void:
	# Process 1: a run as "Ren" reaches stage 3 and the player starts over, so
	# the seal stores that stage in the shadow (the live stage is gone with the
	# process).
	SaveSystem.begin_new_game("Ren")
	GameState.player_name = "Ren"
	GameState.day = 4
	GameState.turn = 7
	GameState.set_meter(&"instability", 55.0)  # stage 3 band (50–69)
	assert_int(GameState.stage).is_equal(3)
	SaveSystem.begin_new_game("Ren")
	assert_int(int(SaveSystem.shadow_data().get("last_stage", 0))).is_equal(3)
	# Process 2: a fresh launch starts at stage 0 / day 1 / turn 0. The line
	# must still fire — that is the flow the shadow save exists for (DES-2).
	GameState.reset()
	assert_int(GameState.stage).is_equal(0)
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Haru"
	scene.confirm_name()
	await get_tree().process_frame
	assert_str(scene.feedback_label.text).is_equal("That's not what you were called last time.")


func test_new_game_shadow_line_silent_when_the_sealed_run_stayed_low() -> void:
	# The stored stage is a real gate, not "any sealed run": a stage-1 run does
	# not earn the line in the next process either.
	SaveSystem.begin_new_game("Ren")
	GameState.player_name = "Ren"
	GameState.day = 3
	GameState.turn = 5
	GameState.set_meter(&"instability", 12.0)  # stage 0
	assert_int(GameState.stage).is_equal(0)
	SaveSystem.begin_new_game("Ren")
	assert_int(int(SaveSystem.shadow_data().get("last_stage", 0))).is_equal(0)
	GameState.reset()
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Haru"
	scene.confirm_name()
	await get_tree().process_frame
	assert_str(scene.feedback_label.text).is_equal("")


func test_session_stage2_never_decays() -> void:
	for turn: int in range(1, 10):
		var session := CorruptionSession.new()
		session.begin_turn({"turn": turn, "stage": 2, "player_name": "Renji"})
		var out := session.transform_beat(0, "Renji, stay with me.")
		assert_bool(out.contains("… Renji")).is_false()


## ── helpers ───────────────────────────────────────────────────────────────


func _remove_tree(path: String) -> void:
	var root := path.trim_suffix("/")
	if not DirAccess.dir_exists_absolute(root):
		return
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.set_include_hidden(true)
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
