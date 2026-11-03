extends Node
## GameState — the game's truth: meters, stage, day, flags, behaviour-profile
## counters and a serialisable snapshot (docs/07 §2, docs/01 §2).
##
## The model never writes here. The Director applies each Turn through
## apply_mood()/apply_read() (docs/02 §4 step 7), which clamp and scale per
## docs/01 §2 and docs/02 §1.1. Read the public vars freely; mutate them only
## through the methods so clamping, the ratchet and the signals always hold.
##
## Stage is monotonic: good days can lower Instability (ratchet floor =
## peak − 15, docs/01 §2) but never de-escalate her — stage transitions are
## one-way diegetic events and the path locks at stage 3 (docs/01 §3–§4).

signal meter_changed(meter: StringName, value: float)
signal stage_changed(previous: int, current: int)
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

## Instability ratchet (docs/01 §2): never below floor = peak − 15.
const RATCHET_DROP := 15.0

## Stage instability bands (docs/01 §3): stage i holds while instability ≥ BANDS[i].
const STAGE_BANDS: Array[int] = [0, 15, 30, 50, 70, 90]
const STAGE_MAX := 5

## Campaign length in in-game days (docs/01 §1).
const DAY_MAX := 14

## Model mood application (docs/02 §1.1): each mood field is an int −3..3,
## scaled per meter when applied.
const MOOD_LIMIT := 3.0
const MOOD_SCALE_AFFECTION := 1.5
const MOOD_SCALE_TRUST := 2.0
const MOOD_SCALE_STRESS := 0.6
## Per-turn caps on model-suggested moves (docs/01 §2 "Moves by" column) —
## enforced per turn against the running total, not per apply_mood() call.
const MAX_AFFECTION_SUGGESTION := 5.0
const MAX_INSTABILITY_SUGGESTION := 3.0

## Slow burn (docs/01 §2): +0.35 +0.15·(Fixation/100) −0.2·(Lucidity/100) per
## turn, +3 per day. Triggers add their spikes on top via adjust_meter().
const SLOW_BURN_BASE := 0.35
const SLOW_BURN_FIXATION := 0.15
const SLOW_BURN_LUCIDITY := 0.2
const DAILY_BURN := 3.0

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
## Read-only: the lowest Instability may ever sit at (docs/01 §2 ratchet).
var instability_floor: float:
	get:
		return maxf(0.0, instability_peak - RATCHET_DROP)
## Derived from Instability bands (docs/01 §3); only ever moves upward.
var stage := 0:
	set(v):
		stage = clampi(v, 0, STAGE_MAX)

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
		instability_peak = maxf(instability_peak, capped)
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
## The player's name (docs/08 §1.5); "Senpai" when they typed nothing.
var player_name := "Senpai"
## JSON-safe flag store for triggers/scenario state: bools, counts, small data.
var flags := {}
## Behaviour-profile counters (docs/01 §2); bump via bump_profile()/apply_read().
var profile := _blank_profile()

var _last_tone: StringName = &""
## Per-turn model-suggestion budget (docs/01 §2): meter → applied delta total,
## reset whenever `turn` changes.
var _mood_turn := -1
var _mood_spent := {}
var _profile_map_cache := {}


## Fresh New-Game state (docs/05 M08 leaves the shadow save to SaveSystem).
func reset() -> void:
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
	player_name = "Senpai"
	flags = {}
	profile = _blank_profile()
	_last_tone = &""
	_mood_turn = -1
	_mood_spent.clear()
	state_reset.emit()


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


## docs/02 §1.1 + §4 step 7: model mood ints −3..3, scaled per meter
## (affection ×1.5, trust ×2, stress → instability ×0.6), docs/01 §2 caps.
func apply_mood(mood: Dictionary) -> void:
	if _mood_turn != turn:
		_mood_turn = turn
		_mood_spent.clear()
	if mood.has("affection"):
		_apply_mood_meter(
			&"affection", mood["affection"], MOOD_SCALE_AFFECTION, MAX_AFFECTION_SUGGESTION
		)
	if mood.has("trust"):
		_apply_mood_meter(&"trust", mood["trust"], MOOD_SCALE_TRUST, INF)
	if mood.has("stress"):
		_apply_mood_meter(
			&"instability", mood["stress"], MOOD_SCALE_STRESS, MAX_INSTABILITY_SUGGESTION
		)


