extends GdUnitTestSuite
## P2.15 — the stage-3/4 visuals on the Character FX host: shake_big, flicker,
## darken, vignette_red, glitch and text_bleed, plus the stage baseline's
## desaturation ramp (docs/02 §2.3, docs/01 §3, docs/03 §4).
##
## Every effect is a uniform on ONE full-screen pass (see stage_fx.gdshader):
## Godot's 2D screen texture is a single copy per frame, so stacked sampling
## rects cannot compose — the later one erases the earlier. The suite therefore
## asserts uniforms and the pass's visibility, and guards the single pass.
##
## The acceptance criterion "photosensitive mode verified (no flashes > 3 Hz)"
## is checked twice: structurally on the pattern the host will play, and on the
## frames actually rendered while it plays (level sampled every frame, then
## counted for direction changes).

const CharScene := preload("res://scenes/character/Character.tscn")
const CharScript := preload("res://scenes/character/Character.gd")

var _char  # untyped so private hooks (_screen_tweens/...) resolve
var _cam: Camera2D
var _stage_fx: ColorRect
var _mat: ShaderMaterial


func before_test() -> void:
	FX.reset()
	FX.fx_overrides.clear()
	FX.stage = 0
	FX.photosensitive = false
	_char = CharScene.instantiate()
	get_tree().root.add_child(_char)
	_cam = _char.get_node("Camera2D")
	_stage_fx = _char.get_node("OverlayFX/StageFX")
	_mat = _stage_fx.material


func after_test() -> void:
	_char.queue_free()
	FX.reset()
	FX.photosensitive = false


func _wait_seconds(s: float, probe: Callable = Callable()) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()
		if probe.is_valid():
			probe.call()


## Samples a float every frame for `seconds` and keeps only the changes, as
## [[seconds, value], ...] — the luminance timeline a photosensitive check
## needs (how fast, and how far, the screen actually moved).
func _sample_timeline(seconds: float, getter: Callable) -> Array:
	var timeline := []
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var value := float(getter.call())
		if timeline.is_empty() or not is_equal_approx(float(timeline[-1][1]), value):
			timeline.append([t, value])
	return timeline


## Direction changes in a sampled timeline, ignoring wobble under `epsilon`.
## One change down and one back up = 1; a 20 Hz strobe = dozens.
func _reversals(timeline: Array, epsilon := 0.02) -> int:
	if timeline.size() < 2:
		return 0
	var reversals := 0
	var direction := 0
	var extreme := float(timeline[0][1])
	for i: int in range(1, timeline.size()):
		var value := float(timeline[i][1])
		var delta := value - extreme
		if absf(delta) < epsilon:
			continue
		var next_direction := 1 if delta > 0.0 else -1
		if direction != 0 and next_direction != direction:
			reversals += 1
		direction = next_direction
		extreme = value
	return reversals


# --- architecture guard -------------------------------------------------------


## Regression guard: the stage stack is one screen-sampling pass. A second
## sampling CanvasItem would re-sample the pre-effect frame and erase the
## stage FX (that bug is why the five per-effect rects were collapsed).
func test_exactly_one_screen_sampling_pass_exists() -> void:
	var samplers := 0
	for node: Node in _char.find_children("*", "CanvasItem", true, false):
		var canvas_item := node as CanvasItem
		var material := canvas_item.material
		if not material is ShaderMaterial:
			continue
		var shader: Shader = (material as ShaderMaterial).shader
		if shader != null and shader.code.contains("hint_screen_texture"):
			samplers += 1
	assert_int(samplers).is_equal(1)
	assert_object(_stage_fx.material).is_equal(_mat)


# --- shake_big ----------------------------------------------------------------


## docs/02 §2.3: shake_big is "0.6 s heavy shake". Heavy means a wider throw
## than shake_small's 4 px, and 0.6 s means it is still moving after small has
## already stopped (0.2 s) — then the camera must come back to rest.
func test_shake_big_is_longer_and_heavier_than_shake_small() -> void:
	assert_str(_char.play_fx("shake_big")).is_equal("")
	var probe := {"dev": 0.0}
	await _wait_seconds(
		0.25, func() -> void: probe["dev"] = maxf(float(probe["dev"]), _cam.offset.length())
	)
	assert_float(float(probe["dev"])).is_greater(3.0)
	var late := {"dev": 0.0}
	await _wait_seconds(
		0.2, func() -> void: late["dev"] = maxf(float(late["dev"]), _cam.offset.length())
	)
	assert_float(float(late["dev"])).is_greater(0.5)  # still shaking at ~0.45 s
	await _wait_seconds(0.3)
	assert_vector(_cam.offset).is_equal_approx(Vector2.ZERO, Vector2(0.001, 0.001))
	# a pure camera move: it must not force the screen pass on by itself
	assert_bool(_stage_fx.visible).is_false()


