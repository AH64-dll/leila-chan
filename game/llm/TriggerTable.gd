class_name TriggerTable
extends RefCounted
## TriggerTable — the trigger catalogue's loader and parser: res://data/triggers.json
## in, the canonical table `TriggerEngine` runs on out.
##
## Split out of TriggerEngine (P3.07) for the same reason the meter math lives in
## Meters and the stage machine in Stages: the engine had reached gdlint's file
## cap, and the data vocabulary now grows with every trigger round (P2.10 added
## `guard`; P3.07 adds `mentions_memory`, `name_mention`, `text_match`,
## `absence_hours_lt` and event-fed flag values). Nothing here matches a trigger;
## this file only decides what a legal row is.
##
## Healing beats crashing (docs/07 §2): an unknown field, a typo'd key or a bad
## scalar keeps the documented default it belongs to, so a broken file still
## plays her triggers. tests/test_triggers.py rejects the typos a review can
## catch, and every value the loader drops is listed in that file's vocabulary.

const TABLE_PATH := "res://data/triggers.json"
const VERSION := 1
const MAX_STAGE := 5
const BEHAVIORS: Array[String] = ["once", "repeatable", "escalating"]
## docs/01 §5 "C clock / OS": every condition a clock detector may carry.
## T17 uses the strict `absence_hours_lt` (P3.07) so a 7-day absence reaches
## T18 only, and 168 h itself stays on T18's side of the boundary;
## `absence_hours_lte` is the same bound inclusive and no row uses it.
const CLOCK_KEYS: Array[String] = [
	"day_gte",
	"day_lte",
	"day_eq",
	"turn_gte",
	"hour_from",
	"hour_to",
	"absence_hours_gte",
	"absence_hours_lte",
	"absence_hours_lt",
]
const CLOCK_FLAG_KEYS: Array[String] = ["flag_set", "flag_absent"]

## docs/02 §1.2 as code: the detector weights, the defaults every row falls back
## to, and the engine's own identity. The data file is authoritative; this is
## the in-code fallback so a missing or unusable file still plays her triggers.
const DOCS_TABLE := {
	"strength": {"agreement": 1.0, "keyword": 1.0, "model": 0.5, "engine": 1.0, "clock": 1.0},
	"defaults":
	{
		"requires": "any",
		"behavior": "repeatable",
		"cooldown_turns": 3,
		"stage_min": 0,
		"stage_max": 5,
		"escalate": {"axis": "step", "max_steps": 3, "step_scale": 0.5},
	},
}

static var _file_cache: Dictionary = {}


## Test hook: drop the loaded file table so the next call re-reads the data file.
static func clear_cache() -> void:
	_file_cache = {}


## The merged table the file declares (defaults overlaid with triggers.json).
## READ-ONLY: it is shared, and the detectors run on every submit.
static func default_table() -> Dictionary:
	if _file_cache.is_empty():
		_file_cache = load_file()
	return _file_cache


static func load_file() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("TriggerTable: %s missing; using the docs defaults" % TABLE_PATH)
		return parse_document({})
	return parse_document(JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH)))


## Parses a trigger document into the canonical table — data-driven on purpose:
## a test (or a mod) hands it a synthetic document and proves the loader decides
## the catalogue, not a hard-coded copy. Unusable input keeps the documented
## default it belongs to, so a broken file still plays.
static func parse_document(parsed: Variant, origin := TABLE_PATH) -> Dictionary:
	var out := _docs_table()
	if not parsed is Dictionary:
		push_warning("TriggerTable: %s is not a JSON object; using the defaults" % origin)
		return out
	var document: Dictionary = parsed
	_merge_strength(out["strength"], document.get("strength"))
	_merge_defaults(out["defaults"], document.get("defaults"))
	var rows: Variant = document.get("triggers")
	if not rows is Dictionary:
		return out
	for key: Variant in rows:
		var id := str(key).strip_edges()
		if id.is_empty():
			continue
		var record := _parse_row(rows[key], out["defaults"])
		if record.is_empty():
			push_warning("TriggerTable: trigger '%s' is unusable and was skipped" % id)
			continue
		out["triggers"][id] = record
	return out


