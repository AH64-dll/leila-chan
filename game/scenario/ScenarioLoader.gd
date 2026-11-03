class_name ScenarioLoader
extends RefCounted
## ScenarioLoader — loads, validates, and resolves scenarios (docs/08 §7).
##
## Scenarios define the setting, her goal, stage variants, path twists,
## scripted events, opening beats, and turn bounds for a scene.
##
## This loader integrates with PromptBuilder by resolving a turn's scenario
## into {"goal", "prompt", "variant", "event"} and injecting it into ctx.scene.
## It also enforces scenario end rules (min_turns / max_turns / on_goal).

const DEFAULT_SCENARIO_PATH := "res://data/scenarios/D02_cafe.json"
const SCHEMA_PATH := "res://data/schemas/scenario.schema.json"
const VALID_KINDS: Array[String] = ["date", "interrupt", "overnight", "setpiece"]
const CANONICAL_PATHS: Array[String] = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]
const REQUIRED_KEYS: Array[String] = [
	"id",
	"kind",
	"title",
	"background",
	"music",
	"ambience",
	"available",
	"goal",
	"prompt",
	"stage_variants",
	"path_twists",
	"events",
	"end",
]


## Loads a scenario JSON file from res:// or user:// path.
static func load_scenario(path: String = DEFAULT_SCENARIO_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("ScenarioLoader: file not found: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	return load_scenario_from_string(text)


## Parses a scenario JSON string and returns the dictionary.
static func load_scenario_from_string(json_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		push_warning("ScenarioLoader: failed to parse JSON or root is not an object")
		return {}
	return parsed as Dictionary


## Validates scenario dictionary against the schema requirements.
## Returns {"ok": bool, "errors": Array[String]}.
static func validate_scenario(data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for key: String in REQUIRED_KEYS:
		if not data.has(key):
			errors.append("missing required key: %s" % key)

	var kind := String(data.get("kind", ""))
	if not VALID_KINDS.has(kind):
		errors.append("invalid kind '%s'; expected one of %s" % [kind, str(VALID_KINDS)])

	var available: Variant = data.get("available")
	if available is Dictionary:
		_validate_available(available as Dictionary, errors)
	else:
		errors.append("available must be an object")

	var end_rules: Variant = data.get("end")
	if end_rules is Dictionary:
		_validate_end_rules(end_rules as Dictionary, errors)
	else:
		errors.append("end must be an object")

	var events: Variant = data.get("events")
	if not events is Array:
		errors.append("events must be an array")

	var stage_variants: Variant = data.get("stage_variants")
	if not stage_variants is Dictionary:
		errors.append("stage_variants must be an object")

	var path_twists: Variant = data.get("path_twists")
	if not path_twists is Dictionary:
		errors.append("path_twists must be an object")
	else:
		for path_key: Variant in (path_twists as Dictionary).keys():
			var p_str := String(path_key)
			if not CANONICAL_PATHS.has(p_str):
				errors.append(
					"invalid path_twist key '%s'; must be one of %s" % [p_str, str(CANONICAL_PATHS)]
				)

	return {"ok": errors.is_empty(), "errors": errors}


## Resolves a scenario for a specific turn and stage into a scene dictionary
## suitable for PromptBuilder.gd ctx["scene"].
static func resolve_scene(
	scenario: Dictionary,
	stage: int,
	path: String = "",
	turn: int = 1,
	player_name: String = "Senpai"
) -> Dictionary:
	var goal := String(scenario.get("goal", "")).replace("{player_name}", player_name)
	var prompt := String(scenario.get("prompt", "")).replace("{player_name}", player_name)
	var variant := _resolve_variant(scenario, stage, path, player_name)
	var event := _resolve_turn_event(scenario, turn, player_name)

	return {
		"goal": goal.strip_edges(),
		"prompt": prompt.strip_edges(),
		"variant": variant.strip_edges(),
		"event": event.strip_edges(),
	}


## Injects the resolved scene dictionary into a PromptBuilder turn context.
static func inject_scene_layer(
	ctx: Dictionary,
	scenario: Dictionary,
	stage: int,
	path: String = "",
	turn: int = 1,
	player_name: String = ""
) -> Dictionary:
	var name := player_name
	if name.is_empty():
		name = String(ctx.get("player_name", "Senpai"))
	ctx["scene"] = resolve_scene(scenario, stage, path, turn, name)
	return ctx


## Returns true if the scenario is allowed to end at current_turn (turn >= min_turns).
static func can_end(scenario: Dictionary, current_turn: int) -> bool:
	var end_rules: Dictionary = scenario.get("end", {})
	var min_turns := int(end_rules.get("min_turns", 1))
	return current_turn >= min_turns


## Returns true if current_turn reached or exceeded max_turns.
static func must_end(scenario: Dictionary, current_turn: int) -> bool:
	var end_rules: Dictionary = scenario.get("end", {})
	var max_turns := int(end_rules.get("max_turns", 999))
	return current_turn >= max_turns


## Enforces min_turns, max_turns, and goal/action end condition.
## Returns true if the scene should terminate now.
static func should_end(
	scenario: Dictionary,
	current_turn: int,
	goal_completed: bool = false,
	requested_action: String = ""
) -> bool:
	var end_rules: Dictionary = scenario.get("end", {})
	var min_turns := int(end_rules.get("min_turns", 1))
	var max_turns := int(end_rules.get("max_turns", 999))

	if current_turn >= max_turns:
		return true
	if current_turn < min_turns:
		return false

	var on_goal := String(end_rules.get("on_goal", ""))
	if goal_completed:
		return true
	if not requested_action.is_empty() and requested_action == on_goal:
		return true

	return false


## Detailed evaluation of the scenario end state for this turn.
static func evaluate_turn_end(
	scenario: Dictionary,
	current_turn: int,
	goal_completed: bool = false,
	requested_action: String = ""
) -> Dictionary:
	var end_rules: Dictionary = scenario.get("end", {})
	var min_turns := int(end_rules.get("min_turns", 1))
	var max_turns := int(end_rules.get("max_turns", 999))
	var on_goal := String(end_rules.get("on_goal", ""))

	var ended := false
	var reason := "in_progress"

	if current_turn >= max_turns:
		ended = true
		reason = "max_turns_reached"
	elif current_turn < min_turns:
		ended = false
		reason = "below_min_turns"
	elif goal_completed:
		ended = true
		reason = "goal_completed"
	elif not requested_action.is_empty() and requested_action == on_goal:
		ended = true
		reason = "action_triggered"

	return {
		"ended": ended,
		"reason": reason,
		"can_end": current_turn >= min_turns,
		"min_turns": min_turns,
		"max_turns": max_turns,
		"current_turn": current_turn,
	}


## Returns opening beats configured for the scenario and stage.
static func get_opening_beats(
	scenario: Dictionary, stage: int = 0, player_name: String = "Senpai"
) -> Array[Dictionary]:
	var raw: Variant = scenario.get("opening_beats", {})
	var beats_source: Array = []

	if raw is Dictionary:
		var key := str(stage)
		if (raw as Dictionary).has(key):
			beats_source = (raw as Dictionary)[key]
		elif (raw as Dictionary).has("0"):
			beats_source = (raw as Dictionary)["0"]
	elif raw is Array:
		beats_source = raw as Array

	var result: Array[Dictionary] = []
	for item: Variant in beats_source:
		if item is Dictionary:
			var beat: Dictionary = (item as Dictionary).duplicate(true)
			if beat.has("say"):
				beat["say"] = String(beat["say"]).replace("{player_name}", player_name)
			result.append(beat)

	return result


## Returns the narrative setting description (prompt + stage variant).
static func get_scene_description(
	scenario: Dictionary, stage: int = 0, path: String = "", player_name: String = "Senpai"
) -> String:
	var prompt := String(scenario.get("prompt", "")).replace("{player_name}", player_name)
	var variant := _resolve_variant(scenario, stage, path, player_name)
	if variant.is_empty():
		return prompt.strip_edges()
	return ("%s\n%s" % [prompt.strip_edges(), variant.strip_edges()]).strip_edges()


## Returns event lines scheduled for a specific turn.
static func get_events_for_turn(
	scenario: Dictionary, turn: int, player_name: String = "Senpai"
) -> Array[String]:
	var events_raw: Variant = scenario.get("events", [])
	if not events_raw is Array:
		return []

	var lines: Array[String] = []
	for item: Variant in events_raw:
		if item is Dictionary:
			var event_dict: Dictionary = item as Dictionary
			if int(event_dict.get("at_turn", -1)) == turn:
				var line := String(event_dict.get("line", ""))
				if not line.is_empty():
					lines.append(line.replace("{player_name}", player_name))
	return lines


## Returns the event line for a triggered event ID or trigger ID.
static func get_event_for_trigger(
	scenario: Dictionary, trigger_id: String, player_name: String = "Senpai"
) -> String:
	var events_raw: Variant = scenario.get("events", [])
	if not events_raw is Array:
		return ""

	for item: Variant in events_raw:
		if item is Dictionary:
			var event_dict: Dictionary = item as Dictionary
			var on_trigger := String(event_dict.get("on_trigger", ""))
			var event_id := String(event_dict.get("id", ""))
			if on_trigger == trigger_id or event_id == trigger_id:
				var line := String(event_dict.get("line", ""))
				return line.replace("{player_name}", player_name)
	return ""


static func _validate_available(available: Dictionary, errors: Array[String]) -> void:
	var days: Variant = available.get("days")
	if not days is Array or (days as Array).size() != 2:
		errors.append("available.days must be an array of [min, max]")
	else:
		var min_day := int((days as Array)[0])
		var max_day := int((days as Array)[1])
		if min_day < 1 or min_day > max_day:
			errors.append("available.days invalid range [%d, %d]" % [min_day, max_day])

	var stages: Variant = available.get("stages")
	if not stages is Array or (stages as Array).size() != 2:
		errors.append("available.stages must be an array of [min, max]")
	else:
		var min_stage := int((stages as Array)[0])
		var max_stage := int((stages as Array)[1])
		if min_stage < 0 or max_stage > 5 or min_stage > max_stage:
			errors.append("available.stages invalid range [%d, %d]" % [min_stage, max_stage])

	if not available.has("paths"):
		errors.append("available.paths is required")


static func _validate_end_rules(end_rules: Dictionary, errors: Array[String]) -> void:
	if not end_rules.has("min_turns"):
		errors.append("end.min_turns is required")
	if not end_rules.has("max_turns"):
		errors.append("end.max_turns is required")
	if not end_rules.has("on_goal"):
		errors.append("end.on_goal is required")

	var min_turns := int(end_rules.get("min_turns", -1))
	var max_turns := int(end_rules.get("max_turns", -1))
	if min_turns < 1:
		errors.append("end.min_turns must be >= 1")
	if max_turns < min_turns:
		errors.append("end.max_turns must be >= min_turns")


static func _resolve_variant(
	scenario: Dictionary, stage: int, path: String, player_name: String
) -> String:
	var stage_variants: Dictionary = scenario.get("stage_variants", {})
	var variant := ""

	var stage_key := str(stage)
	if stage_variants.has(stage_key):
		variant = String(stage_variants[stage_key])
	else:
		# Fall back to highest defined stage <= requested stage
		for s: int in range(stage, -1, -1):
			var k := str(s)
			if stage_variants.has(k):
				variant = String(stage_variants[k])
				break

	if not path.is_empty():
		var path_twists: Dictionary = scenario.get("path_twists", {})
		if path_twists.has(path):
			var twist := String(path_twists[path])
			if not twist.is_empty():
				if variant.is_empty():
					variant = twist
				else:
					variant += " " + twist

	return variant.replace("{player_name}", player_name)


static func _resolve_turn_event(scenario: Dictionary, turn: int, player_name: String) -> String:
	var events := get_events_for_turn(scenario, turn, player_name)
	if events.is_empty():
		return ""
	return events[0]
