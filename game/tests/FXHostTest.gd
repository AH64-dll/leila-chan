extends GdUnitTestSuite
## P1.11 — FX v1: blush_glow/hearts/sparkle/shake_small/zoom_face on the
## Character host, per-effect stage gates + 3-turn cooldowns from casting.fx,
## the shake_big/glitch window cap, reduced-motion cuts and the F6 debug menu.
## Kept logic-only like the other suites: node state, tweens and signals,
## no pixels sampled.

## sibling suite FXTest.gd owns the autoload side (gates, cooldowns, menu);
## this one owns the Character host visuals (docs/07 §3.3 FX node + ScreenFX).
const CharScene := preload("res://scenes/character/Character.tscn")
const CharScript := preload("res://scenes/character/Character.gd")
const PALETTE_PATH := "res://assets/sprites/leila/palette.json"

## The five docs/02 §2.3 stage-0 effects this task implements.
const V1: PackedStringArray = ["blush_glow", "hearts", "sparkle", "shake_small", "zoom_face"]
## docs/02 §2.3 gate column, transcribed so a hand-edited casting.fx regresses loudly.
const DOC_GATES := {
	"none": 0,
	"blush_glow": 0,
	"hearts": 0,
	"sparkle": 0,
	"shake_small": 0,
	"zoom_face": 0,
	"rain": 1,
	"shake_big": 3,
	"flicker": 3,
	"darken": 3,
	"vignette_red": 3,
	"glitch": 3,
	"text_bleed": 4,
	"invert_flash": 4,
	"her_eyes": 5,
}

var _char  # untyped so private hooks (_fx_root/_glow/_cam_tween/...) resolve
var _cam: Camera2D
var _fx_root: Node2D
var _glow: TextureRect
var _fakes: Array = []  # spawned FakeHosts; freed in after_test (orphan-proof)


class FakeHost:
	extends Node
	var calls: PackedStringArray = []

	func play_fx(name: String) -> String:
		calls.append(name)
		return ""


func before_test() -> void:
	FX.reset()
	FX.fx_overrides.clear()
	_char = CharScene.instantiate()
	get_tree().root.add_child(_char)
	_cam = _char.get_node("Camera2D")
	_fx_root = _char.get_node("MotionRoot/LeanRoot/FX")
	_glow = _char.get_node("ScreenFX/BlushGlow")


func after_test() -> void:
	if FX._menu != null:  # dev panel persists; free it so it never goes stale
		FX._menu.queue_free()
		FX._menu = null
	_char.queue_free()
	for fake in _fakes:
		if is_instance_valid(fake):
			FX.unregister_host(fake)
			fake.queue_free()
	_fakes.clear()
	FX.reset()
	FX.fx_overrides.clear()


func _wait_seconds(s: float, probe: Callable = Callable()) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()
		if probe.is_valid():
			probe.call()


func _spawn_fake_host() -> FakeHost:
	var host := FakeHost.new()
	get_tree().root.add_child(host)
	_fakes.append(host)
	FX.register_host(host)
	return host


# --- Character host visuals ---------------------------------------------------


func test_blush_glow_pulses_vignette_then_hides() -> void:
	assert_str(_char.play_fx("blush_glow")).is_equal("")
	assert_bool(_glow.visible).is_true()
	var probe := {"peak": 0.0}
	await _wait_seconds(
		0.5, func() -> void: probe["peak"] = maxf(float(probe["peak"]), _glow.modulate.a)
	)
	assert_float(float(probe["peak"])).is_greater(0.2)
	await _wait_seconds(0.7)
	assert_bool(_glow.visible).is_false()
	assert_float(_glow.modulate.a).is_equal_approx(0.0, 0.001)


func test_hearts_rise_and_free() -> void:
	assert_str(_char.play_fx("hearts")).is_equal("")
	assert_int(_fx_root.get_child_count()).is_equal(3)
	var heart: Sprite2D = _fx_root.get_child(0)
	var y0 := heart.position.y
	await _wait_seconds(0.35)
	assert_float(heart.position.y).is_less(y0 - 4.0)  # rising toward +up
	await _wait_seconds(0.7)
	assert_int(_fx_root.get_child_count()).is_equal(0)  # all freed, none leak


func test_sparkle_twinkles_and_respects_reduced_motion() -> void:
	assert_str(_char.play_fx("sparkle")).is_equal("")
	assert_int(_fx_root.get_child_count()).is_equal(6)
	var probe := {"lit": 0}
	await _wait_seconds(
		0.3,
		func() -> void:
			for child: Node in _fx_root.get_children():
				if (child as Sprite2D).modulate.a > 0.4:
					probe["lit"] = int(probe["lit"]) + 1,
	)
	assert_int(int(probe["lit"])).is_greater_equal(2)  # staggered lights on
	# reduced motion: same sparkles appear, the scale-throb is cut
	_char.set_reduced_motion(true)
	assert_str(_char.play_fx("sparkle")).is_equal("")
	var scales := {}
	await _wait_seconds(0.3)
	for child: Node in _fx_root.get_children():
		scales[(child as Sprite2D).scale.x] = true
	assert_bool(not scales.has(0.75)).is_true()  # nothing shrank toward 0.75
	_char.set_reduced_motion(false)


