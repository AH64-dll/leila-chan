class_name Endings
extends RefCounted
## Endings — docs/01 §7's endings as a data table plus the two rules the bible
## gives: which row a run has reached, and what the run has to look like for a
## row to be reachable. The catalogue, the conditions, the priorities and the
## per-path fallbacks all live in res://data/endings.json; adding an ending is a
## data edit, and a row that names a key this class does not know is dropped at
## load instead of quietly widening a condition (a typo must never make an
## ending easier to reach).
##
## The evaluator is pure: every entry point takes a GameState snapshot
## (GameState.to_dict()) and returns a decision, so the same state and the same
## table always give the same ending, whatever ran before. `force()` is the one
## dev-tool seam: it replaces the live run with a state that satisfies a row, so
## the F3 overlay can demonstrate every ending and the suite can prove each row
## is reachable (see `satisfying_state`).
##
## Timing (docs/01 §1/§7): `at: "campaign_end"` rows are the last night's
## business; `at: "any_time"` rows are checked at every turn close and every
## night — that is E14 "Static", which ends the run early when Instability
## reaches 100 before Day 7. A row that satisfies none of the doc's conditions
## still owes the run an ending, so `defaults` names one fallback per path.

const TABLE_PATH := "res://data/endings.json"
const GameStateScript := preload("res://autoload/GameState.gd")

## The two moments the game asks the question. The night of day 14 (or a forced
## state) closes the campaign; a turn close can only be an `any_time` ending.
const PHASE_TURN := "turn"
const PHASE_CAMPAIGN_END := "campaign_end"

const KIND_ENDING := "ending"
const KIND_SECRET := "secret"
const KINDS: Array[String] = [KIND_ENDING, KIND_SECRET]

const AT_CAMPAIGN_END := "campaign_end"
const AT_ANY_TIME := "any_time"
const AT_TIMES: Array[String] = [AT_CAMPAIGN_END, AT_ANY_TIME]

## docs/01 §7 gives the secret no id and no path; the table names it and it is
## never a run's ending.
const ANY_PATH := "ANY"
const SECRET_ID := "SECRET"

## docs/01 §7's fourteen rows, in the doc's order. A table that loses or renames
## one is a load problem, not a thirteenth-ending release.
const DOCS_IDS: Array[String] = [
	"E01", "E02", "E03", "E04", "E05", "E06", "E07", "E08", "E09", "E10", "E11", "E12", "E13", "E14"
]

## The condition vocabulary. A row naming anything else is dropped at load.
const CONDITION_KEYS: Array[String] = [
	"stage_min",
	"stage_max",
	"day_min",
	"day_max",
	"meters",
	"counters",
	"flags",
	"not_flags",
]

## GameState flags this system owns: the ending this run reached (in the
## snapshot, so a save carries it) and the once-per-run log guard.
const FLAG_ENDING := &"ending_id"
const FLAG_RECORDED := &"ending_recorded"

static var _table_cache: Dictionary = {}
static var _problems: Array[String] = []


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}
	_problems = []


## Test hook: install a parsed document as the live table (a synthetic ending is
## how the suite proves adding one needs no code). Returns the load problems;
## clear_cache() restores the shipped file.
static func use_document(parsed: Variant) -> Array[String]:
	var result := _parse(parsed)
	_table_cache = result["table"]
	_problems = []
	for problem: Variant in result["problems"]:
		_problems.append(String(problem))
	return problems()


## Everything wrong with the live table ([] when the shipped file is whole).
## A row that is wrong is left out of the table, so its problem is also why an
## ending cannot be reached.
static func problems() -> Array[String]:
	table()
	return _problems.duplicate()


## The merged table. READ-ONLY: it is shared, and an evaluation runs at every
## turn close.
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_load()
	return _table_cache


## Every usable row, in file order (secret included). READ-ONLY.
static func rows() -> Array:
	return table()["endings"]


## The row named `id`, as a copy ({} when the table has no such row).
static func get_ending(id: String) -> Dictionary:
	var key := id.strip_edges().to_upper()
	for row: Dictionary in rows():
		if String(row.get("id", "")) == key:
			return row.duplicate(true)
	return {}


## docs/01 §7's "Weights" row: an Extras unlock, never a run's ending.
static func secret_row() -> Dictionary:
	for row: Dictionary in rows():
		if String(row.get("kind", "")) == KIND_SECRET:
			return row.duplicate(true)
	return {}


