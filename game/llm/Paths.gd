class_name Paths
extends RefCounted
## Paths — docs/01 §4's fracture paths: the six Stage-2 score formulas, the soft
## assignment at Stage 2, the permanent lock at Stage 3, and the hybrid
## runner-up the prompt's path layer borrows one line from.
##
## Split out of GameState the way the meter math was split into Meters (P2.01)
## and the stage machine into Stages (P2.02): GameState owns the live path, the
## lock flag and the signals; this owns the score table, the tie-break and the
## data load. Everything here is pure except the table load, and the
## coefficients live in res://data/paths.json (the docs §4 formulas are also the
## in-code fallback, so a broken file degrades to the documented formulas
## instead of to zero scores).
##
## Formulas are fixed by the bible: if one is wrong in play, the fix is a DCR
## plus a data change and a test update — never a quiet tweak here.

const TABLE_PATH := "res://data/paths.json"

## docs/01 §4 as code: the six score formulas, the Stage-2 soft assignment and
## the Stage-3 lock. The data-file test pins these against the bible.
const DOCS_TABLE := {
	"assign_stage": 2,
	"lock_stage": 3,
	"paths": ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"],
	"scores":
	{
		"YANDERE":
		[
			{"counter": "warmth", "weight": 1.0},
			{"counter": "jealousy_bait", "weight": 2.0},
			{"counter": "leaving_talk", "weight": 2.0},
			{"meter": "fixation", "weight": 1.0, "divisor": 10.0},
		],
		"SPLIT":
		[
			{"counter": "inconsistency", "weight": 3.0},
			{"counter": "leaving_talk", "weight": 1.0},
			{"counter": "broken_promises", "weight": 4.0},
		],
		"TSUN":
		[
			{"counter": "teasing", "weight": 2.0},
			{"counter": "control", "weight": 1.0},
			{"counter": "flattery_rejected", "weight": 1.0},
		],
		"HOLLOW":
		[
			{"counter": "apathy", "weight": 2.0},
			{"counter": "coldness", "weight": 1.0},
			{"counter": "ignored_questions", "weight": 1.0},
		],
		"AWAKE": [{"counter": "meta_curiosity", "weight": 3.0}],
		"ANCHOR":
		[
			{"counter": "honesty", "weight": 2.0},
			{"counter": "boundaries", "weight": 2.0},
			{"counter": "warmth", "weight": 1.0},
			{"counter": "inconsistency", "weight": -1.0},
			{"counter": "jealousy_bait", "weight": -1.0},
		],
	},
}

static var _table_cache: Dictionary = {}


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}


## The merged table (docs values overlaid with paths.json). READ-ONLY: it is
## shared, and a path check runs at every turn close and every stage crossing.
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _load_table()
	return _table_cache


## The six path ids in canonical order — the score report's order and the
## last-resort tie-break (docs/01 §4.1–§4.6).
static func path_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for path_id: Variant in table()["paths"]:
		out.append(StringName(str(path_id)))
	return out


## docs/01 §4: "soft-assigned at Stage 2".
static func assign_stage() -> int:
	return int(table()["assign_stage"])


## docs/01 §4: "locks at Stage 3".
static func lock_stage() -> int:
	return int(table()["lock_stage"])


## Every behaviour-profile counter the formulas read, deduplicated in doc order.
## The three §4-only counters (broken_promises, flattery_rejected,
## ignored_questions) are stored in the profile beside the twelve §2 tags.
static func counters() -> Array[StringName]:
	var out: Array[StringName] = []
	for path_id: Variant in table()["paths"]:
		for term: Variant in table()["scores"][path_id]:
			if not (term as Dictionary).has("counter"):
				continue
			var counter := StringName(str((term as Dictionary)["counter"]))
			if not out.has(counter):
				out.append(counter)
	return out


## True when `counter` is one of the formula counters (GameState's gate for
## counters outside docs/01 §2's twelve-item tag list).
static func is_counter(counter: StringName) -> bool:
	var key := String(counter)
	for path_id: Variant in table()["paths"]:
		for term: Variant in table()["scores"][path_id]:
			var row: Dictionary = term
			if row.has("counter") and str(row["counter"]) == key:
				return true
	return false


