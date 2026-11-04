extends GdUnitTestSuite
## P1.11 — FX v1: blush_glow/hearts/sparkle/shake_small/zoom_face on the
## Character host, per-effect stage gates + 3-turn cooldowns from casting.fx,
## the shake_big/glitch window cap, reduced-motion cuts and the F6 debug menu.
## P2.15 — the stage-3/4 vocabulary (shake_big, flicker, darken, vignette_red,
## glitch, text_bleed) plus the stage baseline: casting.stage_fx's desaturation
## row and the photosensitive-mode switch. Kept logic-only like the other
## suites: node state, tweens and signals, no pixels sampled.

const CharScene := preload("res://scenes/character/Character.tscn")
const CharScript := preload("res://scenes/character/Character.gd")
const PALETTE_PATH := "res://assets/sprites/leila/palette.json"

## The five docs/02 §2.3 stage-0 effects FX v1 implements.
const V1: PackedStringArray = ["blush_glow", "hearts", "sparkle", "shake_small", "zoom_face"]
## P2.15's six cues with their docs/02 §2.3 gates (name -> gate stage).
const STAGE_CUES := {
	"shake_big": 3,
	"flicker": 3,
	"darken": 3,
	"vignette_red": 3,
	"glitch": 3,
	"text_bleed": 4,
}
## docs/01 §3 + docs/03 §4: onset at stage 3, saturation x (1 - 0.15*stage).
const DOC_STAGE_FX := {"0": 0.0, "1": 0.0, "2": 0.0, "3": 0.45, "4": 0.6, "5": 0.75}
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
var _stage_fx: ColorRect
var _fakes: Array = []  # spawned FakeHosts; freed in after_test (orphan-proof)


class FakeHost:
	extends Node
	var calls: PackedStringArray = []
	var stage_profiles: Array = []
	var photosensitive_calls: Array = []

	func play_fx(name: String) -> String:
		calls.append(name)
		return ""

	func apply_stage_fx(profile: Dictionary) -> void:
		stage_profiles.append(profile)

	func set_photosensitive(enabled: bool) -> void:
		photosensitive_calls.append(enabled)


func before_test() -> void:
	FX.reset()
	FX.fx_overrides.clear()
	FX.stage = 0
	FX.photosensitive = false
	_char = CharScene.instantiate()
	get_tree().root.add_child(_char)
	_cam = _char.get_node("Camera2D")
	_fx_root = _char.get_node("MotionRoot/LeanRoot/FX")
	_glow = _char.get_node("ScreenFX/BlushGlow")
	_stage_fx = _char.get_node("OverlayFX/StageFX")


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


# --- casting table ----------------------------------------------------------


## docs/02 §2.3: the data table mirrors the doc's vocabulary + gates, so the
## schema builder and the FX autoload read one source.
func test_casting_fx_table_matches_doc_gates() -> void:
	var table: Dictionary = SpriteResolver.casting.get("fx", {})
	assert_dict(table).contains_keys(DOC_GATES.keys())
	for name: String in DOC_GATES:
		assert_int(int(table[name]["gate"])).is_equal(int(DOC_GATES[name]))
	assert_int(int(table["shake_big"]["max_per"]["count"])).is_equal(1)
	assert_int(int(table["shake_big"]["max_per"]["turns"])).is_equal(2)
	assert_int(int(table["glitch"]["max_per"]["count"])).is_equal(1)


## P1.11's five effects exist in data at gate 0 with the doc's 3-turn cooldown;
## P2.15 adds six gated cues, and the autoload advertises exactly the eleven.
func test_implemented_v1_effects_are_gate0_with_3turn_cooldown() -> void:
	for name: String in V1:
		assert_bool(name in FX.IMPLEMENTED).is_true()
		assert_int(int(SpriteResolver.casting["fx"][name]["gate"])).is_equal(0)
		assert_int(int(SpriteResolver.casting["fx"][name]["cooldown_turns"])).is_equal(3)
	assert_int(FX.IMPLEMENTED.size()).is_equal(V1.size() + STAGE_CUES.size())
	for name: String in STAGE_CUES:
		assert_bool(name in FX.IMPLEMENTED).is_true()
	# the stage baseline is not a cue: no button, no trigger name
	assert_bool("desaturation" in FX.IMPLEMENTED).is_false()


