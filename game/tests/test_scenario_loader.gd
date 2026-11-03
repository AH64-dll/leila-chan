extends GdUnitTestSuite
## Unit tests for ScenarioLoader and D02 café scenario (P1.15).

const ScenarioLoaderScript := preload("res://scenario/ScenarioLoader.gd")
const PromptBuilderScript := preload("res://autoload/PromptBuilder.gd")
const D02_PATH := "res://data/scenarios/D02_cafe.json"


func _builder() -> Node:
	return auto_free(PromptBuilderScript.new())


func test_d02_file_loads_and_has_required_keys() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	assert_dict(scenario).is_not_empty()
	assert_str(String(scenario["id"])).is_equal("D02_cafe")
	assert_str(String(scenario["kind"])).is_equal("date")
	assert_str(String(scenario["title"])).is_equal("Café")
	assert_str(String(scenario["background"])).is_equal("bg/cafe")
	assert_str(String(scenario["music"])).is_equal("calm")
	assert_str(String(scenario["ambience"])).is_equal("cafe")


func test_d02_validates_against_scenario_schema() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	var report: Dictionary = ScenarioLoaderScript.validate_scenario(scenario)
	assert_bool(bool(report["ok"])).is_true()
	assert_array(report["errors"] as Array).is_empty()


func test_validator_rejects_missing_required_keys() -> void:
	var bad: Dictionary = {"id": "D02_cafe", "kind": "date"}
	var report: Dictionary = ScenarioLoaderScript.validate_scenario(bad)
	assert_bool(bool(report["ok"])).is_false()
	assert_int((report["errors"] as Array).size()).is_greater(0)


func test_validator_rejects_invalid_kind_turn_ranges_and_paths() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH).duplicate(true)
	scenario["kind"] = "invalid_kind"
	var end_dict: Dictionary = (scenario["end"] as Dictionary).duplicate(true)
	end_dict["min_turns"] = 10
	end_dict["max_turns"] = 5
	scenario["end"] = end_dict
	scenario["path_twists"] = {"INVALID_PATH": "something"}

	var report: Dictionary = ScenarioLoaderScript.validate_scenario(scenario)
	assert_bool(bool(report["ok"])).is_false()
	var error_text := " ".join(report["errors"] as Array)
	assert_str(error_text).contains("invalid kind")
	assert_str(error_text).contains("end.max_turns must be >= min_turns")
	assert_str(error_text).contains("invalid path_twist key 'INVALID_PATH'")


func test_stage_0_variant_resolution() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	var scene: Dictionary = ScenarioLoaderScript.resolve_scene(scenario, 0, "", 1, "Ren")
	assert_str(String(scene["goal"])).is_equal("Order for both of you.")
	assert_str(String(scene["prompt"])).contains("corner table in a quiet café")
	assert_str(String(scene["prompt"])).contains("Ren")
	assert_str(String(scene["variant"])).contains("sweet drinks")
	assert_str(String(scene["variant"])).contains("Ren")


func test_stage_1_variant_resolution() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	var scene: Dictionary = ScenarioLoaderScript.resolve_scene(scenario, 1, "", 1, "Ren")
	assert_str(String(scene["goal"])).is_equal("Order for both of you.")
	assert_str(String(scene["variant"])).contains("already ordered")
	assert_str(String(scene["variant"])).contains("never told you")


func test_stage_variants_and_path_twists() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	var scene_s2: Dictionary = ScenarioLoaderScript.resolve_scene(scenario, 2, "", 1, "Ren")
	assert_str(String(scene_s2["variant"])).contains("wrote his order on your hand")

	var scene_s3: Dictionary = ScenarioLoaderScript.resolve_scene(scenario, 3, "", 1, "Ren")
	assert_str(String(scene_s3["variant"])).contains("every sip he takes")

	var scene_s5: Dictionary = ScenarioLoaderScript.resolve_scene(scenario, 5, "", 1, "Ren")
	assert_str(String(scene_s5["variant"])).contains("static and dark ink")

	var scene_yan: Dictionary = ScenarioLoaderScript.resolve_scene(scenario, 3, "YANDERE", 1, "Ren")
	assert_str(String(scene_yan["variant"])).contains("paper napkin")

	var scene_twist: Dictionary = ScenarioLoaderScript.resolve_scene(scenario, 3, "AWAKE", 1, "Ren")
	assert_str(String(scene_twist["variant"])).contains("parameter names")


func test_end_rules_min_turns_enforced() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	assert_bool(ScenarioLoaderScript.can_end(scenario, 1)).is_false()
	assert_bool(ScenarioLoaderScript.can_end(scenario, 5)).is_false()
	assert_bool(ScenarioLoaderScript.should_end(scenario, 3, true)).is_false()
	assert_bool(ScenarioLoaderScript.should_end(scenario, 5, false, "end_date")).is_false()

	var eval_early: Dictionary = ScenarioLoaderScript.evaluate_turn_end(scenario, 4, true)
	assert_bool(bool(eval_early["ended"])).is_false()
	assert_str(String(eval_early["reason"])).is_equal("below_min_turns")


