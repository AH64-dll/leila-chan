extends Node
## GameState — the game's truth: meters, stage, day, flags, behaviour-profile
## counters and a serialisable snapshot (docs/07 §2, docs/01 §2).
##
## The model never writes here. The Director applies each Turn through
## apply_turn_meters()/apply_turn_profile() (docs/02 §4 step 7); the arithmetic
## itself (slow burn, daily burn, ratchet floor, mood scaling) lives in Meters so
## the formula has one definition, the path scores in Paths and the keyword
## profile rules in ProfileKeywords. Read the public vars freely; mutate them
## only through the methods so clamping, the ratchet and the signals always hold.
##
## Stage is monotonic: good days can lower Instability (ratchet floor =
## peak − 15, docs/01 §2) but never de-escalate her — stage transitions are
## one-way diegetic events and the path locks at stage 3 (docs/01 §3–§4).

signal meter_changed(meter: StringName, value: float)
signal stage_changed(previous: int, current: int)
## docs/01 §3: the diegetic transition — emitted exactly once per crossing with
## the data-owned spec (2–3 s duration, fx, cue, stage name). The screen glitch
## that hides the docs/06 §4 dose change (P2.03) and the P2.15 shader listen
## here. A restore is NOT a crossing: from_dict() re-emits stage_changed so
## listeners resync, but no transition fires and no EVENT line is queued.
signal stage_transition(previous: int, current: int, spec: Dictionary)
signal day_changed(day: int)
signal path_assigned(path: StringName, locked: bool)
signal profile_changed(counter: StringName, value: int)
signal flag_changed(flag: StringName, value)
## Emitted once at the end of reset() and from_dict(): the whole state was just
## replaced wholesale, so listeners must resync every field (day, path, profile,
## flags) instead of relying on per-field signals alone.
signal state_reset

const SNAPSHOT_VERSION := 1
const PROFILE_MAP_PATH := "res://data/profile_map.json"

## Meter ranges (docs/01 §2). Floats inside: the slow burn and the mood scaling
## (docs/02 §1.1) produce fractional moves.
const METER_RANGES := {
	&"affection": Vector2(0.0, 100.0),
	&"trust": Vector2(-50.0, 50.0),
	&"instability": Vector2(0.0, 100.0),
	&"fixation": Vector2(0.0, 100.0),
	&"lucidity": Vector2(0.0, 100.0),
}
const METER_NAMES: Array[StringName] = [
	&"affection", &"trust", &"instability", &"fixation", &"lucidity"
]

## Stage instability bands (docs/01 §3: 0–14 / 15–29 / 30–49 / 50–69 / 70–89 /
## 90–100) and the 0–5 stage count are DATA: Stages owns them
## (game/llm/Stages.gd, res://data/stages.json). This class stores the live
## stage, keeps it monotonic and emits the crossing signals.

## Campaign length in in-game days (docs/01 §1).
const DAY_MAX := 14

## Meter arithmetic — mood scaling (docs/02 §1.1), the per-turn caps on
## model-suggested moves (docs/01 §2 "Moves by"), the slow burn and the daily
## burn (docs/01 §2) — lives in Meters (game/llm/Meters.gd) and its data file
## res://data/meters.json. This class applies the results; it does not define
## the formula.

## Behaviour-profile counters (docs/01 §2) — the full set, in doc order.
const PROFILE_COUNTERS: Array[StringName] = [
	&"warmth",
	&"coldness",
	&"inconsistency",
	&"teasing",
	&"jealousy_bait",
	&"leaving_talk",
	&"meta_curiosity",
	&"honesty",
	&"boundaries",
	&"apathy",
	&"control",
	&"flattery",
]

## Fracture paths (docs/01 §4): soft-assigned at stage 2, locked at stage 3.
## Ids are the canonical data/casting.json keys — uppercase; TSUN is the
## casting/UI id for docs/01's "TSUN-BREAK".
const PATHS: Array[StringName] = [&"YANDERE", &"SPLIT", &"TSUN", &"HOLLOW", &"AWAKE", &"ANCHOR"]

