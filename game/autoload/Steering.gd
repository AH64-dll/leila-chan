extends Node
## Steering — dose schedule, vector mixing (docs/06).
##
## docs/06 §3:
##     dose(turn) = base[stage] + path_mix + spike + scene_modifier
##                  - player_slider                  → clamped to [0, 12]
##
## `dose_for(ctx)` turns the docs/02 §4 turn snapshot into the control-vector
## scales carried on `TurnRequest.dose` (docs/07 §3.1). The Director calls it in
## step 4 of every turn; the request, the transcript and the F3 overlay read the
## result. The malice scale plus one path slot are scheduled, both llama.cpp
## vector scales:
##   malice   — the tweet-malice scale (docs/06 §1 curve, docs/02 §9 base column)
##   path slot — `path_mix`, the §3 interim weight, while ctx.path is unset;
##              once the narrative path is assigned the slot carries that path's
##              keep vector (`possessive`/`aware`/`lucid`, P3.03 keep decisions)
##              at the dose.json weight curve. `lucid` (ANCHOR) is the signed
##              exception: paths.json `anchors.lucid` documents that its positive
##              side is the anchor voice while docs/06 §2 applies it *back*, so
##              its curve weights are negative (P3.19 r2). The three remaining
##              fallback paths (D21) are prompt-only and schedule no path
##              weight. Deliberately not `path`
##              — that name already means the narrative path (`GameState.path`,
##              the F3 panel's `Path:` line) and the control-vector *file* in the
##              launcher's `control_vectors` entries.
##
## `malice` is a scale in [0, 12]. The path slot keeps its sign: its clamp is a
## **code rule** on the magnitude (|scale| ≤ 12, docs/06 §3/§5) so the lucid
## negative reaches the launcher — no data file can widen it either way. The
## calmer-mode cap (docs/06 §5, docs/02 §8) is the stage-3 row of the same table
## applied after the modifiers, magnitude-wise (a negative weight caps toward
## zero, never deeper), so retuning stage 3 moves the calmer ceiling with it —
## docs/06 §5 defines calmer as "stage-3 levels". The stage numbers live in
## `game/data/steering/dose.json`; the docs/06 §3 table is the in-code
## fallback, so a broken data file degrades to the documented values.
##
## Prototype limit (docs/06 §4): the dose is a llama-server *launch flag*, so it
## only changes when the stage-change restart relaunches the server. Per-turn
## spikes (+3..+4 for 1–2 turns) therefore cannot be applied yet — see
## `spike_for()`. The shipping GDExtension applies them with
## `llama_set_adapter_cvec` before decoding (P4.03).

const TABLE_PATH := "res://data/steering/dose.json"

## docs/06 §2 vector name; also docs/02 §9's "steering dose (base)" column.
const MALICE_KEY := "malice"
## docs/06 §3's `path_mix` term, scheduled only while the narrative path is
## unassigned: once ctx.path exists the slot is the path's vector name
## (dose.json `path_vectors`), and a prompt-only fallback path emits no path
## weight at all.
const PATH_MIX_KEY := "path_mix"

const DOSE_MIN := 0.0
const DOSE_MAX := 12.0

## docs/02 §8 + docs/06 §5: calmer mode never goes past the stage-3 schedule.
const CALMER_LEVEL := "calmer"
const CALMER_STAGE := 3

## docs/06 §3 spike term; P4.03 turns it live with the runtime cvec path.
const SPIKE_MAX := 4.0
const SPIKES_LIVE := false

## docs/06 §3 stage table (malice scale, pre-assignment interim path weight),
## in-code fallback — retuned P3.04 into the ≤0.5 coherent band.
const FALLBACK_TABLE := {
	0: {MALICE_KEY: 0.0, PATH_MIX_KEY: 0.0},
	1: {MALICE_KEY: 2.5, PATH_MIX_KEY: 0.1},
	2: {MALICE_KEY: 3.5, PATH_MIX_KEY: 0.2},
	3: {MALICE_KEY: 4.5, PATH_MIX_KEY: 0.2},
	4: {MALICE_KEY: 6.0, PATH_MIX_KEY: 0.2},
	5: {MALICE_KEY: 8.0, PATH_MIX_KEY: 0.2},
}

