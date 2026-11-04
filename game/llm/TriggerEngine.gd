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
## writes and the prompt lines, and TriggerTable (P3.07) owns the data
## vocabulary — the loader, the parser and the healing rules. Everything here is
## pure except the table load — the caller injects the turn, day, stage, hour,
## absence and flags — so a transcript replays identically.
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
## thing being decided; every other declared detector must match too.
##
## Escalation has two axes (docs/01 §5): the default `step` grows the effect and
## the line with each firing and stops after max_steps, while `stage` grows them
## with the stage since stage_min (T08 "escalates with stage") and keeps
## repeating, cooldown-gated — the stage, not the repeat count, is the dose.
##
## A row may also split its effects: `effects` lands on every firing, while
## `first_effects` lands on the first one only (P2.22B). T01 uses the split
## because docs/01 §5 gives the mention spike +8 once and keeps the *question*
## repeating; without it a repeatable row's spike stacks into the whole curve.
##
## Guards: a `guard` block holds conditions that must ALSO hold but that are not
## detectors, so docs/01 §5's detection column stays honest (T03 "before Day 3").
## A row with no detector at all is a guard row — the game's own check is its
## evidence, so it fires at full strength (T13, T15; P2.10 DCR-1/DCR-2).

## Fired results kept for the F3 overlay and the transcript; state, not a log.
const MAX_HISTORY := 16
## The firing label -> strength-table key (docs/02 §1.2). A label missing here is
## full strength, which is what a guard firing gets on purpose.
const AGREEMENT_STRENGTH_KEYS := {
	"model": "model", "both": "agreement", "keyword": "keyword", "event": "engine", "clock": "clock"
}

## A row's `observe` writes, collected on its evidence: no count, no cooldown, no line.
var observed_flags: Dictionary = {}

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
	TriggerTable.clear_cache()


## The merged table the file declares (defaults overlaid with triggers.json).
## READ-ONLY: it is shared, and the detectors run on every submit.
static func default_table() -> Dictionary:
	return TriggerTable.default_table()


## The data vocabulary in one call (tests and mods author against it).
static func parse_document(parsed: Variant, origin := TriggerTable.TABLE_PATH) -> Dictionary:
	return TriggerTable.parse_document(parsed, origin)


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
	observed_flags.clear()


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
	observed_flags.clear()


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
		if _guard_only(rec):
			# No detector: the game's own check is the evidence (T13, T15).
			if _eligible(id, rec, ctx):
				fired.append(_fire(id, rec, ctx, "guard"))
			continue
		# Merge, never overwrite: an engine event may already have matched this
		# row for this same turn (handle_event runs before the submit).
		var sources: Dictionary = (_matched.get(id, {}) as Dictionary).duplicate()
		var detect: Dictionary = rec["detect"]
		if detect.has("keyword"):
			sources["keyword"] = _keyword_matches(detect["keyword"], text)
		if detect.has("clock"):
			sources["clock"] = _clock_matches(detect["clock"], ctx)
		_matched[id] = sources
		if _any_source(sources):
			_observe(rec, ctx)
		if (rec["detect"] as Dictionary).has("model") and String(rec["requires"]) == "all":
			continue  # agreement is decided at close_turn
		var satisfied := (
			_all_sources(rec, sources) if String(rec["requires"]) == "all" else _any_source(sources)
		)
		if not satisfied or not _eligible(id, rec, ctx):
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
		_observe(rec, ctx)  # the event is this row's evidence by definition
		if (rec["detect"] as Dictionary).has("model") and String(rec["requires"]) == "all":
			continue  # agreement is decided at close_turn
		if String(rec["requires"]) == "all" and not _all_sources(rec, sources):
			continue  # the event matched, a declared detector has not (yet)
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
	var rows := _catalogue()
	for id: String in rows:
		if _fired.has(id):
			continue
		var rec: Dictionary = rows[id]
		if _guard_only(rec):
			# Guard rows need the closed turn (T15's counter bump lands in
			# step 7), and they do not need a `read` label to decide.
			if _eligible(id, rec, ctx):
				fired.append(_fire(id, rec, ctx, "guard"))
			continue
		if read.is_empty():
			continue
		if not ((rec["detect"] as Dictionary).get("model", []) as Array).has(read):
			continue
		_observe(rec, ctx)  # the model named it; that is this row's evidence
		if String(rec["requires"]) == "all":
			if not _all_sources(rec, _matched.get(id, {})) or not _eligible(id, rec, ctx):
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


