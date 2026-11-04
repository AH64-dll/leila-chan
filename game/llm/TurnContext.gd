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

## The four docs/02 §9 row columns: the first three go to the request's
## sampling, `dose` is the steering base (docs/06 §4 owns applying it). Named
## for the table row so it stays distinct from LlamaServerBackend.SAMPLING_KEYS,
## the ten-key transport allowlist that must never carry `dose`.
const SAMPLING_ROW_KEYS: Array[String] = ["temperature", "top_p", "repeat_penalty", "dose"]

static var _sampling_cache: Dictionary = {}


static func clear_cache() -> void:
	_sampling_cache = {}


## docs/02 §9 sampling row for `stage`: the data row when present, else the
## documented fallback. Always a complete four-key row, and always a copy so a
## consumer cannot poison the cache.
static func sampling_spec(stage: int) -> Dictionary:
	if _sampling_cache.is_empty():
		_sampling_cache = _load_sampling()
	var row: Variant = _sampling_cache.get(stage)
	if row is Dictionary:
		return (row as Dictionary).duplicate()
	return (SAMPLING_FALLBACK.get(stage, SAMPLING_FALLBACK[0]) as Dictionary).duplicate()


## The sampling subset a TurnRequest carries (docs/07 §3.1): exactly the three
## docs/02 §9 columns the transport sends. `dose` is steering, not sampling, so
## it never leaks into this dictionary (docs/06 §4).
static func request_sampling(stage: int) -> Dictionary:
	var row := sampling_spec(stage)
	return {
		"temperature": float(row["temperature"]),
		"top_p": float(row["top_p"]),
		"repeat_penalty": float(row["repeat_penalty"]),
	}


## Parses a sampling document into {stage: row}, data-driven on purpose: a test
## can hand it a synthetic document and prove the loader (not a hard-coded copy)
## decides the numbers.
##
## Shape: {"stages": {"0": {...}, ..., "5": {...}}}. A missing column falls back
## to that stage's docs/02 §9 row, so a partial file can never send a half-empty
## sampling. A document with no usable stage rows (a misspelled `stages` key, an
## empty or non-object table, only out-of-range keys) warns and resolves every
## stage from the in-code table: silently reverting the one data-owned table is
## exactly the failure this warning exists to make visible.
static func parse_sampling(parsed: Variant) -> Dictionary:
	if not (parsed is Dictionary):
		return _fallback_table()
	var document: Dictionary = parsed
	var table := {}
	var rows_from_data := 0
	var stages: Variant = document.get("stages")
	if stages is Dictionary:
		for key: Variant in stages:
			var name := str(key)
			var stage := int(name) if name.is_valid_int() else -1
			if stage < 0 or stage > GameState.STAGE_MAX:
				push_warning(
					(
						"TurnContext: %s stage key '%s' is not 0..%d; ignored"
						% [SAMPLING_PATH, name, GameState.STAGE_MAX]
					)
				)
				continue
			table[stage] = _stage_row(stage, _numeric_sampling(stages[key]))
			rows_from_data += 1
	for stage: int in SAMPLING_FALLBACK:
		if not table.has(stage):
			table[stage] = _stage_row(stage, {})
	if rows_from_data == 0:
		push_warning(
			"TurnContext: %s has no usable stage rows; using the in-code table" % SAMPLING_PATH
		)
	return table


## One complete row: the docs/02 §9 row for `stage` overlaid with the file's
## numeric keys. The file is authoritative; a missing key keeps the documented
## value so a partial edit can never send a half-empty sampling.
static func _stage_row(stage: int, row: Dictionary) -> Dictionary:
	var out := (SAMPLING_FALLBACK[stage] as Dictionary).duplicate()
	for key: String in SAMPLING_ROW_KEYS:
		if row.has(key):
			out[key] = row[key]
	return out


## The numeric sampling keys of `source`, as floats (JSON numbers arrive as int
## or float; anything else is not a setting and is ignored).
static func _numeric_sampling(source: Variant) -> Dictionary:
	var out := {}
	if not (source is Dictionary):
		return out
	for key: String in SAMPLING_ROW_KEYS:
		var value: Variant = source.get(key)
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			var number := float(value)
			if is_finite(number):
				out[key] = number
	return out


static func _fallback_table() -> Dictionary:
	var out := {}
	for stage: int in SAMPLING_FALLBACK:
		out[stage] = (SAMPLING_FALLBACK[stage] as Dictionary).duplicate()
	return out


static func _load_sampling() -> Dictionary:
	if not FileAccess.file_exists(SAMPLING_PATH):
		push_warning("TurnContext: %s missing; using the in-code sampling table" % SAMPLING_PATH)
		return _fallback_table()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLING_PATH))
	if not (parsed is Dictionary):
		push_warning(
			"TurnContext: %s is not a JSON object; using the in-code table" % SAMPLING_PATH
		)
		return _fallback_table()
	return parse_sampling(parsed)


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
## debug panel never reaches into GameState itself. The ratchet pair and the
## current per-turn slow burn ride along (P2.01) so the F3 overlay and the night
## screen can show what the docs/01 §2 math is doing without recomputing it.
static func meters() -> Dictionary:
	return {
		"affection": GameState.affection,
		"trust": GameState.trust,
		"instability": GameState.instability,
		"fixation": GameState.fixation,
		"lucidity": GameState.lucidity,
		"instability_peak": GameState.instability_peak,
		"instability_floor": GameState.instability_floor,
		"slow_burn": Meters.slow_burn(GameState.fixation, GameState.lucidity),
	}


## Everything she said in a completed turn as one string — every beat's `say`
## joined. The Director matches stored facts against it for the docs/02 §6
## importance bump ("+1 each time she quotes it"), so the rule lives next to the
## other turn-shape helpers instead of inside Director's line budget.
static func spoken_text(turn_data: Dictionary) -> String:
	var raw: Variant = turn_data.get("beats", [])
	if not raw is Array:
		return ""
	var parts := PackedStringArray()
	for beat: Variant in raw:
		if beat is Dictionary:
			var line := String((beat as Dictionary).get("say", "")).strip_edges()
			if not line.is_empty():
				parts.append(line)
	return " ".join(parts)