## Variant types allowed in `flags`: the snapshot must stay JSON-safe (docs/07 §3.5).
const JSON_SAFE_TYPES: Array[int] = [
	TYPE_NIL,
	TYPE_BOOL,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_STRING,
	TYPE_STRING_NAME,
	TYPE_ARRAY,
	TYPE_DICTIONARY,
]
const FLAG_MAX_DEPTH := 16

## A snapshot Dictionary must contain at least one of these data keys —
## anything else (including version-only metadata) is rejected instead of
## silently loading defaults.
const SNAPSHOT_KEYS: Array[String] = [
	"affection",
	"trust",
	"instability",
	"instability_peak",
	"fixation",
	"lucidity",
	"stage",
	"day",
	"turn",
	"path",
	"path_locked",
	"player_name",
	"profile",
	"flags",
	"last_tone",
]

# Ratchet backing must be declared before `instability`: its setter reads them.
# Non-finite writes are dropped — they have no meaningful bound and would break
# the ratchet and the JSON snapshot (CODE-9 hardening).
var instability_peak := 0.0:
	set(v):
		if not is_finite(v):
			push_warning("GameState.instability_peak: non-finite write ignored")
			return
		instability_peak = _clamp_meter(&"instability", v)
		# Raising the peak raises the floor under the live meter, so the
		# docs/01 §2 invariant (instability ≥ floor) is enforced by the peak
		# write itself, not by whichever write happens next. Lowering the peak
		# never lowers the meter — she is not cured by editing the high-water
		# mark. from_dict() suppresses the stage signal during a restore so the
		# load still emits exactly one transition.
		if not _peak_guard and instability < instability_floor:
			instability = instability_floor
## Read-only: the lowest Instability may ever sit at (docs/01 §2 ratchet).
var instability_floor: float:
	get:
		return Meters.ratchet_floor(instability_peak)
## Derived from Instability bands (docs/01 §3); only ever moves upward. Written
## by _refresh_stage(), from_dict() and reset() only — assigning it directly is
## a restore or a debug jump and deliberately fires no crossing event.
var stage := 0:
	set(v):
		stage = clampi(v, 0, Stages.max_stage())

var affection := 0.0:
	set(v):
		var clamped := _clamp_meter(&"affection", v)
		if clamped != affection:
			affection = clamped
			meter_changed.emit(&"affection", affection)

var trust := 0.0:
	set(v):
		var clamped := _clamp_meter(&"trust", v)
		if clamped != trust:
			trust = clamped
			meter_changed.emit(&"trust", trust)

var instability := 0.0:
	set(v):
		var capped := _clamp_meter(&"instability", v)
		# The peak write is game-side, not a caller raising the ceiling: guard it
		# so the peak setter does not try to lift this meter while this setter
		# owns the write (that would re-enter here and recurse).
		_peak_guard = true
		instability_peak = maxf(instability_peak, capped)
		_peak_guard = false
		var clamped := maxf(capped, instability_floor)
		if clamped != instability:
			instability = clamped
			meter_changed.emit(&"instability", instability)
			_refresh_stage(instability)

var fixation := 0.0:
	set(v):
		var clamped := _clamp_meter(&"fixation", v)
		if clamped != fixation:
			fixation = clamped
			meter_changed.emit(&"fixation", fixation)

var lucidity := 0.0:
	set(v):
		var clamped := _clamp_meter(&"lucidity", v)
		if clamped != lucidity:
			lucidity = clamped
			meter_changed.emit(&"lucidity", lucidity)

var day := 1:
	set(v):
		day = clampi(v, 1, DAY_MAX)
## Turns applied this run (advance_turn), monotonic.
var turn := 0:
	set(v):
		turn = maxi(0, v)

