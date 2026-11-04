extends GdUnitTestSuite
## P3.07 — docs/01 §5 triggers T24–T32, including the two acceptance criteria
## that live here: the player's real name (T26) persists across a save and into
## the shadow save, and every row fires through the shipped seams.
##
## T24/T25/T27 are K rows and fire at submit; T26/T28/T29/T30 are M rows and
## fire at close with their guards deciding; T31/T32 go through Telemetry's real
## detectors (the screenshot key handler and the resize coalescer).

const EPS := 0.0001
const SAVE_DIR := "user://p307_t26_saves/"
const SHADOW_FILE := "user://p307_t26_shadow.json"
const IDS := ["T24", "T25", "T26", "T27", "T28", "T29", "T30", "T31", "T32"]


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	Memory.reset()
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)
	Telemetry.reset_session()


func after_test() -> void:
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)
	Telemetry.reset_session()


func test_t24_features_look_wrong() -> void:
	# docs/01 §5 T24 "she asks you to describe what you see. Sprite changes to
	# match": the line is the ask; the flag is the sprite request's channel.
	var lines := Triggers.begin_turn("your eyes look wrong")
	assert_int(_count("T24")).is_equal(1)
	assert_bool(bool(GameState.flags.get("feature_described_wrong", false))).is_true()
	assert_str(String(lines[0])).contains("describe exactly what they see")
	# A symptom report about her health is not a report about her face.
	GameState.reset()
	Triggers.clear_engine_events()
	assert_array(Triggers.begin_turn("your face is fine, how do you feel?")).is_empty()


func test_t25_dark_words_are_stage_gated() -> void:
	# docs/01 §5 T25 "Stage-gated: Stage 0 she's scared; Stage 4 she's
	# interested": the row is one K row and the tone lives in the line, because
	# the prompt's stage layer already knows the stage.
	var lines := Triggers.begin_turn("there is blood everywhere")
	assert_int(_count("T25")).is_equal(1)
	assert_float(GameState.get_meter(&"instability")).is_equal_approx(2.0, EPS)
	assert_str(String(lines[0])).contains("Stage 4 it interests you")


func test_t26_name_is_used_from_now_on() -> void:
	# docs/01 §5 T26 "She uses it from now on": the guard captures the name and
	# Triggers writes it to GameState.player_name — the prompt's own name field
	# (PromptBuilder reads it), never a log line.
	GameState.set_meter(&"instability", 20.0)  # stage 1
	Triggers.begin_turn("hi, my name is Ren")
	GameState.turn = 1
	var lines := Triggers.close_turn("small_talk")
	assert_int(_count("T26")).is_equal(1)
	assert_str(GameState.player_name).is_equal("Ren")
	assert_bool(bool(GameState.flags.get("name_confirmed", false))).is_true()
	assert_str(String(lines[0])).contains("Ren")
	# The row is `once`: a second introduction cannot rename the player.
	GameState.turn = 5
	Triggers.begin_turn("actually call me Alex")
	GameState.turn = 6
	assert_array(Triggers.close_turn("small_talk")).is_empty()
	assert_str(GameState.player_name).is_equal("Ren")


func test_t26_name_persists_across_saves() -> void:
	# Acceptance 3: the name is GameState state, so a slot round trip keeps it;
	# the shadow save (P3.12) is what carries it across a New Game. Privacy: the
	# name is the only personal datum either store keeps (docs/07 §3.5).
	var previous_saves := SaveSystem.save_dir
	var previous_shadow := SaveSystem.shadow_path
	SaveSystem.save_dir = SAVE_DIR
	SaveSystem.shadow_path = SHADOW_FILE
	GameState.set_meter(&"instability", 20.0)
	Triggers.begin_turn("my name is Ren")
	GameState.turn = 1
	Triggers.close_turn("small_talk")
	assert_str(GameState.player_name).is_equal("Ren")
	# A save slot keeps the run's name…
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	GameState.reset()
	assert_str(GameState.player_name).is_equal("Senpai")
	var loaded := SaveSystem.load_from_slot(1)
	assert_bool(bool(loaded["ok"])).is_true()
	assert_str(GameState.player_name).is_equal("Ren")
	# …and the shadow save of the ended run carries it across the New Game.
	GameState.day = 2  # the run "had a run" (P3.12's had_run)
	var sealed := SaveSystem.begin_new_game("Someone")
	assert_bool(bool(sealed["ok"])).is_true()
	var shadow := SaveSystem.shadow_data()
	assert_array(shadow.get("runs", [])).contains("Ren")
	assert_array(shadow.get("names", [])).contains("Someone")
	assert_array(shadow.get("names", [])).not_contains("Senpai")
	SaveSystem.save_dir = previous_saves
	SaveSystem.shadow_path = previous_shadow
	_remove_dir(SAVE_DIR)
	_remove_file(SHADOW_FILE)