## dose.json `path_vectors`: narrative path -> keep vector name; a path missing
## from the map is the P3.03 fallback decision (D21) — prompt-only, no weight.
## ANCHOR binds `lucid`, the signed vector (negative curve weights).
const FALLBACK_PATH_VECTORS := {
	"YANDERE": "possessive",
	"AWAKE": "aware",
	"ANCHOR": "lucid",
}

## dose.json `weight_curves`: keep vector -> per-stage weight (|w| ≤0.5 band).
## `lucid`'s curve is negative on purpose — see `anchors.lucid` in paths.json.
const FALLBACK_WEIGHT_CURVES := {
	"possessive": {0: 0.0, 1: 0.1, 2: 0.2, 3: 0.3, 4: 0.4, 5: 0.5},
	"aware": {0: 0.0, 1: 0.1, 2: 0.2, 3: 0.3, 4: 0.4, 5: 0.5},
	"lucid": {0: 0.0, 1: 0.0, 2: -0.2, 3: -0.3, 4: -0.4, 5: -0.5},
}

var _table: Dictionary = {}
var _path_vectors: Dictionary = {}
var _weight_curves: Dictionary = {}


func _ready() -> void:
	reload_table()


## The control-vector scales for this turn, e.g. `{"malice": 4.5, "aware": 0.3}`
## or, on an ANCHOR run, `{"malice": 4.5, "lucid": -0.3}` — the shape
## `TurnRequest.dose` documents. Never empty: an unknown stage falls
## back to stage 0.
func dose_for(ctx: Dictionary = {}) -> Dictionary:
	var schedule := schedule_for(ctx)
	return (schedule["dose"] as Dictionary).duplicate()


## The docs/06 §3 breakdown behind `dose_for`: every term, the clamps and the
## calmer cap, for the F3 overlay and the tests. `dose_for` is the transport
## shape; this is the explanation of it. `spike` is the applied scale;
## `spike_requested` is what the trigger asked for, so the prototype's dropped
## spike stays visible instead of reading as "the trigger never fired".
func schedule_for(ctx: Dictionary = {}) -> Dictionary:
	var stage := _stage_of(ctx)
	var row := _row(stage)
	var spike_requested := float(ctx.get("spike", 0.0))
	var spike := spike_for(ctx)
	var scene := float(ctx.get("scene_modifier", 0.0))
	var slider := float(ctx.get("player_slider", 0.0))
	var malice := float(row[MALICE_KEY]) + spike + scene - slider
	var path := _path_of(ctx)
	var vector := _vector_for(path)
	var weight := _weight(vector, path, stage, row)

	# docs/02 §8 "caps stage at 3": compare magnitude by magnitude, so a calmer
	# stage-5 turn is exactly a stage-3 turn — at the ceiling, not below it. The
	# cap runs after the modifiers so a scene kick cannot climb past it either.
	# The path slot's cap is magnitude-wise too: a negative weight (lucid)
	# caps toward zero at the same |weight| ceiling, keeping its sign.
	var calmer := is_calmer_mode(ctx)
	var capped := false
	if calmer:
		var cap := _row(CALMER_STAGE)
		var cap_weight := _weight(vector, path, CALMER_STAGE, cap)
		capped = malice > float(cap[MALICE_KEY]) or absf(weight) > absf(cap_weight)
		malice = minf(malice, float(cap[MALICE_KEY]))
		# The bound vector caps toward zero at the same |weight| ceiling; an
		# unbound interim `path_mix` is a plain magnitude and caps the old way.
		weight = (
			(signf(weight) * minf(absf(weight), absf(cap_weight)))
			if not vector.is_empty()
			else minf(weight, cap_weight)
		)

	malice = clampf(malice, DOSE_MIN, DOSE_MAX)
	# A bound vector slot is sign-preserving: llama.cpp takes negative scales
	# and lucid's curve is deliberately negative, so its code clamp binds the
	# magnitude, not the value. The unbound `path_mix` slot is a magnitude —
	# a typo'd negative row must still clamp to 0 like before.
	weight = (
		(signf(weight) * minf(absf(weight), DOSE_MAX))
		if not vector.is_empty()
		else clampf(weight, DOSE_MIN, DOSE_MAX)
	)
	var dose := {MALICE_KEY: malice}
	if not vector.is_empty():
		dose[vector] = weight
	elif path.is_empty():
		dose[PATH_MIX_KEY] = weight
	return {
		"stage": stage,
		"malice": malice,
		"path": path,
		"path_vector": vector,
		"path_weight": weight,
		"spike": spike,
		"spike_requested": spike_requested,
		"scene_modifier": scene,
		"player_slider": slider,
		"calmer": calmer,
		"calmer_capped": capped,
		"clamp_min": DOSE_MIN,
		"clamp_max": DOSE_MAX,
		"dose": dose,
	}