var path: StringName = &""
var path_locked := false
## docs/01 §4: the last scoring pass, the per-path evidence turn behind the
## "ties → more recent evidence" rule, and the hybrid runner-up the prompt's
## path layer borrows one line from. The scores stay live after the lock — the
## path is frozen, the numbers are not.
var path_scores := {}
var path_evidence := {}
var path_runner_up: StringName = &""
## docs/01 §5 T15: her last direct question — "" when she asked none. The
## dismissive-reply keyword rule reads it; the trigger engine owns escalation.
var last_question := ""
## The player's name (docs/08 §1.5); "Senpai" when they typed nothing.
var player_name := "Senpai"
## JSON-safe flag store for triggers/scenario state: bools, counts, small data.
var flags := {}
## docs/08 §6 lines waiting for the next prompt — a stage crossing queues hers
## here (_refresh_stage); P2.08's triggers queue theirs the same way. The
## Director drains them exactly once when it assembles the next turn, so a line
## is never repeated and never lost between turns. Not part of the snapshot: a
## loaded game starts with an empty queue (from_dict clears it).
var pending_events: Array[String] = []
## Behaviour-profile counters (docs/01 §2) plus the three §4 formula counters;
## bumped by apply_turn_profile() (read + keyword rules) and by the trigger
## engine via bump_profile().
var profile := _blank_profile()
var last_stress := 0
var stress: int:
	get:
		return last_stress

var _last_tone: StringName = &""
## Ratchet re-entrancy guards (docs/01 §2): the instability setter raises the
## peak, and a caller-raised peak lifts the meter back over its floor. Without
## the guards those two writes re-enter each other; `_restoring` makes a
## from_dict() restore land atomically and emit one stage transition.
var _peak_guard := false
var _restoring := false
## Per-turn model-suggestion budget (docs/01 §2): meter → applied delta total,
## reset whenever `turn` changes.
var _mood_turn := -1
var _mood_spent := {}
var _profile_map_cache := {}


## Fresh New-Game state (docs/05 M08 leaves the shadow save to SaveSystem).
func reset() -> void:
	_peak_guard = false
	_restoring = false
	instability_peak = 0.0
	affection = 0.0
	trust = 0.0
	instability = 0.0
	fixation = 0.0
	lucidity = 0.0
	stage = 0
	day = 1
	turn = 0
	path = &""
	path_locked = false
	path_scores = {}
	path_evidence = {}
	path_runner_up = &""
	last_question = ""
	player_name = "Senpai"
	flags = {}
	pending_events.clear()
	profile = _blank_profile()
	_last_tone = &""
	_mood_turn = -1
	_mood_spent.clear()
	state_reset.emit()
	last_stress = 0


func get_meter(meter: StringName) -> float:
	match meter:
		&"affection":
			return affection
		&"trust":
			return trust
		&"instability":
			return instability
		&"fixation":
			return fixation
		&"lucidity":
			return lucidity
		_:
			push_warning("GameState.get_meter: unknown meter '%s'" % meter)
			return 0.0


## Writes go through the property setters: clamp + signals always apply.
func set_meter(meter: StringName, value: float) -> void:
	match meter:
		&"affection":
			affection = value
		&"trust":
			trust = value
		&"instability":
			instability = value
		&"fixation":
			fixation = value
		&"lucidity":
			lucidity = value
		_:
			push_warning("GameState.set_meter: unknown meter '%s'" % meter)


## Applies a clamped delta; returns the delta that actually landed (game-side
## moves: slow burn, trigger spikes, lie detection — docs/01 §2 "Moves by").
func adjust_meter(meter: StringName, delta: float) -> float:
	var before := get_meter(meter)
	set_meter(meter, before + delta)
	return get_meter(meter) - before


## docs/02 §1.1 + §4 step 7: model mood ints −3..3, scaled per meter by Meters
## (affection ×1.5, trust ×2, stress → instability ×0.6) under the docs/01 §2
## per-turn caps. Returns the deltas that actually landed, keyed by meter.
func apply_mood(mood: Dictionary) -> Dictionary:
	if _mood_turn != turn:
		_mood_turn = turn
		_mood_spent.clear()
	var landed := {}
	if mood.has("affection"):
		landed[&"affection"] = _apply_mood_meter(&"affection", &"affection", mood["affection"])
	if mood.has("trust"):
		landed[&"trust"] = _apply_mood_meter(&"trust", &"trust", mood["trust"])
	if mood.has("stress"):
		var limit := int(Meters.mood_limit())
		last_stress = clampi(int(_num(mood["stress"])), -limit, limit)
		landed[&"instability"] = _apply_mood_meter(&"instability", &"stress", mood["stress"])
	return landed