func test_fx_particles_stay_palette_and_pixel_art() -> void:
	var palette: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	var flat: Array = []
	for ramp: String in palette:
		flat.append_array(palette[ramp])
	for col: Color in [
		CharScript.COL_BLUSH,
		CharScript.COL_HEART,
		CharScript.COL_HEART_EDGE,
		CharScript.COL_SPARKLE,
		CharScript.COL_SPARKLE_CORE,
	]:
		assert_bool(col.to_html(false) in flat).append_failure_message(
			"fx colour %s is outside the project palette" % col.to_html()
		)
	# authored x2, displayed at 0.5 like the body: one fx pixel == one body texel
	assert_vector(CharScript.FX_PIXEL_SCALE).is_equal(Vector2(0.5, 0.5))
	assert_int(_char._heart_tex.get_width()).is_equal(14)


# --- budget enforcement ------------------------------------------------------


## Acceptance: cooldown 3 turns, enforced per effect. Firing on turn T locks
## T+1..T+3; T+4 is free. "hearts" cools down while "sparkle" stays ready —
## the cooldown is per effect, not global.
func test_cooldown_3_turns_per_effect() -> void:
	var host := _spawn_fake_host()
	assert_bool(FX.trigger("hearts", 0)).is_true()
	assert_bool("hearts" in host.calls).is_true()
	# still the same turn: already cooling
	assert_bool(FX.trigger("hearts", 0)).is_false()
	for i: int in 3:
		FX.end_turn()
		assert_str(FX.check("hearts", 0)).is_equal("cooldown")
		assert_bool(FX.trigger("hearts", 0)).is_false()
		# per-effect: an untouched effect stays fireable throughout
		assert_str(FX.check("sparkle", 0)).is_equal("")
	FX.end_turn()  # turn 4 since the firing
	assert_bool(FX.trigger("hearts", 0)).is_true()
	assert_int(host.calls.count("hearts")).is_equal(2)


## docs/02 §5: over-budget picks are dropped, never sent back — the drop is
## silent to the model but reported on fx_dropped for the debug overlay.
func test_drops_report_reasons_and_stay_silent() -> void:
	var drops := []
	FX.fx_dropped.connect(func(n: String, r: String) -> void: drops.append([n, r]))
	_spawn_fake_host()
	FX.trigger("hearts", 0)
	FX.trigger("hearts", 0)
	FX.trigger("bogus_fx", 0)
	FX.trigger("rain", 0)  # gate 1 at stage 0
	FX.trigger("rain", 1)  # gate passes, but v1 has no visual yet
	assert_array(drops).contains(
		[
			["hearts", "cooldown"],
			["bogus_fx", "unknown"],
			["rain", "gated"],
			["rain", "unimplemented"]
		]
	)
	# "none" is the default pick: passes, no signal, no cooldown bookkeeping
	assert_bool(FX.trigger("none", 0)).is_true()
	assert_str(FX.check("hearts", 0)).is_equal("cooldown")


func test_unimplemented_names_drop_before_cooldown() -> void:
	_spawn_fake_host()
	# a gated name reports the gate first — the honest reason at stage 0
	assert_str(FX.check("her_eyes", 0)).is_equal("gated")
	assert_str(FX.check("her_eyes", 5)).is_equal("unimplemented")
	# invert_flash is still unimplemented after P2.15 (the task's cues stop at
	# text_bleed); it must drop without booking anything
	assert_str(FX.check("invert_flash", 4)).is_equal("unimplemented")
	assert_bool(FX.trigger("invert_flash", 4)).is_false()
	assert_str(FX.check("invert_flash", 4)).is_equal("unimplemented")


## docs/02 §5 second clause: shake_big/glitch "max 1 per 2 turns" — the window
## cap is separate from the cooldown and enforced on top of it. No v1 effect
## carries a cap, so an override exercises the engine path.
func test_max_per_window_cap() -> void:
	FX.fx_overrides["sparkle"] = {"max_per": {"count": 1, "turns": 2}, "cooldown_turns": 0}
	_spawn_fake_host()
	assert_bool(FX.trigger("sparkle", 0)).is_true()
	FX.end_turn()
	assert_str(FX.check("sparkle", 0)).is_equal("rate_cap")
	FX.end_turn()
	assert_bool(FX.trigger("sparkle", 0)).is_true()  # window expired, fresh one opens
	FX.end_turn()
	assert_bool(FX.trigger("sparkle", 0)).is_false()


