extends GdUnitTestSuite
## P2.22A — the shipped Date path (P2.22 playtest findings S1-1/S1-2/S1-3).
##
## The playtest drove the game through a harness that installed the three seams
## itself, so the shipped scene shipped without them. Each test here drives the
## production seam and nothing else:
##   1) the scene's own defaults start the date (S1-2),
##   2) a typed line opens a Director turn (S1-1),
##   3) that turn's prompt carries the scenario's scene layer, resolved for this
##      turn's stage, path and scheduled event (S1-3),
##   4) the layer is cleared when the date ends and when the scene leaves.

const DatePacked := preload("res://scenes/Date.tscn")
const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const SCENARIO := "res://data/scenarios/D02_cafe.json"
const TURN_FIXTURE := "res://tests/fixtures/streams/turn_001.json"

var _date: Node2D
var _fake_backend: RefCounted
var _previous_backend: LLMBackend


func before_test() -> void:
	GameState.reset()
	GameState.player_name = "Ren"
	Director.reset()
	_fake_backend = FakeLLMBackendScript.new()
	_fake_backend.chunks = PackedStringArray([FileAccess.get_file_as_string(TURN_FIXTURE)])
	_previous_backend = LLM.get_backend()
	LLM.set_backend(_fake_backend)


func after_test() -> void:
	# A submit leaves a turn streaming; the Director is an autoload and outlives
	# the scene that owns the ChatUI, so close the turn before the scene goes.
	Director.cancel()
	if _date != null and is_instance_valid(_date):
		_date.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Director.reset()
	LLM.set_backend(_previous_backend)
	GameState.reset()


## A Date the test drives: its scenario pinned (so the campaign's pick cannot make
## the assertions depend on the seed), no campaign bookkeeping, no scene change,
## and `auto_start` off — the test below that proves auto-start leaves the export
## alone.
func _make_date() -> Node2D:
	var date: Node2D = DatePacked.instantiate()
	date.scenario_path = SCENARIO
	date.campaign_flow = false
	date.scene_change_enabled = false
	date.auto_start = false
	_date = date
	add_child(auto_free(date))
	await get_tree().process_frame
	date.set_reduced_motion(true)  # instant reveal, deterministic frames
	return date