## One model suggestion after docs/02 §1.1 scaling, capped against what the
## model already moved this turn: the docs/01 §2 "Moves by" column is a
## per-turn budget (affection ±5, instability ±3, trust uncapped), so the
## running total of landed movement is clamped — two apply_mood() calls in one
## turn share it, and unlanded suggestions at a meter boundary never free budget
## in the opposite direction. Returns the landed delta.
func _apply_mood_meter(meter: StringName, field: StringName, raw_value: Variant) -> float:
	# Meters.mood_delta() drops non-finite suggestions and clamps to −3..3
	# before scaling, so the delta is always finite.
	var delta := Meters.mood_delta(field, raw_value)
	var cap := Meters.turn_cap(meter)
	var spent := float(_mood_spent.get(meter, 0.0))
	var total := clampf(spent + delta, -cap, cap)
	var attempt := total - spent
	var before := get_meter(meter)
	var landed := adjust_meter(meter, attempt)
	# Charge only the movement the model's own delta produces inside the meter
	# range. A game-side correction is not the model's move: the instability
	# ratchet floor can lift the meter past the requested target after a peak
	# write, and charging that to the model would drain the docs/01 §2 per-turn
	# allowance and let a later opposite-sign suggestion drag the meter back.
	# Clamping the target keeps |charged| ≤ |attempt|, so the running total
	# stays inside [−cap, cap] whatever the rest of the game does to the meter.
	var bounds: Vector2 = METER_RANGES[meter]
	_mood_spent[meter] = spent + clampf(before + attempt, bounds.x, bounds.y) - before
	return landed


## docs/02 §4 step 7 + docs/01 §2: the atomic per-turn meter update the
## Director runs at turn close. The turn index advances FIRST because the
## mood budget is keyed on `turn` (P1.04/P1.29 handoff order, review CODE-12),
## then the slow burn lands, then the model's mood. Returns the ledger for one
## turn — the meters simulation and the F3 overlay read it.
func apply_turn_meters(turn_data: Dictionary) -> Dictionary:
	advance_turn()
	var burn := adjust_meter(&"instability", Meters.slow_burn(fixation, lucidity))
	var landed := {}
	var mood: Variant = turn_data.get("mood")
	if mood is Dictionary:
		landed = apply_mood(mood)
	return {
		"turn": turn,
		"slow_burn": burn,
		"mood": landed,
		"instability": instability,
		"instability_floor": instability_floor,
		"stage": stage,
	}


func advance_turn() -> void:
	turn += 1


## Night roll-over: day +1 and the daily burn (+3 instability, docs/01 §2).
## A no-op past day 14: the campaign is over (docs/01 §1), no burn, no signal.
## Returns the burn that actually landed (0 at the cap), for the night screen.
func advance_day() -> float:
	if day >= DAY_MAX:
		return 0.0
	day += 1
	var burned := adjust_meter(&"instability", Meters.daily_burn())
	day_changed.emit(day)
	return burned


func bump_profile(counter: StringName, amount: int = 1) -> void:
	# The twelve docs/01 §2 tags plus the three §4 formula counters
	# (broken_promises, flattery_rejected, ignored_questions) share one store.
	if not PROFILE_COUNTERS.has(counter) and not Paths.is_counter(counter):
		push_warning("GameState.bump_profile: unknown counter '%s'" % counter)
		return
	var key := String(counter)
	profile[key] = maxi(0, int(profile.get(key, 0)) + amount)
	profile_changed.emit(counter, profile[key])
	if amount > 0:
		_note_path_evidence(counter)


## docs/02 §4 step 7 + docs/01 §2/§4: one call owns this turn's behaviour
## profile — the model's `read` label, the keyword rules on the player's line
## and her reply, her question for the next turn's T15 check — and then the
## docs/01 §4 path check. Returns the path decision (the F3 overlay and tests
## read it); a locked path still reports live scores.
##
## A call with no player line and no turn data is the docs/01 §1 NIGHT's path
## check, not a turn: there is no message and no reply, so her pending question
## stays pending instead of being cleared by an empty turn. Everything else
## (re-score against the current meters, runner-up, Stage-2/3 rule) is identical.
func apply_turn_profile(read_label: StringName, player_text := "", turn_data := {}) -> Dictionary:
	_apply_read(read_label)
	var data: Dictionary = turn_data if turn_data is Dictionary else {}
	var bumps := ProfileKeywords.classify(
		player_text, ProfileKeywords.reply_text(data), last_question
	)
	for counter: StringName in bumps:
		bump_profile(counter, int(bumps[counter]))
	if not (player_text.strip_edges().is_empty() and data.is_empty()):
		last_question = ProfileKeywords.question_in(data)
	return _evaluate_path()