func test_shake_big_skipped_under_reduced_motion() -> void:
	_char.set_reduced_motion(true)
	assert_str(_char.play_fx("shake_big")).is_equal("reduced_motion")
	var probe := {"dev": 0.0}
	await _wait_seconds(
		0.3, func() -> void: probe["dev"] = maxf(float(probe["dev"]), _cam.offset.length())
	)
	assert_float(float(probe["dev"])).is_equal_approx(0.0, 0.0001)
	_char.set_reduced_motion(false)


# --- flicker + photosensitive mode ---------------------------------------------


## flicker, normal mode: the lights fail. The dips are fast and deep on
## purpose — which is exactly why photosensitive mode must not use this pattern.
func test_flicker_strobes_then_restores() -> void:
	assert_str(_char.play_fx("flicker")).is_equal("")
	assert_bool(_stage_fx.visible).is_true()
	var timeline: Array = await _sample_timeline(
		0.55, func() -> float: return _char.flicker_level()
	)
	var min_level := 1.0
	for entry: Array in timeline:
		min_level = minf(min_level, float(entry[1]))
	assert_float(min_level).is_less(0.4)  # the lights actually drop out
	var edges := timeline.size() - 1
	var span := maxf(float(timeline[-1][0]), 0.001)
	assert_float(edges / span).is_greater(3.0)  # a real strobe, above the 3 Hz rule
	await _wait_seconds(0.8)
	assert_float(_char.flicker_level()).is_equal_approx(1.0, 0.001)
	assert_bool(_stage_fx.visible).is_false()  # back to a clean (unlit) pass


## Acceptance criterion "photosensitive mode verified (no flashes > 3 Hz)".
func test_photosensitive_flicker_is_a_dim_not_a_strobe() -> void:
	_char.set_photosensitive(true)
	var dim: Array = _char.flicker_pattern()
	_char.set_photosensitive(false)
	var fast: Array = _char.flicker_pattern()
	assert_bool(dim != fast).is_true()
	# structural: no dim step shorter than 1/3 s, and at most two luminance
	# edges in the whole cue → at most 2 Hz against the 3 Hz limit
	for step: Array in dim:
		assert_float(float(step[0])).is_greater_equal(CharScript.FX_FLASH_MIN_STEP_S)
	assert_bool(dim.size() - 1 <= CharScript.FX_FLASH_MAX_HZ).is_true()
	assert_float(CharScript.FX_FLASH_MAX_HZ).is_equal_approx(3.0, 0.0001)
	# and the normal pattern really is the strobe the mode exists to avoid
	var fast_edges := 0
	var fast_time := 0.0
	for step: Array in fast:
		fast_edges += 1
		fast_time += float(step[0])
	assert_float(fast_edges / fast_time).is_greater(5.0)
	# sampled: the dim never reaches the strobe's dip, and it never flickers
	_char.set_photosensitive(true)
	assert_str(_char.play_fx("flicker")).is_equal("")
	var timeline: Array = await _sample_timeline(1.3, func() -> float: return _char.flicker_level())
	var min_level := 1.0
	for entry: Array in timeline:
		min_level = minf(min_level, float(entry[1]))
	assert_float(min_level).is_greater_equal(CharScript.FX_FLICKER_DIM_LEVEL - 0.02)
	assert_int(_reversals(timeline)).is_less_equal(2)
	assert_bool(_stage_fx.visible).is_false()
	_char.set_photosensitive(false)


## Turning the mode on mid-cue must land immediately: the running strobe is cut
## and the light returns in one step, so no further dips reach the frame.
func test_photosensitive_switch_cuts_an_inflight_flicker() -> void:
	assert_str(_char.play_fx("flicker")).is_equal("")
	await _wait_seconds(0.15)
	var before: float = _char.flicker_level()
	_char.set_photosensitive(true)
	var timeline: Array = await _sample_timeline(0.6, func() -> float: return _char.flicker_level())
	for entry: Array in timeline:
		assert_float(float(entry[1])).is_greater_equal(before - 0.02)
	assert_float(float(timeline[-1][1])).is_equal_approx(1.0, 0.001)
	assert_int(_reversals(timeline)).is_less_equal(1)
	assert_bool(_stage_fx.visible).is_false()
	_char.set_photosensitive(false)


