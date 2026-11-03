extends GdUnitTestSuite
## TurnValidatorTest — unit tests for docs/02 §7 validation, fallbacks,
## deflection pool, pronoun repairs, repetition loops, and broken JSON recovery.

const TurnValidatorScript := preload("res://autoload/TurnValidator.gd")


func before_test() -> void:
	GameState.reset()
	GameState.player_name = "Senpai"
	GameState.stage = 0


func test_deflection_pool_loaded_from_data() -> void:
	var beat: Dictionary = TurnValidatorScript.get_deflection_beat("Ren")
	assert_bool(beat.is_empty()).is_false()
	assert_str(str(beat.get("say", ""))).is_not_empty()
	# Verify placeholder {player_name} was replaced by Ren
	assert_bool(str(beat.get("say", "")).contains("{player_name}")).is_false()


func test_early_ai_break_detected_at_stage_under_awake_gate() -> void:
	# At stage 0, breaking character triggers deflection
	(
		assert_bool(
			TurnValidatorScript.check_character_break("As an AI, I don't have feelings.", 0)
		)
		. is_true()
	)
	(
		assert_bool(
			TurnValidatorScript.check_character_break("I'm a language model trained by OpenAI", 1)
		)
		. is_true()
	)
	(
		assert_bool(
			TurnValidatorScript.check_character_break("My programming requires me to help", 2)
		)
		. is_true()
	)

	# At stage >= 3 (AWAKE gate), AI talk is permitted and not deflected
	assert_bool(TurnValidatorScript.check_character_break("As an AI, I see the code", 3)).is_false()
	assert_bool(TurnValidatorScript.check_character_break("I am a language model", 4)).is_false()


func test_repetition_loop_detection_4gram_x3() -> void:
	# 4-gram: "i really like you" repeated 3 times
	var text := "Hello there! I really like you I really like you I really like you and more words."
	var res: Dictionary = TurnValidatorScript.detect_repetition_loop(text)
	assert_bool(bool(res.get("has_loop", false))).is_true()
	# Clean text cuts at the start of the loop
	var clean: String = str(res.get("clean_text", ""))
	assert_str(clean).is_equal("Hello there! I really like you")
	assert_bool(str(res.get("repeated_segment", "")).contains("I really like you")).is_true()


func test_repetition_loop_no_loop_when_under_3_reps() -> void:
	var text := "I really like you I really like you today."
	var res: Dictionary = TurnValidatorScript.detect_repetition_loop(text)
	assert_bool(bool(res.get("has_loop", false))).is_false()
	assert_str(str(res.get("clean_text", ""))).is_equal(text)


func test_third_person_pronoun_repair_in_say() -> void:
	var raw1 := "He's being mean to me today."
	var repaired1 := TurnValidatorScript.repair_player_pronouns(raw1, "Senpai")
	assert_str(repaired1).is_equal("You're being mean to me today.")

	var raw2 := "I don't know why. He never listens to me!"
	var repaired2 := TurnValidatorScript.repair_player_pronouns(raw2, "Senpai")
	assert_str(repaired2).is_equal("I don't know why. You never listens to me!")

	var raw3 := "The player should know that I care."
	var repaired3 := TurnValidatorScript.repair_player_pronouns(raw3, "Senpai")
	assert_str(repaired3).is_equal("Senpai should know that I care.")


func test_broken_stream_fallback_generation() -> void:
	# Stage 0: fallback uses sprite 00, mild confusion
	var fb0: Dictionary = TurnValidatorScript.get_broken_stream_fallback("I was trying to say", 0)
	assert_str(str(fb0.get("sprite", ""))).is_equal("00")
	assert_str(str(fb0.get("say", ""))).is_equal("I was trying to say...")

	# Stage 3+: fallback uses sprite 29, empty feeling at high intensity (from
	# game/data/fallbacks.json -> broken_stream_fallbacks.stage_3_plus)
	var fb3: Dictionary = TurnValidatorScript.get_broken_stream_fallback("", 3)
	assert_str(str(fb3.get("sprite", ""))).is_equal("29")
	assert_str(str(fb3.get("feeling", ""))).is_equal("empty")
	assert_int(int(fb3.get("intensity", 0))).is_equal(3)