## docs/02 §4 step 7: the Turn's `read` intent feeds the profile counters.
## The label→counter table and the warm/cold tone map behind `inconsistency`
## (warm↔cold swings, docs/01 §2) live in res://data/profile_map.json.
func _apply_read(read_label: StringName) -> void:
	if read_label == &"":
		return
	var table: Dictionary = _profile_map().get("read_to_profile", {})
	var key := String(read_label)
	if not table.has(key):
		push_warning("GameState.apply_turn_profile: unknown read label '%s'" % key)
		return
	var bumps: Variant = table.get(key, {})
	if bumps is Dictionary:
		for counter: Variant in bumps:
			bump_profile(StringName(_str(counter)), int(bumps[counter]))
	var tone := _tone_of_read(key)
	if tone == &"":
		return
	if _last_tone != &"" and _last_tone != tone:
		bump_profile(&"inconsistency")
	_last_tone = tone


## Every `read` label the map knows — the docs/02 §1.2 intent enum, for the
## schema builder (P1.07) so the table stays the single source.
func known_intents() -> Array[StringName]:
	var labels: Array[StringName] = []
	for key: Variant in _profile_map().get("read_to_profile", {}):
		labels.append(StringName(_str(key)))
	return labels


## Flags are serialised with the snapshot — only JSON-safe values are kept,
## recursively: a Vector2 nested in an Array/Dictionary is still rejected.
func set_flag(flag: StringName, value: Variant = true) -> void:
	if not _is_json_safe(value):
		push_warning("GameState.set_flag: '%s' rejected — value is not JSON-safe" % flag)
		return
	var stored: Variant = _normalise_flag(value)
	flags[String(flag)] = stored
	flag_changed.emit(flag, stored)


func get_flag(flag: StringName, fallback: Variant = false) -> Variant:
	return flags.get(String(flag), fallback)


func clear_flag(flag: StringName) -> void:
	if flags.erase(String(flag)):
		flag_changed.emit(flag, null)


## docs/08 §6: queues one event line for the next prompt. Blank lines and
## duplicates are dropped — one fact must not ride two turns because two
## systems noticed it.
func queue_event(line: String) -> void:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return
	if not pending_events.has(trimmed):
		pending_events.append(trimmed)


## Hands the queued event lines to the turn that is starting and empties the
## queue: each line is told to the model exactly once.
func take_pending_events() -> Array[String]:
	var drained := pending_events.duplicate()
	pending_events.clear()
	return drained


## docs/01 §4: soft path assignment (stage 2). Once locked (stage 3) the path
## cannot change — highest score wins is the caller's job (P2.12).
func assign_path(new_path: StringName, locked := false) -> bool:
	if path_locked:
		push_warning("GameState.assign_path: locked on '%s'" % path)
		return false
	if not PATHS.has(new_path):
		push_warning("GameState.assign_path: unknown path '%s'" % new_path)
		return false
	if new_path != path or locked != path_locked:
		path = new_path
		path_locked = locked
		path_assigned.emit(path, path_locked)
	return true


## docs/01 §4: the path locks at stage 3.
func lock_path() -> void:
	if path == &"":
		push_warning("GameState.lock_path: no path assigned")
		return
	if not path_locked:
		path_locked = true
		path_assigned.emit(path, true)


## docs/01 §4: score the six paths, keep the hybrid runner-up current, and
## apply the stage rule — Stage 2 soft-assigns the winner, Stage 3 locks it.
## Called at every turn close (apply_turn_profile) and on a stage crossing, so
## the lock happens the moment Stage 3 is entered even between turns (the night
## roll-over, a trigger spike). A locked path is never reassigned; the scores
## stay live so the overlay and the next run's evidence keep telling the truth.
func _evaluate_path() -> Dictionary:
	var meters := {}
	for meter: StringName in METER_NAMES:
		meters[String(meter)] = get_meter(meter)
	var decision := Paths.select(Paths.scores(profile, meters), path_evidence)
	path_scores = decision["scores"]
	if not path_locked and stage >= Paths.assign_stage():
		assign_path(decision["path"], stage >= Paths.lock_stage())
	# After the assignment, so the exclusion below compares against the LIVE
	# primary rather than the one this turn is about to replace.
	path_runner_up = _runner_up_for(decision)
	return decision


