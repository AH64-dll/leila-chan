extends GdUnitTestSuite
## P1.14 — Boot → Title → NewGame → Date scene flow contract (docs/08 §1.5).
## Covers:
## - Name rules of docs/08 §1.5: 1–16 chars, letters/spaces/-', Safety check, empty → "Senpai",
##   special "Leila" (+Fixation).
## - Name reaching PromptBuilder and the NameTag / ChatLog.
## - Flow from fresh launch, keyboard navigation, and Esc handling.

const BootScene := preload("res://scenes/Boot.tscn")
const TitleScene := preload("res://scenes/Title.tscn")
const NewGameScene := preload("res://scenes/NewGame.tscn")
const DateScene := preload("res://scenes/Date.tscn")
const RulesScr := preload("res://scenes/ui/PlayerNameRules.gd")
const GameStateScript := preload("res://autoload/GameState.gd")


func before_test() -> void:
	if has_node("/root/GameState"):
		GameState.reset()


## ── 1. Name rules (docs/08 §1.5) ──────────────────────────────────────────


func test_name_rules_empty_or_whitespace_resolves_to_senpai() -> void:
	var cases: Array[String] = ["", " ", "   ", "\t", "\n  \t"]
	for candidate: String in cases:
		var res: Dictionary = RulesScr.validate(candidate)
		assert_bool(bool(res["valid"])).is_true()
		assert_str(String(res["resolved_name"])).is_equal("Senpai")
		assert_str(String(res["error"])).is_empty()
		assert_bool(bool(res["is_special_leila"])).is_false()


func test_name_rules_valid_names_within_1_to_16_chars() -> void:
	var cases := {
		"Ren": "Ren",
		"A": "A",
		"SixteenLettersOk": "SixteenLettersOk",
		"Mary-Jane": "Mary-Jane",
		"O'Connor": "O'Connor",
		"John Doe": "John Doe",
		"René": "René",
		"  Padded  ": "Padded",
	}
	for raw: String in cases:
		var expected: String = cases[raw]
		var res: Dictionary = RulesScr.validate(raw)
		assert_bool(bool(res["valid"])).is_true()
		assert_str(String(res["resolved_name"])).is_equal(expected)
		assert_str(String(res["error"])).is_empty()
		assert_bool(bool(res["is_special_leila"])).is_false()


func test_name_rules_length_bounds() -> void:
	# 17 characters is over the 16 character limit
	var too_long := "SeventeenLetterss"
	assert_int(too_long.length()).is_equal(17)
	var res: Dictionary = RulesScr.validate(too_long)
	assert_bool(bool(res["valid"])).is_false()
	assert_str(String(res["error"])).is_equal("too_long")
	assert_str(String(res["message"])).is_equal("Name must be 16 characters or less.")


func test_name_rules_invalid_characters() -> void:
	var bad_cases: Array[String] = [
		"Player1",
		"Ren!",
		"Cool_Guy",
		"Senpai@home",
		"<script>",
		"User#1",
		"Hello$World",
		"Dot.Name",
	]
	for bad: String in bad_cases:
		var res: Dictionary = RulesScr.validate(bad)
		assert_bool(bool(res["valid"])).is_false()
		assert_str(String(res["error"])).is_equal("invalid_characters")
		assert_str(String(res["message"])).is_equal(
			"Only letters, spaces, hyphens, and apostrophes are allowed."
		)


func test_name_rules_safety_check_slurs_and_obscenity() -> void:
	var unsafe_words: Array[String] = ["bitch", "shit", "fuck", "nigger", "faggot"]
	for word: String in unsafe_words:
		var res: Dictionary = RulesScr.validate(word)
		assert_bool(bool(res["valid"])).is_false()
		assert_str(String(res["error"])).is_equal("unsafe")
		assert_str(String(res["message"])).is_equal(
			"That's not a real name… tell me your real one."
		)

	# Injected custom safety checker
	var blocked_name := "Voldemort"
	var custom_checker := func(n: String) -> bool: return n != "Voldemort"
	var res_custom: Dictionary = RulesScr.validate(blocked_name, custom_checker)
	assert_bool(bool(res_custom["valid"])).is_false()
	assert_str(String(res_custom["error"])).is_equal("unsafe")
	assert_str(String(res_custom["message"])).is_equal(
		"That's not a real name… tell me your real one."
	)


func test_name_rules_special_leila() -> void:
	var leila_variants: Array[String] = ["Leila", "leila", "LEILA", "  Leila  "]
	for variant: String in leila_variants:
		var res: Dictionary = RulesScr.validate(variant)
		assert_bool(bool(res["valid"])).is_true()
		assert_bool(bool(res["is_special_leila"])).is_true()
		assert_str(String(res["message"])).is_equal("That's *my* name. …Do you want to be me?")
		assert_str(String(res["resolved_name"])).is_equal(variant.strip_edges())


## ── 2. NewGame scene ───────────────────────────────────────────────────────


func test_new_game_scene_confirmation_sets_game_state() -> void:
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Ren"
	var spy := {"confirmed": false, "name": ""}
	scene.name_confirmed.connect(
		func(p_name: String) -> void:
			spy["confirmed"] = true
			spy["name"] = p_name
	)

	scene.confirm_name()

	assert_bool(bool(spy["confirmed"])).is_true()
	assert_str(String(spy["name"])).is_equal("Ren")
	assert_str(GameState.player_name).is_equal("Ren")


