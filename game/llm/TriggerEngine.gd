class_name TriggerEngine
extends RefCounted
## TriggerEngine — the docs/01 §5 hidden-trigger engine: four detectors (K
## keyword/regex, M the Turn's `read` label, E engine event, C clock/OS), the
## once / repeatable / escalating behaviours, per-trigger cooldowns, and the
## docs/02 §1.2 agreement rule (both detectors agree → full strength, model-only
## → half strength).
##
## Split out of the Triggers autoload the way the meter math was split into
## Meters (P2.01) and the stage machine into Stages (P2.02): this class owns the
## matching, the caps and the effect arithmetic; Triggers owns the GameState
## writes and the prompt lines. Everything here is pure except the table load —
## the caller injects the turn, day, stage, hour, absence and flags — so a
## transcript replays identically.
##
## Data is the whole story (docs/07 §2): res://data/triggers.json holds the
## strength weights, the defaults and one row per trigger. Adding a trigger is a
## data row, never code — the loader and this engine only know the vocabulary
## (see the file's `doc` string). A broken row is skipped with a warning and the
## rest of the catalogue still plays.
##
## Timing: a trigger fires at the first point where its evidence is complete.
## K/E/C are known when the player submits (or while she waits), so they fire at
## begin_turn/handle_event and their line rides the *current* turn. M arrives
## with the completed Turn's `read`, so a row that needs the model fires at
## close_turn and its line rides the *next* prompt. `requires: "all"` rows have
## to wait for M even when the keyword already matched, because agreement is the
## thing being decided.

const TABLE_PATH := "res://data/triggers.json"
const VERSION := 1
const MAX_STAGE := 5
## Fired results kept for the F3 overlay and the transcript; state, not a log.
const MAX_HISTORY := 16
const BEHAVIORS: Array[String] = ["once", "repeatable", "escalating"]
const DETECTORS: Array[String] = ["keyword", "model", "event", "clock"]
## docs/01 §5 "C clock / OS": every condition a clock detector may carry.
const CLOCK_KEYS: Array[String] = [
	"day_gte", "day_lte", "day_eq", "turn_gte", "hour_from", "hour_to", "absence_hours_gte"
]
const CLOCK_FLAG_KEYS: Array[String] = ["flag_set", "flag_absent"]
## Effect groups in row order; `flags` is the only one that is not scaled by
## strength (a marker is either set or not).
const EFFECT_GROUPS: Array[String] = ["meters", "profile", "path", "flags"]

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
		"escalate": {"max_steps": 3, "step_scale": 0.5},
	},
}

static var _file_cache: Dictionary = {}

var _table: Dictionary = {}
var _state: Dictionary = {}
var _matched: Dictionary = {}
var _fired: Dictionary = {}
var _turn := -1
var _history: Array[Dictionary] = []
var _path_scores: Dictionary = {}
var _regex_cache: Dictionary = {}


## Test hook: drop the loaded file table so the next call re-reads the data file.
static func clear_cache() -> void:
	_file_cache = {}


## The merged table the file declares (defaults overlaid with triggers.json).
## READ-ONLY: it is shared, and the detectors run on every submit.
static func default_table() -> Dictionary:
	if _file_cache.is_empty():
		_file_cache = _load_file()
	return _file_cache


## Installs a canonical table (the parse_document() shape) — how the autoload
## loads the file and how a test or a mod ships a different catalogue.
func use_table(table_data: Dictionary) -> void:
	_table = table_data
	_regex_cache.clear()  # a fixed pattern must not stay cached as broken
	_state.clear()
	_matched.clear()
	_fired.clear()
	_turn = -1
	_path_scores.clear()


## The installed table, lazily the shipped one. READ-ONLY: copy before editing.
func table() -> Dictionary:
	if _table.is_empty():
		_table = default_table()
	return _table


## Session boundary (Director.reset()): every firing, cooldown and path point
## goes. The catalogue stays — it is data, not session state.
func reset() -> void:
	_state.clear()
	_matched.clear()
	_fired.clear()
	_turn = -1
	_history.clear()
	_path_scores.clear()


