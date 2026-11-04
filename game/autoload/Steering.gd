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
## result. Two keys are scheduled in P2, both llama.cpp vector scales:
##   malice   — the tweet-malice scale (docs/06 §1 curve, docs/02 §9 base column)
##   path_mix — the stage's path-vector weight, the §3 `path_mix` term. Interim:
##              the real vectors are possessive/unstable/contempt/hollow/aware/
##              lucid (docs/06 §2) and P3.04 replaces this one number with the
##              locked path's vector name(s) and their own weight curves.
##
## Both keys are scales in [0, 12]. The clamp is a **code rule** (docs/06 §3/§5):
## no data file can widen it. The calmer-mode cap (docs/06 §5, docs/02 §8) is the
## stage-3 row of the same table applied after the modifiers, so retuning stage 3
## moves the calmer ceiling with it — docs/06 §5 defines calmer as "stage-3
## levels". The stage numbers live in `game/data/steering/dose.json`; the
## docs/06 §3 table is the in-code fallback, so a broken data file degrades to the
## documented values.
##
## Prototype limit (docs/06 §4): the dose is a llama-server *launch flag*, so it
## only changes when the stage-change restart relaunches the server. Per-turn
## spikes (+3..+4 for 1–2 turns) therefore cannot be applied yet — see
## `spike_for()`. The shipping GDExtension applies them with
## `llama_set_adapter_cvec` before decoding (P4.03).

const TABLE_PATH := "res://data/steering/dose.json"

## docs/06 §2 vector name; also docs/02 §9's "steering dose (base)" column.
const MALICE_KEY := "malice"
## docs/06 §3's `path_mix` term as one weight for the locked path. Interim: P3.04
## replaces it with that path's own vector name (docs/06 §2). Deliberately not
## `path` — that name already means the narrative path (`GameState.path`, the
## ctx's `path`, the F3 panel's `Path:` line) and the control-vector *file* in
## the launcher's `control_vectors` entries.
const PATH_MIX_KEY := "path_mix"

const DOSE_MIN := 0.0
const DOSE_MAX := 12.0

## docs/02 §8 + docs/06 §5: calmer mode never goes past the stage-3 schedule.
const CALMER_LEVEL := "calmer"
const CALMER_STAGE := 3

## docs/06 §3 spike term; P4.03 turns it live with the runtime cvec path.
const SPIKE_MAX := 4.0
const SPIKES_LIVE := false

## docs/06 §3 stage table (malice scale, path-vector weight), in-code fallback.
const FALLBACK_TABLE := {
	0: {MALICE_KEY: 0.0, PATH_MIX_KEY: 0.0},
	1: {MALICE_KEY: 2.5, PATH_MIX_KEY: 1.0},
	2: {MALICE_KEY: 3.5, PATH_MIX_KEY: 2.0},
	3: {MALICE_KEY: 4.5, PATH_MIX_KEY: 3.0},
	4: {MALICE_KEY: 6.0, PATH_MIX_KEY: 4.0},
	5: {MALICE_KEY: 8.0, PATH_MIX_KEY: 5.0},
}

var _table: Dictionary = {}


func _ready() -> void:
	reload_table()


## The control-vector scales for this turn, e.g.
## `{"malice": 4.5, "path_mix": 3.0}` — the shape `TurnRequest.dose` documents.
## Never empty: an unknown stage falls back to stage 0.
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
	var path_mix := float(row[PATH_MIX_KEY])

	# docs/02 §8 "caps stage at 3": compare component by component, so a calmer
	# stage-5 turn is exactly a stage-3 turn — at the ceiling, not below it. The
	# cap runs after the modifiers so a scene kick cannot climb past it either.
	var calmer := is_calmer_mode(ctx)
	var capped := false
	if calmer:
		var cap := _row(CALMER_STAGE)
		capped = malice > float(cap[MALICE_KEY]) or path_mix > float(cap[PATH_MIX_KEY])
		malice = minf(malice, float(cap[MALICE_KEY]))
		path_mix = minf(path_mix, float(cap[PATH_MIX_KEY]))

	malice = clampf(malice, DOSE_MIN, DOSE_MAX)
	path_mix = clampf(path_mix, DOSE_MIN, DOSE_MAX)
	return {
		"stage": stage,
		"malice": malice,
		"path_mix": path_mix,
		"spike": spike,
		"spike_requested": spike_requested,
		"scene_modifier": scene,
		"player_slider": slider,
		"calmer": calmer,
		"calmer_capped": capped,
		"clamp_min": DOSE_MIN,
		"clamp_max": DOSE_MAX,
		"dose": {MALICE_KEY: malice, PATH_MIX_KEY: path_mix},
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


## Dev-overlay rendering of a dose map: `malice 4.5/12 · path_mix 3.0`. Only the
## malice scale gets a `/12` suffix — it is the axis docs/06 §1's curve and
## docs/02 §9's table are written in; both keys are clamped to that range.
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
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary and (parsed as Dictionary).get("stages") is Dictionary):
		push_warning("Steering: %s has no stages table; using the docs/06 §3 fallback" % path)
		_table = FALLBACK_TABLE.duplicate(true)
		return false
	_table = _rows_from((parsed as Dictionary)["stages"])
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