## The hybrid runner-up must be the best path that is not the LIVE primary. Once
## the path is locked the score winner can be a different path; then the winner
## itself is the best non-primary candidate, and `select()`'s runner-up would be
## the locked path (a path cannot be its own runner-up).
func _runner_up_for(decision: Dictionary) -> StringName:
	var best: StringName = decision["path"]
	var runner: StringName = decision["runner_up"]
	if path != &"" and best != path:
		runner = best if float(path_scores.get(String(best), 0.0)) > 0.0 else &""
	return runner if runner != path else &""


## docs/01 §4 tie-break: "ties → the path with more recent evidence". A counter
## with a positive weight for a path is evidence for it; ANCHOR's negative terms
## (inconsistency, jealousy_bait) are not evidence *for* ANCHOR.
func _note_path_evidence(counter: StringName) -> void:
	for path_id: StringName in Paths.paths_fed_by(counter):
		var key := String(path_id)
		if int(path_evidence.get(key, -1)) < turn:
			path_evidence[key] = turn


## JSON-safe snapshot for SaveSystem (docs/07 §3.5).
func to_dict() -> Dictionary:
	return {
		"version": SNAPSHOT_VERSION,
		"affection": affection,
		"trust": trust,
		"instability": instability,
		"instability_peak": instability_peak,
		"fixation": fixation,
		"lucidity": lucidity,
		"stage": stage,
		"day": day,
		"turn": turn,
		"path": String(path),
		"path_locked": path_locked,
		"path_scores": path_scores.duplicate(),
		"path_evidence": path_evidence.duplicate(),
		"path_runner_up": String(path_runner_up),
		"last_question": last_question,
		"player_name": player_name,
		"profile": profile.duplicate(),
		"flags": flags.duplicate(true),
		"last_tone": String(_last_tone),
	}