## docs/01 §5 detection at submit (docs/02 §4 step 0): K against the player's
## text, C against the injected turn/day/hour/absence/flags. Returns the rows
## that fired, in catalogue order.
func begin_turn(ctx: Dictionary) -> Array[Dictionary]:
	_turn_begin(ctx)
	var fired: Array[Dictionary] = []
	var text := str(ctx.get("text", ""))
	var rows := _catalogue()
	for id: String in rows:
		if _fired.has(id):
			continue
		var rec: Dictionary = rows[id]
		# Merge, never overwrite: an engine event may already have matched this
		# row for this same turn (handle_event runs before the submit).
		var sources: Dictionary = (_matched.get(id, {}) as Dictionary).duplicate()
		var detect: Dictionary = rec["detect"]
		if detect.has("keyword"):
			sources["keyword"] = _keyword_matches(detect["keyword"], text)
		if detect.has("clock"):
			sources["clock"] = _clock_matches(detect["clock"], ctx)
		_matched[id] = sources
		if _needs_model(rec) and String(rec["requires"]) == "all":
			continue  # agreement is decided at close_turn
		if not _any_source(sources) or not _eligible(id, rec, ctx):
			continue
		fired.append(_fire(id, rec, ctx, _sources_label(sources)))
	return fired


## docs/01 §5 "E engine event" (P2.09's Telemetry): ctx["event"] is the
## normalized event. Matched rows fire immediately — an alt-tab has to reach the
## turn she is already answering.
func handle_event(ctx: Dictionary) -> Array[Dictionary]:
	_turn_begin(ctx)
	var fired: Array[Dictionary] = []
	var event: Variant = ctx.get("event")
	if not event is Dictionary:
		return fired
	var kind := str((event as Dictionary).get("event", ""))
	if kind.is_empty():
		return fired
	var rows := _catalogue()
	for id: String in rows:
		if _fired.has(id):
			continue
		var rec: Dictionary = rows[id]
		var detect: Dictionary = rec["detect"]
		if not (detect.get("event", []) as Array).has(kind):
			continue
		var sources: Dictionary = (_matched.get(id, {}) as Dictionary).duplicate()
		sources["event"] = true
		_matched[id] = sources
		if _needs_model(rec) and String(rec["requires"]) == "all":
			continue  # agreement is decided at close_turn
		if not _eligible(id, rec, ctx):
			continue
		fired.append(_fire(id, rec, ctx, "event"))
	return fired


## docs/01 §5 "M model labels it via the Turn's read field": the only detector
## that needs the finished Turn. `requires: "all"` rows fire here at full
## strength once M agrees with the sources matched earlier this turn;
## everything else is model-only and therefore halved (docs/02 §1.2).
func close_turn(ctx: Dictionary) -> Array[Dictionary]:
	_turn_begin(ctx)
	var fired: Array[Dictionary] = []
	var read := str(ctx.get("read", ""))
	if read.is_empty():
		return fired
	var rows := _catalogue()
	for id: String in rows:
		if _fired.has(id):
			continue
		var rec: Dictionary = rows[id]
		if not ((rec["detect"] as Dictionary).get("model", []) as Array).has(read):
			continue
		if String(rec["requires"]) == "all":
			if not _any_source(_matched.get(id, {})) or not _eligible(id, rec, ctx):
				continue
			fired.append(_fire(id, rec, ctx, "both"))
			continue
		if not _eligible(id, rec, ctx):
			continue
		fired.append(_fire(id, rec, ctx, "model"))
	return fired


## Everything the F3 overlay, the transcript and the tests read in one call.
func report() -> Dictionary:
	var counts := {}
	for id: Variant in _state:
		counts[str(id)] = int((_state[id] as Dictionary).get("count", 0))
	return {
		"turn": _turn,
		"catalogue": _catalogue().size(),
		"fired_this_turn": _fired.keys(),
		"counts": counts,
		"path_scores": _path_scores.duplicate(),
		"last": _history.duplicate(true),
	}


