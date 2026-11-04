extends GdUnitTestSuite
## P1.10 — SpriteResolver T0-T1 (docs/03 §3) + P0-gate C7 res-path mapping.
## The resolver is instantiated fresh per test (no autoload state leaks);
## casting.json in the resolver is the table the tests compare against.

var _resolver: Node


func before_test() -> void:
	_resolver = load("res://autoload/SpriteResolver.gd").new()
	_resolver.reload()


func after_test() -> void:
	_resolver.free()


func test_tier_for_stage_matches_casting_tiers() -> void:
	assert_str(_resolver.tier_for_stage(0)).is_equal("T0")
	assert_str(_resolver.tier_for_stage(1)).is_equal("T0")
	assert_str(_resolver.tier_for_stage(2)).is_equal("T1")
	assert_str(_resolver.tier_for_stage(3)).is_equal("T2")
	assert_str(_resolver.tier_for_stage(4)).is_equal("T3")
	assert_str(_resolver.tier_for_stage(5)).is_equal("T3")
	assert_str(_resolver.tier_for_stage(-1)).is_empty()
	assert_str(_resolver.tier_for_stage(6)).is_empty()


## Acceptance: every feeling x intensity at stage 0-2 resolves to the
## casting.json sprite (22 x 3 x 3 = 198 cells through resolve()).
func test_table_driven_stages_0_to_2() -> void:
	var feelings: Dictionary = _resolver.casting["feelings"]
	var cells := 0
	var wrong: Array[String] = []
	for feeling: String in feelings:
		for stage: int in [0, 1, 2]:
			var tier: String = _resolver.tier_for_stage(stage)
			var row: Dictionary = feelings[feeling]["tiers"][tier]["sprite"]
			for i: int in 3:
				cells += 1
				var got: String = _resolver.resolve(feeling, i + 1, stage)
				var want := String(row[str(i + 1)])
				if got != want:
					wrong.append("%s i%d st%d -> %s (want %s)" % [feeling, i + 1, stage, got, want])
	assert_int(cells).is_equal(198)
	assert_array(wrong).is_empty()


## docs/03 §3.1 spot checks the test can't derive from the table alone.
func test_doc_spot_checks() -> void:
	assert_str(_resolver.resolve("joy", 1, 0)).is_equal("01")
	assert_str(_resolver.resolve("love", 3, 0)).is_equal("01")
	assert_str(_resolver.resolve("love", 1, 0)).is_equal("06")
	assert_str(_resolver.resolve("afraid", 1, 0)).is_equal("11")
	assert_str(_resolver.resolve("afraid", 3, 0)).is_equal("20")
	assert_str(_resolver.resolve("crying", 3, 0)).is_equal("16")
	assert_str(_resolver.resolve("manic", 1, 0)).is_equal("03")
	assert_str(_resolver.resolve("manic", 3, 0)).is_equal("13")


## docs/03 §3 step 6: invalid/missing feeling -> T0-T2 fallback 00, T3 -> 29.
func test_fallback_for_invalid_feeling() -> void:
	assert_str(_resolver.resolve("bogus", 1, 0)).is_equal("00")
	assert_str(_resolver.resolve("bogus", 1, 2)).is_equal("00")
	assert_str(_resolver.resolve("", 2, 1)).is_equal("00")
	assert_str(_resolver.resolve("bogus", 1, 4)).is_equal("29")


## Intensity is the i1/i2/i3 column of the row; out-of-range clamps to it.
func test_intensity_clamps_to_columns() -> void:
	assert_str(_resolver.resolve("sad", 0, 0)).is_equal("14")
	assert_str(_resolver.resolve("sad", 9, 0)).is_equal("15")
	assert_str(_resolver.resolve("afraid", -3, 0)).is_equal("11")
	assert_str(_resolver.resolve("afraid", 99, 0)).is_equal("20")


## docs/03 §3 step 4: the third identical sprite in a row swaps to the
## family's sibling — the doc's own example is repeated 06 -> 01.
func test_anti_repeat_swaps_to_sibling() -> void:
	var first: Dictionary = _resolver.resolve_beat("shy", 2, 0)
	var second: Dictionary = _resolver.resolve_beat("shy", 2, 0)
	var third: Dictionary = _resolver.resolve_beat("shy", 2, 0)
	assert_str(String(first["sprite"])).is_equal("06")
	assert_str(String(second["sprite"])).is_equal("06")
	assert_str(String(third["sprite"])).is_equal("01")
	assert_bool(bool(third["anti_repeated"])).is_true()
	# after the swap the window cleared: a fourth shy beat shows 06 again
	var fourth: Dictionary = _resolver.resolve_beat("shy", 2, 0)
	assert_str(String(fourth["sprite"])).is_equal("06")
	# resolve() stays pure — no history bleed into the table lookup
	assert_str(_resolver.resolve("shy", 2, 0)).is_equal("06")


