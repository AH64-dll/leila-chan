extends Node
## Triggers — the docs/01 §5 hidden-trigger engine and the single sink for the
## docs/05 §1.3 engine events (P2.08).
##
## The matching, caps and effect arithmetic live in `TriggerEngine`
## (game/llm/TriggerEngine.gd) and the catalogue in res://data/triggers.json;
## this node is the GameState/prompt seam:
##   begin_turn(text)   ← InputHook at docs/02 §4 step 0 (K and C detectors)
##   handle_engine_event(event) ← Telemetry, real time (E detectors)
##   close_turn(read)   ← Director.turn_completed (M detector + agreement)
## Each fired row's effects land on GameState (meters, profile counters, flags;
## path points are kept for P2.12) and its docs/08 §6 line is queued for the
## next prompt — except a step-0 line, which rides the turn that is starting.
##
## Agreement (docs/02 §1.2): a K+M row with `requires: "all"` only fires when
## both detectors agree, at full strength; a model-only detection fires at half
## strength. Every weight is data, so the rule is tunable without code.
##
## This node keeps no content: no trigger id, threshold or line is hard-coded
## here, so P2.10's T01–T15 rows are a data edit.

signal engine_event(event: Dictionary)  ## One normalized engine event (P2.09).
signal triggered(result: Dictionary)  ## One trigger fired (F3 overlay, tests).

const DATA_PATH := "res://data/triggers.json"
## The session's engine events, oldest first (bounded — trigger state, not a log).
const EVENT_LOG_MAX := 32
const RESULT_LOG_MAX := 8

var received_events: Array[Dictionary] = []

var _engine := TriggerEngine.new()
var _last_results: Array[Dictionary] = []
var _clock: Callable = Callable()
var _last_seen_unix := 0
## This turn's profile counters at submit, so a guard can read what changed.
var _profile_baseline: Dictionary = {}
var _profile_baseline_open := false


func _ready() -> void:
	load_catalog()
	# The M detector needs the finished Turn, and turn_completed is where the
	# `read` label and the stage are final. Using the signal keeps Director.gd
	# at its gdlint line cap and keeps this a listener, not a pipeline step.
	if Director != null and not Director.turn_completed.is_connected(_on_turn_completed):
		Director.turn_completed.connect(_on_turn_completed)


## ── Catalogue ─────────────────────────────────────────────────────────────


## Reads res://data/triggers.json (docs/07 §2: content is data). Returns false
## when no trigger row survived; the engine still holds the docs defaults.
func load_catalog() -> bool:
	TriggerEngine.clear_cache()
	var table := TriggerEngine.default_table()
	_engine.use_table(table)
	return not (table["triggers"] as Dictionary).is_empty()


## Installs a catalogue from a parsed JSON document — what the file loader uses,
## and how a test or a mod proves a new trigger needs no code. Returns false
## when no row survived the parse (the engine still holds the docs defaults).
func set_catalog(document: Variant) -> bool:
	var table := TriggerEngine.parse_document(document, "triggers catalogue")
	_engine.use_table(table)
	return not (table["triggers"] as Dictionary).is_empty()


## Trigger ids in catalogue order (tests, mods and P2.10's authoring read the
## live catalogue this way; the F3 overlay shows its size).
func trigger_ids() -> Array[String]:
	var ids: Array[String] = []
	var rows: Dictionary = _engine.table()["triggers"]
	for id: Variant in rows:
		ids.append(str(id))
	return ids


## ── Per-turn entry points ─────────────────────────────────────────────────


## docs/02 §4 step 0: the K (keyword) and C (clock) detectors for the line the
## player just sent. Returns the docs/08 §6 lines that belong to THIS turn.
func begin_turn(input_text: String) -> Array[String]:
	# Snapshot the profile counters: a guard row can then ask what the game
	# bumped *this* turn (docs/01 §5 T15's `ignored_questions`).
	_profile_baseline = GameState.profile.duplicate(true)
	_profile_baseline_open = true
	var ctx := _context(true)
	ctx["text"] = input_text
	var lines: Array[String] = []
	for result: Dictionary in _engine.begin_turn(ctx):
		var line := _apply(result, false)
		if not line.is_empty():
			lines.append(line)
	_write_observed()
	return lines