## docs/05 §1.1 M01: one row's stage gate from the data (−1 when unknown). The
## close intercept reads T10's gate here, so the row stays the only copy.
func stage_min_of(id: String) -> int:
	var rows := _catalogue()
	if not rows.has(id):
		return -1
	return int((rows[id] as Dictionary)["stage_min"])


## Drains the batch, so a second entry point cannot write a marker twice.
func take_observed_flags() -> Dictionary:
	var out := observed_flags
	observed_flags = {}
	return out


func _observe(rec: Dictionary, ctx: Dictionary) -> void:
	var flags: Dictionary = rec["observe"]
	var known: Variant = ctx.get("flags")
	for name: Variant in flags:
		observed_flags[str(name)] = flags[name]
		if known is Dictionary:
			(known as Dictionary)[str(name)] = flags[name]  # deliberate: T03 → T04


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
		"version": TriggerTable.VERSION,
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
	var version := TriggerTable.int_value(document.get("version"), TriggerTable.VERSION)
	if version != TriggerTable.VERSION:
		push_warning(
			(
				"TriggerEngine: trigger state v%d (expected v%d) — best effort"
				% [version, TriggerTable.VERSION]
			)
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
				"count": maxi(0, TriggerTable.int_value(state.get("count"), 0)),
				"last_turn": TriggerTable.int_value(state.get("last_turn"), 0),
			}
	var points: Variant = document.get("path_scores")
	if points is Dictionary:
		for name: Variant in points:
			_path_scores[str(name)] = TriggerTable.int_value(points[name], 0)
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
	var stage := clampi(int(ctx.get("stage", 0)), 0, TriggerTable.MAX_STAGE)
	if stage < int(rec["stage_min"]) or stage > int(rec["stage_max"]):
		return false
	var state: Dictionary = _state.get(id, {})
	var count := int(state.get("count", 0))
	var behavior := String(rec["behavior"])
	if behavior == "once" and count > 0:
		return false
	if behavior == "escalating":
		var escalate: Dictionary = rec["escalate"]
		# A step-axis row stops at max_steps. A stage-axis row repeats — the
		# stage, not the repeat count, is the escalation — and its cap is the
		# stage→step cap inside _escalation_step(); the cooldown is its gate.
		if String(escalate["axis"]) != "stage" and count >= int(escalate["max_steps"]):
			return false
	if count > 0:
		var cooldown := int(rec["cooldown_turns"])
		if int(ctx.get("turn", 0)) - int(state.get("last_turn", 0)) < cooldown:
			return false
	if not _guard_matches(rec, ctx):
		return false
	return true


func _fire(id: String, rec: Dictionary, ctx: Dictionary, agreement: String) -> Dictionary:
	var state: Dictionary = _state.get(id, {})
	var step := int(state.get("count", 0)) + 1
	var strength := _base_strength(agreement) * _escalation(rec, step, ctx)
	var effects := TriggerEffects.scale(rec["effects"], strength)
	# P2.22B: a row may split its effects — `first_effects` is the spike that
	# lands once (docs/01 §5 T01's mention), `effects` repeats. The spike is
	# scaled by the same strength, so a model-only firing would still halve.
	if step == 1:
		TriggerEffects.merge(effects, TriggerEffects.scale(rec.get("first_effects", {}), strength))
	var details := _guard_values(rec, ctx)
	var result := {
		"id": id,
		"name": String(rec["name"]),
		"step": step,
		"strength": strength,
		"agreement": agreement,
		"effects": effects,
		"player_name": str(details.get("name", "")),
		"line": _line_for(rec, step, ctx, details),
	}
	_state[id] = {"count": step, "last_turn": int(ctx.get("turn", 0))}
	_fired[id] = true
	TriggerEffects.add_path(_path_scores, effects)
	_history.append(result.duplicate(true))
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	return result


## docs/02 §1.2's agreement rule as data: the detector that decided the firing
## picks the weight. "both" is the agreement case; "model" is the model-only
## case and nothing else. A "guard" firing is the game's own deterministic
## check (T13, T15), so docs/02 §1.2's halving does not apply to it.
func _base_strength(agreement: String) -> float:
	if agreement == "guard":
		return 1.0
	var strength: Dictionary = table()["strength"]
	var key: String = str(AGREEMENT_STRENGTH_KEYS.get(agreement, ""))
	if key.is_empty() or not strength.has(key):
		return 1.0
	return float(strength[key])