func test_shake_small_offsets_camera_200ms_then_restores() -> void:
	assert_str(_char.play_fx("shake_small")).is_equal("")
	var probe := {"dev": 0.0}
	await _wait_seconds(
		0.16, func() -> void: probe["dev"] = maxf(float(probe["dev"]), _cam.offset.length())
	)
	assert_float(float(probe["dev"])).is_greater(0.5)
	await _wait_seconds(0.15)
	assert_vector(_cam.offset).is_equal_approx(Vector2.ZERO, Vector2(0.001, 0.001))


func test_shake_small_skipped_under_reduced_motion() -> void:
	_char.set_reduced_motion(true)
	assert_str(_char.play_fx("shake_small")).is_equal("reduced_motion")
	var probe := {"dev": 0.0}
	await _wait_seconds(
		0.25, func() -> void: probe["dev"] = maxf(float(probe["dev"]), _cam.offset.length())
	)
	assert_float(float(probe["dev"])).is_equal_approx(0.0, 0.0001)
	_char.set_reduced_motion(false)


func test_zoom_face_pushes_to_bust_then_returns() -> void:
	_char.set_camera("full", true)
	assert_str(_char.play_fx("zoom_face")).is_equal("")
	await _wait_seconds(0.45)
	assert_float(_cam.zoom.x).is_equal(3.0)  # settled on the bust grid
	assert_str(_char._cam_live).is_equal("bust")
	await _wait_seconds(1.1)  # hold ends at 1.0 s, the return needs 0.35 s
	assert_float(_cam.zoom.x).is_equal(1.0)  # and returned to the caller's preset
	assert_str(_char._cam_live).is_equal("full")


func test_zoom_face_return_loses_to_a_newer_camera_move() -> void:
	_char.play_fx("zoom_face")
	await _wait_seconds(0.45)
	_char.set_camera("face", true)  # a real beat move during the hold (instant: deterministic)
	await _wait_seconds(0.8)  # past the hold: the stale return must not fire
	await _wait_seconds(0.6)  # and past any stale return tween
	assert_str(_char._cam_live).is_equal("face")
	assert_float(_cam.zoom.x).is_equal(4.0)


## Reduced motion landing mid-shake kills the shake; particles mid-drift are
## dropped. The vignette is colour, not motion — it is allowed to finish.
func test_reduced_motion_cuts_inflight_shake_and_drift() -> void:
	_char.play_fx("shake_small")
	_char.play_fx("hearts")
	await _wait_seconds(0.08)
	_char.set_reduced_motion(true)
	assert_vector(_cam.offset).is_equal(Vector2.ZERO)
	assert_int(_fx_root.get_child_count()).is_equal(0)
	var probe := {"dev": 0.0}
	await _wait_seconds(
		0.2, func() -> void: probe["dev"] = maxf(float(probe["dev"]), _cam.offset.length())
	)
	assert_float(float(probe["dev"])).is_equal_approx(0.0, 0.0001)
	_char.set_reduced_motion(false)


## The whole path a Director beat takes: FX.trigger -> the registered host.
func test_trigger_routes_through_character_host() -> void:
	assert_bool(FX.has_host()).is_true()
	var fired := []
	FX.fx_triggered.connect(func(n: String) -> void: fired.append(n))
	assert_bool(FX.trigger("sparkle", 0)).is_true()
	assert_int(_fx_root.get_child_count()).is_equal(6)
	assert_array(fired).contains(["sparkle"])
	# and the cooldown is now real for the next beats of this turn
	assert_bool(FX.trigger("sparkle", 0)).is_false()


## P1.10 contract: twitch_fired flips the chromatic split on for 1-2 frames.
## P2.15 moved the split onto the single stage pass (a second screen-sampling
## rect would erase the stage effects), so the contract is a uniform + the
## pass being shown for exactly those frames.
func test_twitch_fires_chromatic_split() -> void:
	_char._on_twitch_fired()
	assert_float(float(_char._stage_mat.get_shader_parameter("split"))).is_equal_approx(1.0, 0.0001)
	assert_bool(_char._stage_fx.visible).is_true()
	await _wait_seconds(0.08)
	assert_float(float(_char._stage_mat.get_shader_parameter("split"))).is_equal_approx(0.0, 0.0001)
	assert_bool(_char._stage_fx.visible).is_false()
