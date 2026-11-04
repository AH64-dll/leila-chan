extends Node
## SpriteResolver — feeling x intensity x stage x path x flags -> sprite (docs/03 §3).
## P2.14 completes the T2-T3 side: the base table's T2/T3 rows are live, YANDERE and
## AWAKE path overrides resolve against the sprite's documented tier, the YANDERE
## reveal budget is scene-scoped, corrupt faces get path-aware siblings, and every
## sprite change carries its docs/10 §3 on-enter effects.
##
## Two signals: `beat_resolved` carries the routed packet, `sprite_entered` carries the
## on-enter effects the instant the face actually changes (the Director fires them —
## engine-owned sound groups are not the model's budget to spend).

signal beat_resolved(packet: Dictionary)
signal sprite_entered(events: Dictionary)

const CASTING_PATH := "res://data/casting.json"
const SPRITE_DIR := "res://assets/sprites/leila/"
## docs/03 §3 step 4: "same sprite 3 beats in a row" -> sibling. The window is the
## two beats that precede the current one.
const ANTI_REPEAT_WINDOW := 2
const TIER_ORDER: PackedStringArray = ["T0", "T1", "T2", "T3"]
## docs/10 §3 below-stage variants and budget wording (validated by build_casting.py).
const BELOW_STAGE4 := "cue_below_stage4"
const BELOW_STAGE5 := "fx_below_stage5"
const TERMINAL_CLIMAX := "terminal climax only"

## The whole casting table, loaded at boot. Tests and tools read it from here so
## casting.json stays the single source (role playbook: never fork tables into code).
var casting: Dictionary = {}

var _min_tier := {}  # sprite_id -> earliest tier index (0-3) the sprite can appear at
var _recent: PackedStringArray = []  # sprites actually shown, for anti-repeat
## docs/10 §3 budget, scene-scoped: sprite id -> times that face appeared this scene.
## "1 reveal per scene" on 21 lives here, not in resolve() — resolve() stays pure.
var _reveals: Dictionary = {}
var _last_entered := ""  # sprite whose on-enter effects fired last ("" = none yet)


func _ready() -> void:
	reload()


## (Re)loads a casting table and derives the resolver's index tables. `path` is the
## test/tool seam — the game always loads CASTING_PATH.
func reload(path := CASTING_PATH) -> void:
	casting = _load_json(path)
	_min_tier = _derive_min_tiers()
	reset_scene()


## docs/03 §3 step 1: tier = T0 (st 0-1) | T1 (st 2) | T2 (st 3) | T3 (st 4-5),
## read from casting.tiers so the table stays authoritative. "" when out of range.
func tier_for_stage(stage: int) -> String:
	for key: String in casting.get("tiers", {}):
		var span: Array = casting["tiers"][key]
		if stage >= int(span[0]) and stage <= int(span[1]):
			return key
	return ""


## docs/03 §3 steps 1-3, pure: no history, no side effects. Every cell of the
## table-driven test resolves through this.
func resolve(feeling: String, intensity: int, stage: int, path := "", flags := {}) -> String:
	return _resolve_excluding(feeling, intensity, stage, path, flags, "")