func test_no_host_drops_as_no_host() -> void:
	FX.unregister_host(_char)
	assert_str(FX.check("hearts", 0)).is_equal("no_host")
	var drops := []
	FX.fx_dropped.connect(func(n: String, r: String) -> void: drops.append([n, r]))
	assert_bool(FX.trigger("hearts", 0)).is_false()
	assert_array(drops).contains([["hearts", "no_host"]])
	# a freed host falls off the weakref on its own
	var host := _spawn_fake_host()
	FX.unregister_host(host)
	host.queue_free()
	await get_tree().process_frame
	assert_bool(FX.has_host()).is_false()


# --- debug menu ---------------------------------------------------------------


func test_debug_menu_triggers_each_v1_effect() -> void:
	FX.toggle_debug_menu()
	var menu: CanvasLayer = FX._menu
	assert_bool(FX.is_debug_menu_open()).is_true()
	var buttons := menu.find_children("*", "Button", true, false)
	# one button per implemented effect + "end turn"
	assert_int(buttons.size()).is_equal(FX.IMPLEMENTED.size() + 1)
	var names := buttons.map(func(b: Button) -> String: return b.text)
	for name: String in FX.IMPLEMENTED:
		assert_bool(name in names).is_true()
	# every effect triggerable: pressing each button fires the visual through
	# the live Character host (no extra wiring — the scene registered itself)
	for name: String in V1:
		assert_str(FX.debug_trigger(name)).is_equal("")
	assert_int(_fx_root.get_child_count()).is_greater_equal(8)  # 3 hearts + 6 sparks live
	assert_bool(_glow.visible).is_true()
	assert_str(_char._cam_live).is_equal("bust")  # zoom_face pushed toward the bust preset


## P2.15: the six new cues are force-fireable from the dev panel and each one
## actually moves its uniform on the single stage pass — the menu drives the
## same host contract a real Director trigger does.
func test_debug_trigger_fires_each_stage_effect() -> void:
	for name: String in STAGE_CUES:
		assert_str(FX.debug_trigger(name)).is_equal("")
	assert_bool(_stage_fx.visible).is_true()
	var mat: ShaderMaterial = _stage_fx.material
	assert_float(float(mat.get_shader_parameter("glitch"))).is_equal_approx(1.0, 0.05)
	# shake_big books its camera timeline immediately (the offset moves on the
	# first processed frame, so assert the timer, not the offset)
	assert_bool(_char._screen_tweens.has("shake")).is_true()
	# flicker oscillates: watch a window and take the darkest frame, not one
	# arbitrary instant (the lit steps are part of the same cue)
	var probe := {"flicker": 1.0}
	await _wait_seconds(
		0.3,
		func() -> void:
			probe["flicker"] = minf(
				float(probe["flicker"]), float(mat.get_shader_parameter("flicker"))
			)
	)
	assert_float(float(probe["flicker"])).is_less(0.5)
	assert_float(float(mat.get_shader_parameter("darken"))).is_less(0.9)
	assert_float(float(mat.get_shader_parameter("vignette"))).is_greater(0.3)
	assert_float(float(mat.get_shader_parameter("bleed"))).is_greater(0.3)


func test_debug_trigger_bypasses_budgets_without_booking() -> void:
	_spawn_fake_host()
	FX.trigger("hearts", 0)  # now cooling for 3 turns
	assert_str(FX.debug_trigger("hearts")).is_equal("")  # still plays
	assert_str(FX.check("hearts", 0)).is_equal("cooldown")  # but books nothing
	assert_str(FX.debug_trigger("rain")).is_equal("unimplemented")
	assert_str(FX.debug_trigger("bogus")).is_equal("unimplemented")


# --- P2.15 stage vocabulary ---------------------------------------------------


## docs/02 §2.3 + §5: each stage cue is gated, runs at its gate stage, and then
## cools down for 3 turns (per effect, not globally). This is the acceptance
## criterion "each effect gated + cooldown", one row at a time.
func test_stage_cues_are_gated_and_cooled() -> void:
	var host := _spawn_fake_host()
	for cue_name: String in STAGE_CUES:
		var gate := int(STAGE_CUES[cue_name])
		FX.reset()
		host.calls.clear()
		assert_str(FX.check(cue_name, gate - 1)).is_equal("gated")
		assert_bool(FX.trigger(cue_name, gate)).is_true()
		assert_bool(cue_name in host.calls).is_true()
		# same turn: already cooling; T+1..T+3 stay locked, T+4 is free
		assert_str(FX.check(cue_name, gate)).is_equal("cooldown")
		for i: int in 3:
			FX.end_turn()
			assert_str(FX.check(cue_name, gate)).is_equal("cooldown")
		FX.end_turn()
		assert_str(FX.check(cue_name, gate)).is_equal("")


