extends GdUnitTestSuite
## P1.11 — FX v1: blush_glow/hearts/sparkle/shake_small/zoom_face on the
## Character host, per-effect stage gates + 3-turn cooldowns from casting.fx,
## the shake_big/glitch window cap, reduced-motion cuts and the F6 debug menu.
## Kept logic-only like the other suites: node state, tweens and signals,
## no pixels sampled.

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
var _glitch: ColorRect
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
	_glitch = _char.get_node("ScreenFX/GlitchSplit")


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


## P1.11's five effects exist in data at gate 0 with the doc's 3-turn cooldown,
## and the autoload advertises exactly them.
func test_implemented_v1_effects_are_gate0_with_3turn_cooldown() -> void:
	for name: String in V1:
		assert_bool(name in FX.IMPLEMENTED).is_true()
		assert_int(int(SpriteResolver.casting["fx"][name]["gate"])).is_equal(0)
		assert_int(int(SpriteResolver.casting["fx"][name]["cooldown_turns"])).is_equal(3)
	assert_int(FX.IMPLEMENTED.size()).is_equal(5)


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
	assert_str(FX.check("glitch", 3)).is_equal("unimplemented")
	assert_bool(FX.trigger("glitch", 3)).is_false()
	# dropping never books the effect: it can still say "unimplemented", not "cooldown"
	assert_str(FX.check("glitch", 3)).is_equal("unimplemented")


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
	assert_int(buttons.size()).is_equal(6)  # five effects + "end turn"
	var names := buttons.map(func(b: Button) -> String: return b.text)
	for name: String in V1:
		assert_bool(name in names).is_true()
	# every effect triggerable: pressing each button fires the visual through
	# the live Character host (no extra wiring — the scene registered itself)
	for name: String in V1:
		assert_str(FX.debug_trigger(name)).is_equal("")
	assert_int(_fx_root.get_child_count()).is_greater_equal(8)  # 3 hearts + 6 sparks live
	assert_bool(_glow.visible).is_true()
	assert_str(_char._cam_live).is_equal("bust")  # zoom_face pushed toward the bust preset


func test_debug_trigger_bypasses_budgets_without_booking() -> void:
	_spawn_fake_host()
	FX.trigger("hearts", 0)  # now cooling for 3 turns
	assert_str(FX.debug_trigger("hearts")).is_equal("")  # still plays
	assert_str(FX.check("hearts", 0)).is_equal("cooldown")  # but books nothing
	assert_str(FX.debug_trigger("rain")).is_equal("unimplemented")
	assert_str(FX.debug_trigger("bogus")).is_equal("unimplemented")