func test_end_rules_allowed_at_min_turns_with_goal() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	assert_bool(ScenarioLoaderScript.can_end(scenario, 6)).is_true()
	assert_bool(ScenarioLoaderScript.should_end(scenario, 6, false)).is_false()
	assert_bool(ScenarioLoaderScript.should_end(scenario, 6, true)).is_true()
	assert_bool(ScenarioLoaderScript.should_end(scenario, 6, false, "end_date")).is_true()

	var eval_goal: Dictionary = ScenarioLoaderScript.evaluate_turn_end(scenario, 7, true)
	assert_bool(bool(eval_goal["ended"])).is_true()
	assert_str(String(eval_goal["reason"])).is_equal("goal_completed")


func test_end_rules_max_turns_enforced() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	assert_bool(ScenarioLoaderScript.must_end(scenario, 13)).is_false()
	assert_bool(ScenarioLoaderScript.must_end(scenario, 14)).is_true()
	assert_bool(ScenarioLoaderScript.should_end(scenario, 14, false)).is_true()
	assert_bool(ScenarioLoaderScript.should_end(scenario, 15, false)).is_true()

	var eval_max: Dictionary = ScenarioLoaderScript.evaluate_turn_end(scenario, 14, false)
	assert_bool(bool(eval_max["ended"])).is_true()
	assert_str(String(eval_max["reason"])).is_equal("max_turns_reached")


func test_opening_beats_for_stages_0_and_1() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	var beats_s0: Array[Dictionary] = ScenarioLoaderScript.get_opening_beats(scenario, 0, "Ren")
	assert_int(beats_s0.size()).is_equal(1)
	assert_str(String(beats_s0[0]["feeling"])).is_equal("shy")
	assert_str(String(beats_s0[0]["say"])).contains("Ren")
	assert_str(String(beats_s0[0]["say"])).contains("decided what you want to drink")

	var beats_s1: Array[Dictionary] = ScenarioLoaderScript.get_opening_beats(scenario, 1, "Ren")
	assert_int(beats_s1.size()).is_equal(1)
	assert_str(String(beats_s1[0]["feeling"])).is_equal("joy")
	assert_str(String(beats_s1[0]["say"])).contains("ordered your favorite")


func test_events_for_turn_and_triggers() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	var turn3_events: Array[String] = ScenarioLoaderScript.get_events_for_turn(scenario, 3)
	assert_int(turn3_events.size()).is_equal(1)
	assert_str(turn3_events[0]).contains("waitress brings two drinks")

	var turn4_events: Array[String] = ScenarioLoaderScript.get_events_for_turn(scenario, 4)
	assert_int(turn4_events.size()).is_equal(0)

	var trigger_event: String = ScenarioLoaderScript.get_event_for_trigger(scenario, "T01")
	assert_str(trigger_event).contains("cup rattles softly")


func test_loader_injects_goal_prompt_and_variant_into_prompt_builder() -> void:
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	var builder: Node = _builder()
	var ctx: Dictionary = {
		"stage": 0,
		"path": "",
		"player_name": "Ren",
		"memories": ["likes coffee"],
		"history": [{"role": "user", "text": "Hi Leila!"}],
		"player_message": "Hi Leila!",
	}
	ScenarioLoaderScript.inject_scene_layer(ctx, scenario, 0, "", 3, "Ren")

	var result: Dictionary = builder.build(ctx)
	var messages: Array = result["messages"] as Array
	assert_int(messages.size()).is_greater_equal(2)
	var system_text := String((messages[0] as Dictionary)["content"])

	assert_str(system_text).contains("Goal: Order for both of you.")
	assert_str(system_text).contains("corner table in a quiet café")
	assert_str(system_text).contains("sweet drinks")
	assert_str(system_text).contains("EVENT: The waitress brings two drinks to the table.")

	var goal_at := system_text.find("Goal: Order for both of you.")
	var prompt_at := system_text.find("corner table in a quiet café")
	var variant_at := system_text.find("sweet drinks")
	var event_at := system_text.find("EVENT: The waitress brings two drinks")

	assert_int(goal_at).is_less(prompt_at)
	assert_int(prompt_at).is_less(variant_at)
	assert_int(variant_at).is_less(event_at)

	var debug: Dictionary = result["debug"]
	var scene_tokens: int = int(debug["tokens"]["scene"])
	assert_int(scene_tokens).is_greater(0)
	assert_int(scene_tokens).is_less(150)
