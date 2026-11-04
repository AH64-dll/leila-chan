class_name TurnContext
extends RefCounted
## TurnContext — the docs/02 §4 step 1 state snapshot and the docs/02 §9 sampling
## table, split out of Director.gd so the pipeline file stays inside gdlint's
## file-size cap (the same reason DirectorFallbackTest was split off).
##
## Everything here is pure: it reads GameState/data and returns dictionaries. The
## Director owns when a turn starts; this owns what the turn is told about.

const SAMPLING_PATH := "res://data/sampling.json"

## docs/02 §9, the in-code fallback for a missing or partial data file. The data
## file is authoritative (P2.02 owns retuning it); this exists so a broken
## sampling.json degrades to the documented numbers instead of to defaults.
const SAMPLING_FALLBACK := {
	0: {"temperature": 0.75, "top_p": 0.90, "repeat_penalty": 1.10, "dose": 0.0},
	1: {"temperature": 0.80, "top_p": 0.90, "repeat_penalty": 1.10, "dose": 2.5},
	2: {"temperature": 0.80, "top_p": 0.92, "repeat_penalty": 1.12, "dose": 3.5},
	3: {"temperature": 0.85, "top_p": 0.95, "repeat_penalty": 1.15, "dose": 4.5},
	4: {"temperature": 0.90, "top_p": 0.95, "repeat_penalty": 1.15, "dose": 6.0},
	5: {"temperature": 0.95, "top_p": 0.97, "repeat_penalty": 1.18, "dose": 8.0},
}

static var _sampling_cache: Dictionary = {}


static func clear_cache() -> void:
	_sampling_cache = {}


## docs/02 §9 sampling row for `stage`: the data row when present, else the
## documented fallback.
static func sampling_spec(stage: int) -> Dictionary:
	if _sampling_cache.is_empty():
		_sampling_cache = _load_sampling()
	var row: Variant = _sampling_cache.get(stage)
	if row is Dictionary:
		return row
	return SAMPLING_FALLBACK.get(stage, SAMPLING_FALLBACK[0])


static func _load_sampling() -> Dictionary:
	var out := {}
	if FileAccess.file_exists(SAMPLING_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLING_PATH))
		if parsed is Dictionary and parsed.get("stages") is Dictionary:
			for key: Variant in parsed["stages"]:
				var stage_key := str(key)
				if stage_key.is_valid_int():
					out[int(stage_key)] = parsed["stages"][key]
		else:
			push_warning(
				"TurnContext: %s has no stages table; using the in-code table" % SAMPLING_PATH
			)
	else:
		push_warning("TurnContext: %s missing; using the in-code sampling table" % SAMPLING_PATH)
	for stage: int in SAMPLING_FALLBACK:
		if not out.has(stage):
			out[stage] = SAMPLING_FALLBACK[stage]
	return out


## docs/08 §5 "Offered this turn — …": the enums the schema compiles for this
## turn, so the model reads the same vocabulary it is allowed to emit. The cue,
## music and fx lists come from the stage gates; `action` is the offered set.
static func offered_values(stage: int, offered_actions: Array) -> Dictionary:
	var actions: Array = ["none"]
	for action: Variant in offered_actions:
		var action_name := String(action)
		if not actions.has(action_name):
			actions.append(action_name)
	return {
		"cue": TurnSchema.get_allowed_cues(stage),
		"music": TurnSchema.get_allowed_music(stage),
		"fx": TurnSchema.get_allowed_fx(stage),
		"action": actions,
	}


## The docs/02 §4 step 1 snapshot: stage, path, meters, scene, memories, this
## turn's trigger events, the history window and the offered values. PromptBuilder,
## Steering.dose_for and the transcript all read this one shape.
static func build(
	player_text: String,
	events: Array,
	scene: Dictionary,
	memories: Array,
	history: Array,
	offered_actions: Array
) -> Dictionary:
	var stage := int(GameState.stage)
	return {
		"stage": stage,
		"path": String(GameState.path),
		"player_name": GameState.player_name,
		"scene": scene,
		"memories": memories.duplicate(),
		"events": events.duplicate(),
		"history": _prior_history(history, player_text),
		"player_message": player_text,
		"offered_actions": offered_actions.duplicate(),
		"offered": offered_values(stage, offered_actions),
		"meters": meters(),
	}


## docs/08 §1: the history layer is the *prior* exchanges as user/assistant
## pairs; this turn's line reaches the model as `player_message`. The Director
## appends a submitted line to its own `history` before the turn opens (so the
## next window has it), so the snapshot drops that trailing copy — otherwise the
## prompt ends with the same user message twice (review r3 DES-1).
static func _prior_history(history: Array, player_text: String) -> Array:
	var text := player_text.strip_edges()
	var kept: Array = history
	if not text.is_empty() and not history.is_empty():
		var tail: Variant = history[history.size() - 1]
		if tail is Dictionary:
			var entry := tail as Dictionary
			var same_text := String(entry.get("text", entry.get("content", ""))).strip_edges()
			if String(entry.get("role", "")) == "user" and same_text == text:
				kept = history.slice(0, history.size() - 1)
	return kept.duplicate(true)


## docs/02 §4 step 1 "meters": the raw GameState values, so a prompt layer or a
## debug panel never reaches into GameState itself.
static func meters() -> Dictionary:
	return {
		"affection": GameState.affection,
		"trust": GameState.trust,
		"instability": GameState.instability,
		"fixation": GameState.fixation,
		"lucidity": GameState.lucidity,
	}
