extends GdUnitTestSuite
## P2.15 — shader parameter sanity for the stage FX pass.
##
## The whole docs/02 §2.3 stage vocabulary is one canvas_item shader
## (stage_fx.gdshader) for a hard reason: Godot's 2D screen texture is a single
## copy per frame, so two full-screen sampling shaders cannot compose — the
## later one re-samples the pre-effect screen and erases the earlier effect.
## This suite pins the contract without a rendered frame: the shader parses,
## every uniform the host drives exists with the type it writes, ranged
## uniforms keep the look and accessibility bounds, and the host seeds its
## material explicitly instead of trusting .gdshader defaults.
##
## Note: `hint_screen_texture` samplers do not appear in
## Shader.get_shader_uniform_list(), so the screen sampler is checked in the
## code text instead.

const STAGE_SHADER := "res://shaders/stage_fx.gdshader"
const SCREEN_SAMPLER := "uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;"
const CharScene := preload("res://scenes/character/Character.tscn")
const CharScript := preload("res://scenes/character/Character.gd")
const PALETTE_PATH := "res://assets/sprites/leila/palette.json"

## uniform -> expected Variant type (the type the host writes)
const UNIFORMS := {
	"desaturation": TYPE_FLOAT,
	"flicker": TYPE_FLOAT,
	"darken": TYPE_FLOAT,
	"vignette_tint": TYPE_COLOR,
	"vignette": TYPE_FLOAT,
	"vignette_inner": TYPE_FLOAT,
	"vignette_outer": TYPE_FLOAT,
	"vignette_pulse_hz": TYPE_FLOAT,
	"vignette_pulse_depth": TYPE_FLOAT,
	"glitch": TYPE_FLOAT,
	"glitch_seed": TYPE_FLOAT,
	"split": TYPE_FLOAT,
	"bleed_rect": TYPE_VECTOR4,
	"input_rect": TYPE_VECTOR4,
	"bleed": TYPE_FLOAT,
	"bleed_length": TYPE_FLOAT,
	"bleed_seed": TYPE_FLOAT,
}
## uniform -> fragment of the hint_range the shader must declare
const RANGES := {
	"desaturation": "0.0,1.0",
	"flicker": "0.0,1.0",
	"darken": "0.0,1.0",
	"vignette": "0.0,1.0",
	# the pulse ceiling is the photosensitive rule, not taste
	"vignette_pulse_hz": "0.0,2.0",
	"glitch": "0.0,1.0",
	"split": "0.0,2.0",
	"bleed": "0.0,1.0",
	"bleed_length": "0.0,0.25",
}
## uniform -> the value the host seeds on its material at boot
const HOST_SEEDS := {
	"desaturation": 0.0,
	"flicker": 1.0,
	"darken": 1.0,
	"vignette": 0.0,
	"glitch": 0.0,
	"split": 0.0,
	"bleed": 0.0,
	"vignette_pulse_hz": CharScript.FX_VIGNETTE_PULSE_HZ,
	"bleed_length": CharScript.FX_BLEED_LENGTH,
}

var _char  # untyped preload fixture, freed in after_test


func before_test() -> void:
	FX.reset()
	FX.stage = 0
	FX.photosensitive = false


func after_test() -> void:
	if is_instance_valid(_char):
		_char.queue_free()
	FX.reset()


func _uniform_entries(shader: Shader) -> Dictionary:
	var entries := {}
	for entry: Dictionary in shader.get_shader_uniform_list():
		entries[String(entry["name"])] = entry
	return entries


func test_stage_shader_parses_with_every_uniform_the_host_drives() -> void:
	var shader := load(STAGE_SHADER) as Shader
	assert_object(shader).is_not_null()
	if shader == null:
		return
	assert_bool(shader.code.begins_with("shader_type canvas_item;")).is_true()
	var entries := _uniform_entries(shader)
	assert_int(entries.size()).is_greater(0)  # an unparsed shader lists nothing
	for uniform_name: String in UNIFORMS:
		(
			assert_bool(entries.has(uniform_name))
			. append_failure_message("missing uniform %s" % uniform_name)
			. is_true()
		)
		if entries.has(uniform_name):
			(
				assert_int(int(entries[uniform_name]["type"]))
				. append_failure_message("%s type" % uniform_name)
				. is_equal(int(UNIFORMS[uniform_name]))
			)
	# no extra untyped state: the host's setters are the whole contract
	assert_int(entries.size()).is_equal(UNIFORMS.size())