## The paths whose score rises when `counter` rises — the evidence map's
## update set (a negative-weight term is not evidence *for* its path).
static func paths_fed_by(counter: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var key := String(counter)
	for path_id: Variant in table()["paths"]:
		for term: Variant in table()["scores"][path_id]:
			var row: Dictionary = term
			if row.has("counter") and str(row["counter"]) == key and float(row["weight"]) > 0.0:
				out.append(StringName(str(path_id)))
				break
	return out


## One docs/01 §4 score. Counters come from the behaviour profile, meters from
## GameState; an unknown id warns and scores 0 so a typo cannot silently win.
static func score_of(path_id: String, profile: Dictionary, meters: Dictionary) -> float:
	var terms: Variant = table()["scores"].get(path_id)
	if not terms is Array:
		push_warning("Paths.score_of: unknown path '%s'" % path_id)
		return 0.0
	var total := 0.0
	for term: Variant in terms:
		var row: Dictionary = term
		var weight := float(row["weight"])
		if row.has("meter"):
			var divisor := float(row.get("divisor", 1.0))
			total += weight * float(meters.get(str(row["meter"]), 0.0)) / divisor
		else:
			total += weight * float(profile.get(str(row["counter"]), 0))
	return total


## The six docs/01 §4 scores, keyed by path id, in canonical order.
static func scores(profile: Dictionary, meters: Dictionary) -> Dictionary:
	var out := {}
	for path_id: StringName in path_ids():
		out[String(path_id)] = score_of(String(path_id), profile, meters)
	return out


## docs/01 §4: "highest wins; ties → the path with more recent evidence". The
## evidence map is path id → the turn index of that path's last positive
## contribution. A tie with no evidence at all falls to the canonical order, so
## the check always resolves. The runner-up is the second-best path with a
## positive score (the hybrid flavour must not appear for a path the player's
## behaviour never fed). Returns {path, runner_up, scores, tied}.
static func select(score_table: Dictionary, evidence: Dictionary) -> Dictionary:
	var ids := path_ids()
	var best := {}
	var second := {}
	var scores_out := {}
	for index: int in ids.size():
		var path_id := ids[index]
		var key := String(path_id)
		var value := float(score_table.get(key, 0.0))
		scores_out[key] = value
		var row := {
			"path": path_id,
			"score": value,
			"evidence": int(evidence.get(key, -1)),
			"order": index,
		}
		if best.is_empty() or _is_better(row, best):
			if not best.is_empty():
				second = best
			best = row
		elif second.is_empty() or _is_better(row, second):
			second = row
	var runner_up := &""
	if not second.is_empty() and float(second["score"]) > 0.0:
		runner_up = second["path"]
	return {
		"path": best["path"],
		"runner_up": runner_up,
		"scores": scores_out,
		"tied": not second.is_empty() and float(best["score"]) == float(second["score"]),
	}


## Parses a path document into the canonical table — data-driven on purpose: a
## test hands it a synthetic document and proves the loader (not a hard-coded
## copy) decides the formulas. Shape: {"assign_stage", "lock_stage",
## "paths": [six ids], "scores": {path: [{counter|meter, weight, divisor?}]}}.
## Anything unusable keeps the docs/01 §4 value it belongs to, so a broken file
## still yields a complete, playable table.
static func parse_document(parsed: Variant) -> Dictionary:
	var out: Dictionary = DOCS_TABLE.duplicate(true)
	if not parsed is Dictionary:
		push_warning("Paths: %s is not a JSON object; using the docs/01 §4 formulas" % TABLE_PATH)
		return out
	var document: Dictionary = parsed
	var ids := _parse_paths(document.get("paths"))
	if ids.is_empty():
		push_warning("Paths: %s paths are not the six §4 ids; using the docs order" % TABLE_PATH)
	else:
		out["paths"] = ids
	var stages := _parse_stages(document, out)
	out["assign_stage"] = stages[0]
	out["lock_stage"] = stages[1]
	var scores := _parse_scores(document.get("scores"), out["paths"])
	if scores.is_empty():
		push_warning("Paths: %s scores do not match the §4 formulas' shape" % TABLE_PATH)
	else:
		out["scores"] = scores
	return out


## A permutation of the six docs ids; any missing, extra, duplicate or unknown
## id is unusable (the bible fixes the six paths — a seventh is a DCR).
static func _parse_paths(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if not value is Array or (value as Array).size() != (DOCS_TABLE["paths"] as Array).size():
		return out
	for item: Variant in value:
		if not (item is String or item is StringName):
			out.clear()
			return out
		var path_id := StringName(str(item))
		if out.has(path_id) or not (DOCS_TABLE["paths"] as Array).has(String(path_id)):
			out.clear()
			return out
		out.append(path_id)
	return out


## The Stage-2/Stage-3 pair: both integers inside 0..5 (Stages' range) with the
## lock no earlier than the assignment. An invalid pair keeps the docs values.
static func _parse_stages(document: Dictionary, defaults: Dictionary) -> Array[int]:
	var found: Array[int] = [int(defaults["assign_stage"]), int(defaults["lock_stage"])]
	var assigned := _stage_value(document.get("assign_stage"), found[0])
	var locked := _stage_value(document.get("lock_stage"), found[1])
	if locked < assigned:
		push_warning(
			"Paths: lock_stage %d precedes assign_stage %d — docs values kept" % [locked, assigned]
		)
		return found
	found[0] = assigned
	found[1] = locked
	return found


static func _stage_value(value: Variant, fallback: int) -> int:
	if not (value is int or value is float):
		return fallback
	var number := float(value)
	if not is_finite(number) or number != floor(number) or number < 0.0:
		return fallback
	if number > float(Stages.max_stage()):
		return fallback
	return int(number)


## The score table: exactly the six ids, each a non-empty term list. Any invalid
## term makes the whole block unusable (an empty result) — a half-parsed formula
## would silently score a path wrong, which is worse than the docs fallback.
static func _parse_scores(value: Variant, ids: Variant) -> Dictionary:
	var out := {}
	if not value is Dictionary:
		return out
	var source: Dictionary = value
	var ordered: Array = ids
	if source.size() != ordered.size():
		return out
	for path_id: Variant in ordered:
		var key := String(path_id)
		if not source.has(key):
			return out
		var terms := _parse_terms(source[key])
		if terms.is_empty():
			return out
		out[key] = terms
	return out


static func _parse_terms(value: Variant) -> Array:
	var out: Array = []
	if not value is Array or (value as Array).is_empty():
		return out
	for item: Variant in value:
		var term := _parse_term(item)
		if term.is_empty():
			return []
		out.append(term)
	return out


static func _parse_term(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	var has_counter := source.has("counter")
	var has_meter := source.has("meter")
	if has_counter == has_meter:
		return {}
	var name := str(source["counter"] if has_counter else source["meter"]).strip_edges()
	if name.is_empty():
		return {}
	var weight: Variant = source.get("weight")
	if not (weight is int or weight is float) or not is_finite(float(weight)):
		return {}
	var term := {"counter" if has_counter else "meter": name, "weight": float(weight)}
	if has_meter:
		var divisor: Variant = source.get("divisor", 1.0)
		if not (divisor is int or divisor is float):
			return {}
		var number := float(divisor)
		if not is_finite(number) or number <= 0.0:
			return {}
		term["divisor"] = number
	return term


static func _is_better(candidate: Dictionary, current: Dictionary) -> bool:
	if float(candidate["score"]) > float(current["score"]):
		return true
	if float(candidate["score"]) < float(current["score"]):
		return false
	if int(candidate["evidence"]) > int(current["evidence"]):
		return true
	if int(candidate["evidence"]) < int(current["evidence"]):
		return false
	return int(candidate["order"]) < int(current["order"])


static func _load_table() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("Paths: %s missing; using the docs/01 §4 formulas" % TABLE_PATH)
		return parse_document({})
	return parse_document(JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH)))