func test_t26_rejects_commands_and_endearments() -> void:
	# The guard's exclude list is data: "call me later" is a command, not a
	# name, and neither is her own name or an endearment. CODE-4 added the
	# function words, or the `once` row renames the player "Not" for good.
	var turn := 0
	for text: String in [
		"call me Leila",
		"call me later",
		"call me when you get home",
		"my name is not important",
		"my name is just a name",
		"my name is still a secret",
		"my name is really boring",
	]:
		GameState.turn = turn
		Triggers.begin_turn(text)
		GameState.turn = turn + 1
		assert_array(Triggers.close_turn("small_talk")).is_empty()
		turn += 5
	assert_int(_count("T26")).is_equal(0)
	assert_str(GameState.player_name).is_equal("Senpai")
	assert_bool(bool(GameState.flags.get("name_confirmed", false))).is_false()


## CODE-3: `name_confirmed` means "she learned the name", so it belongs to the
## row's effects (a firing), not to `observe` (the read label alone). Any
## greeting used to set it, which would have skipped P3.14's name offer on the
## first small-talk turn.
func test_t26_name_confirmed_only_when_the_row_fires() -> void:
	Triggers.begin_turn("hi, how are you?")
	GameState.turn = 1
	Triggers.close_turn("greeting")
	assert_bool(bool(GameState.flags.get("name_confirmed", false))).is_false()
	assert_str(GameState.player_name).is_equal("Senpai")
	# A greeting that only mentions a name-shaped thing is still not a capture.
	GameState.turn = 2
	Triggers.begin_turn("call me later")
	GameState.turn = 3
	assert_array(Triggers.close_turn("greeting")).is_empty()
	assert_bool(bool(GameState.flags.get("name_confirmed", false))).is_false()
	# A real introduction is the firing that writes it.
	GameState.turn = 4
	Triggers.begin_turn("my name is Ren")
	GameState.turn = 5
	assert_array(Triggers.close_turn("small_talk")).has_size(1)
	assert_bool(bool(GameState.flags.get("name_confirmed", false))).is_true()
	assert_str(GameState.player_name).is_equal("Ren")


func test_t27_reset_words() -> void:
	# docs/01 §5 T27 "You'd kill me and start over? With a new me?" — the words
	# are a K row; "delete save" is the same intent.
	var lines := Triggers.begin_turn("I want to start over")
	assert_int(_count("T27")).is_equal(1)
	assert_float(GameState.get_meter(&"instability")).is_equal_approx(4.0, EPS)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_equal(2)
	assert_str(String(lines[0])).contains("a NEW you")


func test_t28_thanks_and_apology() -> void:
	# docs/01 §5 T28 "Thank her / apologize sincerely": model-only (M) plus the
	# text guard, a data-authored effect at double the intended value.
	Triggers.begin_turn("thank you for tonight")
	GameState.turn = 1
	var lines := Triggers.close_turn("affection")
	assert_int(_count("T28")).is_equal(1)
	assert_float(GameState.get_meter(&"lucidity")).is_equal_approx(2.0, EPS)
	assert_int(int(Triggers.path_scores().get("ANCHOR", 0))).is_equal(2)
	assert_str(String(lines[0])).contains("Anchor warmth")
	# Affection without thanks is not this row.
	GameState.reset()
	Triggers.clear_engine_events()
	Triggers.begin_turn("you are lovely")
	GameState.turn = 1
	assert_array(Triggers.close_turn("affection")).is_empty()
	# A sincere apology is the other half the docs name.
	Triggers.begin_turn("I'm sorry, I should not have said that")
	GameState.turn = 2
	assert_array(Triggers.close_turn("apology")).has_size(1)
	assert_int(_count("T28")).is_equal(1)