## Siblings are healthy faces only (casting.siblings) and the swap never
## crosses the healthy/corrupt band.
func test_siblings_table_is_healthy_and_distinct() -> void:
	var siblings: Dictionary = _resolver.casting.get("siblings", {})
	for feeling: String in _resolver.casting["feelings"]:
		var sib := String(siblings.get(feeling, ""))
		assert_str(sib).is_not_empty()
		if sib.is_empty():
			continue
		assert_int(int(sib)).is_less(21)
		for stage: int in [0, 1, 2]:
			for i: int in 3:
				var own: String = _resolver.resolve(feeling, i + 1, stage)
				if own == sib:
					fail("%s sibling %s equals own face at st%d i%d" % [feeling, sib, stage, i + 1])


## Path machinery is inert at T0-T1 (paths list only T2/T3) and works
## through the same data when a path is active.
func test_path_overrides_inert_at_t0_t1() -> void:
	assert_str(_resolver.resolve("love", 1, 2, "YANDERE")).is_equal("06")
	assert_str(_resolver.resolve("playful", 1, 1, "AWAKE")).is_equal("03")
	assert_str(_resolver.resolve("angry", 3, 0, "YANDERE")).is_equal("17")
	# same data fires at T3 where the path's tiers list it
	assert_str(_resolver.resolve("love", 1, 4, "YANDERE")).is_equal("24")
	assert_str(_resolver.resolve("joy", 1, 4, "YANDERE")).is_equal("22")


## docs/03 §3 step 3 gates: the flagged sprite 27 only lands with rival_gone.
func test_flag_gate_rival_gone() -> void:
	var no_flag: String = _resolver.resolve("warmth", 1, 4, "YANDERE")
	var flagged: String = _resolver.resolve("warmth", 1, 4, "YANDERE", {"rival_gone": true})
	assert_str(no_flag).is_equal("05")
	assert_str(flagged).is_equal("27")


## A corrupted face can never resolve at T0-T1 through any input
## (min_tier gate derived from casting, not a hand list).
func test_corrupt_sprites_never_resolve_at_t0_t1() -> void:
	for feeling: String in _resolver.casting["feelings"]:
		for stage: int in [0, 1, 2]:
			for i: int in 3:
				var got: String = _resolver.resolve(
					feeling, i + 1, stage, "YANDERE", {"rival_gone": true}
				)
				assert_int(int(got)).is_less(21)


## P0 gate C7: every repo-relative casting asset path maps to a valid
## res:// path; repo-side paths (px/, raw pool) map to "".
func test_c7_every_casting_asset_maps_to_res_path() -> void:
	var casting: Dictionary = _resolver.casting
	for sprite_id: String in casting["sprites"]:
		var res_path: String = _resolver.sprite_texture_path(sprite_id)
		assert_bool(res_path.begins_with("res://")).is_true()
		assert_bool(ResourceLoader.exists(res_path)).is_true()
		var tex: Resource = ResourceLoader.load(res_path)
		assert_object(tex).is_instanceof(CompressedTexture2D).append_failure_message(
			"not an imported texture: " + res_path
		)
		# native px path is repo-side metadata, never a res:// path
		var native := String(casting["sprites"][sprite_id]["native"])
		assert_str(_resolver.to_res_path(native)).is_empty()
	# palette maps too
	var palette: String = _resolver.to_res_path(String(casting["art"]["palette"]))
	assert_str(palette).is_equal("res://assets/sprites/leila/palette.json")
	assert_bool(ResourceLoader.exists(palette)).is_true()
	# audio pool paths and unknown paths stay unmapped
	assert_str(_resolver.to_res_path("assets/audio/_raw/x.wav")).is_empty()
	assert_str(_resolver.to_res_path("")).is_empty()


## The beat packet carries everything the Director routes: motion, tint,
## fx/cues/music pools, on_enter and the i3 camera push.
func test_beat_packet_contents() -> void:
	var packet: Dictionary = _resolver.resolve_beat("joy", 2, 0)
	assert_str(String(packet["sprite"])).is_equal("01")
	assert_str(String(packet["motion"])).is_equal("bounce")
	assert_str(String(packet["tint"])).is_equal("#ff7a6e")
	assert_str(String(packet["tier"])).is_equal("T0")
	assert_str(String(packet["camera"])).is_empty()
	# intensity 3 pushes the camera to bust (casting.intensity_3)
	var push: Dictionary = _resolver.resolve_beat("joy", 3, 0)
	assert_str(String(push["camera"])).is_equal("bust")
	# sprite on_enter.motion wins over the feeling's intensity motion
	var terror: Dictionary = _resolver.resolve_beat("afraid", 1, 2)
	assert_str(String(terror["sprite"])).is_equal("20")
	assert_str(String(terror["motion"])).is_equal("tremble")


func test_reset_scene_clears_the_window() -> void:
	_resolver.resolve_beat("shy", 2, 0)
	_resolver.resolve_beat("shy", 2, 0)
	_resolver.reset_scene()
	var packet: Dictionary = _resolver.resolve_beat("shy", 2, 0)
	assert_str(String(packet["sprite"])).is_equal("06")
	assert_bool(bool(packet["anti_repeated"])).is_false()