## One model suggestion after docs/02 §1.1 scaling, capped against what the
## model already moved this turn: the docs/01 §2 "Moves by" column is a
## per-turn budget (affection ±5, instability ±3, trust uncapped), so the
## running total of landed movement is clamped — two apply_mood() calls in one
## turn share it, and unlanded suggestions at a meter boundary never free budget
## in the opposite direction.
func _apply_mood_meter(meter: StringName, raw_value: Variant, scale: float, cap: float) -> void:
	# _num() drops non-finite suggestions and the clamp bounds the rest before
	# scaling, so the scaled delta is always finite.
	var delta := clampf(_num(raw_value), -MOOD_LIMIT, MOOD_LIMIT) * scale
	var spent := float(_mood_spent.get(meter, 0.0))
	var total := clampf(spent + delta, -cap, cap)
	var attempt := total - spent
	var before := get_meter(meter)
	adjust_meter(meter, attempt)
	# Charge only the movement the model's own delta produces inside the meter
	# range. A game-side correction is not the model's move: the instability
	# ratchet floor can lift the meter past the requested target after a peak
	# write, and charging that to the model would drain the docs/01 §2 per-turn
	# allowance and let a later opposite-sign suggestion drag the meter back.
	# Clamping the target keeps |charged| ≤ |attempt|, so the running total
	# stays inside [−cap, cap] whatever the rest of the game does to the meter.
	var bounds: Vector2 = METER_RANGES[meter]
	_mood_spent[meter] = spent + clampf(before + attempt, bounds.x, bounds.y) - before


## docs/01 §2: the per-turn slow-burn increment.
func slow_burn_delta() -> float:
	return (
		SLOW_BURN_BASE
		+ SLOW_BURN_FIXATION * (fixation / 100.0)
		- SLOW_BURN_LUCIDITY * (lucidity / 100.0)
	)


func apply_slow_burn() -> void:
	adjust_meter(&"instability", slow_burn_delta())


func advance_turn() -> void:
	turn += 1


## Night roll-over: day +1 and the daily burn (+3 instability, docs/01 §2).
## A no-op past day 14: the campaign is over (docs/01 §1), no burn, no signal.
func advance_day() -> void:
	if day >= DAY_MAX:
		return
	day += 1
	adjust_meter(&"instability", DAILY_BURN)
	day_changed.emit(day)


func bump_profile(counter: StringName, amount: int = 1) -> void:
	if not PROFILE_COUNTERS.has(counter):
		push_warning("GameState.bump_profile: unknown counter '%s'" % counter)
		return
	var key := String(counter)
	profile[key] = maxi(0, int(profile.get(key, 0)) + amount)
	profile_changed.emit(counter, profile[key])


## docs/02 §4 step 7: the Turn's `read` intent feeds the profile counters.
## The label→counter table and the warm/cold tone map behind `inconsistency`
## (warm↔cold swings, docs/01 §2) live in res://data/profile_map.json.
func apply_read(read_label: StringName) -> void:
	var table: Dictionary = _profile_map().get("read_to_profile", {})
	var key := String(read_label)
	if not table.has(key):
		push_warning("GameState.apply_read: unknown read label '%s'" % key)
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
	instability_peak = _num(data.get("instability_peak"), 0.0)
	instability_peak = maxf(
		instability_peak, _clamp_meter(&"instability", _num(data.get("instability"), 0.0))
	)
	var healed_stage := _stage_for_instability(instability_peak)
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
	if stage != previous_stage:
		stage_changed.emit(previous_stage, stage)
	day = int(_num(data.get("day"), 1.0))
	turn = int(_num(data.get("turn"), 0.0))
	_mood_turn = -1
	_mood_spent.clear()
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
	player_name = _str(data.get("player_name"))
	if player_name.is_empty():
		player_name = "Senpai"
	# Partial profiles rebuild from zeroed counters, never from live leftovers.
	profile = _blank_profile()
	var stored_profile: Variant = data.get("profile", {})
	if stored_profile is Dictionary:
		for key: Variant in stored_profile:
			var counter := StringName(_str(key))
			if PROFILE_COUNTERS.has(counter):
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


static func _stage_for_instability(value: float) -> int:
	var band := 0
	for i: int in STAGE_BANDS.size():
		if value >= STAGE_BANDS[i]:
			band = i
	return band


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
func _refresh_stage(value: float) -> void:
	var band := _stage_for_instability(value)
	if band > stage:
		var previous := stage
		stage = band
		stage_changed.emit(previous, stage)


func _blank_profile() -> Dictionary:
	var counters := {}
	for counter: StringName in PROFILE_COUNTERS:
		counters[String(counter)] = 0
	return counters


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