## docs/03 §3 full pipeline for one streamed beat: resolve() + the scene-scoped
## reveal budget, step 4 anti-repeat, the docs/10 §3 on-enter effects and the AWAKE
## glitch rule. Returns the packet the Director routes.
func resolve_beat(
	feeling: String, intensity: int, stage: int, path := "", flags := {}
) -> Dictionary:
	var tier := tier_for_stage(stage)
	var sprite := resolve(feeling, intensity, stage, path, flags)
	var budget_spent := ""
	var cap := _reveal_cap(sprite)
	if cap > 0 and int(_reveals.get(sprite, 0)) >= cap:
		# docs/03 §3 step 3 / docs/03 §1: 21 is a once-per-scene reveal. The next
		# candidate wins (the feeling's own T3 face) — never the fallback face.
		budget_spent = sprite
		sprite = _resolve_excluding(feeling, intensity, stage, path, flags, sprite)

	var anti_repeated := false
	if _recent.size() >= ANTI_REPEAT_WINDOW and _recent[-1] == sprite and _recent[-2] == sprite:
		var sibling := _sibling_for(feeling, sprite, tier, flags)
		if not sibling.is_empty():
			sprite = sibling
			anti_repeated = true
	_recent.push_back(sprite)
	while _recent.size() > ANTI_REPEAT_WINDOW:
		_recent.remove_at(0)
	_reveals[sprite] = int(_reveals.get(sprite, 0)) + 1

	var packet := _beat_packet(feeling, intensity, stage, tier, sprite, path)
	packet["anti_repeated"] = anti_repeated
	if not budget_spent.is_empty():
		packet["budget_spent"] = budget_spent
	var events := _entry_events(sprite, stage, path)
	packet["on_enter_events"] = events
	var changed := sprite != _last_entered
	_last_entered = sprite
	# docs/10 §4 AWAKE: "glitch shader on every sprite change" — the shader itself is
	# P2.15's; the resolver reports the intent so the beat and the visual never disagree.
	packet["shader"] = _path_shader(path, tier) if changed else ""
	beat_resolved.emit(packet)
	if changed:
		sprite_entered.emit(events)
	return packet


## P0 gate C7: repo-relative casting paths -> res:// paths (docs/07 §2 "Bridged
## data"). Returns "" for paths that are repo-side only (px/, _raw audio pool).
func to_res_path(repo_path: String) -> String:
	var display_dir := String(casting.get("art", {}).get("display", ""))
	if not display_dir.is_empty() and repo_path.begins_with(display_dir + "/"):
		return SPRITE_DIR + repo_path.get_file()
	var palette := String(casting.get("art", {}).get("palette", ""))
	if not palette.is_empty() and repo_path == palette:
		return SPRITE_DIR + palette.get_file()
	return ""


## sprite id -> res:// texture path (C7: the mapping every sprite is tested through).
func sprite_texture_path(sprite_id: String) -> String:
	var repo_file := String(casting.get("sprites", {}).get(sprite_id, {}).get("file", ""))
	return to_res_path(repo_file)


