class_name Meters
extends RefCounted
## Meters — the docs/01 §2 meter arithmetic in one place: the instability
## ratchet floor (peak − 15), the per-turn slow burn, the per-day burn, and the
## docs/02 §1.1 mood scaling under the docs/01 §2 per-turn suggestion caps.
##
## Split out of GameState so the formula has exactly one definition: GameState
## owns the values, the clamping and the signals; this owns the numbers and the
## math. Everything here is pure except the table load, and the numbers live in
## res://data/meters.json (the docs values are also the in-code fallback, so a
## broken file degrades to the documented formula instead of to zero math).
##
## Formulas are fixed by the bible: if one is wrong in play, the fix is a DCR
## plus a data change and a test update — never a quiet tweak here.

const TABLE_PATH := "res://data/meters.json"

## docs/01 §2 + docs/02 §1.1 as code: the fallback table, and the values the
## data-file test pins. Kept identical to DOCS values on purpose.
const DOCS_TABLE := {
	"ratchet_drop": 15.0,
	"slow_burn": {"base": 0.35, "per_fixation": 0.15, "per_lucidity": 0.2},
	"daily_burn": 3.0,
	"mood":
	{
		"limit": 3.0,
		"scale": {"affection": 1.5, "trust": 2.0, "stress": 0.6},
		"turn_caps": {"affection": 5.0, "instability": 3.0},
	},
}

static var _table_cache: Dictionary = {}


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}


## The merged table (docs values overlaid with meters.json). READ-ONLY: it is
## shared, and copying it per meter write would allocate on a hot path.
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _load_table()
	return _table_cache


## docs/01 §2 ratchet: Instability may dip on good days but never below
## `peak − 15`. Instability is 0–100, so an early peak has floor zero.
static func ratchet_floor(peak: float) -> float:
	if not is_finite(peak):
		return 0.0
	return maxf(0.0, peak - float(table()["ratchet_drop"]))


## docs/01 §2 per turn: `+0.35 base +0.15 × (Fixation/100) −0.2 × (Lucidity/100)`.
## Inputs are meters (0–100); clamped and finite-guarded so the formula stays
## defined for any caller.
static func slow_burn(fixation: float, lucidity: float) -> float:
	var spec: Dictionary = table()["slow_burn"]
	var fix := clampf(_num(fixation), 0.0, 100.0) / 100.0
	var luc := clampf(_num(lucidity), 0.0, 100.0) / 100.0
	return (
		float(spec["base"]) + float(spec["per_fixation"]) * fix - float(spec["per_lucidity"]) * luc
	)


## docs/01 §2 per day: a flat `+3` Instability at the night roll-over.
static func daily_burn() -> float:
	return float(table()["daily_burn"])


## docs/02 §1.1: each mood int is −3..3 before scaling.
static func mood_limit() -> float:
	return float(table()["mood"]["limit"])


## docs/02 §1.1 scaling: affection ×1.5, trust ×2, stress (→ Instability) ×0.6.
## An unknown field scales by zero and warns: a typo must never move a meter.
static func mood_scale(field: StringName) -> float:
	var scale: Dictionary = table()["mood"]["scale"]
	if not scale.has(String(field)):
		push_warning("Meters.mood_scale: unknown mood field '%s'" % field)
		return 0.0
	return float(scale[String(field)])


## One mood field after the −3..3 clamp and its scale — the delta the model
## asked for, before GameState applies the docs/01 §2 per-turn cap to the
## running total.
static func mood_delta(field: StringName, raw: Variant) -> float:
	var limit := mood_limit()
	return clampf(_num(raw), -limit, limit) * mood_scale(field)


## docs/01 §2 "Moves by": the model's own suggestion is capped per turn at ±5
## (Affection) and ±3 (Instability). Other meters have no model cap → INF.
static func turn_cap(meter: StringName) -> float:
	var caps: Dictionary = table()["mood"]["turn_caps"]
	if caps.has(String(meter)):
		return float(caps[String(meter)])
	return INF


static func _load_table() -> Dictionary:
	var merged: Dictionary = DOCS_TABLE.duplicate(true)
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("Meters: %s missing; using the docs/01 §2 values" % TABLE_PATH)
		return merged
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	if not parsed is Dictionary:
		push_warning("Meters: %s is not a JSON object; using the docs/01 §2 values" % TABLE_PATH)
		return merged
	_merge_into(merged, parsed)
	return merged


## Overlays the data values on the docs defaults key by key: the known shape is
## fixed by DOCS_TABLE, unknown keys are ignored, and a non-numeric or
## non-finite value keeps the documented default — a hand-edited meters.json
## can never zero a formula or make the ratchet non-finite.
static func _merge_into(target: Dictionary, source: Variant) -> void:
	if not source is Dictionary:
		return
	for key: Variant in target.keys():
		if not source.has(key):
			continue
		var current: Variant = target[key]
		var incoming: Variant = source[key]
		if current is Dictionary:
			_merge_into(current, incoming)
		elif incoming is float or incoming is int:
			if is_finite(float(incoming)):
				target[key] = float(incoming)
			else:
				push_warning("Meters: non-finite '%s' in %s ignored" % [key, TABLE_PATH])


## Numeric coercion for data/model input: ints and finite floats only, anything
## else (including NAN/INF, which cannot round-trip JSON) takes the fallback.
static func _num(value: Variant, fallback := 0.0) -> float:
	if value is int:
		return float(value)
	if value is float:
		return value if is_finite(value) else fallback
	return fallback
