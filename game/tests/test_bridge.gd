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


func _initialize() -> void:
	var casting: Variant = _load_json("res://data/casting.json")
	_check(casting is Dictionary, "res://data/casting.json loads and parses")
	if casting is Dictionary:
		var tier := _tier_for_stage(casting["tiers"], 0)
		_check(tier == "T0", "stage 0 resolves to tier T0")

		## docs/03 §3 step 2: feeling x tier x intensity -> sprite id.
		var feelings: Dictionary = casting["feelings"]
		var sprite_id := String(feelings["joy"]["tiers"][tier]["sprite"]["1"])
		_check(sprite_id == "01", "joy / T0 / intensity 1 -> sprite 01 (got %s)" % sprite_id)

		var sprites: Dictionary = casting["sprites"]
		var sprite_file := String(sprites[sprite_id]["file"]).get_file()
		var tex := ResourceLoader.load(SPRITE_DIR + sprite_file)
		_check(tex is CompressedTexture2D,
			"sprite 01 file %s imports and loads" % sprite_file)
		if tex is CompressedTexture2D:
			_check(tex.get_width() == 768 and tex.get_height() == 1376,
				"sprite 01 is the x2 768x1376 art")

		## All casting sprite ids resolve to an imported, mipmaps-off texture.
		var n := 0
		var all_ok := true
		for key: Variant in sprites:
			var name := String(sprites[key]["file"]).get_file()
			n += 1
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
		_check(n == 31, "casting.json lists 31 sprites (got %d)" % n)
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