## docs/01 §5 "M model labels it via the Turn's read field": called once per
## completed turn. Its lines are queued for the next prompt (she reacts to the
## intent the model read, not to words the game already saw).
func close_turn(read_label: String) -> Array[String]:
	var ctx := _context(false)
	ctx["read"] = read_label
	var lines: Array[String] = []
	var fired := _engine.close_turn(ctx)
	# One close per turn: the delta belongs to the turn that just ended.
	_profile_baseline = {}
	_profile_baseline_open = false
	for result: Dictionary in fired:
		var line := _apply(result, true)
		if not line.is_empty():
			lines.append(line)
	_write_observed()
	return lines


## The P2.09 contract: one normalized event, exactly as Telemetry emits it:
## {trigger, event, stage_min, line, data, seq, ts}. Detection is ungated;
## `stage_min` is the docs/05 gate the engine applies to its effect.
func handle_engine_event(event: Dictionary) -> void:
	var copy := event.duplicate(true)
	received_events.append(copy)
	while received_events.size() > EVENT_LOG_MAX:
		received_events.pop_front()
	engine_event.emit(copy)
	var ctx := _context(true)
	ctx["event"] = copy
	for result: Dictionary in _engine.handle_event(ctx):
		_apply(result, true)
	_write_observed()


## Last event of a kind, or {} (debug overlay / tests).
func last_event(kind: String) -> Dictionary:
	for i: int in range(received_events.size() - 1, -1, -1):
		var event: Dictionary = received_events[i]
		if str(event.get("event", "")) == kind:
			return event.duplicate(true)
	return {}


## Session boundary (`Director.reset()` / tests): per-session trigger state.
func clear_engine_events() -> void:
	received_events.clear()
	_last_results.clear()
	_profile_baseline = {}
	_profile_baseline_open = false
	_engine.reset()


## ── Observability / persistence ───────────────────────────────────────────


## The F3 overlay, the transcript and the tests read everything here in one call.
func report() -> Dictionary:
	var view := _engine.report()
	view["events"] = received_events.size()
	view["fired"] = _last_results.duplicate(true)
	return view


## docs/01 §4/§5 path points added by triggers so far — P2.12 folds these into
## the path scores ("YANDERE +3", "AWAKE +4" in the trigger table).
func path_scores() -> Dictionary:
	return _engine.path_scores()


## docs/05 §1.1 M01: the docs/05 stage gate a trigger row declares (−1 when the
## id is unknown). The close intercept reads T10's gate here instead of keeping
## a second copy of the number; the row is authoritative.
func stage_min_of(id: String) -> int:
	return _engine.stage_min_of(id)


## P2.20's save seam: cooldowns and "once" firings must survive a reload.
func to_dict() -> Dictionary:
	return _engine.to_dict()


func from_dict(data: Variant) -> bool:
	return _engine.from_dict(data)


## Deterministic tests / replay: Callable() -> float unix seconds. Callable()
## restores the system clock (same seam Telemetry and TranscriptLogger use).
func set_clock(clock: Callable) -> void:
	_clock = clock


## P2.20/P3.07 seam for docs/01 §5 T17/T18 ("return after 24 h+"): the last
## session's unix time. 0 keeps the absence at 0, so nothing fires by accident.
func set_last_seen(unix_seconds: int) -> void:
	_last_seen_unix = unix_seconds


## ── Internals ─────────────────────────────────────────────────────────────


func _on_turn_completed(_turn_index: int, turn_data: Dictionary) -> void:
	close_turn(str(turn_data.get("read", "")))