## path → ending id, the fallback a run gets when no condition matches.
static func defaults() -> Dictionary:
	return table()["defaults"]


## May this row be the ending at `phase`, and does `state` satisfy it? The only
## clause the caller supplies is the moment; everything else is the row's.
static func matches(row: Dictionary, state: Dictionary, phase := PHASE_CAMPAIGN_END) -> bool:
	if String(row.get("kind", KIND_ENDING)) != KIND_ENDING:
		return false
	var at := String(row.get("at", AT_CAMPAIGN_END))
	if at != AT_ANY_TIME and phase != PHASE_CAMPAIGN_END:
		return false
	var path := String(row.get("path", ANY_PATH))
	if path != ANY_PATH and path != _str(state.get("path")):
		return false
	return _condition_holds(_dict(row.get("condition", {})), state)


## The decision for `state` at `phase`: the lowest-priority matching row
## (priority 0 wins, ties by file order), else the path's declared fallback.
## Returns {} only when the table lost both, which is a broken table.
static func evaluate(state: Dictionary, phase := PHASE_CAMPAIGN_END) -> Dictionary:
	var matched: Array[String] = []
	var winner := {}
	for row: Dictionary in _ranked():
		if not matches(row, state, phase):
			continue
		matched.append(String(row.get("id", "")))
		if winner.is_empty():
			winner = row
	if not winner.is_empty():
		return _decision(winner, matched, "condition", phase, state)
	# A turn close with nothing due is the normal answer — the run continues. Only
	# the campaign's end owes the player an ending whatever the state looks like.
	if phase != PHASE_CAMPAIGN_END:
		return {}
	var fallback := _fallback_row(state)
	if fallback.is_empty():
		push_warning("Endings.evaluate: no ending matched and the table declares no fallback")
		return {}
	return _decision(fallback, matched, "default", phase, state)


## The turn-close question: only `any_time` rows can end a run mid-campaign.
## {} is the normal answer for every turn that is not an early burnout.
static func due(state: Dictionary) -> Dictionary:
	return evaluate(state, PHASE_TURN)


## Does `seen_paths` satisfy the secret's requirement? The rule is the row's
## (`requires.paths`); the fact is the ending log's.
static func secret_available(seen_paths: Array) -> bool:
	var requires: Variant = _dict(secret_row().get("requires", {})).get("paths")
	if not requires is Array:
		return false
	for required: Variant in requires:
		var found := false
		for seen: Variant in seen_paths:
			if _str(seen) == _str(required):
				found = true
				break
		if not found:
			return false
	return true


## One line for the F3 overlay and a review: id, path and the conditions the row
## actually evaluates.
static func describe(row: Dictionary) -> String:
	var condition := _dict(row.get("condition", {}))
	var parts: Array[String] = []
	for edge: Array in [["stage_min", "stage ≥"], ["stage_max", "stage ≤"]]:
		if condition.has(edge[0]):
			parts.append("%s %d" % [edge[1], int(_num(condition[edge[0]]))])
	for edge: Array in [["day_min", "day ≥"], ["day_max", "day ≤"]]:
		if condition.has(edge[0]):
			parts.append("%s %d" % [edge[1], int(_num(condition[edge[0]]))])
	for name: Variant in _dict(condition.get("meters", {})):
		var bounds: Dictionary = condition["meters"][name]
		for edge: String in bounds:
			parts.append(
				"%s %s %s" % [_str(name), "≥" if edge == "min" else "≤", str(bounds[edge])]
			)
	for name: Variant in _dict(condition.get("counters", {})):
		var bounds: Dictionary = condition["counters"][name]
		for edge: String in bounds:
			parts.append(
				"%s %s %s" % [_str(name), "≥" if edge == "min" else "≤", str(bounds[edge])]
			)
	for name: Variant in _dict(condition.get("flags", {})):
		parts.append("%s = %s" % [_str(name), str(condition["flags"][name])])
	var prose := ", ".join(parts) if not parts.is_empty() else "no condition"
	return "%s %s · %s" % [String(row.get("id", "")), String(row.get("name", "")), prose]


