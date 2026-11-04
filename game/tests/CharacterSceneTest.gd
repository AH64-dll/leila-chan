extends GdUnitTestSuite
## P1.10 — Character scene: doc stack, <=150 ms crossfade, motion presets,
## camera presets full/knees/bust/face, pixel-perfect nearest scaling.
## Kept logic-only: transforms, modulates and tween state, no pixels sampled
## (gdUnit4 headless note in docs/07 §2).

const CharScene := preload("res://scenes/character/Character.tscn")
const CharScript := preload("res://scenes/character/Character.gd")
const VIEW := Vector2(384.0, 688.0)
const FEET := Vector2(192.0, 668.0)

var _char  # untyped so private test hooks (_current/_incoming/_motion/_breathe) resolve
var _cam: Camera2D
var _motion_root: Node2D
var _lean_root: Node2D
var _body: Node2D


func before_test() -> void:
	_char = CharScene.instantiate()
	get_tree().root.add_child(_char)
	_cam = _char.get_node("Camera2D")
	_motion_root = _char.get_node("MotionRoot")
	_lean_root = _char.get_node("MotionRoot/LeanRoot")
	_body = _char.get_node("MotionRoot/LeanRoot/Body")


func after_test() -> void:
	_char.queue_free()


## Waits `s` seconds of scene time, calling `probe` each frame when given.
func _wait_seconds(s: float, probe: Callable = Callable()) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()
		if probe.is_valid():
			probe.call()


## The acceptance property for every SETTLED camera (code r1 CODE-1): zoom is
## an integer (1 native px -> N viewport px) and the camera sits on the 1/zoom
## grid, so nearest gives uniform pixel replication in crop shots too.
func _assert_pixel_grid() -> void:
	var z: float = _cam.zoom.x
	assert_float(z).is_equal_approx(roundf(z), 0.0001)
	for p: Vector2 in [Vector2(0, 0), Vector2(37, 129), Vector2(383, 687)]:
		var screen: Vector2 = (p - _cam.position) * z + VIEW / 2.0
		assert_vector(screen).is_equal_approx(screen.round(), Vector2(0.001, 0.001))


## Composed camera + viewport transform, at rest: Body is centred on the frame,
## so a native pixel corner IS the world coordinate p. The canvas transform must
## map every one to a whole viewport pixel (the 768x1376 window stretch is an
## integer 2x on top). Callers await process_frame first — the canvas transform
## is refreshed per frame.
func _assert_canvas_grid() -> void:
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var canvas_scale := canvas.get_scale()
	assert_float(canvas_scale.x).is_equal_approx(roundf(canvas_scale.x), 0.0001)
	assert_float(canvas_scale.y).is_equal_approx(roundf(canvas_scale.y), 0.0001)
	for p: Vector2 in [Vector2(0, 0), Vector2(37, 129), Vector2(383, 687)]:
		var screen: Vector2 = canvas * p
		assert_vector(screen).is_equal_approx(screen.round(), Vector2(0.001, 0.001))


## Composed check through the REAL node chain and viewport transform: a native
## sprite pixel corner must land on a whole viewport pixel. get_screen_transform
## is local->screen composed (node chain + current camera + viewport), refreshed
## per frame — callers must await process_frame after set_camera. Only
## meaningful while breathing is off (freeze) — the authored breathing sine is
## deliberately sub-pixel (docs/03 §4) and must stay.
func _assert_native_px_lands_on_grid(p: Vector2) -> void:
	var sprite: Sprite2D = _char._current
	# x2 texture is centred: local coord of native px corner p is 2p - size/2
	var local := p * 2.0 - sprite.texture.get_size() / 2.0
	var screen: Vector2 = sprite.get_screen_transform() * local
	assert_vector(screen).is_equal_approx(screen.round(), Vector2(0.001, 0.001))