# --- darken, vignette_red, glitch, text_bleed ---------------------------------


## docs/02 §2.3: darken is "scene darkens to 40%" — down, hold, back.
func test_darken_fades_to_40_percent_then_restores() -> void:
	assert_str(_char.play_fx("darken")).is_equal("")
	assert_bool(_stage_fx.visible).is_true()
	await _wait_seconds(0.4)
	assert_float(float(_mat.get_shader_parameter("darken"))).is_equal_approx(
		CharScript.FX_DARKEN_TO, 0.02
	)
	await _wait_seconds(1.0)
	assert_float(float(_mat.get_shader_parameter("darken"))).is_equal_approx(1.0, 0.001)
	assert_bool(_stage_fx.visible).is_false()


## docs/02 §2.3: "red pulsing vignette". The envelope fades in and out; the
## pulse is the shader's, and its rate is capped under the photosensitive limit.
func test_vignette_red_pulses_then_returns_to_zero() -> void:
	assert_str(_char.play_fx("vignette_red")).is_equal("")
	assert_bool(_stage_fx.visible).is_true()
	assert_float(float(_mat.get_shader_parameter("vignette_pulse_hz"))).is_less(
		CharScript.FX_FLASH_MAX_HZ
	)
	await _wait_seconds(0.35)
	assert_float(float(_mat.get_shader_parameter("vignette"))).is_greater(0.5)
	await _wait_seconds(0.7)
	assert_float(float(_mat.get_shader_parameter("vignette"))).is_equal_approx(0.0, 0.001)
	assert_bool(_stage_fx.visible).is_false()


## docs/02 §2.3: glitch is a burst on the whole screen — it decays to nothing
## within FX_GLITCH_S, and each firing re-seeds the scanline pattern.
func test_glitch_burst_decays_and_reseeds() -> void:
	assert_str(_char.play_fx("glitch")).is_equal("")
	assert_bool(_stage_fx.visible).is_true()
	var first_seed := float(_mat.get_shader_parameter("glitch_seed"))
	assert_float(float(_mat.get_shader_parameter("glitch"))).is_equal_approx(1.0, 0.05)
	await _wait_seconds(0.2)
	assert_float(float(_mat.get_shader_parameter("glitch"))).is_less(0.95)
	await _wait_seconds(0.3)
	assert_float(float(_mat.get_shader_parameter("glitch"))).is_equal_approx(0.0, 0.001)
	assert_bool(_stage_fx.visible).is_false()
	assert_str(_char.play_fx("glitch")).is_equal("")
	assert_float(float(_mat.get_shader_parameter("glitch_seed"))).is_not_equal(first_seed)


## docs/02 §2.3: text bleeds "out of the box" — so the band starts at the live
## TextBox rect the scene supplies, and drains back to nothing.
func test_text_bleed_uses_the_text_box_rect_and_drains() -> void:
	_char.set_bleed_rect_provider(func() -> Rect2: return Rect2(8, 500, 368, 120))
	assert_str(_char.play_fx("text_bleed")).is_equal("")
	assert_bool(_stage_fx.visible).is_true()
	var rect: Vector4 = _mat.get_shader_parameter("bleed_rect")
	assert_float(rect.x).is_equal_approx(8.0 / 384.0, 0.0001)
	assert_float(rect.y).is_equal_approx(500.0 / 688.0, 0.0001)
	assert_float(rect.z).is_equal_approx(376.0 / 384.0, 0.0001)
	assert_float(rect.w).is_equal_approx(620.0 / 688.0, 0.0001)
	await _wait_seconds(0.35)
	assert_float(float(_mat.get_shader_parameter("bleed"))).is_greater(0.6)
	await _wait_seconds(0.9)
	assert_float(float(_mat.get_shader_parameter("bleed"))).is_equal_approx(0.0, 0.001)
	assert_bool(_stage_fx.visible).is_false()


# --- stage baseline -----------------------------------------------------------


## docs/01 §3 + docs/03 §4: the stage baseline ramps (a drain, not a snap) and
## amount 0 hides the pass, so an intact world pays no full-screen shader.
func test_stage_baseline_ramps_desaturation() -> void:
	assert_bool(_stage_fx.visible).is_false()
	_char.apply_stage_fx({"desaturation": 0.75})
	assert_bool(_stage_fx.visible).is_true()
	await _wait_seconds(1.0)
	assert_float(float(_mat.get_shader_parameter("desaturation"))).is_equal_approx(0.75, 0.01)
	_char.apply_stage_fx({"desaturation": 0.0})
	await _wait_seconds(1.0)
	assert_float(float(_mat.get_shader_parameter("desaturation"))).is_equal_approx(0.0, 0.01)
	assert_bool(_stage_fx.visible).is_false()