func test_stage_shader_samples_the_screen_with_nearest_filtering() -> void:
	var code: String = (load(STAGE_SHADER) as Shader).code
	# pixel art: a bilinear screen sample would smear the 384x688 set
	assert_bool(code.contains(SCREEN_SAMPLER)).is_true()
	# exactly one screen sampler — a second would need a second pass, which
	# cannot compose (see the file header)
	assert_int(code.count("hint_screen_texture")).is_equal(1)


func test_ranged_uniforms_keep_the_look_and_accessibility_bounds() -> void:
	var entries := _uniform_entries(load(STAGE_SHADER) as Shader)
	for uniform_name: String in RANGES:
		(
			assert_bool(entries.has(uniform_name))
			. append_failure_message("missing %s" % uniform_name)
			. is_true()
		)
		if not entries.has(uniform_name):
			continue
		var hint_string := String(entries[uniform_name]["hint_string"])
		(
			assert_bool(hint_string.contains(String(RANGES[uniform_name])))
			. append_failure_message("%s hint '%s'" % [uniform_name, hint_string])
			. is_true()
		)


## The host owns the final say on the safety ceiling: pulse_hz is seeded from
## the host constant, so a shader edit cannot quietly raise the flash rate.
func test_host_pins_the_vignette_pulse_below_the_flash_limit() -> void:
	_char = CharScene.instantiate()
	get_tree().root.add_child(_char)
	await get_tree().process_frame
	var mat: ShaderMaterial = _char.get_node("OverlayFX/StageFX").material
	var pulse_hz := float(mat.get_shader_parameter("vignette_pulse_hz"))
	assert_float(pulse_hz).is_equal_approx(float(CharScript.FX_VIGNETTE_PULSE_HZ), 0.0001)
	assert_float(pulse_hz).is_less(float(CharScript.FX_FLASH_MAX_HZ))


## One rect, one material, every uniform at rest, and the pass hidden — a clean
## stage must not pay a full-screen blit.
func test_host_seeds_every_uniform_and_starts_hidden() -> void:
	_char = CharScene.instantiate()
	get_tree().root.add_child(_char)
	await get_tree().process_frame
	var rect: ColorRect = _char.get_node("OverlayFX/StageFX")
	var mat := rect.material as ShaderMaterial
	assert_object(mat).is_not_null()
	if mat == null:
		return
	assert_object(mat.shader).is_not_null()
	assert_bool(rect.visible).is_false()
	for uniform_name: String in HOST_SEEDS:
		(
			assert_float(float(mat.get_shader_parameter(uniform_name)))
			. append_failure_message("seed %s" % uniform_name)
			. is_equal_approx(float(HOST_SEEDS[uniform_name]), 0.0001)
		)


## Palette compliance for the generated shader colours: the vignette tint is a
## palette colour (docs/03 §6), and the shader keeps that value in its default.
func test_vignette_tint_is_a_palette_colour() -> void:
	var palette: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	var flat: Array = []
	for ramp: String in palette:
		flat.append_array(palette[ramp])
	var crimson := Color8(216, 50, 58)  # palette fx[0] d8323a
	(
		assert_bool(crimson.to_html(false) in flat)
		. append_failure_message("crimson is not in the palette")
		. is_true()
	)
	var code: String = (load(STAGE_SHADER) as Shader).code
	var literal := "%.3f, %.3f, %.3f" % [crimson.r, crimson.g, crimson.b]
	(
		assert_bool(code.contains(literal))
		. append_failure_message("vignette tint default is not palette fx[0] (%s)" % literal)
		. is_true()
	)