## docs/01 §5 "escalating": the effect grows with each escalation step (the
## firing count or the stage, see _escalation_step) up to max_steps; every
## other behaviour keeps strength 1.
func _escalation(rec: Dictionary, step: int, ctx: Dictionary) -> float:
	if String(rec["behavior"]) != "escalating":
		return 1.0
	var spec: Dictionary = rec["escalate"]
	return 1.0 + float(spec["step_scale"]) * float(_escalation_step(rec, step, ctx) - 1)


## The escalation step. `axis: "step"` (the default) is the firing count capped
## by max_steps; `axis: "stage"` is the stage since stage_min, so a row grows
## with the dose rather than with how often the player poked it (docs/01 §5 T08
## "escalates with stage") and a line array advances with the stage too. A
## non-escalating row keeps the plain firing count, so its line array still
## walks one entry per firing.
func _escalation_step(rec: Dictionary, step: int, ctx: Dictionary) -> int:
	if String(rec["behavior"]) != "escalating":
		return step
	var spec: Dictionary = rec["escalate"]
	if String(spec["axis"]) == "stage":
		var stage := clampi(int(ctx.get("stage", 0)), 0, TriggerTable.MAX_STAGE)
		return clampi(stage - int(rec["stage_min"]) + 1, 1, int(spec["max_steps"]))
	return mini(step, int(spec["max_steps"]))


## docs/08 §6 line style. A row may carry one template or an array indexed by
## escalation step (the last line repeats past the array's end). `details`
## carries the guard's own values, so a T13 line can quote the fact she caught.
func _line_for(rec: Dictionary, step: int, ctx: Dictionary, details := {}) -> String:
	var raw: Variant = rec.get("line", "")
	if raw is Array:
		var lines: Array = raw
		if lines.is_empty():
			return ""
		raw = lines[mini(_escalation_step(rec, step, ctx), lines.size()) - 1]
	if not raw is String:
		return ""
	return _render(raw, step, ctx, details)


static func _render(template: String, step: int, ctx: Dictionary, details := {}) -> String:
	var line := template
	line = line.replace("{count}", str(step))
	line = line.replace("{ordinal}", _ordinal(step))
	line = line.replace("{stage}", str(int(ctx.get("stage", 0))))
	line = line.replace("{day}", str(int(ctx.get("day", 1))))
	line = line.replace("{turn}", str(int(ctx.get("turn", 0))))
	if details is Dictionary:
		line = line.replace("{fact}", str((details as Dictionary).get("fact", "")))
		line = line.replace("{name}", str((details as Dictionary).get("name", "")))
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
	if (
		spec.has("absence_hours_gte")
		or spec.has("absence_hours_lte")
		or spec.has("absence_hours_lt")
	):
		var absent := float(ctx.get("absence_hours", 0.0))
		if spec.has("absence_hours_gte"):
			matches = matches and absent >= float(spec["absence_hours_gte"])
		if spec.has("absence_hours_lte"):
			matches = matches and absent <= float(spec["absence_hours_lte"])
		if spec.has("absence_hours_lt"):
			matches = matches and absent < float(spec["absence_hours_lt"])
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


## A row with no detector at all. Its evidence is a guard the game evaluates
## itself, so it fires at full strength and needs no `read` label (T13, T15).
func _guard_only(rec: Dictionary) -> bool:
	return (rec["detect"] as Dictionary).is_empty()


## Every declared guard condition must hold; a row without a guard always
## passes. Guards never contribute to the detection letters in docs/01 §5.
func _guard_matches(rec: Dictionary, ctx: Dictionary) -> bool:
	var guard: Dictionary = rec["guard"]
	if guard.is_empty():
		return true
	if guard.has("clock") and not _clock_matches(guard["clock"], ctx):
		return false
	if not _counters_reached(guard, ctx):
		return false
	# The evidence guards: each answers "did the game see the thing this guard
	# is about?". They are OR-ed into one negative so the function stays inside
	# gdlint's return budget without nesting six ifs.
	var missing := (
		(
			guard.has("contradicts_memory")
			and _contradiction(ctx, guard["contradicts_memory"]).is_empty()
		)
		or (
			guard.has("mentions_memory")
			and _memory_mention(ctx, guard["mentions_memory"]).is_empty()
		)
		or (guard.has("name_mention") and _player_name(ctx, guard["name_mention"]).is_empty())
		or (guard.has("text_match") and not _text_hit(ctx, guard["text_match"]))
	)
	return not missing