## New scene / new date / tests: forgets the anti-repeat window, the per-scene
## reveal budget and the last on-enter face.
func reset_scene() -> void:
	_recent.clear()
	_reveals.clear()
	_last_entered = ""


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("SpriteResolver: missing " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary:
		return data
	push_error("SpriteResolver: " + path + " is not a JSON object")
	return {}


## Earliest tier each sprite may appear at. casting.sprites[id].tiers is the
## documented range (docs/03 §1, generated by build_casting.py) and wins outright —
## derivation would wrongly lower a path-only face like 21 to the path's T2. Only
## sprites a hand/mock table does not describe fall back to the earliest tier the
## tables cast them at.
func _derive_min_tiers() -> Dictionary:
	var best := {}
	var derived := {}
	for sprite_id: String in casting.get("sprites", {}):
		for tier: Variant in casting["sprites"][sprite_id].get("tiers", []):
			_note_tier(best, sprite_id, String(tier))
	for feeling: String in casting.get("feelings", {}):
		for tier: String in casting["feelings"][feeling].get("tiers", {}):
			for i: String in casting["feelings"][feeling]["tiers"][tier].get("sprite", {}):
				_note_tier(derived, casting["feelings"][feeling]["tiers"][tier]["sprite"][i], tier)
	for path_name: String in casting.get("paths", {}):
		var spec: Dictionary = casting["paths"][path_name]
		for tier: String in spec.get("tiers", []):
			for pool: String in ["override", "flagged", "break", "idealize", "devalue", "drift_to"]:
				var ids: Variant = spec.get(pool, {})
				for key: Variant in ids:
					var ids_any: Variant = ids[key] if ids is Dictionary else key
					var ids_list: Array = ids_any if ids_any is Array else [ids_any]
					_note_tier(derived, String(ids_list[0]), tier)
	for tier: String in casting.get("fallback", {}):
		_note_tier(derived, casting["fallback"][tier], tier)
	for sprite_id: String in derived:
		if not best.has(sprite_id):
			best[sprite_id] = derived[sprite_id]
	return best


func _note_tier(best: Dictionary, sprite_id: String, tier: String) -> void:
	var idx := TIER_ORDER.find(tier)
	if idx < 0:
		return
	if not best.has(sprite_id) or idx < best[sprite_id]:
		best[sprite_id] = idx


## docs/03 §3 step 2: PATH_OVERRIDE[path][tier][feeling] ?? BASE — path rows only
## exist for the tiers they list (T2/T3 in casting.json, so inert at T0-T1). A
## flagged row ("warmth -> 27 *if* rival_gone") wins over the generic override and
## is only returned once its flag is set.
func _path_candidate(feeling: String, tier: String, path: String, flags: Dictionary) -> String:
	if path.is_empty():
		return ""
	var spec: Dictionary = casting.get("paths", {}).get(path, {})
	if spec.is_empty() or not tier in spec.get("tiers", []):
		return ""
	var flagged: Dictionary = spec.get("flagged", {})
	if flagged.has(feeling):
		var pair: Array = flagged[feeling]
		if bool(flags.get(String(pair[1]), false)):
			return String(pair[0])
	return String(spec.get("override", {}).get(feeling, ""))


func _base_sprite(feeling: String, tier: String, intensity: int) -> String:
	var entry: Dictionary = casting.get("feelings", {}).get(feeling, {})
	if entry.is_empty():
		return ""
	var col := clampi(intensity, 1, 3)
	return String(entry.get("tiers", {}).get(tier, {}).get("sprite", {}).get(str(col), ""))


## docs/03 §3 step 3 gates for a *candidate* (path override or sibling swap):
## the sprite's documented minimum tier (docs/03 §1) and any sprite-level flag
## (27 needs rival_gone). Base-table cells are not tier-gated — docs/03 §3.1 is
## the table, and it casts 16 at T0 i3 on purpose.
func _candidate_gated(sprite_id: String, tier: String, flags: Dictionary) -> bool:
	if int(_min_tier.get(sprite_id, 99)) > TIER_ORDER.find(tier):
		return true
	return not _flag_ok(sprite_id, flags)


func _flag_ok(sprite_id: String, flags: Dictionary) -> bool:
	var flag := String(
		casting.get("sprites", {}).get(sprite_id, {}).get("on_enter", {}).get("flag", "")
	)
	return flag.is_empty() or bool(flags.get(flag, false))


func _fallback_for(tier: String) -> String:
	return String(casting.get("fallback", {}).get(tier, "00"))


## docs/03 §3 step 4: the family's sibling. Healthy repeats use casting.siblings
## (mood family, ids 01-20); corrupt repeats use casting.siblings_corrupt, because
## a corrupted face can never quietly turn healthy. A swap never crosses the band.
func _sibling_for(feeling: String, repeated: String, tier: String, flags: Dictionary) -> String:
	var sibling := ""
	if _is_corrupt(repeated):
		sibling = String(casting.get("siblings_corrupt", {}).get(repeated, ""))
	else:
		sibling = String(casting.get("siblings", {}).get(feeling, ""))
	if sibling.is_empty() or sibling == repeated:
		return ""
	if _is_corrupt(sibling) != _is_corrupt(repeated):
		return ""
	if _candidate_gated(sibling, tier, flags):
		return ""
	return sibling


## A sprite is "corrupt" when its documented tier starts at T2+ (healthy ids
## reach T0-T1).
func _is_corrupt(sprite_id: String) -> bool:
	return int(_min_tier.get(sprite_id, 99)) >= TIER_ORDER.find("T2")


## docs/10 §3 budget, parsed from the data: "1 reveal per scene" -> 1. The
## "terminal climax only" wording scopes the effects instead (see _entry_events),
## so it yields no sprite-level cap.
func _reveal_cap(sprite_id: String) -> int:
	var budget := String(
		casting.get("sprites", {}).get(sprite_id, {}).get("on_enter", {}).get("budget", "")
	)
	if budget.is_empty():
		return 0
	var head := budget.split(" ")[0]
	return int(head) if head.is_valid_int() else 0


## Pure resolution with one sprite banned: `exclude` is how the reveal budget
## steps past an already-spent face without leaving the table.
func _resolve_excluding(
	feeling: String, intensity: int, stage: int, path: String, flags: Dictionary, exclude: String
) -> String:
	var tier := tier_for_stage(stage)
	if tier.is_empty():
		return "00"
	var candidate := _path_candidate(feeling, tier, path, flags)
	if candidate == exclude:
		candidate = ""
	if not candidate.is_empty() and not _candidate_gated(candidate, tier, flags):
		return candidate
	var base := _base_sprite(feeling, tier, intensity)
	if base == exclude:
		base = ""
	if not base.is_empty():
		return base
	return _fallback_for(tier)


## docs/10 §3: the extra sound / music / fx / motion the instant a sprite appears.
## Below-stage variants apply first (22's cue under stage 4, 30's fx under stage 5),
## then the budget: "terminal climax only" withholds the `system` sting below stage 5.
## `withheld` records what a stage rule dropped, so a silent cut is never invisible.
func _entry_events(sprite_id: String, stage: int, path: String) -> Dictionary:
	var spec: Dictionary = casting.get("sprites", {}).get(sprite_id, {}).get("on_enter", {})
	var events := {
		"sprite": sprite_id,
		"stage": stage,
		"path": path,
		"cue": "",
		"system": [],
		"fx": "",
		"music": "",
		"motion": "",
		"withheld": [],
	}
	if spec.is_empty():
		return events
	var cue := String(spec.get("cue", ""))
	if stage < 4 and spec.has(BELOW_STAGE4):
		cue = String(spec[BELOW_STAGE4])
	events["cue"] = cue
	var systems: Array = []
	var climax_only := String(spec.get("budget", "")) == TERMINAL_CLIMAX
	if spec.has("system") and not (climax_only and stage < 5):
		systems = (spec["system"] as Array).duplicate()
	elif spec.has("system"):
		(events["withheld"] as Array).append("system:terminal_climax")
	events["system"] = systems
	var fx := String(spec.get("fx", ""))
	if stage < 5 and spec.has(BELOW_STAGE5):
		fx = String(spec[BELOW_STAGE5])
	events["fx"] = fx
	events["music"] = String(spec.get("music", ""))
	events["motion"] = String(spec.get("motion", ""))
	return events


## docs/10 §4's data-side rule for a path at this tier (AWAKE's "glitch shader on
## every sprite change" is casting.paths.AWAKE.shader). "" when the path is inert.
func _path_shader(path: String, tier: String) -> String:
	if path.is_empty():
		return ""
	var spec: Dictionary = casting.get("paths", {}).get(path, {})
	if spec.is_empty() or not tier in spec.get("tiers", []):
		return ""
	return String(spec.get("shader", ""))


## Everything a beat needs besides the sprite: motion (and its intensity amplitude),
## tint, fx/cues/music pools, the sprite's on_enter effects (docs/10 §3; its "motion"
## wins over the feeling's intensity motion) and the intensity-3 camera push
## (casting.intensity_3).
func _beat_packet(
	feeling: String, intensity: int, stage: int, tier: String, sprite_id: String, path: String
) -> Dictionary:
	var entry: Dictionary = casting.get("feelings", {}).get(feeling, {})
	var row: Dictionary = entry.get("tiers", {}).get(tier, {})
	var col := str(clampi(intensity, 1, 3))
	var on_enter: Dictionary = casting.get("sprites", {}).get(sprite_id, {}).get("on_enter", {})
	return {
		"feeling": feeling,
		"intensity": intensity,
		"stage": stage,
		"tier": tier,
		"path": path,
		"sprite": sprite_id,
		"motion": String(on_enter.get("motion", entry.get("motion", {}).get(col, "breathe"))),
		"motion_scale": float(casting.get("motion_intensity", {}).get(col, 1.0)),
		"tint": String(entry.get("tint", "")),
		"valence": int(entry.get("valence", 0)),
		"fx": row.get("fx", []),
		"cues": row.get("cues", []),
		"music": String(row.get("music", "keep")),
		"on_enter": on_enter,
		"camera": _i3_camera(intensity),
	}


## casting.intensity_3.camera is prose ("push to bust_crop"); map it to a camera
## preset name the Character scene understands ("" when no push).
func _i3_camera(intensity: int) -> String:
	if intensity < 3:
		return ""
	var text := String(casting.get("intensity_3", {}).get("camera", ""))
	return "bust" if "bust" in text else ""