## A scene that installs after a stage change starts already drained: FX.gd
## pushes the row into the host when it registers (FX.register_host).
func test_a_new_host_starts_on_the_current_stage() -> void:
	FX.set_stage(5)
	var late = CharScene.instantiate()
	get_tree().root.add_child(late)
	await get_tree().process_frame
	var screen: ColorRect = late.get_node("OverlayFX/StageFX")
	assert_bool(screen.visible).is_true()
	await _wait_seconds(0.95)
	var mat: ShaderMaterial = screen.material
	assert_float(float(mat.get_shader_parameter("desaturation"))).is_equal_approx(0.75, 0.01)
	late.queue_free()
	await get_tree().process_frame


## The whole stage stack in one pass: a desaturated stage can still flicker,
## darken and glitch at the same time, because they are uniforms of the same
## sample. (Before the collapse, the last-drawn effect erased the rest.)
func test_stage_effects_compose_on_one_pass() -> void:
	_char.apply_stage_fx({"desaturation": 0.75})
	await _wait_seconds(1.0)
	_char.play_fx("flicker")
	_char.play_fx("darken")
	_char.play_fx("glitch")
	var probe := {"flicker": 1.0}
	await _wait_seconds(
		0.2,
		func() -> void:
			probe["flicker"] = minf(
				float(probe["flicker"]), float(_mat.get_shader_parameter("flicker"))
			)
	)
	assert_float(float(_mat.get_shader_parameter("desaturation"))).is_equal_approx(0.75, 0.01)
	assert_float(float(probe["flicker"])).is_less(1.0)  # the strobe ran
	assert_float(float(_mat.get_shader_parameter("darken"))).is_less(1.0)
	assert_float(float(_mat.get_shader_parameter("glitch"))).is_greater(0.0)
	assert_bool(_stage_fx.visible).is_true()


# --- round 2: cue bookkeeping and the reset seam -----------------------------


## CODE-1 (r2): pass visibility must not be derived from the uniforms alone. A
## stepped cue sits at exactly 1.0 between its dips, so another cue's end (the
## twitch's split clearing, a darken finishing) used to hide the pass there and
## the rest of the flicker never rendered.
func test_a_live_flicker_survives_another_cues_end_callback() -> void:
	assert_str(_char.play_fx("flicker")).is_equal("")
	var waited := 0.0
	while waited < 0.06 or _char.flicker_level() < 0.999:
		await get_tree().process_frame
		waited += get_process_delta_time()
	assert_float(_char.flicker_level()).is_equal_approx(1.0, 0.001)  # a lit step
	_char._set_split(0.0)  # what _process does when the twitch's split ends
	assert_bool(_stage_fx.visible).is_true()
	var probe := {"dips": 0, "erased": 0}
	await _wait_seconds(
		0.25,
		func() -> void:
			if _char.flicker_level() < 0.8:
				probe["dips"] += 1
				if not _stage_fx.visible:
					probe["erased"] += 1
	)
	assert_int(int(probe["dips"])).is_greater(0)  # the rest of the cue rendered
	assert_int(int(probe["erased"])).is_zero()
	await _wait_seconds(0.4)
	assert_bool(_stage_fx.visible).is_false()  # the cue ended and released it


## CODE-2 (r2): clear_screen_fx promises "back to neutral". A killed shake
## tween used to leave the camera on its last interpolated offset (the dev tool
## captured every later still displaced) and a live cue kept the pass on.
func test_clear_screen_fx_restores_the_camera_and_drops_live_cues() -> void:
	assert_str(_char.play_fx("shake_big")).is_equal("")
	await _wait_seconds(0.1)
	assert_float(_cam.offset.length()).is_greater(0.5)
	assert_str(_char.play_fx("flicker")).is_equal("")
	await _wait_seconds(0.05)
	assert_bool(_stage_fx.visible).is_true()
	_char.clear_screen_fx()
	assert_vector(_cam.offset).is_equal_approx(Vector2.ZERO, Vector2(0.001, 0.001))
	assert_bool(_stage_fx.visible).is_false()
	assert_float(_char.flicker_level()).is_equal_approx(1.0, 0.001)
	assert_float(float(_mat.get_shader_parameter("darken"))).is_equal_approx(1.0, 0.001)