## docs/01 §4/§5: the path points the triggers have added so far ("YANDERE +3"
## and friends). P2.12 folds these into the path scores; nothing else writes
## here, so the trigger contribution stays attributable.
func path_scores() -> Dictionary:
	return _path_scores.duplicate()


## P2.20's save seam: firings and cooldowns survive a reload, or a "once"
## trigger would repeat every time the player comes back.
func to_dict() -> Dictionary:
	var triggers := {}
	for id: Variant in _state:
		var state: Dictionary = _state[id]
		triggers[str(id)] = {
			"count": int(state.get("count", 0)),
			"last_turn": int(state.get("last_turn", 0)),
		}
	return {
		"version": VERSION,
		"triggers": triggers,
		"path_scores": _path_scores.duplicate(),
	}


## Restores to_dict(); unknown ids are kept (the catalogue may have grown since
## the save) and counts are healed to non-negative ints.
func from_dict(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var document: Dictionary = data
	if not document.has("triggers") and not document.has("path_scores"):
		return false
	var version := _int(document.get("version"), VERSION)
	if version != VERSION:
		push_warning(
			"TriggerEngine: trigger state v%d (expected v%d) — best effort" % [version, VERSION]
		)
	reset()
	var triggers: Variant = document.get("triggers")
	if triggers is Dictionary:
		for id: Variant in triggers:
			var stored: Variant = triggers[id]
			if not stored is Dictionary:
				continue
			var state: Dictionary = stored
			_state[str(id)] = {
				"count": maxi(0, _int(state.get("count"), 0)),
				"last_turn": _int(state.get("last_turn"), 0),
			}
	var points: Variant = document.get("path_scores")
	if points is Dictionary:
		for name: Variant in points:
			_path_scores[str(name)] = _int(points[name], 0)
	return true


## ── Firing ────────────────────────────────────────────────────────────────


## One turn boundary: the per-turn dedupe set only survives inside a turn, so a
## row can fire at begin_turn OR at close_turn, never both.
func _turn_begin(ctx: Dictionary) -> void:
	var turn := int(ctx.get("turn", 0))
	if turn == _turn:
		return
	_turn = turn
	_fired.clear()
	_matched.clear()


## Stage gate, behaviour cap and cooldown — the three docs/01 §5 caps that make
## her "not feel like a keyword machine".
func _eligible(id: String, rec: Dictionary, ctx: Dictionary) -> bool:
	var stage := clampi(int(ctx.get("stage", 0)), 0, MAX_STAGE)
	if stage < int(rec["stage_min"]) or stage > int(rec["stage_max"]):
		return false
	var state: Dictionary = _state.get(id, {})
	var count := int(state.get("count", 0))
	var behavior := String(rec["behavior"])
	if behavior == "once" and count > 0:
		return false
	if behavior == "escalating" and count >= int((rec["escalate"] as Dictionary)["max_steps"]):
		return false
	if count > 0:
		var cooldown := int(rec["cooldown_turns"])
		if int(ctx.get("turn", 0)) - int(state.get("last_turn", 0)) < cooldown:
			return false
	return true


func _fire(id: String, rec: Dictionary, ctx: Dictionary, agreement: String) -> Dictionary:
	var state: Dictionary = _state.get(id, {})
	var step := int(state.get("count", 0)) + 1
	var strength := _base_strength(agreement) * _escalation(rec, step)
	var effects := _scaled_effects(rec["effects"], strength)
	var result := {
		"id": id,
		"name": String(rec["name"]),
		"step": step,
		"strength": strength,
		"agreement": agreement,
		"effects": effects,
		"line": _line_for(rec, step, ctx),
	}
	_state[id] = {"count": step, "last_turn": int(ctx.get("turn", 0))}
	_fired[id] = true
	_add_path(effects)
	_history.append(result.duplicate(true))
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	return result


## docs/02 §1.2's agreement rule as data: the detector that decided the firing
## picks the weight. "both" is the agreement case; "model" is the model-only
## case and nothing else.
func _base_strength(agreement: String) -> float:
	var strength: Dictionary = table()["strength"]
	match agreement:
		"model":
			return float(strength["model"])
		"both":
			return float(strength["agreement"])
		"keyword":
			return float(strength["keyword"])
		"event":
			return float(strength["engine"])
		"clock":
			return float(strength["clock"])
	return 1.0


## docs/01 §5 "escalating": the effect grows with each firing, up to max_steps;
## once is repeatable and every other behaviour keeps strength 1.
func _escalation(rec: Dictionary, step: int) -> float:
	if String(rec["behavior"]) != "escalating":
		return 1.0
	var spec: Dictionary = rec["escalate"]
	var capped := mini(step, int(spec["max_steps"]))
	return 1.0 + float(spec["step_scale"]) * float(capped - 1)


## Scales one row's effects by the firing's strength. Meters stay fractional;
## profile counters and path points are integers and round half away from zero,
## so a data author who needs an exact halving uses an even value.
func _scaled_effects(effects: Dictionary, strength: float) -> Dictionary:
	var out := {"meters": {}, "profile": {}, "path": {}, "flags": {}}
	var meters: Dictionary = effects.get("meters", {})
	for name: Variant in meters:
		var value := float(meters[name]) * strength
		if not is_zero_approx(value):
			out["meters"][str(name)] = value
	for group: String in ["profile", "path"]:
		var points: Dictionary = effects.get(group, {})
		for name: Variant in points:
			var value := roundi(float(points[name]) * strength)
			if value != 0:
				out[group][str(name)] = value
	var flags: Dictionary = effects.get("flags", {})
	for name: Variant in flags:
		out["flags"][str(name)] = flags[name]
	return out


func _add_path(effects: Dictionary) -> void:
	var points: Dictionary = effects.get("path", {})
	for name: Variant in points:
		var key := str(name)
		_path_scores[key] = int(_path_scores.get(key, 0)) + int(points[name])


## docs/08 §6 line style. A row may carry one template or an array indexed by
## escalation step (the last line repeats past the array's end).
func _line_for(rec: Dictionary, step: int, ctx: Dictionary) -> String:
	var raw: Variant = rec.get("line", "")
	if raw is Array:
		var lines: Array = raw
		if lines.is_empty():
			return ""
		raw = lines[mini(step - 1, lines.size() - 1)]
	if not raw is String:
		return ""
	return _render(raw, step, ctx)


static func _render(template: String, step: int, ctx: Dictionary) -> String:
	var line := template
	line = line.replace("{count}", str(step))
	line = line.replace("{ordinal}", _ordinal(step))
	line = line.replace("{stage}", str(int(ctx.get("stage", 0))))
	line = line.replace("{day}", str(int(ctx.get("day", 1))))
	line = line.replace("{turn}", str(int(ctx.get("turn", 0))))
	return line.strip_edges()


static func _ordinal(value: int) -> String:
	var number := maxi(1, value)
	var suffix := "th"
	var tens := number % 100
	if tens < 11 or tens > 13:
		match number % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [number, suffix]


## ── Detectors ─────────────────────────────────────────────────────────────


func _keyword_matches(spec: Dictionary, text: String) -> bool:
	if text.is_empty():
		return false
	var ignore_case := bool(spec.get("ignore_case", true))
	var all_patterns: Array = spec.get("all", [])
	for pattern: Variant in all_patterns:
		if _search(str(pattern), text, ignore_case) == null:
			return false
	var any_patterns: Array = spec.get("any", [])
	if any_patterns.is_empty():
		return not all_patterns.is_empty()
	for pattern: Variant in any_patterns:
		if _search(str(pattern), text, ignore_case) != null:
			return true
	return false


## One compiled-pattern cache per engine: the detectors run on every submit and
## PCRE2 compilation is not free. A pattern that will not compile is remembered
## as null so the warning is printed once, not per turn.
func _search(pattern: String, text: String, ignore_case: bool) -> RegExMatch:
	var source := pattern
	if ignore_case and not source.begins_with("(?i"):
		source = "(?i)" + source
	if not _regex_cache.has(source):
		var regex := RegEx.new()
		if regex.compile(source) == OK:
			_regex_cache[source] = regex
		else:
			push_warning("TriggerEngine: cannot compile keyword pattern '%s'" % pattern)
			_regex_cache[source] = null
	var cached: Variant = _regex_cache[source]
	if not cached is RegEx:
		return null
	return (cached as RegEx).search(text)


## docs/01 §5 "C clock / OS": every condition present must hold. `hour_from` /
## `hour_to` is a half-open window that may wrap midnight (23 → 3).
func _clock_matches(spec: Dictionary, ctx: Dictionary) -> bool:
	var day := int(ctx.get("day", 1))
	var hour := int(ctx.get("hour", 0))
	var flags: Dictionary = {}
	var raw_flags: Variant = ctx.get("flags")
	if raw_flags is Dictionary:
		flags = raw_flags
	var matches := _hour_in_window(
		hour, int(spec.get("hour_from", 0)), int(spec.get("hour_to", 24))
	)
	if spec.has("day_gte"):
		matches = matches and day >= int(spec["day_gte"])
	if spec.has("day_lte"):
		matches = matches and day <= int(spec["day_lte"])
	if spec.has("day_eq"):
		matches = matches and day == int(spec["day_eq"])
	if spec.has("turn_gte"):
		matches = matches and int(ctx.get("turn", 0)) >= int(spec["turn_gte"])
	if spec.has("absence_hours_gte"):
		var absent := float(ctx.get("absence_hours", 0.0))
		matches = matches and absent >= float(spec["absence_hours_gte"])
	if spec.has("flag_set"):
		matches = matches and bool(flags.get(str(spec["flag_set"]), false))
	if spec.has("flag_absent"):
		matches = matches and not bool(flags.get(str(spec["flag_absent"]), false))
	return matches


## A half-open [from, to) window; `from > to` means it spans midnight.
static func _hour_in_window(hour: int, from: int, to: int) -> bool:
	if from <= to:
		return hour >= from and hour < to
	return hour >= from or hour < to


func _needs_model(rec: Dictionary) -> bool:
	return (rec["detect"] as Dictionary).has("model")


func _any_source(sources: Variant) -> bool:
	if not sources is Dictionary:
		return false
	var matched: Dictionary = sources
	return (
		bool(matched.get("keyword", false))
		or bool(matched.get("event", false))
		or bool(matched.get("clock", false))
	)


func _sources_label(sources: Dictionary) -> String:
	if bool(sources.get("keyword", false)):
		return "keyword"
	if bool(sources.get("event", false)):
		return "event"
	if bool(sources.get("clock", false)):
		return "clock"
	return ""


func _catalogue() -> Dictionary:
	return table()["triggers"]


## ── Loading ───────────────────────────────────────────────────────────────


static func _load_file() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("TriggerEngine: %s missing; using the docs defaults" % TABLE_PATH)
		return parse_document({})
	return parse_document(JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH)))


## Parses a trigger document into the canonical table — data-driven on purpose:
## a test (or a mod) hands it a synthetic document and proves the loader decides
## the catalogue, not a hard-coded copy. Unusable input keeps the documented
## default it belongs to, so a broken file still plays.
static func parse_document(parsed: Variant, origin := TABLE_PATH) -> Dictionary:
	var out := _docs_table()
	if not parsed is Dictionary:
		push_warning("TriggerEngine: %s is not a JSON object; using the defaults" % origin)
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
			push_warning("TriggerEngine: trigger '%s' is unusable and was skipped" % id)
			continue
		out["triggers"][id] = record
	return out


static func _parse_row(raw: Variant, defaults: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var row: Dictionary = raw
	var detect := _parse_detect(row.get("detect"))
	if detect.is_empty():
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
		"requires": requires,
		"behavior": behavior,
		"escalate": escalate,
		"cooldown_turns": cooldown,
		"stage_min": stage_min,
		"stage_max": stage_max,
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
			var value: Variant = table_flags[name]
			if key.is_empty():
				continue
			if value is bool or value is int or value is float or value is String:
				out["flags"][key] = value
			else:
				push_warning("TriggerEngine: flag '%s' is not a scalar; ignored" % key)
	return out


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