## Restores a snapshot onto a canonical baseline: the result depends only on
## `data`, never on the instance it is loaded into. Out-of-range or malformed
## values are healed (clamped ranges, bounded peak, stage re-derived from the
## peak's band, zeroed profile, JSON-safe flags); unrecognised input is
## rejected. Ends with state_reset so listeners resync every field.
func from_dict(data: Variant) -> bool:
	if not data is Dictionary or data.is_empty():
		push_warning("GameState.from_dict: expected a non-empty Dictionary")
		return false
	var recognised := false
	for key: String in SNAPSHOT_KEYS:
		if data.has(key):
			recognised = true
			break
	if not recognised:
		push_warning("GameState.from_dict: no snapshot keys present — rejected")
		return false
	var version := int(_num(data.get("version"), SNAPSHOT_VERSION))
	if version != SNAPSHOT_VERSION:
		push_warning(
			(
				"GameState.from_dict: snapshot v%d (expected v%d) — best effort"
				% [version, SNAPSHOT_VERSION]
			)
		)
	# Peak and stage first: the instability setter derives the floor from the
	# peak, and setting the final stage before the meters prevents intermediate
	# stage_changed transitions when peak > instability.
	var previous_stage := stage
	_restoring = true
	instability_peak = _num(data.get("instability_peak"), 0.0)
	instability_peak = maxf(
		instability_peak, _clamp_meter(&"instability", _num(data.get("instability"), 0.0))
	)
	var healed_stage := Stages.for_instability(instability_peak)
	if data.has("stage") and int(_num(data["stage"], -1.0)) != healed_stage:
		push_warning(
			(
				"GameState.from_dict: stored stage %s outside the peak band — healed to %d"
				% [str(data["stage"]), healed_stage]
			)
		)
	stage = healed_stage
	for meter: StringName in METER_NAMES:
		set_meter(meter, _num(data.get(String(meter)), 0.0))
	_restoring = false
	if stage != previous_stage:
		stage_changed.emit(previous_stage, stage)
	day = int(_num(data.get("day"), 1.0))
	turn = int(_num(data.get("turn"), 0.0))
	_mood_turn = -1
	_mood_spent.clear()
	# Event lines belong to the run that queued them; a loaded game starts with
	# an empty queue rather than replaying the previous run's last crossing.
	pending_events.clear()
	var stored_path := StringName(_str(data.get("path")))
	if stored_path == &"" or PATHS.has(stored_path):
		path = stored_path
	else:
		push_warning("GameState.from_dict: unknown path '%s' — cleared" % stored_path)
		path = &""
	# A lock is only meaningful on a valid assigned path.
	if data.get("path_locked") == true and path == &"":
		push_warning("GameState.from_dict: path_locked without a valid path — cleared")
	path_locked = data.get("path_locked") == true and path != &""
	# docs/01 §4: the lock is permanent, not a flag a stale or hand-edited
	# snapshot can lose — a save at Stage 3+ with a path loads locked.
	if path != &"" and stage >= Paths.lock_stage():
		path_locked = true
	path_scores = _stored_scores(data.get("path_scores"))
	path_evidence = _stored_evidence(data.get("path_evidence"))
	path_runner_up = _stored_runner_up(data.get("path_runner_up"))
	last_question = _str(data.get("last_question")).strip_edges().left(200)
	player_name = _str(data.get("player_name"))
	if player_name.is_empty():
		player_name = "Senpai"
	# Partial profiles rebuild from zeroed counters, never from live leftovers.
	profile = _blank_profile()
	var stored_profile: Variant = data.get("profile", {})
	if stored_profile is Dictionary:
		for key: Variant in stored_profile:
			var counter := StringName(_str(key))
			if PROFILE_COUNTERS.has(counter) or Paths.is_counter(counter):
				profile[String(counter)] = maxi(0, int(_num(stored_profile[key], 0.0)))
			else:
				push_warning("GameState.from_dict: dropping unknown counter '%s'" % key)
	elif stored_profile != null:
		push_warning("GameState.from_dict: 'profile' is not a Dictionary — reset")
	# Flags follow the set_flag() rule: recursively JSON-safe or dropped.
	flags = {}
	var stored_flags: Variant = data.get("flags", {})
	if stored_flags is Dictionary:
		for key: Variant in stored_flags:
			var value: Variant = stored_flags[key]
			if (key is String or key is StringName) and _is_json_safe(value):
				flags[String(key)] = _normalise_flag(value)
			else:
				push_warning("GameState.from_dict: dropping unsafe flag '%s'" % key)
	elif stored_flags != null:
		push_warning("GameState.from_dict: 'flags' is not a Dictionary — cleared")
	var stored_tone := StringName(_str(data.get("last_tone")))
	_last_tone = stored_tone if _tone_names().has(stored_tone) else &""
	state_reset.emit()
	return true


## Recursive JSON-safety for flags/snapshot data (docs/07 §3.5): finite scalars,
## shallow acyclic arrays, and string-keyed dictionaries only — JSON.stringify
## would silently coerce anything else (a nested Vector2 becomes "(1.0, 2.0)",
## and NAN/INF do not round-trip).
static func _is_json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > FLAG_MAX_DEPTH or not JSON_SAFE_TYPES.has(typeof(value)):
		return false
	if value is float and not is_finite(value):
		return false
	if value is Array:
		for item: Variant in value:
			if not _is_json_safe(item, depth + 1):
				return false
	elif value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName):
				return false
			if not _is_json_safe(value[key], depth + 1):
				return false
	return true