func test_doc_stack_structure() -> void:
	# docs/07 §3.3: Shadow · Body · Overlay · FX + Camera2D
	assert_object(_char.get_node_or_null("Shadow")).is_not_null()
	assert_object(_body).is_not_null()
	assert_object(_body.get_node_or_null("SpriteA")).is_not_null()
	assert_object(_body.get_node_or_null("SpriteB")).is_not_null()
	assert_object(_char.get_node_or_null("MotionRoot/LeanRoot/Overlay")).is_not_null()
	assert_object(_char.get_node_or_null("MotionRoot/LeanRoot/FX")).is_not_null()
	assert_object(_cam).is_not_null()
	assert_str(_char.current_sprite).is_equal("00")  # base_reference is the idle face


func test_pixel_perfect_nearest_scaling() -> void:
	var sprite: Sprite2D = _char._current
	assert_float(sprite.scale.x).is_equal_approx(0.5, 0.0001)
	assert_float(sprite.scale.y).is_equal_approx(0.5, 0.0001)
	# x2 texture rendered at 0.5 = 1:1 texels in the 384x688 viewport
	assert_int(sprite.texture.get_width()).is_equal(768)
	assert_int(sprite.texture.get_height()).is_equal(1376)
	var filter: int = ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter"
	)
	assert_int(filter).is_equal(0)
	# the scene also pins Nearest itself, so it cannot regress with the project setting
	assert_int(_char.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	# per-import contract from P0.08: lossless, no mipmaps
	var cfg := ConfigFile.new()
	var err := cfg.load("res://assets/sprites/leila/00_base_reference.png.import")
	assert_int(err).is_equal(OK)
	assert_bool(bool(cfg.get_value("params", "mipmaps/generate", true))).is_false()
	assert_int(int(cfg.get_value("params", "compress/mode", 99))).is_equal(0)


func test_crossfade_within_150ms_and_blends() -> void:
	var start_ms := Time.get_ticks_msec()
	_char.set_feeling("joy", 2, 0)
	# the swap is immediate: resolver output, texture armed on the incoming
	# sprite and the fade running before the first say chunk could land
	assert_str(_char.current_sprite).is_equal("01")
	assert_bool(_char.is_fading()).is_true()
	assert_float(_char._incoming.modulate.a).is_equal_approx(0.0, 0.0001)
	var saw_blend := false
	while _char.is_fading():
		await get_tree().process_frame
		var a: float = _char._incoming.modulate.a
		if a > 0.001 and a < 0.999:
			saw_blend = true
	var elapsed_ms := Time.get_ticks_msec() - start_ms
	# configured duration is the criterion; the wall clock adds at most a frame
	assert_float(CharScript.CROSSFADE_MS).is_less_equal(150.0)
	assert_int(elapsed_ms).is_less_equal(200)
	assert_bool(saw_blend).is_true()
	# landed: new face fully in, texture is the 01 x2 png
	assert_float(_char._current.modulate.a).is_equal_approx(1.0, 0.001)
	assert_str(String(_char._current.texture.resource_path)).ends_with("01_radiant_joy.png")


func test_camera_presets_settle_on_integer_native_pixels() -> void:
	# freeze (empty i1) stops breathing so the composed chain is exact
	_char.set_feeling("empty", 1, 0)
	var eyes: Array = SpriteResolver.casting["sprites"]["07"]["eyes_native"]
	var eye_mid := (Vector2(eyes[0][0], eyes[0][1]) + Vector2(eyes[1][0], eyes[1][1])) / 2.0
	_char.set_camera("full", true)
	assert_float(_cam.zoom.x).is_equal(1.0)
	assert_vector(_cam.position).is_equal(VIEW / 2.0)
	_char.set_camera("knees", true)
	assert_float(_cam.zoom.x).is_equal(2.0)
	assert_vector(_cam.position).is_equal(Vector2(192, 196))  # head -> mid-thigh
	_char.set_camera("bust", true)
	assert_float(_cam.zoom.x).is_equal(3.0)
	# anchored on the authored bust_crop_native centre [104,20,280,220]
	assert_vector(_cam.position).is_equal(Vector2(192, 120))
	_char.set_camera("face", true)
	assert_float(_cam.zoom.x).is_equal(4.0)
	# anchored on the eyes_native midpoint + the 24 px eye-line drop
	assert_vector(_cam.position).is_equal(eye_mid + Vector2(0, 24))
	# the composed viewport transform for every preset lands native px on grid;
	# the canvas transform refreshes per frame, hence the awaits
	await get_tree().process_frame
	assert_bool(_cam.is_current()).is_true()  # or the check below would pass vacuously
	for preset: String in ["full", "knees", "bust", "face"]:
		_char.set_camera(preset, true)
		await get_tree().process_frame
		_assert_pixel_grid()
		_assert_canvas_grid()
		_assert_native_px_lands_on_grid(Vector2(0, 0))
		_assert_native_px_lands_on_grid(Vector2(37, 129))
		_assert_native_px_lands_on_grid(Vector2(383, 687))


func test_intensity3_pushes_camera_to_bust() -> void:
	_char.set_camera("full", true)
	# freeze i3: body at rest, so the composed viewport transform is exact
	_char.set_feeling("empty", 3, 0)  # i3 -> casting.intensity_3.camera push
	await _wait_seconds(0.6)
	assert_float(_cam.zoom.x).is_equal(3.0)  # settled ON the bust preset's grid
	_assert_pixel_grid()
	await get_tree().process_frame
	assert_bool(_cam.is_current()).is_true()
	_assert_canvas_grid()
	_assert_native_px_lands_on_grid(Vector2(0, 0))
	_assert_native_px_lands_on_grid(Vector2(37, 129))
	_assert_native_px_lands_on_grid(Vector2(383, 687))
	# next non-i3 beat returns to the caller's preset
	_char.set_feeling("joy", 1, 0)
	await _wait_seconds(0.6)
	assert_float(_cam.zoom.x).is_equal(1.0)
	_assert_pixel_grid()
	await get_tree().process_frame
	_assert_canvas_grid()


func test_motion_bounce_hops_and_returns() -> void:
	_char.set_feeling("joy", 2, 0)  # bounce: 6 px hop, 180 ms
	# dictionaries are captured by reference; bare floats are copied into a lambda
	var probe := {"min_y": FEET.y}
	await _wait_seconds(
		0.4, func() -> void: probe["min_y"] = minf(float(probe["min_y"]), _motion_root.position.y)
	)
	assert_float(float(probe["min_y"])).is_less_equal(FEET.y - 3.0)
	assert_float(_motion_root.position.y).is_equal_approx(FEET.y, 0.5)


func test_motion_shake_offsets_x() -> void:
	_char.set_feeling("angry", 2, 0)  # shake: +-4 px, 250 ms
	var probe := {"dev": 0.0}
	await _wait_seconds(
		0.4,
		func() -> void:
			probe["dev"] = maxf(float(probe["dev"]), absf(_motion_root.position.x - FEET.x))
	)
	assert_float(float(probe["dev"])).is_greater_equal(2.0)
	assert_float(_motion_root.position.x).is_equal_approx(FEET.x, 0.5)


func test_motion_tremble_jitters_within_1px() -> void:
	_char.set_feeling("afraid", 2, 0)  # tremble: +-1 px @ 30 Hz
	var probe := {"dev": 0.0, "moved": 0}
	await _wait_seconds(
		0.5,
		func() -> void:
			var d: float = _lean_root.position.distance_to(_char._lean_base)
			probe["dev"] = maxf(float(probe["dev"]), d)
			if d > 0.05:
				probe["moved"] = int(probe["moved"]) + 1
	)
	assert_float(float(probe["dev"])).is_greater(0.05)
	assert_float(float(probe["dev"])).is_less_equal(1.6)
	assert_int(int(probe["moved"])).is_greater_equal(3)


func test_motion_freeze_stops_breathing() -> void:
	_char.set_feeling("empty", 1, 0)  # freeze: no idle sine
	var probe := {"lo": 99.0, "hi": -99.0}
	await _wait_seconds(
		0.5,
		func() -> void:
			probe["lo"] = minf(float(probe["lo"]), _motion_root.scale.y)
			probe["hi"] = maxf(float(probe["hi"]), _motion_root.scale.y)
	)
	assert_float(float(probe["lo"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(probe["hi"])).is_equal_approx(1.0, 0.0001)


func test_motion_sink_drops_and_darkens() -> void:
	# docs/03 §4 baseline at i2: -10 px over 1 s, 2% darker (casting i2 = 1.0)
	_char.set_feeling("sad", 2, 0)
	await _wait_seconds(1.3)
	assert_float(_motion_root.position.y).is_equal_approx(FEET.y + 10.0, 0.5)
	assert_float(_char._current.self_modulate.r).is_equal_approx(0.98, 0.005)
	# i1 runs the same preset at 0.6 x (casting.motion_intensity "1")
	_char.set_feeling("sad", 1, 0)
	await _wait_seconds(1.3)
	assert_float(_motion_root.position.y).is_equal_approx(FEET.y + 6.0, 0.5)


## P2.14: docs/03 §4 "no extra art per intensity" — the packet's motion_scale scales
## the same preset (i1 x0.6, i2 x1.0 = the doc's 1.15, i3 x1.4). lean_in settles on
## an exact value, so the whole ladder is frame-independent.
func test_motion_lean_in_zooms_toward_face() -> void:
	var ladder: Array = [[1, "pleading", 1.09], [2, "suspicious", 1.15], [3, "suspicious", 1.21]]
	for step: Array in ladder:
		_char.set_feeling(String(step[1]), int(step[0]), 0)
		await _wait_seconds(0.6)
		assert_vector(_lean_root.scale).is_equal_approx(
			Vector2(float(step[2]), float(step[2])), Vector2(0.012, 0.012)
		)


func test_motion_breathe_oscillates_in_band() -> void:
	_char.set_feeling("joy", 1, 0)  # breathe: scale.y 1.000 <-> 1.006, 4 s sine
	var probe := {"lo": 99.0, "hi": -99.0}
	await _wait_seconds(
		4.3,
		func() -> void:
			probe["lo"] = minf(float(probe["lo"]), _motion_root.scale.y)
			probe["hi"] = maxf(float(probe["hi"]), _motion_root.scale.y)
	)
	assert_float(float(probe["lo"])).is_greater_equal(0.999)
	assert_float(float(probe["hi"])).is_less_equal(1.007)
	assert_float(float(probe["hi"]) - float(probe["lo"])).is_greater(0.004)


func test_motion_twitch_offsets_then_restores() -> void:
	_char.set_feeling("manic", 2, 0)  # twitch: 1-frame offset every 2-5 s
	var probe := {"fired": false}
	_char.twitch_fired.connect(func() -> void: probe["fired"] = true)
	var t := 0.0
	while t < 6.0 and not bool(probe["fired"]):
		await get_tree().process_frame
		t += get_process_delta_time()
	assert_bool(bool(probe["fired"])).is_true()
	# after the flicker the lean pivot rests on its base
	await _wait_seconds(0.1)
	assert_vector(_lean_root.position).is_equal_approx(_char._lean_base, Vector2(0.01, 0.01))


func test_reduced_motion_cuts_shakes_and_drifts() -> void:
	_char.set_reduced_motion(true)
	var probe := {"dev": 0.0}
	_char.set_feeling("afraid", 2, 0)  # tremble -> no jitter at all
	await _wait_seconds(
		0.4,
		func() -> void:
			probe["dev"] = maxf(
				float(probe["dev"]), _lean_root.position.distance_to(_char._lean_base)
			)
	)
	assert_float(float(probe["dev"])).is_equal_approx(0.0, 0.0001)
	probe["dev"] = 0.0
	_char.set_feeling("angry", 2, 0)  # shake -> x stays put
	await _wait_seconds(
		0.4,
		func() -> void:
			probe["dev"] = maxf(float(probe["dev"]), absf(_motion_root.position.x - FEET.x))
	)
	assert_float(float(probe["dev"])).is_equal_approx(0.0, 0.0001)
	_char.set_feeling("sad", 1, 0)  # sink -> drift cut, 2% darken kept
	await _wait_seconds(0.3)
	assert_float(_motion_root.position.y).is_equal_approx(FEET.y, 0.01)
	assert_float(_char._current.self_modulate.r).is_equal_approx(0.98, 0.005)
	_char.set_reduced_motion(false)


## CODE-2 (code r1): enabling reduced motion mid-move must kill the camera
## tween and snap to the LIVE target — the caller's preset, or an intensity-3
## push if one is active — instead of letting it keep animating.
func test_reduced_motion_snaps_in_flight_camera() -> void:
	_char.set_camera("full", true)
	_char.set_camera("face")  # animated, CAMERA_MOVE_S = 0.35 s
	await _wait_seconds(0.08)  # mid-flight: tween running, zoom still fractional
	assert_bool(_char._cam_tween != null and _char._cam_tween.is_running()).is_true()
	assert_float(_cam.zoom.x).is_less(4.0)
	_char.set_reduced_motion(true)
	# the tween is dead and the camera sits on the live target NOW
	assert_bool(_char._cam_tween == null or not _char._cam_tween.is_running()).is_true()
	assert_float(_cam.zoom.x).is_equal(4.0)
	_assert_pixel_grid()
	var settled := _cam.zoom.x
	await _wait_seconds(0.3)
	assert_float(_cam.zoom.x).is_equal(settled)  # nothing keeps animating
	_char.set_reduced_motion(false)
	# an in-flight i3 push stays pushed instead of falling back to the preset
	_char.set_camera("full", true)
	_char.set_feeling("angry", 3, 0)  # starts the bust push (i3 camera)
	await _wait_seconds(0.08)  # mid-push
	_char.set_reduced_motion(true)
	assert_float(_cam.zoom.x).is_equal(3.0)  # bust, not "full"
	_assert_pixel_grid()
	_char.set_reduced_motion(false)


## CODE-2: lean_in must not animate under reduced motion — it lands on the
## static end pose instead of creating a scale tween.
func test_reduced_motion_lean_in_is_static() -> void:
	_char.set_reduced_motion(true)
	_char.set_feeling("suspicious", 2, 0)  # lean_in beat
	await get_tree().process_frame
	assert_bool(_char._motion_tween == null or not _char._motion_tween.is_running()).is_true()
	assert_vector(_lean_root.scale).is_equal(Vector2(1.15, 1.15))  # pose, no tween
	_char.set_reduced_motion(false)


func test_set_feeling_applies_casting_motion() -> void:
	# resolved motion preset reaches the scene (feeling.motion[intensity])
	_char.set_feeling("nervous", 1, 0)  # motion "breathe"
	assert_str(_char._motion).is_equal("breathe")
	_char.set_feeling("nervous", 2, 0)  # motion "tremble"
	assert_str(_char._motion).is_equal("tremble")
	_char.set_feeling("empty", 1, 0)  # motion "freeze"
	assert_str(_char._motion).is_equal("freeze")


## Every motion name casting.json can emit (feeling columns + sprite on_enter)
## is a preset the scene implements; an unknown one would silently fall back
## to breathe, which docs/03 §4 would show as the wrong motion.
func test_every_casting_motion_is_a_known_preset() -> void:
	var names := {}
	for feeling: String in SpriteResolver.casting["feelings"]:
		var motions: Dictionary = SpriteResolver.casting["feelings"][feeling]["motion"]
		for col: String in motions:
			names[String(motions[col])] = true
	for sprite_id: String in SpriteResolver.casting["sprites"]:
		var motion := String(
			SpriteResolver.casting["sprites"][sprite_id].get("on_enter", {}).get("motion", "")
		)
		if not motion.is_empty():
			names[motion] = true
	assert_int(names.size()).is_greater(0)
	for name: String in names:
		assert_bool(name in CharScript.MOTION_NAMES).append_failure_message(
			"casting motion '%s' has no Character preset" % name
		)