## docs/06 §3's spike term (+3..+4 for 1–2 turns, decaying). **Stubbed in P2**:
## the prototype's dose is a `--control-vector-scaled` launch flag (docs/06 §4),
## so it can only change on a stage-change server restart — a one-turn spike
## cannot reach the running model. The applied scale is 0.0; the request is
## still reported, unchanged, as `spike_requested` in `schedule_for()` so a
## debug read can tell a dropped spike from a spike that never fired. P4.03's
## runtime `llama_set_adapter_cvec` makes it live.
func spike_for(ctx: Dictionary = {}) -> float:
	var requested := float(ctx.get("spike", 0.0))
	if requested <= 0.0 or not SPIKES_LIVE:
		return 0.0
	return minf(requested, SPIKE_MAX)


## docs/02 §7 "retry once at dose −2": the offset lands once, on the dose
## (malice) scale. Cutting both scales would halve the retry's intent and take
## the path_mix weight with it. Maps without `malice` (pre-P2 shapes) keep the
## old behaviour: every numeric entry shifts, clamped at 0.
func offset_dose(dose: Dictionary, offset: float) -> Dictionary:
	var out := dose.duplicate()
	if out.is_empty():
		return out
	if out.has(MALICE_KEY):
		out[MALICE_KEY] = clampf(float(out[MALICE_KEY]) + offset, DOSE_MIN, DOSE_MAX)
		return out
	for name: Variant in out:
		out[name] = maxf(DOSE_MIN, float(out[name]) + offset)
	return out


## docs/02 §8's "calmer mode" switch. The caller's ctx can ask for it and
## `Settings.content_level` (the settings menu, P3.13) can force it, never loosen
## it — the same precedence Safety.gd uses, so the dose cap and the content gates
## always agree. Missing/invalid settings never enable the cap.
func is_calmer_mode(ctx: Dictionary = {}) -> bool:
	if String(ctx.get("content_level", "")) == CALMER_LEVEL:
		return true
	return _settings_level() == CALMER_LEVEL


## Dev-overlay rendering of a dose map: `malice 4.5/12 · path_mix 3.0` —
## signed keys render their sign (`lucid -0.3`). Only the malice scale gets a
## `/12` suffix — it is the axis docs/06 §1's curve and docs/02 §9's table are
## written in; both keys are magnitude-clamped to that range.
func describe(dose: Dictionary) -> String:
	if dose.is_empty():
		return "none"
	var parts := PackedStringArray()
	for name: Variant in dose:
		var value: Variant = dose[name]
		if value is int or value is float:
			if str(name) == MALICE_KEY:
				parts.append("%s %.1f/%.0f" % [str(name), float(value), DOSE_MAX])
			else:
				parts.append("%s %.1f" % [str(name), float(value)])
		else:
			parts.append("%s %s" % [str(name), str(value)])
	return " · ".join(parts)


## Load the stage table. Returns false when the file is missing or malformed;
## the docs/06 §3 fallback then holds, so a broken file degrades to the
## documented numbers instead of to defaults.
func reload_table(path := TABLE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("Steering: %s missing; using the docs/06 §3 fallback table" % path)
		_table = FALLBACK_TABLE.duplicate(true)
		_path_vectors = FALLBACK_PATH_VECTORS.duplicate(true)
		_weight_curves = FALLBACK_WEIGHT_CURVES.duplicate(true)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary and (parsed as Dictionary).get("stages") is Dictionary):
		push_warning("Steering: %s has no stages table; using the docs/06 §3 fallback" % path)
		_table = FALLBACK_TABLE.duplicate(true)
		_path_vectors = FALLBACK_PATH_VECTORS.duplicate(true)
		_weight_curves = FALLBACK_WEIGHT_CURVES.duplicate(true)
		return false
	_table = _rows_from((parsed as Dictionary)["stages"])
	_weight_curves = _curves_from((parsed as Dictionary).get("weight_curves"))
	_path_vectors = _map_from((parsed as Dictionary).get("path_vectors"))
	return true


