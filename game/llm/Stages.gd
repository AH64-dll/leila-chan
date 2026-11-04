class_name Stages
extends RefCounted
## Stages — the docs/01 §3 stage machine: the six Instability bands, the
## diegetic transition that runs when one is crossed, and the docs/08 §6 EVENT
## line she is told in her next prompt afterwards.
##
## Split out of GameState the way the meter math was split into Meters (P2.01):
## GameState owns the live stage value, the monotonic rule and the signals; this
## owns the numbers and the per-stage data. Everything here is pure except the
## table load, and the numbers live in res://data/stages.json (the docs bands
## are also the in-code fallback, so a broken file degrades to the documented
## stage boundaries instead of to a single stage).
##
## This class only DERIVES a stage; it never stores one. GameState calls
## for_instability() on every instability write and emits stage_transition()
## exactly once per crossing — writing instability again inside the same band
## does not fire a second time, one write that jumps two bands fires once, and
## a save restore is not a crossing at all.

const TABLE_PATH := "res://data/stages.json"

## docs/01 §3 as code: the stage floors, the stage names and the transition
## window. The data-file test pins these against the bible; the prose of the
## EVENT lines lives only in the data file (content is not code).
const DOCS_TABLE := {
	"bands": [0, 15, 30, 50, 70, 90],
	"names": ["Honeymoon", "Hairline Cracks", "Leaks", "Fracture", "Collapse", "Terminal"],
	"transition":
	{
		"duration_s": 2.5,
		"fx": "glitch",
		"cue": "stinger.stage_change",
	},
}

## docs/01 §3: "the screen glitches for 2–3 seconds". The data file retunes the
## duration inside that window; widening the window itself is a DCR.
const MIN_DURATION_S := 2.0
const MAX_DURATION_S := 3.0

## docs/01 §3: the bible fixes six stages, so the data file may move the
## boundaries but not add or drop a stage (sampling.json, stage_gates.json and
## the stage prompt modules all key on 0–5).
const STAGE_COUNT := 6

static var _table_cache: Dictionary = {}


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}


## The merged table (docs values overlaid with stages.json). READ-ONLY: it is
## shared, and the band lookups run on every instability write.
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _load_table()
	return _table_cache


## docs/01 §3: the Instability value each stage begins at, as a copy — callers
## get the bands but can never rewrite the shared table.
static func bands() -> Array[int]:
	return (table()["bands"] as Array).duplicate()


## The highest stage index: five, i.e. docs/01 §3's six stages.
static func max_stage() -> int:
	return STAGE_COUNT - 1


## docs/01 §3: the stage an Instability value sits in — the highest floor it has
## reached, so 14 → 0, 15 → 1, 100 → 5. Total on purpose: out-of-range input
## still resolves (NAN reads as the healthiest band; the meter layer clamps and
## drops non-finite writes long before this is called).
static func for_instability(value: float) -> int:
	var floors: Array = table()["bands"]
	var band := 0
	for index: int in floors.size():
		if value >= float(floors[index]):
			band = index
	return band


## docs/01 §3 stage name ("Honeymoon" … "Terminal"); "" outside 0..5.
static func name_of(stage: int) -> String:
	var names: Array = table()["names"]
	if stage < 0 or stage >= names.size():
		push_warning("Stages.name_of: stage %d is outside 0..%d" % [stage, names.size() - 1])
		return ""
	return String(names[stage])


## docs/01 §3: the diegetic transition for a crossing into `stage` — how long
## the screen glitches, the fx and cue that fill the window, and where it lands.
## Engine-owned: it fires on every crossing whatever the docs/02 §5 model fx
## budget or the docs/02 §2.3 stage gate says, because the glitch hides the
## docs/06 §4 dose change (P2.03) rather than a beat's mood.
static func transition_spec(stage: int) -> Dictionary:
	var spec: Dictionary = table()["transition"]
	return {
		"stage": stage,
		"name": name_of(stage),
		"duration_s": _clamp_duration(float(spec["duration_s"])),
		"fx": String(spec["fx"]),
		"cue": String(spec["cue"]),
	}


## docs/08 §6: the post-transition line she is told in her next prompt, already
## prefixed ("EVENT: …"). "" when the data has no line for `stage` — the caller
## then queues nothing and warns, rather than inventing prose.
static func event_line(stage: int) -> String:
	var events: Dictionary = table()["transition"]["events"]
	return String(events.get(stage, "")).strip_edges()


static func _load_table() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("Stages: %s missing; using the docs/01 §3 bands" % TABLE_PATH)
		return parse_document({})
	return parse_document(JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH)))