## A GameState snapshot that satisfies `row` — the F3 overlay's force and the
## suite's reachability proof. The state starts from the snapshot schema with
## every meter and counter at zero, then carries exactly the facts the row needs,
## so no sibling ending is satisfied by accident (a specific row is proven by the
## evaluator choosing it, never by the caller asserting it).
## Returns {"state": Dictionary, "ok": bool}; `ok` is the evaluator's verdict.
static func satisfying_state(row: Dictionary) -> Dictionary:
	var state := _blank_state()
	var condition := _dict(row.get("condition", {}))
	var path := String(row.get("path", ANY_PATH))
	if path != ANY_PATH:
		state["path"] = path
	_apply_day(state, condition)
	_apply_meters(state, _dict(condition.get("meters", {})))
	_apply_counters(state, _dict(condition.get("counters", {})))
	_apply_flags(state, _dict(condition.get("flags", {})), condition.get("not_flags"))
	_apply_stage(state, condition)
	var decision := evaluate(state, PHASE_CAMPAIGN_END)
	return {"state": state, "ok": String(decision.get("id", "")) == String(row.get("id", ""))}


## Dev tool (F3 overlay, tests): replace the live run with a state that reaches
## `id`, confirm the evaluator agrees, and stamp the run's ending flag. The log
## is written by the ending scene, which is the one that shows the ending.
## {ok, error, ending}: error is "" on success, else `unknown_ending`,
## `unsatisfiable`, `no_game_state` or `state_rejected`.
static func force(id: String) -> Dictionary:
	var row := get_ending(id)
	if row.is_empty() or String(row.get("kind", "")) != KIND_ENDING:
		return {"ok": false, "error": "unknown_ending", "ending": {}}
	var built := satisfying_state(row)
	if not bool(built.get("ok", false)):
		return {"ok": false, "error": "unsatisfiable", "ending": {}}
	if GameState == null:
		return {"ok": false, "error": "no_game_state", "ending": {}}
	if not GameState.from_dict(built["state"]):
		return {"ok": false, "error": "state_rejected", "ending": {}}
	var decision := evaluate(GameState.to_dict(), PHASE_CAMPAIGN_END)
	GameState.set_flag(FLAG_ENDING, String(row.get("id", "")))
	GameState.clear_flag(FLAG_RECORDED)
	var reached := String(decision.get("id", "")) == String(row.get("id", ""))
	return {"ok": reached, "error": "" if reached else "unsatisfiable", "ending": decision}


# --- table loading -------------------------------------------------------


