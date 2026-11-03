extends GdUnitTestSuite
## P1.06 — PromptBuilder, history side: the sliding 12-exchange window and the
## docs/08 §1 rule that assistant turns are stored as the spoken text only,
## never as JSON (so old cues cannot be copied out of the context).
##
## Split from res://tests/test_prompt_builder.gd because gdlint caps a suite at
## 20 public methods (the GameState suite is split the same way).

const BuilderScript := preload("res://autoload/PromptBuilder.gd")


func _builder() -> BuilderScript:
	var builder: BuilderScript = auto_free(BuilderScript.new())
	return builder


func _entry(role: String, text: String) -> Dictionary:
	return {"role": role, "text": text}


func _ctx(history: Array) -> Dictionary:
	return {
		"stage": 1,
		"player_name": "Ren",
		"history": history,
		"player_message": "And then?",
	}


## The non-system roles, in message order.
func _roles(result: Dictionary) -> Array:
	var roles: Array = []
	for message: Dictionary in result["messages"]:
		var role := String(message["role"])
		if role != "system":
			roles.append(role)
	return roles


func _history(result: Dictionary) -> Dictionary:
	return result["debug"]["history"]


# --- acceptance criterion 2: assistant history is spoken text, not JSON -----


func test_assistant_history_is_stored_as_spoken_text() -> void:
	var turn := {
		"role": "assistant",
		"read": "gift",
		"inner": "He knows me already.",
		"music": "romantic",
		"beats":
		[
			{"feeling": "surprised", "intensity": 2, "cue": "gasp", "say": "A music box?"},
			{"feeling": "joy", "intensity": 2, "cue": "none", "say": "How did you know?"},
		],
		"mood": {"affection": 2, "trust": 1, "stress": 0},
	}
	var result := _builder().build(_ctx([_entry("user", "Did you like the gift?"), turn]))
	assert_array(_roles(result)).is_equal(["user", "assistant", "user"])
	# messages[0] is the system block; [1] the player turn, [2] her reply.
	var spoken := String(result["messages"][2]["content"])
	assert_str(spoken).is_equal("A music box? How did you know?")
	for forbidden: String in ["{", "}", '"beats"', '"cue"', "gasp", "inner", "romantic"]:
		var leak_message := "history leaked " + forbidden
		assert_str(spoken).override_failure_message(leak_message).not_contains(forbidden)


func test_history_accepts_a_wrapped_turn_and_plain_text() -> void:
	var history: Array = [
		_entry("user", "One."),
		{"role": "assistant", "turn": {"beats": [{"say": "First."}, {"say": "Second."}]}},
		_entry("user", "Two."),
		_entry("assistant", "Already plain text."),
	]
	var messages: Array = _builder().build(_ctx(history))["messages"]
	assert_str(String(messages[2]["content"])).is_equal("First. Second.")
	assert_str(String(messages[4]["content"])).is_equal("Already plain text.")


func test_spoken_text_helper_flattens_any_turn_shape() -> void:
	var builder := _builder()
	var turn := {"beats": [{"say": "One."}, {"say": ""}, {"say": "Two."}]}
	assert_str(builder.spoken_text(turn)).is_equal("One. Two.")
	assert_str(builder.spoken_text([{"say": "Just this."}])).is_equal("Just this.")
	assert_str(builder.spoken_text("  plain  ")).is_equal("plain")
	assert_str(builder.spoken_text(42)).is_empty()


func test_unusable_history_entries_are_skipped_with_a_warning() -> void:
	var history: Array = [
		{"role": "system", "text": "not history"},
		{"role": "assistant", "text": "   "},
		_entry("user", "Kept."),
		42,
	]
	var result := _builder().build(_ctx(history))
	assert_array(_roles(result)).is_equal(["user", "user"])
	assert_int(int(_history(result)["entries"])).is_equal(1)
	var skipped := ["history_entry_0_skipped", "history_entry_1_skipped", "history_entry_3_skipped"]
	assert_array(result["debug"]["warnings"]).contains(skipped)


# --- the sliding window ------------------------------------------------------


