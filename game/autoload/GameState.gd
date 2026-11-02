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
## Per-turn caps on model-suggested moves (docs/01 §2 "Moves by" column).
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
const PATHS: Array[StringName] = [&"yandere", &"split", &"tsun", &"hollow", &"awake", &"anchor"]

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

# Ratchet backing must be declared before `instability`: its setter reads them.
var instability_peak := 0.0
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
	if mood.has("affection"):
		adjust_meter(
			&"affection",
			_mood_delta(mood["affection"], MOOD_SCALE_AFFECTION, MAX_AFFECTION_SUGGESTION)
		)
	if mood.has("trust"):
		adjust_meter(&"trust", _mood_delta(mood["trust"], MOOD_SCALE_TRUST, INF))
	if mood.has("stress"):
		adjust_meter(
			&"instability",
			_mood_delta(mood["stress"], MOOD_SCALE_STRESS, MAX_INSTABILITY_SUGGESTION)
		)


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
func advance_day() -> void:
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


## Flags are serialised with the snapshot — only JSON-safe values are kept.
func set_flag(flag: StringName, value: Variant = true) -> void:
	if not JSON_SAFE_TYPES.has(typeof(value)):
		push_warning("GameState.set_flag: '%s' rejected — value is not JSON-safe" % flag)
		return
	var stored: Variant = value
	if value is Array or value is Dictionary:
		stored = value.duplicate(true)
	elif value is StringName:
		stored = String(value)
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


## Restores a snapshot. Out-of-range or malformed values are healed, never
## trusted (clamped ranges, ratchet floor, band floor for stage).
func from_dict(data: Variant) -> bool:
	if not data is Dictionary or data.is_empty():
		push_warning("GameState.from_dict: expected a non-empty Dictionary")
		return false
	var version := int(_num(data.get("version"), SNAPSHOT_VERSION))
	if version != SNAPSHOT_VERSION:
		push_warning(
			(
				"GameState.from_dict: snapshot v%d (expected v%d) — best effort"
				% [version, SNAPSHOT_VERSION]
			)
		)
	# Peak first: the instability setter derives the floor from it.
	instability_peak = maxf(0.0, _num(data.get("instability_peak"), 0.0))
	for meter: StringName in METER_NAMES:
		set_meter(meter, _num(data.get(String(meter)), 0.0))
	var healed_stage := maxi(stage, clampi(int(_num(data.get("stage"), 0.0)), 0, STAGE_MAX))
	if healed_stage != stage:
		var previous := stage
		stage = healed_stage
		stage_changed.emit(previous, stage)
	day = int(_num(data.get("day"), 1.0))
	turn = int(_num(data.get("turn"), 0.0))
	var stored_path := StringName(_str(data.get("path")))
	if stored_path == &"" or PATHS.has(stored_path):
		path = stored_path
	else:
		push_warning("GameState.from_dict: unknown path '%s' — cleared" % stored_path)
		path = &""
	path_locked = data.get("path_locked") == true
	player_name = _str(data.get("player_name"))
	if player_name.is_empty():
		player_name = "Senpai"
	var stored_profile: Variant = data.get("profile", {})
	if stored_profile is Dictionary:
		for key: Variant in stored_profile:
			var counter := StringName(_str(key))
			if PROFILE_COUNTERS.has(counter):
				profile[String(counter)] = maxi(0, int(_num(stored_profile[key], 0.0)))
			else:
				push_warning("GameState.from_dict: dropping unknown counter '%s'" % key)
	var stored_flags: Variant = data.get("flags", {})
	if stored_flags is Dictionary:
		flags = stored_flags.duplicate(true)
	var stored_tone := StringName(_str(data.get("last_tone")))
	_last_tone = stored_tone if _tone_names().has(stored_tone) else &""
	return true


static func _stage_for_instability(value: float) -> int:
	var band := 0
	for i: int in STAGE_BANDS.size():
		if value >= STAGE_BANDS[i]:
			band = i
	return band


static func _mood_delta(raw_value: Variant, scale: float, cap: float) -> float:
	var raw := clampf(_num(raw_value), -MOOD_LIMIT, MOOD_LIMIT)
	return clampf(raw * scale, -cap, cap)


static func _num(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if value is int or value is float else fallback


static func _str(value: Variant) -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""


func _clamp_meter(meter: StringName, value: float) -> float:
	var bounds: Vector2 = METER_RANGES[meter]
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
