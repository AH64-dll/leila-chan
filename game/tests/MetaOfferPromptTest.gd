extends GdUnitTestSuite
## P3.08 round 2 — the docs/02 §2.4 contract proven on the REAL turn path
## (`Director.submit_player_input`), where round 1's unit tests could not see
## it: the OPPORTUNITY line must ride the same submit as the enum that offers
## the action (r1 CODE-1/DES-1), and "never two in a row" must skip exactly one
## turn when the counter advances the way `apply_turn_meters()` advances it
## (r1 CODE-2/DES-2). Both bugs lived in the step-0 drain → step-1 roll → step-7
## execution order, so a MetaDirector-only test cannot pin them.
##
## The backend is scripted (`FakeLLMBackend`) and the filter is the P1.19 test
## double, so the turn runs headless with no model and no sleeps.

const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const FakeSafetyScript := preload("res://tests/helpers/FakeSafetyFilter.gd")

var _fake_backend: RefCounted
var _safety: Node


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	GameState.player_name = "Senpai"
	Director.reset()
	FX.reset()
	_fake_backend = FakeLLMBackendScript.new()
	LLM.set_backend(_fake_backend)
	_safety = FakeSafetyScript.new()
	add_child(_safety)
	Director._safety.set_filter(_safety)
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	MetaDirector.reset_session()
	MetaDirector.set_seed_base(7)
	MetaDirector.load_catalog()
	Settings.immersion = "standard"


func after_test() -> void:
	Director.reset()
	Director._safety.set_filter(Safety)
	MetaDirector.reset_session()
	MetaDirector.load_catalog()
	GameState.reset()
	if is_instance_valid(_safety):
		_safety.queue_free()


func test_opportunity_line_rides_the_turn_that_offers_the_action() -> void:
	# The whole contract in one submit: the enum carries the action, the same
	# prompt carries its reason, and nothing is left in the queue for a later
	# turn whose enum has already moved on.
	_use_rows({"rename_window": _row("M12", 3)})
	GameState.set_meter(&"instability", 55.0)  # stage 3
	_fake_backend.chunks = PackedStringArray([_chunk("none")])
	assert_bool(Director.submit_player_input("Hello")).is_true()
	var offer_line := TurnSchema.opportunity_line("rename_window")
	assert_array(Director.last_offered_actions).contains("rename_window")
	assert_array(_action_enum()).contains("rename_window")
	assert_str(_prompt_text()).contains(offer_line)
	assert_array(GameState.pending_events).not_contains(offer_line)
	await _await_idle()
	# The offer expired with its turn: the next prompt has neither the enum
	# entry nor the sentence (r1 DES-1's stale-line case).
	_fake_backend.chunks = PackedStringArray([_chunk("none")])
	assert_bool(Director.submit_player_input("Still there?")).is_true()
	assert_array(Director.last_offered_actions).is_empty()
	assert_str(_prompt_text()).not_contains(offer_line)
	await _await_idle()


func test_never_two_in_a_row_skips_exactly_one_turn() -> void:
	# Turn 0 takes the offer; turn 1 must roll nothing; turn 2 must roll again.
	# A scene boundary resets the per-scene budget, so only the quiet-turn rule
	# can explain turn 1 — that is the r1 CODE-2 probe, as a test.
	_use_rows({"rename_window": _row("M12", 3)})
	GameState.set_meter(&"instability", 55.0)  # stage 3 → scene cap 1
	_fake_backend.chunk_sets = [
		PackedStringArray([_chunk("rename_window")]),
		PackedStringArray([_chunk("none")]),
		PackedStringArray([_chunk("none")]),
	]
	assert_bool(Director.submit_player_input("Hello")).is_true()
	await _await_idle()
	assert_int(int(MetaDirector.state()["last_event_turn"])).is_equal(0)
	assert_int(int(MetaDirector.state()["scene_events"])).is_equal(1)
	MetaDirector.note_scene("D02")
	assert_bool(Director.submit_player_input("Sorry")).is_true()
	assert_array(Director.last_offered_actions).is_empty()
	await _await_idle()
	MetaDirector.note_scene("D03")
	assert_bool(Director.submit_player_input("Hey")).is_true()
	assert_array(Director.last_offered_actions).contains("rename_window")
	await _await_idle()


## A one-action catalogue: the roll has exactly one candidate, so the suite does
## not depend on the lottery's draw.
func _use_rows(rows: Dictionary) -> void:
	var events := {}
	for action: String in rows:
		events[action] = rows[action]
	MetaDirector.set_catalog({"events": events})


## A legal stage-gated row with no cooldown (so the quiet-turn check, not the
## cooldown, is what the assertions measure).
func _row(meta: String, stage: int) -> Dictionary:
	return {
		"meta": meta,
		"stage": stage,
		"repeat": ["repeatable", 0],
		"fallback": "In-window swap: the same line is shown as a system message.",
		"note_line": "EVENT: The window now carries your words.",
	}


func _chunk(action: String) -> String:
	var payload := (
		'{"read":"greeting","inner":"hm","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"cold","intensity":1,"cue":"none","say":"Fine."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"%s"}'
	)
	return payload % action


## This turn's legal action enum, straight from the schema the model was given.
func _action_enum() -> Array:
	var schema: Dictionary = Director._current_schema
	return schema["properties"]["action"]["enum"]


## The whole prompt text of the turn that just started (all message contents).
func _prompt_text() -> String:
	var parts: Array[String] = []
	for message: Variant in Director._current_prompt:
		if message is Dictionary:
			parts.append(str((message as Dictionary).get("content", "")))
	return "\n".join(parts)


func _await_idle() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while Director.is_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