## Parses a stage document into the canonical table — data-driven on purpose: a
## test hands it a synthetic document and proves the loader (not a hard-coded
## copy) decides the bands. Shape: {"bands": [6 ascending floors starting at
## 0], "names": [6 strings], "transition": {"duration_s", "fx", "cue",
## "events": {"1".."5": line}}}. Anything unusable keeps the docs/01 §3 value
## it belongs to, so a broken file still yields a complete, playable table.
static func parse_document(parsed: Variant) -> Dictionary:
	var out := _docs_table()
	if not parsed is Dictionary:
		push_warning("Stages: %s is not a JSON object; using the docs/01 §3 bands" % TABLE_PATH)
		return out
	var document: Dictionary = parsed
	var floors := _parse_bands(document.get("bands"))
	if floors.is_empty():
		push_warning(
			"Stages: %s bands are not six ascending floors; using the docs/01 §3 bands" % TABLE_PATH
		)
	else:
		out["bands"] = floors
	var names := _parse_names(document.get("names"))
	if names.is_empty():
		push_warning(
			"Stages: %s names do not match the bands; using the docs/01 §3 names" % TABLE_PATH
		)
	else:
		out["names"] = names
	_merge_transition(out["transition"], document.get("transition"))
	return out


## docs/01 §3's stage floors: exactly STAGE_COUNT values, integral, ascending,
## the first one 0 and every one inside the 0–100 Instability range. An empty
## array means "unusable" and the caller keeps the documented bands.
static func _parse_bands(value: Variant) -> Array[int]:
	var out: Array[int] = []
	if not value is Array or (value as Array).size() != STAGE_COUNT:
		return out
	for item: Variant in value:
		if not (item is int or item is float):
			out.clear()
			return out
		var number := float(item)
		if not is_finite(number) or number != floor(number) or number < 0.0 or number > 100.0:
			out.clear()
			return out
		out.append(int(number))
	if out[0] != 0:
		out.clear()
		return out
	for index: int in range(1, out.size()):
		if out[index] <= out[index - 1]:
			out.clear()
			return out
	return out


## One non-empty name per band; an empty array means "unusable".
static func _parse_names(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if not value is Array or (value as Array).size() != STAGE_COUNT:
		return out
	for item: Variant in value:
		var name := String(item).strip_edges()
		if name.is_empty():
			out.clear()
			return out
		out.append(name)
	return out


## Overlays the transition block on the docs defaults. A non-finite duration,
## an empty fx/cue or a non-string event line keeps the documented value — a
## hand-edited stages.json can never stretch the glitch outside docs/01 §3's
## 2–3 s window or blank out a stage's line.
static func _merge_transition(target: Dictionary, source: Variant) -> void:
	if not source is Dictionary:
		return
	var spec: Dictionary = source
	var duration: Variant = spec.get("duration_s")
	if (duration is float or duration is int) and is_finite(float(duration)):
		target["duration_s"] = _clamp_duration(float(duration))
	var fx: Variant = spec.get("fx")
	if fx is String and not (fx as String).strip_edges().is_empty():
		target["fx"] = (fx as String).strip_edges()
	var cue: Variant = spec.get("cue")
	if cue is String and not (cue as String).strip_edges().is_empty():
		target["cue"] = (cue as String).strip_edges()
	var events: Variant = spec.get("events")
	if not events is Dictionary:
		return
	for key: Variant in events:
		var stage := _stage_key(key)
		var raw: Variant = events[key]
		var line := (raw as String).strip_edges() if raw is String else ""
		if stage > 0 and stage <= max_stage() and not line.is_empty():
			target["events"][stage] = line


## docs/01 §3's window is the contract, the data value is the tuning knob.
static func _clamp_duration(value: float) -> float:
	if not is_finite(value):
		return float(DOCS_TABLE["transition"]["duration_s"])
	return clampf(value, MIN_DURATION_S, MAX_DURATION_S)


static func _stage_key(key: Variant) -> int:
	var text := str(key)
	return int(text) if text.is_valid_int() else -1


## A fresh copy of the docs table with the canonical shape: typed bands, an
## events dictionary (prose is data-only, so it starts empty).
static func _docs_table() -> Dictionary:
	var out: Dictionary = DOCS_TABLE.duplicate(true)
	var floors: Array[int] = []
	for value: Variant in out["bands"] as Array:
		floors.append(int(value))
	out["bands"] = floors
	var transition: Dictionary = out["transition"]
	transition["events"] = {}
	return out