func test_history_window_keeps_the_last_twelve_exchanges() -> void:
	var history: Array[Dictionary] = []
	for i: int in 20:
		history.append(_entry("user", "question_%d" % i))
		history.append(_entry("assistant", "answer_%d" % i))
	var result := _builder().build(_ctx(history))
	var messages: Array = result["messages"]
	# system + 12 exchanges + the current player turn.
	assert_int(messages.size()).is_equal(1 + 24 + 1)
	assert_str(String(messages[1]["content"])).is_equal("question_8")
	assert_str(String(messages[2]["content"])).is_equal("answer_8")
	assert_str(String(messages[24]["content"])).is_equal("answer_19")
	var debug := _history(result)
	assert_int(int(debug["exchanges"])).is_equal(12)
	assert_int(int(debug["dropped"])).is_equal(16)
	assert_int(int(debug["entries"])).is_equal(40)
	assert_int(int(debug["limit"])).is_equal(12)


func test_history_window_never_splits_a_pair() -> void:
	var history: Array = [
		_entry("assistant", "orphan reply"),
		_entry("user", "One."),
		_entry("assistant", "Answer."),
	]
	var result := _builder().build(_ctx(history))
	assert_array(_roles(result)).is_equal(["user", "assistant", "user"])
	assert_str(String(result["messages"][0]["content"])).not_contains("orphan reply")
	assert_int(int(_history(result)["dropped"])).is_equal(1)


func test_history_limit_is_overridable() -> void:
	var history: Array = [
		_entry("user", "Old."),
		_entry("assistant", "Old answer."),
		_entry("user", "New."),
		_entry("assistant", "New answer."),
	]
	var ctx := _ctx(history)
	ctx["history_limit"] = 1
	var result := _builder().build(ctx)
	assert_array(_roles(result)).is_equal(["user", "assistant", "user"])
	assert_str(String(result["messages"][1]["content"])).is_equal("New.")
	assert_int(int(_history(result)["limit"])).is_equal(1)


func test_history_token_budget_drops_whole_exchanges_oldest_first() -> void:
	var long_line := "word ".repeat(600)
	var history: Array = [
		_entry("user", long_line),
		_entry("assistant", long_line),
		_entry("user", "Short."),
		_entry("assistant", "Short answer."),
	]
	var result := _builder().build(_ctx(history))
	var debug := _history(result)
	assert_int(int(debug["tokens"])).is_less_equal(int(debug["budget"]))
	assert_array(_roles(result)).is_equal(["user", "assistant", "user"])
	assert_str(String(result["messages"][1]["content"])).is_equal("Short.")
	assert_int(int(debug["dropped"])).is_equal(2)


func test_history_budget_is_overridable_and_reported() -> void:
	var history: Array = [
		_entry("user", "One two three."),
		_entry("assistant", "Four five six."),
		_entry("user", "Seven eight nine."),
	]
	var ctx := _ctx(history)
	# Room for the newest exchange only: the oldest pair goes, pairs stay whole.
	ctx["history_token_budget"] = 8
	var result := _builder().build(ctx)
	var debug := _history(result)
	assert_int(int(debug["budget"])).is_equal(8)
	assert_int(int(debug["tokens"])).is_less_equal(8)
	assert_array(_roles(result)).is_equal(["user", "user"])
	assert_str(String(result["messages"][1]["content"])).is_equal("Seven eight nine.")
	assert_int(int(debug["dropped"])).is_equal(2)
	# A budget nothing fits into empties the window instead of exceeding it.
	var tiny := _ctx(history)
	tiny["history_token_budget"] = 1
	var squeezed := _builder().build(tiny)
	assert_int(int(_history(squeezed)["tokens"])).is_zero()
	assert_array(_roles(squeezed)).is_equal(["user"])
	assert_int(int(_history(squeezed)["dropped"])).is_equal(3)


func test_missing_history_key_is_legal() -> void:
	var result := _builder().build({"stage": 0, "player_name": "Ren", "player_message": "Hi."})
	assert_array(_roles(result)).is_equal(["user"])
	var debug := _history(result)
	assert_int(int(debug["entries"])).is_zero()
	assert_int(int(debug["tokens"])).is_zero()
	var broken := _builder().build({"stage": 0, "history": "not an array"})
	assert_array(broken["debug"]["warnings"]).contains("history_not_an_array")