## docs/02 §5 second clause, now on real rows: shake_big and glitch also carry
## "max 1 per 2 turns" in the data, not only in an override.
func test_heavy_stage_cues_carry_the_doc_window_cap() -> void:
	for cue_name: String in ["shake_big", "glitch"]:
		var spec: Dictionary = SpriteResolver.casting["fx"][cue_name]
		assert_int(int(spec["gate"])).is_equal(3)
		assert_int(int(spec["cooldown_turns"])).is_equal(3)
		assert_int(int(spec["max_per"]["count"])).is_equal(1)
		assert_int(int(spec["max_per"]["turns"])).is_equal(2)


## docs/01 §3 + docs/03 §4: the stage baseline is data, monotone, and starts at
## stage 3. Out-of-range stages clamp to the end rows instead of failing.
func test_stage_profile_maps_desaturation_from_data() -> void:
	var table: Dictionary = SpriteResolver.casting.get("stage_fx", {})
	assert_int(table.size()).is_equal(6)
	for stage_key: String in DOC_STAGE_FX:
		assert_float(float(table[stage_key]["desaturation"])).is_equal_approx(
			float(DOC_STAGE_FX[stage_key]), 0.0001
		)
		assert_float(float(FX.stage_profile(int(stage_key))["desaturation"])).is_equal_approx(
			float(DOC_STAGE_FX[stage_key]), 0.0001
		)
	# the world never drains less as the stage rises
	for stage: int in range(1, 6):
		var amount := float(FX.stage_profile(stage)["desaturation"])
		var previous := float(FX.stage_profile(stage - 1)["desaturation"])
		assert_float(amount).is_greater_equal(previous)
	assert_float(float(FX.stage_profile(-3)["desaturation"])).is_equal_approx(0.0, 0.0001)
	assert_float(float(FX.stage_profile(9)["desaturation"])).is_equal_approx(0.75, 0.0001)
	# not a cue: no casting.fx row, so a model pick drops as unknown
	assert_bool(SpriteResolver.casting["fx"].has("desaturation")).is_false()
	assert_str(FX.check("desaturation", 5)).is_equal("unknown")


## FX.gd owns the stage -> baseline mapping (the task's "stage-to-fx"): it reads
## the row, names it to the host and keeps the stage it clamped to.
func test_set_stage_names_the_host_with_the_clamped_row() -> void:
	var host := _spawn_fake_host()
	host.stage_profiles.clear()
	FX.set_stage(4)
	assert_int(FX.stage).is_equal(4)
	assert_int(host.stage_profiles.size()).is_equal(1)
	assert_float(float(host.stage_profiles[0]["desaturation"])).is_equal_approx(0.6, 0.0001)
	# out-of-range names clamp: 9 is stage 5
	FX.set_stage(9)
	assert_int(FX.stage).is_equal(5)
	assert_int(host.stage_profiles.size()).is_equal(2)
	assert_float(float(host.stage_profiles[1]["desaturation"])).is_equal_approx(0.75, 0.0001)


## A scene that installs mid-campaign must start already drained: the host
## contract is pushed on registration, not only on the next stage change.
func test_a_late_host_starts_on_the_current_stage() -> void:
	FX.set_stage(3)  # no live host yet — the row is remembered
	var host := _spawn_fake_host()
	assert_int(host.stage_profiles.size()).is_equal(1)
	assert_float(float(host.stage_profiles[0]["desaturation"])).is_equal_approx(0.45, 0.0001)


## docs/02 §2.3 accessibility: photosensitive mode is an accessibility
## contract, so the one effect the doc switches off must never fire — and the
## host must hear about the switch so an in-flight cue can change its look.
func test_photosensitive_switches_invert_flash_off() -> void:
	var host := _spawn_fake_host()
	host.photosensitive_calls.clear()
	assert_str(FX.check("invert_flash", 4)).is_equal("unimplemented")
	FX.set_photosensitive(true)
	assert_bool(FX.photosensitive).is_true()
	assert_array(host.photosensitive_calls).contains([true])
	assert_str(FX.check("invert_flash", 4)).is_equal("photosensitive")
	assert_bool(FX.trigger("invert_flash", 4)).is_false()
	# flicker keeps its cue in both modes — the host dims it instead
	assert_str(FX.check("flicker", 3)).is_equal("")
	FX.set_photosensitive(false)
	assert_str(FX.check("invert_flash", 4)).is_equal("unimplemented")
