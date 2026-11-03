extends Node
## SpriteResolver — feeling x intensity x stage x path x flags -> sprite (docs/03 §3).
## T0-T1 scope for P1.10: base table, flag/min_tier gates, anti-repeat and fallback
## are live for every tier. Path overrides, sibling corruption bands and dissonance
## only matter at T2+; the machinery already reads them from casting.json so P2.14
## adds path rules without touching this pipeline.

signal beat_resolved(packet: Dictionary)

const CASTING_PATH := "res://data/casting.json"
const SPRITE_DIR := "res://assets/sprites/leila/"
## docs/03 §3 step 4: "same sprite 3 beats in a row" -> sibling. The window is the
## two beats that precede the current one.
const ANTI_REPEAT_WINDOW := 2
const TIER_ORDER: PackedStringArray = ["T0", "T1", "T2", "T3"]

## The whole casting table, loaded at boot. Tests and tools read it from here so
## casting.json stays the single source (role playbook: never fork tables into code).
var casting: Dictionary = {}

var _min_tier := {}  # sprite_id -> earliest tier index (0-3) the sprite can appear at
var _recent: PackedStringArray = []  # sprites actually shown, for anti-repeat


func _ready() -> void:
	reload()


## (Re)loads casting.json and derives the resolver's index tables.
func reload() -> void:
	casting = _load_json(CASTING_PATH)
	_min_tier = _derive_min_tiers()
	_recent.clear()


## docs/03 §3 step 1: tier = T0 (st 0-1) | T1 (st 2) | T2 (st 3) | T3 (st 4-5),
## read from casting.tiers so the table stays authoritative. "" when out of range.
func tier_for_stage(stage: int) -> String:
	for key: String in casting.get("tiers", {}):
		var span: Array = casting["tiers"][key]
		if stage >= int(span[0]) and stage <= int(span[1]):
			return key
	return ""


## docs/03 §3 steps 1-3 + 6, pure: no history, no side effects. Every cell of the
## table-driven test resolves through this.
func resolve(feeling: String, intensity: int, stage: int, path := "", flags := {}) -> String:
	var tier := tier_for_stage(stage)
	if tier.is_empty():
		return "00"
	var candidate := _path_candidate(feeling, tier, path, flags)
	if candidate.is_empty():
		candidate = _base_sprite(feeling, tier, intensity)
	if candidate.is_empty() or _gated(candidate, tier, flags):
		return _fallback_for(tier)
	return candidate


## docs/03 §3 full pipeline for one streamed beat: resolve() + step 4 anti-repeat,
## returning the packet the Director routes (sprite, motion, fx, cues, music, tint).
## Step 5 dissonance is stage >= 3 and needs the beat text: P2.14's job.
func resolve_beat(
	feeling: String, intensity: int, stage: int, path := "", flags := {}
) -> Dictionary:
	var tier := tier_for_stage(stage)
	var sprite := resolve(feeling, intensity, stage, path, flags)
	var anti_repeated := false
	if _recent.size() >= ANTI_REPEAT_WINDOW and _recent[-1] == sprite and _recent[-2] == sprite:
		var sibling := _sibling_for(feeling, sprite, tier, flags)
		if not sibling.is_empty():
			sprite = sibling
			anti_repeated = true
	_recent.push_back(sprite)
	while _recent.size() > ANTI_REPEAT_WINDOW:
		_recent.remove_at(0)

	var packet := _beat_packet(feeling, intensity, stage, tier, sprite)
	packet["anti_repeated"] = anti_repeated
	beat_resolved.emit(packet)
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


## Clears the anti-repeat window (new scene, new date, tests).
func reset_repeat() -> void:
	_recent.clear()


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


## Earliest tier each sprite is reachable at: base cells, path overrides/flagged/
## break/drift pools and the fallback table all count as "reachable".
func _derive_min_tiers() -> Dictionary:
	var best := {}
	for feeling: String in casting.get("feelings", {}):
		for tier: String in casting["feelings"][feeling].get("tiers", {}):
			for i: String in casting["feelings"][feeling]["tiers"][tier].get("sprite", {}):
				_note_tier(best, casting["feelings"][feeling]["tiers"][tier]["sprite"][i], tier)
	for path_name: String in casting.get("paths", {}):
		var spec: Dictionary = casting["paths"][path_name]
		for tier: String in spec.get("tiers", []):
			for pool: String in ["override", "flagged", "break", "idealize", "devalue", "drift_to"]:
				var ids: Variant = spec.get(pool, {})
				for key: Variant in ids:
					var ids_any: Variant = ids[key] if ids is Dictionary else key
					var ids_list: Array = ids_any if ids_any is Array else [ids_any]
					_note_tier(best, String(ids_list[0]), tier)
	for tier: String in casting.get("fallback", {}):
		_note_tier(best, casting["fallback"][tier], tier)
	return best


func _note_tier(best: Dictionary, sprite_id: String, tier: String) -> void:
	var idx := TIER_ORDER.find(tier)
	if idx < 0:
		return
	if not best.has(sprite_id) or idx < best[sprite_id]:
		best[sprite_id] = idx


## docs/03 §3 step 2: PATH_OVERRIDE[path][tier][feeling] ?? BASE — path rows only
## exist for the tiers they list (all T2+ in casting.json, so inert at T0-T1).
func _path_candidate(feeling: String, tier: String, path: String, flags: Dictionary) -> String:
	if path.is_empty():
		return ""
	var spec: Dictionary = casting.get("paths", {}).get(path, {})
	if spec.is_empty() or not tier in spec.get("tiers", []):
		return ""
	# flagged override first: "warmth -> 27 *if* rival_gone" beats a generic override.
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


## docs/03 §3 step 3 gates: the sprite must be reachable at this tier, and a
## flag-gated sprite (27: rival_gone) needs its flag set.
func _gated(sprite_id: String, tier: String, flags: Dictionary) -> bool:
	if int(_min_tier.get(sprite_id, 99)) > TIER_ORDER.find(tier):
		return true
	var flag := String(
		casting.get("sprites", {}).get(sprite_id, {}).get("on_enter", {}).get("flag", "")
	)
	return not flag.is_empty() and not bool(flags.get(flag, false))


func _fallback_for(tier: String) -> String:
	return String(casting.get("fallback", {}).get(tier, "00"))


## docs/03 §3 step 4: the family's sibling. casting.siblings only holds healthy
## faces, and a swap never crosses the healthy/corrupt band (a corrupted face can
## never quietly become a healthy one).
func _sibling_for(feeling: String, repeated: String, tier: String, flags: Dictionary) -> String:
	var sibling := String(casting.get("siblings", {}).get(feeling, ""))
	if sibling.is_empty() or sibling == repeated or _gated(sibling, tier, flags):
		return ""
	if _is_corrupt(sibling) != _is_corrupt(repeated):
		return ""
	return sibling


## A sprite is "corrupt" when it can only appear at T2+ (healthy ids reach T0-T1).
func _is_corrupt(sprite_id: String) -> bool:
	return int(_min_tier.get(sprite_id, 99)) >= TIER_ORDER.find("T2")


## Everything a beat needs besides the sprite: motion, tint, fx/cues/music pools,
## the sprite's on_enter effects (docs/10 §3; its "motion" wins over the feeling's
## intensity motion) and the intensity-3 camera push (casting.intensity_3).
func _beat_packet(
	feeling: String, intensity: int, stage: int, tier: String, sprite_id: String
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
		"sprite": sprite_id,
		"motion": String(on_enter.get("motion", entry.get("motion", {}).get(col, "breathe"))),
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