func test_new_game_scene_empty_sets_senpai() -> void:
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame

	scene.name_input.text = ""
	var spy := {"confirmed": false, "name": ""}
	scene.name_confirmed.connect(
		func(p_name: String) -> void:
			spy["confirmed"] = true
			spy["name"] = p_name
	)

	scene.confirm_name()

	assert_bool(bool(spy["confirmed"])).is_true()
	assert_str(String(spy["name"])).is_equal("Senpai")
	assert_str(GameState.player_name).is_equal("Senpai")


func test_new_game_scene_unsafe_name_displays_pout_and_blocks() -> void:
	var scene: Control = auto_free(NewGameScene.instantiate())
	add_child(scene)
	await get_tree().process_frame

	GameState.player_name = "Senpai"
	scene.name_input.text = "fuck"

	var spy := {"failed": false, "err": "", "msg": ""}
	scene.validation_failed.connect(
		func(err: String, msg: String) -> void:
			spy["failed"] = true
			spy["err"] = err
			spy["msg"] = msg
	)

	scene.confirm_name()

	assert_bool(bool(spy["failed"])).is_true()
	assert_str(String(spy["err"])).is_equal("unsafe")
	assert_str(String(spy["msg"])).is_equal("That's not a real name… tell me your real one.")
	assert_str(scene.feedback_label.text).is_equal("That's not a real name… tell me your real one.")
	# Name in GameState must NOT be modified on failure
	assert_str(GameState.player_name).is_equal("Senpai")


func test_new_game_scene_special_leila_bumps_fixation() -> void:
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame

	GameState.reset()
	var initial_fixation := GameState.fixation

	scene.name_input.text = "Leila"
	scene.confirm_name()

	assert_str(GameState.player_name).is_equal("Leila")
	assert_float(GameState.fixation).is_equal(initial_fixation + 5.0)


func test_new_game_scene_esc_requests_back() -> void:
	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame

	var spy := {"back": false}
	scene.back_requested.connect(func() -> void: spy["back"] = true)

	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	scene._unhandled_key_input(ev)

	assert_bool(bool(spy["back"])).is_true()


## ── 3. Name reaches PromptBuilder and NameTag ──────────────────────────────


func test_name_reaches_prompt_builder_and_name_tag() -> void:
	GameState.reset()
	GameState.player_name = "Ren"

	var date: Control = auto_free(DateScene.instantiate())
	add_child(date)
	await get_tree().process_frame

	# 1. Date scene has player name
	assert_str(date.get_player_name()).is_equal("Ren")

	# 2. PromptBuilder has player name
	assert_str(PromptBuilder.get_player_name()).is_equal("Ren")
	var built: Dictionary = PromptBuilder.build()
	var system_content := String(built["messages"][0]["content"])
	assert_bool(system_content.contains("Ren")).is_true()
	assert_str(String(built.get("player_name", ""))).is_equal("Ren")

	# 3. ChatUI has player name and uses it for player lines in ChatLog
	var chat: Control = date.chat_ui
	assert_str(chat.get_player_name()).is_equal("Ren")

	# Simulate player submitting a line
	chat.input_box.text = "Hello Leila!"
	chat.input_box.submitted.emit("Hello Leila!")

	var entries: Array = chat.chat_log.get_entries()
	assert_bool(entries.size() > 0).is_true()
	var first_entry: Dictionary = entries[0]
	assert_str(String(first_entry["speaker"])).is_equal("Ren")
	assert_str(String(first_entry["speaker_key"])).is_equal("player")
	assert_str(String(first_entry["text"])).is_equal("Hello Leila!")


## ── 4. Title scene and fresh launch flow ───────────────────────────────────


func test_title_scene_navigation_and_esc() -> void:
	var title: Control = auto_free(TitleScene.instantiate())
	title.scene_change_enabled = false
	add_child(title)
	await get_tree().process_frame

	assert_object(title.new_game_button).is_not_null()
	assert_object(title.continue_button).is_not_null()
	assert_object(title.settings_button).is_not_null()
	assert_object(title.quit_button).is_not_null()

	# Keyboard focus configuration
	assert_int(title.new_game_button.focus_mode).is_equal(Control.FOCUS_ALL)
	# Esc raises quit_requested
	var spy := {"quit": false}
	title.quit_requested.connect(func() -> void: spy["quit"] = true)

	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	title._unhandled_key_input(ev)

	assert_bool(bool(spy["quit"])).is_true()


func test_boot_scene_initialization() -> void:
	var boot: Node = auto_free(BootScene.instantiate())
	# Prevent automatic scene transition during unit test
	boot.set("auto_advance", false)
	add_child(boot)
	await get_tree().process_frame

	assert_str(boot.TITLE_SCENE_PATH).is_equal("res://scenes/Title.tscn")
	assert_bool(FileAccess.file_exists("res://scenes/Title.tscn")).is_true()
	assert_bool(FileAccess.file_exists("res://scenes/NewGame.tscn")).is_true()
	assert_bool(FileAccess.file_exists("res://scenes/Date.tscn")).is_true()