func _rows_from(stages: Dictionary) -> Dictionary:
	var rows := {}
	for stage: int in FALLBACK_TABLE:
		var raw: Variant = stages.get(str(stage))
		if raw is Dictionary:
			var row := raw as Dictionary
			if row.has(MALICE_KEY) and row.has(PATH_MIX_KEY):
				rows[stage] = {
					MALICE_KEY: float(row[MALICE_KEY]),
					PATH_MIX_KEY: float(row[PATH_MIX_KEY]),
				}
				continue
		push_warning(
			"Steering: %s stage %d incomplete; using the docs/06 §3 row" % [TABLE_PATH, stage]
		)
		rows[stage] = (FALLBACK_TABLE[stage] as Dictionary).duplicate()
	return rows


## ctx.path, normalized to the GameState id shape ("" when unassigned).
func _path_of(ctx: Dictionary) -> String:
	return String(ctx.get("path", "")).strip_edges()


## The keep vector bound to a narrative path ("" for an unassigned path and for
## a prompt-only fallback path — dose.json `path_vectors: null`, D21).
func _vector_for(path: String) -> String:
	if _path_vectors.is_empty():
		_path_vectors = FALLBACK_PATH_VECTORS.duplicate(true)
	return String(_path_vectors.get(path, ""))


## The scheduled path-slot weight: the bound vector's stage-`stage` curve when
## a keep vector applies, the row's interim `path_mix` while the path is
## unassigned, 0 once a prompt-only fallback path is named (D21: no vector at
## all — it never reads the interim row either). A bound curve may be signed:
## `lucid` runs negative (paths.json `anchors.lucid`).
func _weight(vector: String, path: String, stage: int, row: Dictionary) -> float:
	if vector.is_empty():
		if path.is_empty():
			return float(row[PATH_MIX_KEY])
		return 0.0
	if _weight_curves.is_empty():
		_weight_curves = FALLBACK_WEIGHT_CURVES.duplicate(true)
	var curve: Variant = _weight_curves.get(vector)
	if curve is Dictionary:
		var weight: Variant = (curve as Dictionary).get(stage)
		if weight != null:
			return float(weight)
	push_warning(
		"Steering: no %s curve weight for stage %d — using the interim row" % [vector, stage]
	)
	return float(row[PATH_MIX_KEY])


## dose.json `path_vectors` -> {narrative path: vector}. Keys are only the six
## GameState.PATHS ids; a non-string value (the data files use null) is a
## prompt-only path and stores no entry. A path the file does not name keeps
## the docs/06 §2 fallback map when the file carries no `path_vectors` block at
## all — a missing block degrades, an explicit null decides (D21).
func _map_from(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return FALLBACK_PATH_VECTORS.duplicate(true)
	var map := {}
	for path_id: Variant in raw:
		var vector: Variant = raw[path_id]
		if vector is String and not String(vector).is_empty():
			map[String(path_id)] = String(vector)
	return map


## dose.json `weight_curves` -> {vector: {stage int: weight float}}. Weights
## keep the sign the data file wrote (lucid's curve is negative).
func _curves_from(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return FALLBACK_WEIGHT_CURVES.duplicate(true)
	var curves := {}
	for vector: Variant in raw:
		var entries: Variant = raw[vector]
		if not entries is Dictionary:
			continue
		var curve := {}
		for stage_key: Variant in entries:
			var stage := -1
			if stage_key is int:
				stage = int(stage_key)
			elif stage_key is String and String(stage_key).is_valid_int():
				stage = int(String(stage_key))
			if stage < 0:
				continue
			curve[stage] = float(entries[stage_key])
		if not curve.is_empty():
			curves[String(vector)] = curve
	return curves


func _row(stage: int) -> Dictionary:
	if _table.is_empty():
		_table = FALLBACK_TABLE.duplicate(true)
	var row: Variant = _table.get(clampi(stage, 0, 5))
	if row is Dictionary:
		return row
	return FALLBACK_TABLE[0]


func _stage_of(ctx: Dictionary) -> int:
	var raw: Variant = ctx.get("stage", 0)
	if raw is int:
		return clampi(raw, 0, 5)
	if raw is float:
		return clampi(int(raw), 0, 5)
	if raw is String and String(raw).is_valid_int():
		return clampi(int(String(raw)), 0, 5)
	return 0


func _settings_level() -> String:
	if not is_inside_tree():
		return ""
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return ""
	var level: Variant = settings.get("content_level")
	return String(level) if level is String else ""