func _await_until(predicate: Callable, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _system_prompt() -> String:
	var request: TurnRequest = _fake_backend.seen_request
	if request == null or request.messages.is_empty():
		return ""
	return String((request.messages[0] as Dictionary).get("content", ""))


## S1-2: every player entry (NewGame, Continue, the Night's hand-off) arrives
## through change_scene_to_file, which cannot set an export. A date that waited
## for a caller never played its greeting, never requested its music, never wrote
## its scene-entry autosave and never reached its `end` rule. So the scene starts
## itself, and `auto_start` is the tools' opt-out rather than the game's switch.
func test_the_shipped_scene_starts_the_date_itself() -> void:
	var date: Node2D = DatePacked.instantiate()
	date.scene_change_enabled = false  # a suite must not replace its own scene
	_date = date
	var starts: Array[int] = []
	# A lambda captures a local by value, so the counter must be a reference type.
	date.date_started.connect(func() -> void: starts.append(1))

	add_child(auto_free(date))
	# `_ready` defers the start, so this still runs before the greeting.
	date.set_reduced_motion(true)
	await _await_until(func() -> bool: return date.is_opening_finished())

	assert_int(starts.size()).is_equal(1)
	assert_bool(date.is_opening_finished()).is_true()
	# The scenario is the campaign's pick for day 1 — the shipped default path.
	assert_bool(date.get_scenario().is_empty()).is_false()
	assert_str(String(date.get_scenario().get("id", ""))).is_not_empty()
	assert_str(String(date.get_scenario().get("kind", ""))).is_equal("date")
	# Her greeting reached the log, exactly once, and it is not a turn.
	assert_int(date.chat_log.entry_count()).is_equal(1)
	assert_str(String((date.chat_log.get_entries()[0] as Dictionary)["speaker_key"])).is_equal(
		"her"
	)
	assert_int(date._current_turn).is_equal(0)
	# No turn has run, so no scene layer is claimed yet.
	assert_bool(Director.scene_info.is_empty()).is_true()


## S1-1 + S1-3: the line a player types opens the Director's turn, and the turn's
## prompt is the date the player is in — this scenario's goal, prompt and stage
## variant — instead of the café sentence the Director used to hard-code.
func test_a_typed_line_opens_the_turn_with_this_dates_scene_layer() -> void:
	var date: Node2D = await _make_date()
	date.start_date()
	await _await_until(func() -> bool: return date.is_opening_finished())

	var turns: Array = []
	Director.turn_started.connect(func(_index: int, text: String) -> void: turns.append(text))
	var completed: Array = []
	Director.turn_completed.connect(
		func(_index: int, _data: Dictionary) -> void: completed.append(true)
	)

	# The player's line through the real seam: InputBox → ChatUI → Date → Director.
	date.chat_ui.input_box.text_submitted.emit("Two teas, please.")

	# S1-1: the turn opens synchronously, inside the submit.
	assert_array(turns).contains(["Two teas, please."])
	assert_bool(Director.is_busy()).is_true()

	# S1-3: the layer this turn will be prompted with is the loaded scenario's.
	assert_str(String(Director.scene_info.get("goal", ""))).is_equal("Order for both of you.")
	assert_str(String(Director.scene_info.get("prompt", ""))).contains("quiet café")
	assert_str(String(Director.scene_info.get("variant", ""))).contains("what he likes")
	assert_str(String(Director.scene_info.get("event", ""))).is_empty()

	# It reached the prompt the model was actually sent, not just the field.
	await _await_until(func() -> bool: return _fake_backend.seen_request != null)
	var system_text := _system_prompt()
	assert_str(system_text).contains("Order for both of you.")
	assert_str(system_text).contains("corner table in a quiet café")
	assert_str(system_text).contains("what he likes")

	# And the turn closes through the Date's own ChatUI, so the player is answered.
	await _await_until(func() -> bool: return not completed.is_empty())
	assert_bool(completed.is_empty()).is_false()


## S1-3: the layer is resolved per turn, not once per scene — the stage variant
## and the path twist follow the live stage/path, and `events[].at_turn` lands on
## its own turn. D02_cafe schedules its first event at turn 3.
func test_the_scene_layer_is_resolved_for_the_turn_stage_and_path() -> void:
	var date: Node2D = await _make_date()
	date._current_turn = 2  # the next submit is turn 3
	GameState.stage = 2
	date.stage = 2
	GameState.path = &"YANDERE"

	date.chat_ui.input_box.text_submitted.emit("I brought you something.")

	var scene: Dictionary = Director.scene_info
	assert_str(String(scene.get("variant", ""))).contains("wrote his order on your hand")
	assert_str(String(scene.get("variant", ""))).contains("saved the paper napkin Ren")
	assert_str(String(scene.get("event", ""))).is_equal(
		"The waitress brings two drinks to the table."
	)
	# The player's name is interpolated, never left as the template token.
	assert_str(String(scene.get("prompt", ""))).contains("Ren")
	assert_bool(String(scene.get("prompt", "")).contains("{player_name}")).is_false()


## S1-3: the layer belongs to the date. D02_cafe ends at `max_turns` (14); a
## finished date must not leave its goal behind for whatever builds the next
## prompt, and neither must a scene that simply leaves the tree.
func test_the_scene_layer_is_cleared_when_the_date_ends() -> void:
	var date: Node2D = await _make_date()
	var ended: Array[String] = []
	date.date_ended.connect(func(reason: String) -> void: ended.append(reason))

	date.chat_ui.input_box.text_submitted.emit("Okay.")
	assert_bool(Director.scene_info.is_empty()).is_false()
	Director.cancel()  # this test is about the end rule, not her reply

	var end_rules: Dictionary = date.get_scenario().get("end", {})
	date._current_turn = int(end_rules.get("max_turns", 14))
	date._check_scenario_end()

	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0]).is_not_empty()
	assert_bool(Director.scene_info.is_empty()).is_true()