## docs/01 §5 T15's `counter_gte`: the profile counters the game bumped this
## closed turn must reach the row's floors.
func _counters_reached(guard: Dictionary, ctx: Dictionary) -> bool:
	var floors: Dictionary = guard.get("counter_gte", {})
	if floors.is_empty():
		return true
	var raw_delta: Variant = ctx.get("profile_delta")
	var delta: Dictionary = raw_delta if raw_delta is Dictionary else {}
	for name: Variant in floors:
		if int(delta.get(str(name), 0)) < int(floors[name]):
			return false
	return true


## A `text_match` guard is a pattern set the message must satisfy — the same
## matcher a keyword detector uses. It is not a detector: the row's docs/01 §5
## letter stays the model's, and this only keeps a broad `read` label honest.
func _text_hit(ctx: Dictionary, spec: Dictionary) -> bool:
	return _keyword_matches(spec, str(ctx.get("text", "")))


## docs/01 §5 T13 "contradict a remembered fact": the message denies something
## the store still holds. `memory_facts` is injected as {text, source} entries —
## the *true* facts (stage-3 corruption is what she reads, not what she knows)
## and the player message each was grounded in — so the engine stays pure.
func _contradiction(ctx: Dictionary, spec: Dictionary) -> Dictionary:
	var facts: Variant = ctx.get("memory_facts")
	if not facts is Array:
		return {}
	return MemoryRules.contradiction(str(ctx.get("text", "")), facts, spec)


## docs/01 §5 T22 "a gift she already got": the message repeats a fact she
## still remembers. Shares the memory gate's content-word floor with T13 but
## has no denial side — saying "another music box" IS the evidence.
func _memory_mention(ctx: Dictionary, spec: Dictionary) -> Dictionary:
	var facts: Variant = ctx.get("memory_facts")
	if not facts is Array:
		return {}
	return MemoryRules.shared_fact(str(ctx.get("text", "")), facts, spec)


## docs/01 §5 T26 "mention your real name": the row's data regex captures it;
## the exclude list keeps "call me Leila" and "my name is your love" out. The
## guard's own pattern (not the keyword detector) decides, so the same
## compiled regex both proves the mention and produces the name `_fire`
## carries to the GameState write.
func _player_name(ctx: Dictionary, spec: Dictionary) -> String:
	var pattern := str(spec.get("pattern", ""))
	if pattern.is_empty():
		return ""
	var hit := _search(pattern, str(ctx.get("text", "")), bool(spec.get("ignore_case", true)))
	if hit == null:
		return ""
	var name := hit.get_string(1).strip_edges().trim_suffix(".").trim_suffix("!")
	if name.length() < 2:
		return ""
	var excludes: Array = spec.get("exclude", [])
	for word: Variant in excludes:
		if name.to_lower() == str(word).to_lower():
			return ""
	return name.left(1).to_upper() + name.substr(1)


## The values a guard contributes to the line template ({fact}, {name}).
func _guard_values(rec: Dictionary, ctx: Dictionary) -> Dictionary:
	var guard: Dictionary = rec["guard"]
	var out := {}
	if guard.has("name_mention"):
		out["name"] = _player_name(ctx, guard["name_mention"])
	if guard.has("mentions_memory"):
		var repeat := _memory_mention(ctx, guard["mentions_memory"])
		if not repeat.is_empty():
			out["fact"] = String(repeat.get("fact", ""))
	if guard.has("contradicts_memory"):
		var hit := _contradiction(ctx, guard["contradicts_memory"])
		if not hit.is_empty():
			# docs/01 §5 T13 "your earlier message exactly": the player's line.
			var quoted := String(hit.get("source", ""))
			out["fact"] = quoted if not quoted.is_empty() else String(hit.get("fact", ""))
	return out


## `requires: "all"`: every declared non-model detector must have matched this
## turn. The model detector is the one being decided now, in close_turn(), so it
## is not consulted here — a row that declares only the model is a model-only
## row and the agreement weight never applies to it.
func _all_sources(rec: Dictionary, sources: Variant) -> bool:
	var matched: Dictionary = sources if sources is Dictionary else {}
	for detector: String in rec["detect"] as Dictionary:
		if detector == "model":
			continue
		if not bool(matched.get(detector, false)):
			return false
	return true


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
	for label: String in ["keyword", "event", "clock"]:
		if bool(sources.get(label, false)):
			return label
	return ""


func _catalogue() -> Dictionary:
	return table()["triggers"]
