extends SceneTree
## P0.08 asset/data bridge test — run headless:
##   ./tools/godot.sh --headless --path game --script res://tests/test_bridge.gd
## Exits 0 when every check passes.

const SPRITE_DIR := "res://assets/sprites/leila/"

var _failures := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


## docs/03 §3 step 1: tier = T0 (st 0-1) | T1 (st 2) | T2 (st 3) | T3 (st 4-5),
## read from casting.json "tiers" so the table stays the source of truth.
func _tier_for_stage(tiers: Dictionary, stage: int) -> String:
	for key: Variant in tiers:
		var span: Array = tiers[key]
		if stage >= int(span[0]) and stage <= int(span[1]):
			return String(key)
	return ""


## docs/03 §3 step 2 (base table): feeling x tier x intensity -> sprite id.
func _resolve_sprite(casting: Dictionary, feeling: String, tier: String, intensity: int) -> String:
	var entry: Dictionary = casting["feelings"].get(feeling, {})
	var span: Dictionary = entry.get("tiers", {}).get(tier, {})
	return String(span.get("sprite", {}).get(str(intensity), ""))


func _sprite_file(casting: Dictionary, sprite_id: String) -> String:
	return String(casting["sprites"].get(sprite_id, {}).get("file", "")).get_file()


func _initialize() -> void:
	var casting: Variant = _load_json("res://data/casting.json")
	_check(casting is Dictionary, "res://data/casting.json loads and parses")
	if casting is Dictionary:
		var tier := _tier_for_stage(casting["tiers"], 0)
		_check(tier == "T0", "stage 0 resolves to tier T0")

		var sprite_id := _resolve_sprite(casting, "joy", tier, 1)
		_check(sprite_id == "01", "joy / T0 / intensity 1 -> sprite 01 (got %s)" % sprite_id)

		var tex := ResourceLoader.load(SPRITE_DIR + _sprite_file(casting, sprite_id))
		_check(tex is CompressedTexture2D, "sprite 01 imports and loads as texture")
		if tex is CompressedTexture2D:
			_check(tex.get_width() == 768 and tex.get_height() == 1376,
				"sprite 01 is the x2 768x1376 art")

		## Table-driven sweep: every feeling x tier x intensity resolves to a
		## sprite id whose file exists on disk (docs/03 §3.1 base table).
		var cells := 0
		var resolve_ok := true
		for feeling: Variant in casting["feelings"]:
			for t: Variant in casting["feelings"][feeling]["tiers"]:
				for intensity: int in 3:
					var sid := _resolve_sprite(casting, String(feeling), String(t), intensity + 1)
					cells += 1
					if sid == "" or _sprite_file(casting, sid) == "" \
							or not FileAccess.file_exists(SPRITE_DIR + _sprite_file(casting, sid)):
						printerr("  unresolved cell: ", feeling, " ", t, " i", intensity + 1, " -> '", sid, "'")
						resolve_ok = false
		_check(resolve_ok, "all %d feeling x tier x intensity cells resolve to files" % cells)

		## Path overrides (docs/03 §3.2): every override + flagged sprite id exists.
		var path_ok := true
		var paths: Dictionary = casting.get("paths", {})
		for path_name: Variant in paths:
			for feeling: Variant in paths[path_name].get("override", {}):
				var sid := String(paths[path_name]["override"][feeling])
				if _sprite_file(casting, sid) == "" \
						or not FileAccess.file_exists(SPRITE_DIR + _sprite_file(casting, sid)):
					printerr("  override missing sprite: ", path_name, " ", feeling, " -> '", sid, "'")
					path_ok = false
			for feeling: Variant in paths[path_name].get("flagged", {}):
				var sid := String(paths[path_name]["flagged"][feeling][0])
				if _sprite_file(casting, sid) == "" \
						or not FileAccess.file_exists(SPRITE_DIR + _sprite_file(casting, sid)):
					printerr("  flagged missing sprite: ", path_name, " ", feeling, " -> '", sid, "'")
					path_ok = false
		_check(path_ok, "all path override + flagged sprite ids resolve to files")

		## All 31 sprites: file exists, imports as a texture, mipmaps off.
		var sprites: Dictionary = casting["sprites"]
		var all_ok := true
		for key: Variant in sprites:
			var name := String(sprites[key]["file"]).get_file()
			if not FileAccess.file_exists(SPRITE_DIR + name):
				printerr("  missing file: ", name)
				all_ok = false
				continue
			var res := ResourceLoader.load(SPRITE_DIR + name)
			if not (res is CompressedTexture2D):
				printerr("  not an imported texture: ", name)
				all_ok = false
			var cfg := ConfigFile.new()
			if cfg.load(SPRITE_DIR + name + ".import") != OK:
				printerr("  missing .import: ", name)
				all_ok = false
			elif cfg.get_value("params", "mipmaps/generate", true) != false:
				printerr("  mipmaps enabled: ", name)
				all_ok = false
		_check(sprites.size() == 31, "casting.json lists 31 sprites (got %d)" % sprites.size())
		_check(all_ok, "all 31 sprites exist, load as textures, mipmaps off")

	## Godot 4 has no per-import 2D filter: Nearest is the project default,
	## and sprites inherit it (art/leila/README "Filter: Nearest").
	_check(ProjectSettings.get_setting(
			"rendering/textures/canvas_textures/default_texture_filter") == 0,
		"project default texture filter = Nearest")

	_check(_load_json("res://data/cue_map.json") is Dictionary,
		"res://data/cue_map.json loads and parses")
	_check(_load_json(SPRITE_DIR + "palette.json") is Dictionary,
		"res://assets/sprites/leila/palette.json loads and parses")

	if _failures == 0:
		print("test_bridge: all checks passed")
	quit(1 if _failures > 0 else 0)