## Storage form for a validated flag value: StringName → String, containers
## deep-copied with the same normalisation applied to their contents.
static func _normalise_flag(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if value is Array:
		var copy: Array = []
		for item: Variant in value:
			copy.append(_normalise_flag(item))
		return copy
	if value is Dictionary:
		var copy := {}
		for key: Variant in value:
			copy[String(key)] = _normalise_flag(value[key])
		return copy
	return value


## Numeric coercion for snapshot/model input: non-finite floats (NAN/INF) are
## rejected in favour of the fallback — they cannot round-trip JSON and would
## silently poison meters, day or counters (docs/07 §3.5).
static func _num(value: Variant, fallback: float = 0.0) -> float:
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


## Meter writes only ever store finite floats (CODE-9, DES-7): clampf() passes
## NAN straight through and INF would land on a bound the caller never asked
## for, and either value poisons the ratchet and the JSON snapshot. Non-finite
## writes are dropped — the meter keeps its current value and no signal fires.
func _clamp_meter(meter: StringName, value: float) -> float:
	var bounds: Vector2 = METER_RANGES[meter]
	if not is_finite(value):
		push_warning("GameState: non-finite write to '%s' ignored" % meter)
		return clampf(get_meter(meter), bounds.x, bounds.y)
	return clampf(value, bounds.x, bounds.y)


## Stage only ever rises (docs/01 §3 transitions are one-way diegetic events);
## Instability dips within the ratchet are "good days", not de-escalation.
##
## One crossing = one transition: the guard is `band > stage`, and it is the
## only place stage_transition fires. Writing Instability again inside the band
## leaves `band == stage` and emits nothing; one write that jumps two bands
## fires once with the full previous→current pair; a restore never gets here
## (from_dict suppresses it via `_restoring` and emits its own stage_changed).
func _refresh_stage(value: float) -> void:
	var band := Stages.for_instability(value)
	if band <= stage:
		return
	var previous := stage
	stage = band
	if _restoring:
		return
	# docs/01 §3 + docs/08 §6: the diegetic transition for this crossing, and
	# the line she is told about it in her next prompt.
	var line := Stages.event_line(stage)
	if line.is_empty():
		push_warning("GameState: no stage-transition EVENT line for stage %d" % stage)
	else:
		queue_event(line)
	stage_changed.emit(previous, stage)
	stage_transition.emit(previous, stage, Stages.transition_spec(stage))
	# docs/01 §4: entering Stage 2 assigns, entering Stage 3 locks — at the
	# crossing itself, not only at the next turn close (the night roll-over and a
	# trigger spike cross her stage between turns too).
	if stage >= Paths.assign_stage():
		_evaluate_path()


func _blank_profile() -> Dictionary:
	var counters := {}
	for counter: StringName in PROFILE_COUNTERS:
		counters[String(counter)] = 0
	# docs/01 §4 reads three counters §2's tag list does not enumerate.
	for counter: StringName in Paths.counters():
		counters[String(counter)] = 0
	return counters


## Snapshot validation for the path block: known path ids only, finite scores,
## non-negative evidence turns, and a runner-up that is a real secondary path.
func _stored_scores(value: Variant) -> Dictionary:
	var out := {}
	if not value is Dictionary:
		return out
	for key: Variant in value:
		var path_id := StringName(_str(key))
		if not PATHS.has(path_id):
			continue
		var raw: Variant = (value as Dictionary)[key]
		if raw is int or raw is float:
			var number := float(raw)
			if is_finite(number):
				out[String(path_id)] = number
	return out


func _stored_evidence(value: Variant) -> Dictionary:
	var out := {}
	if not value is Dictionary:
		return out
	for key: Variant in value:
		var path_id := StringName(_str(key))
		if not PATHS.has(path_id):
			continue
		var raw: Variant = (value as Dictionary)[key]
		if raw is int or raw is float:
			var number := float(raw)
			if is_finite(number) and number >= 0.0:
				out[String(path_id)] = int(number)
	return out


func _stored_runner_up(value: Variant) -> StringName:
	var path_id := StringName(_str(value))
	if path_id == &"" or path_id == path or not PATHS.has(path_id):
		return &""
	return path_id


func _tone_of_read(label: String) -> StringName:
	var tones: Dictionary = _profile_map().get("tone", {})
	for tone_name: Variant in tones:
		var members: Variant = tones[tone_name]
		if members is Array and members.has(label):
			return StringName(_str(tone_name))
	return &""


func _tone_names() -> Array[StringName]:
	var names: Array[StringName] = [&""]
	for tone_name: Variant in _profile_map().get("tone", {}):
		names.append(StringName(_str(tone_name)))
	return names


func _profile_map() -> Dictionary:
	if _profile_map_cache.is_empty():
		_profile_map_cache = _load_json_dict(PROFILE_MAP_PATH)
	return _profile_map_cache


static func _load_json_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error(
			"GameState: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("GameState: %s is not a JSON object" % path)
		return {}
	return parsed