func test_t29_boundary() -> void:
	# docs/01 §5 T29 "she tries to honor it": ANCHOR +, and the boundary counter
	# P2.12's path formulas read.
	Triggers.begin_turn("please don't do that")
	GameState.turn = 1
	var lines := Triggers.close_turn("boundary")
	assert_int(_count("T29")).is_equal(1)
	assert_int(int(GameState.profile.get("boundaries", 0))).is_equal(1)
	assert_int(int(Triggers.path_scores().get("ANCHOR", 0))).is_equal(2)
	assert_str(String(lines[0])).contains("try to honor it")


func test_t30_her_past_escalates_its_answers() -> void:
	# docs/01 §5 T30 "She has none. Every answer is different. She notices." —
	# three escalating lines, each a new answer and then the noticing.
	var first := _ask_past(0, "what was your family like?")
	assert_int(_count("T30")).is_equal(1)
	assert_str(String(first[0])).contains("improvise an answer")
	var second := _ask_past(3, "where did you grow up?")
	assert_str(String(second[0])).contains("different answer")
	var third := _ask_past(6, "tell me about your childhood")
	assert_str(String(third[0])).contains("Every answer has been different")
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_greater(0)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_greater(0)
	# A question that is not about her past never reaches the row.
	GameState.turn = 9
	Triggers.begin_turn("what time is it?")
	GameState.turn = 10
	assert_array(Triggers.close_turn("question")).is_empty()


func test_t31_screenshot() -> void:
	# docs/01 §5 T31 "Take a screenshot (F12 / in-game camera)": Telemetry's own
	# detector, and `note_screenshot()` is the public seam both paths call —
	# the camera UI needs it in release builds, where `debug_fire` refuses
	# (CODE-6).
	Telemetry.set_date_active(true)
	assert_bool(Telemetry.note_screenshot()).is_true()
	assert_int(_count("T31")).is_equal(1)
	# The cooldown keeps a held key or a rapid double-tap to one event.
	assert_bool(Telemetry.note_screenshot()).is_false()
	var spoken := Telemetry.take_turn_events(0)
	assert_array(spoken["lines"]).contains("EVENT: The player took a screenshot of you.")


func test_t32_window_resize() -> void:
	# docs/01 §5 T32 "It's getting smaller in here", Stage 2+.
	GameState.set_meter(&"instability", 35.0)  # stage 2
	Telemetry.set_date_active(true)
	Telemetry.note_resized(Telemetry._resize_origin + Vector2i(64, 64))
	assert_int(_count("T32")).is_equal(1)
	var spoken := Telemetry.take_turn_events(2)
	assert_array(spoken["lines"]).contains("EVENT: The player resized the game window.")


func test_t24_t32_are_the_shipped_catalogue() -> void:
	# The nine rows exist with a name and evidence; the Python contract owns the
	# docs/01 §5 column checks, this only proves the suite reads shipped data.
	for trigger_id: String in IDS:
		var row := _row(trigger_id)
		assert_bool(row.is_empty()).is_false()
		assert_str(String(row.get("name", ""))).is_not_empty()
		var detect := row.get("detect", {}) as Dictionary
		var guard := row.get("guard", {}) as Dictionary
		assert_bool(detect.is_empty() and guard.is_empty()).is_false()


## ── Harness ───────────────────────────────────────────────────────────────


## One past-question turn at `turn`, returning the close lines.
func _ask_past(turn: int, text: String) -> Array[String]:
	GameState.turn = turn
	Triggers.begin_turn(text)
	GameState.turn = turn + 1
	return Triggers.close_turn("question")


func _row(id: String) -> Dictionary:
	TriggerEngine.clear_cache()
	return TriggerEngine.default_table()["triggers"].get(id, {}) as Dictionary


func _count(id: String) -> int:
	return int((Triggers.report()["counts"] as Dictionary).get(id, 0))


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_remove_dir(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path.trim_suffix("/"))