static func _parse_row(raw: Variant, defaults: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var row: Dictionary = raw
	var detect := _parse_detect(row.get("detect"))
	var guard := _parse_guard(row.get("guard"))
	if detect.is_empty() and guard.is_empty():
		return {}
	var behavior := str(row.get("behavior", defaults["behavior"]))
	if not BEHAVIORS.has(behavior):
		behavior = String(defaults["behavior"])
	var requires := "all" if str(row.get("requires", defaults["requires"])) == "all" else "any"
	var escalate: Dictionary = (defaults["escalate"] as Dictionary).duplicate()
	var raw_escalate: Variant = row.get("escalate")
	if raw_escalate is Dictionary:
		var spec: Dictionary = raw_escalate
		if spec.has("max_steps"):
			escalate["max_steps"] = clampi(_int(spec["max_steps"], 3), 1, 100)
		if spec.has("step_scale"):
			escalate["step_scale"] = maxf(0.0, _float(spec["step_scale"], 0.5))
		if spec.has("axis"):
			escalate["axis"] = _parse_axis(spec["axis"])
	var raw_min := _int(row.get("stage_min", defaults["stage_min"]), -1)
	var raw_max := _int(row.get("stage_max", defaults["stage_max"]), -1)
	var stage_min := int(defaults["stage_min"])
	var stage_max := int(defaults["stage_max"])
	if raw_min >= 0 and raw_min <= MAX_STAGE:
		stage_min = raw_min
	if raw_max >= 0 and raw_max <= MAX_STAGE:
		stage_max = raw_max
	if stage_max < stage_min:
		stage_min = int(defaults["stage_min"])
		stage_max = int(defaults["stage_max"])
	var raw_cooldown := _int(row.get("cooldown_turns", defaults["cooldown_turns"]), -1)
	var cooldown := int(defaults["cooldown_turns"])
	if raw_cooldown >= 0:
		cooldown = raw_cooldown
	var name := str(row.get("name", "")).strip_edges()
	if name.is_empty():
		name = "unnamed"
	return {
		"name": name,
		"detect": detect,
		"guard": guard,
		"requires": requires,
		"behavior": behavior,
		"escalate": escalate,
		"cooldown_turns": cooldown,
		"stage_min": stage_min,
		"stage_max": stage_max,
		"observe": _parse_effects({"flags": row.get("observe")})["flags"],
		"effects": _parse_effects(row.get("effects")),
		"line": _parse_line(row.get("line")),
	}


static func _parse_detect(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	var spec: Dictionary = raw
	var keyword := _parse_keyword(spec.get("keyword"))
	if not keyword.is_empty():
		out["keyword"] = keyword
	var labels := _parse_strings(spec.get("model"))
	if not labels.is_empty():
		out["model"] = labels
	var kinds := _parse_strings(spec.get("event"))
	if not kinds.is_empty():
		out["event"] = kinds
	var clock := _parse_clock(spec.get("clock"))
	if not clock.is_empty():
		out["clock"] = clock
	return out


static func _parse_keyword(raw: Variant) -> Dictionary:
	var any_patterns: Array[String] = []
	var all_patterns: Array[String] = []
	var ignore_case := true
	if raw is Array:
		any_patterns = _parse_strings(raw)
	elif raw is Dictionary:
		var spec: Dictionary = raw
		any_patterns = _parse_strings(spec.get("any"))
		all_patterns = _parse_strings(spec.get("all"))
		ignore_case = bool(spec.get("ignore_case", true))
	if any_patterns.is_empty() and all_patterns.is_empty():
		return {}
	return {"any": any_patterns, "all": all_patterns, "ignore_case": ignore_case}


static func _parse_clock(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	var spec: Dictionary = raw
	for key: String in CLOCK_KEYS:
		if not spec.has(key):
			continue
		var value := _int(spec[key], -1000000)
		if value != -1000000:
			out[key] = value
	for key: String in CLOCK_FLAG_KEYS:
		var flag := str(spec.get(key, "")).strip_edges()
		if not flag.is_empty():
			out[key] = flag
	return out


## docs/01 §5 T08 "escalates with stage": the escalation axis is the firing
## count (`step`, the default) or the stage since stage_min (`stage`). An
## unknown value heals to the default rather than skipping the row.
static func _parse_axis(raw: Variant) -> String:
	return "stage" if str(raw).strip_edges() == "stage" else "step"


## A row's guard: conditions that must also hold but that are NOT detectors.
static func _parse_guard(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	var spec: Dictionary = raw
	var clock := _parse_clock(spec)
	if not clock.is_empty():
		out["clock"] = clock
	var counters: Variant = spec.get("counter_gte")
	if counters is Dictionary:
		var floors := {}
		for name: Variant in counters:
			var key := str(name).strip_edges()
			var value := _int(counters[name], 0)
			if not key.is_empty() and value > 0:
				floors[key] = value
		if not floors.is_empty():
			out["counter_gte"] = floors
	var contradiction: Variant = spec.get("contradicts_memory")
	if contradiction is Dictionary:
		out["contradicts_memory"] = _parse_contradiction(contradiction)
	elif contradiction is bool and bool(contradiction):
		out["contradicts_memory"] = _parse_contradiction({})
	var mention: Variant = spec.get("mentions_memory")
	if mention is Dictionary:
		out["mentions_memory"] = _parse_mention(mention)
	elif mention is bool and bool(mention):
		out["mentions_memory"] = _parse_mention({})
	var naming: Variant = spec.get("name_mention")
	if naming is Dictionary:
		out["name_mention"] = _parse_naming(naming)
	elif naming is bool and bool(naming):
		out["name_mention"] = _parse_naming({})
	var text: Variant = spec.get("text_match")
	if text is Dictionary:
		out["text_match"] = _parse_text_match(text)
	elif text is bool and bool(text):
		out["text_match"] = _parse_text_match({})
	return out


## docs/01 §5 T13: the cues and the shared-word floor are data; omitted keys
## keep MemoryRules' defaults.
static func _parse_contradiction(raw: Dictionary) -> Dictionary:
	var out := {}
	var negations := _parse_strings(raw.get("negations"))
	if not negations.is_empty():
		out["negations"] = negations
	var shared := _int(raw.get("min_shared_words"), 0)
	if shared > 0:
		out["min_shared_words"] = shared
	return out


## docs/01 §5 T22: the shared-content-word floor is data; an omitted key keeps
## MemoryRules' default (the same floor T13's gate uses).
static func _parse_mention(raw: Dictionary) -> Dictionary:
	var out := {}
	var shared := _int(raw.get("min_shared_words"), 0)
	if shared > 0:
		out["min_shared_words"] = shared
	return out


## docs/01 §5 T26: the capture pattern and the words it must not take (her own
## name, endearments) are data; a row without a pattern never matches.
static func _parse_naming(raw: Dictionary) -> Dictionary:
	var out := {}
	var pattern := str(raw.get("pattern", "")).strip_edges()
	if not pattern.is_empty():
		out["pattern"] = pattern
	if raw.has("ignore_case"):
		out["ignore_case"] = bool(raw["ignore_case"])
	var excludes := _parse_strings(raw.get("exclude"))
	if not excludes.is_empty():
		out["exclude"] = excludes
	return out


## P3.07 guard: the message must also contain one of these patterns. It is the
## same shape as a keyword detector (and reuses its matcher), but a guard is a
## precondition, not evidence — docs/01 §5's detection letter for the row stays
## the model's (T28's thanks, T30's question about her past).
static func _parse_text_match(raw: Dictionary) -> Dictionary:
	return _parse_keyword(raw)


## `effects.flags` values are scalars, or `{"from_event": "<name>"}` on an event
## row whose flag follows the event's own data instead of a constant (T21:
## mute → true, unmute → false, one row for the whole "until unmuted" span).
static func _parse_effects(raw: Variant) -> Dictionary:
	var out := {"meters": {}, "profile": {}, "path": {}, "flags": {}}
	if not raw is Dictionary:
		return out
	var spec: Dictionary = raw
	for group: String in ["meters", "profile", "path"]:
		var values: Variant = spec.get(group)
		if not values is Dictionary:
			continue
		var table_values: Dictionary = values
		for name: Variant in table_values:
			var key := str(name).strip_edges()
			if key.is_empty():
				continue
			if group == "meters":
				var value := _float(table_values[name], 0.0)
				if not is_zero_approx(value):
					out[group][key] = value
			else:
				var points := _int(table_values[name], 0)
				if points != 0:
					out[group][key] = points
	var flags: Variant = spec.get("flags")
	if flags is Dictionary:
		var table_flags: Dictionary = flags
		for name: Variant in table_flags:
			var key := str(name).strip_edges()
			if key.is_empty():
				continue
			var value: Variant = table_flags[name]
			var from_event := _parse_from_event(value)
			if not from_event.is_empty():
				out["flags"][key] = from_event
				continue
			if value is bool or value is int or value is float or value is String:
				out["flags"][key] = value
			else:
				push_warning("TriggerTable: flag '%s' is not a scalar; ignored" % key)
	return out


## `{"from_event": "<data key>"}` → the same shape, healed; anything else is {}
## so the caller falls through to the scalar check.
static func _parse_from_event(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var spec: Dictionary = raw
	if spec.size() != 1 or not spec.has("from_event"):
		return {}
	var key := str(spec["from_event"]).strip_edges()
	if key.is_empty():
		push_warning("TriggerTable: flag reads an empty event key; ignored")
		return {}
	return {"from_event": key}


static func _parse_line(raw: Variant) -> Variant:
	if raw is String:
		return (raw as String).strip_edges()
	var out: Array[String] = []
	if raw is Array:
		for item: Variant in raw:
			var line := str(item).strip_edges()
			if not line.is_empty():
				out.append(line)
	return out


static func _parse_strings(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not raw is Array:
		return out
	for item: Variant in raw:
		if not item is String:
			continue
		var value := (item as String).strip_edges()
		if not value.is_empty() and not out.has(value):
			out.append(value)
	return out


static func _merge_strength(target: Dictionary, source: Variant) -> void:
	if not source is Dictionary:
		return
	var given: Dictionary = source
	for key: String in target.keys():
		if not given.has(key):
			continue
		var value := _float(given[key], -1.0)
		if value >= 0.0:
			target[key] = value


static func _merge_defaults(target: Dictionary, source: Variant) -> void:
	if not source is Dictionary:
		return
	var given: Dictionary = source
	target["requires"] = "all" if str(given.get("requires", target["requires"])) == "all" else "any"
	var behavior := str(given.get("behavior", target["behavior"]))
	if BEHAVIORS.has(behavior):
		target["behavior"] = behavior
	if given.has("cooldown_turns"):
		target["cooldown_turns"] = maxi(
			0, _int(given["cooldown_turns"], int(target["cooldown_turns"]))
		)
	if given.has("stage_min"):
		target["stage_min"] = clampi(_int(given["stage_min"], 0), 0, MAX_STAGE)
	if given.has("stage_max"):
		target["stage_max"] = clampi(_int(given["stage_max"], MAX_STAGE), 0, MAX_STAGE)
	var escalate: Variant = given.get("escalate")
	if escalate is Dictionary:
		var spec: Dictionary = escalate
		if spec.has("max_steps"):
			target["escalate"]["max_steps"] = clampi(_int(spec["max_steps"], 3), 1, 100)
		if spec.has("step_scale"):
			target["escalate"]["step_scale"] = maxf(0.0, _float(spec["step_scale"], 0.5))
		if spec.has("axis"):
			target["escalate"]["axis"] = _parse_axis(spec["axis"])


## A fresh copy of the docs table in the canonical shape: typed scalars and an
## empty catalogue (rows are data, never code).
static func _docs_table() -> Dictionary:
	var out: Dictionary = DOCS_TABLE.duplicate(true)
	out["version"] = VERSION
	out["triggers"] = {}
	var escalate: Dictionary = out["defaults"]["escalate"]
	escalate["max_steps"] = int(escalate["max_steps"])
	escalate["step_scale"] = float(escalate["step_scale"])
	return out


## Healed int read for callers outside the loader (TriggerEngine's P2.20 save
## seam reads its own payload with the same rules the rows get).
static func int_value(value: Variant, fallback: int) -> int:
	return _int(value, fallback)


static func _float(value: Variant, fallback: float) -> float:
	if value is int:
		return float(value)
	if value is float:
		return value if is_finite(value) else fallback
	return fallback


static func _int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value) if is_finite(value) else fallback
	if value is String:
		return int(value) if (value as String).is_valid_int() else fallback
	return fallback