## Applies one fired row: meters, profile counters, flags, then the line. Path
## points were folded into the engine's ledger by the firing itself. Returns the
## line so the caller can decide whether it rides this turn or the next.
func _apply(result: Dictionary, queue_line: bool) -> String:
	var effects: Dictionary = {}
	var raw_effects: Variant = result.get("effects")
	if raw_effects is Dictionary:
		effects = raw_effects
	var meters: Dictionary = effects.get("meters", {})
	for meter: Variant in meters:
		GameState.adjust_meter(StringName(str(meter)), float(meters[meter]))
	var profile: Dictionary = effects.get("profile", {})
	for counter: Variant in profile:
		GameState.bump_profile(StringName(str(counter)), int(profile[counter]))
	var flags: Dictionary = effects.get("flags", {})
	for flag: Variant in flags:
		GameState.set_flag(StringName(str(flag)), flags[flag])
	var line := String(result.get("line", ""))
	if queue_line and not line.is_empty():
		GameState.queue_event(line)
	var view := result.duplicate(true)
	_last_results.append(view)
	while _last_results.size() > RESULT_LOG_MAX:
		_last_results.pop_front()
	triggered.emit(view)
	return line


## The engine's input snapshot. Injected on purpose: the turn id, day, stage,
## hour, absence and flags all come from one place, so tests and a replay see
## exactly what the running game sees.
func _context(upcoming: bool) -> Dictionary:
	var now := _now()
	return {
		"turn": int(GameState.turn) + (1 if upcoming else 0),
		"day": int(GameState.day),
		"stage": int(GameState.stage),
		"hour": _local_hour(now),
		"absence_hours": _absence_hours(now),
		# A copy: a fire during this turn must not change what a later row's
		# clock detector sees inside the same evaluation.
		"flags": GameState.flags.duplicate(true),
		# docs/01 §5 T13: the *true* facts (corruption is what she reads, not
		# what she knows), so a lie is measured against her real memory.
		"memory_facts": _memory_facts(),
		# docs/01 §5 T15: what the game bumped during the closed turn. Empty at
		# submit/handle_event — nothing has been applied yet.
		"profile_delta": _profile_delta(upcoming),
		"text": "",
		"read": "",
	}


## The memory store's true facts, each with the player message it was grounded
## in (docs/01 §5 T13 quotes the player, not her paraphrase), for the guard.
func _memory_facts() -> Array:
	if Memory == null:
		return []
	return Memory.facts_with_sources()


## docs/01 §5 T04: flags a row's `observe` block wrote on its own evidence (T03's
## confession on any day). Drained, so a second entry point in the same turn
## cannot write the same marker twice.
func _write_observed() -> void:
	var flags := _engine.take_observed_flags()
	for flag: Variant in flags:
		GameState.set_flag(StringName(str(flag)), flags[flag])


## Counters the game bumped since this turn's begin_turn(). Only the closed turn
## has one; at submit time there is nothing to report yet.
func _profile_delta(upcoming: bool) -> Dictionary:
	if upcoming or not _profile_baseline_open:
		return {}
	var out := {}
	var current: Dictionary = GameState.profile
	for key: Variant in current:
		var before := int(_profile_baseline.get(str(key), 0))
		var after := int(current[key])
		if after > before:
			out[str(key)] = after - before
	return out


func _now() -> float:
	if _clock.is_valid():
		return float(_clock.call())
	return Time.get_unix_time_from_system()


## docs/01 §5 T16 is "between 2:00–4:00 AM (system clock)", i.e. the player's
## local hour — derived from the injected clock so tests are deterministic.
func _local_hour(now: float) -> int:
	if not is_finite(now):
		return 0
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var parts := Time.get_datetime_dict_from_unix_time(int(now) + bias * 60)
	return int(parts.get("hour", 0))


func _absence_hours(now: float) -> float:
	if _last_seen_unix <= 0 or not is_finite(now):
		return 0.0
	return maxf(0.0, (now - float(_last_seen_unix)) / 3600.0)