static func _load() -> void:
	var parsed: Variant = null
	if FileAccess.file_exists(TABLE_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	var result := _parse(parsed)
	_table_cache = result["table"]
	_problems = []
	for problem: Variant in result["problems"]:
		_problems.append(String(problem))
	for problem: String in _problems:
		push_warning("Endings: %s (%s)" % [problem, TABLE_PATH])


## Validates a parsed document into {table, problems}. Invalid rows are dropped:
## a table that loses a row degrades to fewer reachable endings, never to a
## condition the evaluator does not understand.
static func _parse(parsed: Variant) -> Dictionary:
	var problems: Array[String] = []
	var out: Dictionary = {"endings": [], "defaults": {}}
	if not parsed is Dictionary:
		problems.append("the document is not a JSON object")
		return {"table": out, "problems": problems}
	var document: Dictionary = parsed
	var raw: Variant = document.get("endings")
	if not raw is Array:
		problems.append("'endings' is not an array")
		return {"table": out, "problems": problems}
	var seen := {}
	for index: int in (raw as Array).size():
		var row := _valid_row((raw as Array)[index], index, seen, problems)
		if row.is_empty():
			continue
		out["endings"].append(row)
	out["defaults"] = _valid_defaults(document.get("defaults"), out["endings"], problems)
	for id: String in DOCS_IDS:
		if not seen.has(id):
			problems.append("docs/01 §7's %s is missing" % id)
	return {"table": out, "problems": problems}


static func _valid_row(
	entry: Variant, index: int, seen: Dictionary, problems: Array[String]
) -> Dictionary:
	if not entry is Dictionary:
		problems.append("row %d is not an object" % index)
		return {}
	var row: Dictionary = (entry as Dictionary).duplicate(true)
	var problem := _row_problem(row, index, seen)
	if not problem.is_empty():
		problems.append(problem)
		return {}
	seen[String(row["id"])] = true
	return row


static func _row_problem(row: Dictionary, index: int, seen: Dictionary) -> String:
	var id := _str(row.get("id")).strip_edges().to_upper()
	if id.is_empty() or seen.has(id):
		return "row %d has a missing or duplicate id '%s'" % [index, id]
	var name := _str(row.get("name")).strip_edges()
	if name.is_empty():
		return "%s has no name" % id
	var kind := _str(row.get("kind")).strip_edges()
	kind = KIND_ENDING if kind.is_empty() else kind
	if not KINDS.has(kind):
		return "%s has unknown kind '%s'" % [id, kind]
	var path := _str(row.get("path")).strip_edges()
	if not _path_allowed(path):
		return "%s has unknown path '%s'" % [id, path]
	row["id"] = id
	row["name"] = name
	row["kind"] = kind
	row["path"] = path
	var problem := _condition_problem(row) if kind == KIND_ENDING else _secret_problem(row)
	return _timing_problem(row) if problem.is_empty() and kind == KIND_ENDING else problem


static func _condition_problem(row: Dictionary) -> String:
	var id := String(row.get("id", ""))
	var value: Variant = row.get("condition", {})
	if not value is Dictionary:
		return "%s: 'condition' is not an object" % id
	var condition: Dictionary = value
	for key: Variant in condition:
		var name := String(key)
		if not CONDITION_KEYS.has(name):
			return "%s: unknown condition key '%s'" % [id, name]
		var problem := _clause_problem(id, name, condition[key])
		if not problem.is_empty():
			return problem
	return ""


static func _clause_problem(id: String, name: String, value: Variant) -> String:
	if name == "meters" or name == "counters":
		return _bounds_problem(id, name, value)
	if name == "flags" and not value is Dictionary:
		return "%s: 'flags' is not an object" % id
	if name == "not_flags" and not value is Array:
		return "%s: 'not_flags' is not an array" % id
	if name == "stage_min" or name == "stage_max" or name == "day_min" or name == "day_max":
		if not (value is int or value is float):
			return "%s: '%s' is not a number" % [id, name]
	return ""


static func _bounds_problem(id: String, name: String, value: Variant) -> String:
	if not value is Dictionary:
		return "%s: '%s' is not an object" % [id, name]
	for key: Variant in value as Dictionary:
		var problem := _bound_problem(id, "%s.%s" % [name, key], (value as Dictionary)[key])
		if not problem.is_empty():
			return problem
	return ""


static func _bound_problem(id: String, name: String, value: Variant) -> String:
	if not value is Dictionary:
		return "%s: '%s' is not an object" % [id, name]
	var bounds: Dictionary = value
	if not bounds.has("min") and not bounds.has("max"):
		return "%s: '%s' needs a min or a max" % [id, name]
	for edge: Variant in bounds:
		if String(edge) != "min" and String(edge) != "max":
			return "%s: '%s' has unknown bound '%s'" % [id, name, edge]
		if not (bounds[edge] is int or bounds[edge] is float):
			return "%s: '%s.%s' is not a number" % [id, name, edge]
	return ""


static func _secret_problem(row: Dictionary) -> String:
	var id := String(row.get("id", ""))
	var requires: Variant = row.get("requires", {})
	if not requires is Dictionary:
		return "%s (secret): 'requires' is not an object" % id
	var paths: Variant = (requires as Dictionary).get("paths")
	if not paths is Array or (paths as Array).size() != GameStateScript.PATHS.size():
		return "%s (secret): requires.paths must list the six paths" % id
	for item: Variant in paths:
		if _str(item) == ANY_PATH or not _path_allowed(_str(item)):
			return "%s (secret): requires.paths has an unknown path" % id
	return ""


static func _timing_problem(row: Dictionary) -> String:
	var priority: Variant = row.get("priority", 100)
	if not (priority is int or priority is float):
		return "%s: 'priority' is not a number" % String(row.get("id", ""))
	var at := _str(row.get("at")).strip_edges()
	at = AT_CAMPAIGN_END if at.is_empty() else at
	if not AT_TIMES.has(at):
		return "%s: unknown 'at' '%s'" % [String(row.get("id", "")), at]
	row["at"] = at
	row["priority"] = int(priority)
	return ""


## The fallback map, filtered to rows that exist: a default naming a dropped row
## is a load problem, not a crash at the last night.
static func _valid_defaults(value: Variant, rows: Array, problems: Array[String]) -> Dictionary:
	var known := {}
	for row: Dictionary in rows:
		if String(row["kind"]) == KIND_ENDING:
			known[String(row["id"])] = true
	var out := {}
	var block: Variant = value if value is Dictionary else {}
	for key: Variant in block:
		var name := String(key)
		var id := _str((block as Dictionary)[key])
		if name != "any" and not GameStateScript.PATHS.has(StringName(name)):
			problems.append("defaults: unknown path '%s'" % name)
			continue
		if not known.has(id):
			problems.append("defaults[%s]: '%s' is not an ending row" % [name, id])
			continue
		out[name] = id
	if out.is_empty():
		problems.append("defaults: the table names no fallback ending")
	return out


# --- evaluation ----------------------------------------------------------


## Matching rows in selection order: priority ascending, file order on a tie.
## Array.sort_custom() is not stable, so the file index is part of the key.
static func _ranked() -> Array:
	var entries: Array = []
	var all := rows()
	for index: int in all.size():
		var row: Dictionary = all[index]
		if String(row.get("kind", "")) != KIND_ENDING:
			continue
		entries.append({"row": row, "priority": int(row["priority"]), "index": index})
	entries.sort_custom(_runs_first)
	var out: Array = []
	for entry: Dictionary in entries:
		out.append(entry["row"])
	return out


static func _runs_first(a: Dictionary, b: Dictionary) -> bool:
	if int(a["priority"]) != int(b["priority"]):
		return int(a["priority"]) < int(b["priority"])
	return int(a["index"]) < int(b["index"])


static func _condition_holds(condition: Dictionary, state: Dictionary) -> bool:
	if not _timing_holds(condition, state):
		return false
	if not _meters_hold(_dict(condition.get("meters", {})), state):
		return false
	if not _counters_hold(_dict(condition.get("counters", {})), state):
		return false
	return _flags_hold(_dict(condition.get("flags", {})), condition.get("not_flags"), state)


static func _timing_holds(condition: Dictionary, state: Dictionary) -> bool:
	var stage := int(_num(state.get("stage")))
	if condition.has("stage_min") and stage < int(_num(condition["stage_min"])):
		return false
	if condition.has("stage_max") and stage > int(_num(condition["stage_max"])):
		return false
	var day := int(_num(state.get("day"), 1.0))
	if condition.has("day_min") and day < int(_num(condition["day_min"], 1.0)):
		return false
	if condition.has("day_max") and day > int(_num(condition["day_max"], 1.0)):
		return false
	return true


static func _meters_hold(bounds_by_meter: Dictionary, state: Dictionary) -> bool:
	for key: Variant in bounds_by_meter:
		var bounds: Dictionary = bounds_by_meter[key]
		if not _bounds_hold(_num(state.get(String(key))), bounds):
			return false
	return true


static func _counters_hold(bounds_by_counter: Dictionary, state: Dictionary) -> bool:
	var profile := _dict(state.get("profile"))
	for key: Variant in bounds_by_counter:
		var bounds: Dictionary = bounds_by_counter[key]
		if not _bounds_hold(float(int(profile.get(String(key), 0))), bounds):
			return false
	return true


static func _flags_hold(required: Dictionary, not_flags: Variant, state: Dictionary) -> bool:
	var flags := _dict(state.get("flags"))
	for key: Variant in required:
		if not _same_value(flags.get(String(key)), required[key]):
			return false
	if not not_flags is Array:
		return true
	for key: Variant in not_flags:
		if _truthy(flags.get(String(key))):
			return false
	return true


static func _bounds_hold(value: float, bounds: Dictionary) -> bool:
	if bounds.has("min") and value < float(_num(bounds["min"])):
		return false
	if bounds.has("max") and value > float(_num(bounds["max"])):
		return false
	return true


## Flag comparison never lets a type slip: `true` is not `1` and "yes" is not 1.
static func _same_value(actual: Variant, expected: Variant) -> bool:
	if (actual is int or actual is float) and (expected is int or expected is float):
		return is_equal_approx(float(actual), float(expected))
	return actual == expected


static func _truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String or value is StringName:
		return not String(value).strip_edges().is_empty()
	return value != null


static func _fallback_row(state: Dictionary) -> Dictionary:
	var path := _str(state.get("path"))
	var declared := _dict(table().get("defaults", {}))
	var id := _str(declared.get(path)) if not path.is_empty() else ""
	id = _str(declared.get("any")) if id.is_empty() else id
	var row := get_ending(id)
	if not row.is_empty():
		return row
	var ranked := _ranked()
	return ranked[0] if not ranked.is_empty() else {}


static func _decision(
	row: Dictionary, matched: Array[String], reason: String, phase: String, state: Dictionary
) -> Dictionary:
	return {
		"id": String(row.get("id", "")),
		"name": String(row.get("name", "")),
		"path": String(row.get("path", ANY_PATH)),
		"row": row.duplicate(true),
		"matched": matched.duplicate(),
		"reason": reason,
		"phase": phase,
		"day": int(_num(state.get("day"), 1.0)),
		"stage": int(_num(state.get("stage"))),
	}


# --- forced state --------------------------------------------------------


static func _apply_day(state: Dictionary, condition: Dictionary) -> void:
	var day := GameStateScript.DAY_MAX
	if condition.has("day_min"):
		day = int(_num(condition["day_min"], float(day)))
	if condition.has("day_max"):
		day = mini(day, int(_num(condition["day_max"], float(day))))
	state["day"] = clampi(day, 1, GameStateScript.DAY_MAX)


static func _apply_meters(state: Dictionary, meters: Dictionary) -> void:
	for key: Variant in meters:
		var name := String(key)
		if not GameStateScript.METER_RANGES.has(StringName(name)):
			continue
		var bounds: Dictionary = meters[key]
		var value := 0.0
		if bounds.has("min"):
			value = float(_num(bounds["min"]))
		elif bounds.has("max"):
			value = float(_num(bounds["max"]))
		state[name] = value


static func _apply_counters(state: Dictionary, counters: Dictionary) -> void:
	var profile := _dict(state.get("profile"))
	for key: Variant in counters:
		var bounds: Dictionary = counters[key]
		var value := 0
		if bounds.has("min"):
			value = int(_num(bounds["min"]))
		elif bounds.has("max"):
			value = int(_num(bounds["max"]))
		profile[String(key)] = maxi(0, value)
	state["profile"] = profile


static func _apply_flags(state: Dictionary, required: Dictionary, not_flags: Variant) -> void:
	var flags := {}
	for key: Variant in required:
		flags[String(key)] = required[key]
	if not_flags is Array:
		for key: Variant in not_flags:
			flags.erase(String(key))
	state["flags"] = flags


## Reaches the row's stage without breaking GameState's invariants: the stage is
## derived from instability, and instability never sits below peak − 15, so the
## band's floor (raised to the row's own instability bound) is written as the peak
## and the meter lands exactly on it.
static func _apply_stage(state: Dictionary, condition: Dictionary) -> void:
	var floor_stage := clampi(int(_num(condition.get("stage_min"))), 0, Stages.max_stage())
	if condition.has("stage_max"):
		floor_stage = mini(
			floor_stage, clampi(int(_num(condition["stage_max"])), 0, Stages.max_stage())
		)
	var bands := Stages.bands()
	var band := float(bands[floor_stage]) if floor_stage < bands.size() else 90.0
	var instability := maxf(float(_num(state.get("instability"))), band)
	state["instability_peak"] = instability
	state["instability"] = instability
	state["stage"] = Stages.for_instability(instability)


## The snapshot schema with nothing earned: the base a forced state grows from.
## A test loads every forced state into GameState, so this cannot drift from
## GameState.to_dict() silently.
static func _blank_state() -> Dictionary:
	return {
		"version": GameStateScript.SNAPSHOT_VERSION,
		"affection": 0.0,
		"trust": 0.0,
		"instability": 0.0,
		"instability_peak": 0.0,
		"fixation": 0.0,
		"lucidity": 0.0,
		"stage": 0,
		"day": 1,
		"turn": 0,
		"path": "",
		"path_locked": false,
		"path_scores": {},
		"path_evidence": {},
		"path_runner_up": "",
		"last_question": "",
		"player_name": "Senpai",
		"profile": {},
		"flags": {},
		"last_tone": "",
	}


# --- small helpers -------------------------------------------------------


static func _path_allowed(path: String) -> bool:
	if path == ANY_PATH:
		return true
	return GameStateScript.PATHS.has(StringName(path))


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _num(value: Variant, fallback := 0.0) -> float:
	if value is int:
		return float(value)
	if value is float:
		return value if is_finite(value) else fallback
	return fallback


static func _str(value: Variant) -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""
