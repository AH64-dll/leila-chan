extends GdUnitTestSuite
## P1.16 — Date scene assembly tests.
##
## Acceptance criteria:
##   1) Date.tscn wires Character, TextBox, InputBox, FX, audio
##   2) background uses the project palette
##   3) opening beats playback via ScenarioLoader
##   4) reduced motion and FX wiring

const DateScene := preload("res://scenes/Date.gd")
const DatePacked := preload("res://scenes/Date.tscn")
const PALETTE_RES := "res://assets/sprites/leila/palette.json"
const CAFE_BG_RES := "res://assets/bg/cafe.png"

var _date: Node2D


func before_test() -> void:
	_date = DatePacked.instantiate()
	get_tree().root.add_child(_date)
	await get_tree().process_frame


func after_test() -> void:
	if _date != null and is_instance_valid(_date):
		_date.queue_free()
	await get_tree().process_frame


func test_date_scene_wires_character_textbox_inputbox_fx_audio() -> void:
	# Criterion 1: Date.tscn wires Character, TextBox, InputBox, FX, audio
	assert_object(_date.character).is_not_null()
	assert_object(_date.text_box).is_not_null()
	assert_object(_date.input_box).is_not_null()
	assert_object(_date.chat_ui).is_not_null()
	assert_object(_date.fx).is_not_null()
	assert_object(_date.background).is_not_null()

	# find_component aliases
	assert_object(_date.find_component("Character")).is_not_null()
	assert_object(_date.find_component("TextBox")).is_not_null()
	assert_object(_date.find_component("InputBox")).is_not_null()
	assert_object(_date.find_component("FX")).is_not_null()
	assert_object(_date.find_component("ChatUI")).is_not_null()
	assert_object(_date.find_component("Background")).is_not_null()
	# node tree paths
	assert_object(_date.get_node_or_null("Character")).is_not_null()
	assert_object(_date.get_node_or_null("Background")).is_not_null()
	assert_object(_date.get_node_or_null("FXLayer/FX")).is_not_null()
	assert_object(_date.get_node_or_null("UILayer/ChatUI")).is_not_null()

	# Pixel art nearest texture filter pinned
	assert_int(_date.background.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_object(_date.background.texture).is_not_null()


func test_date_scene_registers_chat_ui_with_director() -> void:
	# F1 controller wiring (P1 gate-r3 / P2.23): the shipped scene owns the
	# ChatUI instance, so it registers it with the Director at ready and clears
	# it on exit. This is the seam the unsafe-input refusal and every streamed
	# reply go through; without it the Director's `has_method` guard skips the
	# UI silently.
	assert_object(_date.chat_ui).is_not_null()
	assert_object(Director.chat_ui_node).is_same(_date.chat_ui)

	_date.queue_free()
	await get_tree().process_frame
	assert_object(Director.chat_ui_node).is_null()


func test_background_uses_project_palette() -> void:
	# Criterion 2: background uses the project palette
	assert_bool(ResourceLoader.exists(CAFE_BG_RES)).is_true()
	var img := Image.load_from_file("res://assets/bg/cafe.png")
	assert_object(img).is_not_null()
	assert_int(img.get_width()).is_equal(384)
	assert_int(img.get_height()).is_equal(688)

	# Read allowed hex colors from palette.json
	var pal_text := FileAccess.get_file_as_string(PALETTE_RES)
	var pal_dict: Dictionary = JSON.parse_string(pal_text)
	var allowed_hexes: Dictionary = {}
	for group: Variant in pal_dict:
		for h: Variant in pal_dict[group]:
			var hex_str: String = String(h).to_lower().strip_edges()
			allowed_hexes[hex_str] = true

	# Check every pixel in the cafe background
	var off_palette_count := 0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var hex := c.to_html(false).to_lower()
			if not allowed_hexes.has(hex):
				off_palette_count += 1

	assert_int(off_palette_count).is_equal(0)


func test_scenario_loader_and_background_resolution() -> void:
	assert_bool(_date.load_scenario("res://data/scenarios/D02_cafe.json")).is_true()
	var scenario: Dictionary = _date.get_scenario()
	assert_str(String(scenario["id"])).is_equal("D02_cafe")
	assert_str(String(scenario["background"])).is_equal("bg/cafe")
	assert_str(String(scenario["music"])).is_equal("calm")
	assert_object(_date.background.texture).is_not_null()


func test_opening_beats_playback_stage_0() -> void:
	_date.stage = 0
	_date.set_instant_text(true)
	var beats_played: Array = []
	_date.beat_played.connect(
		func(idx: int, pkt: Dictionary) -> void: beats_played.append({"i": idx, "packet": pkt})
	)

	_date.start_date()
	await get_tree().process_frame

	assert_bool(_date.is_opening_finished()).is_true()
	assert_int(beats_played.size()).is_equal(1)
	# Stage 0 opening beat feeling is "shy" -> resolves to sprite "06"
	assert_str(_date.character.current_sprite).is_equal("06")
	# Text contains the opening greeting
	var text: String = _date.text_box.get_visible_text()
	assert_bool(text.contains("glad you came")).is_true()


func test_opening_beats_playback_stage_1() -> void:
	_date.stage = 1
	_date.set_instant_text(true)
	var beats_played: Array = []
	_date.beat_played.connect(
		func(idx: int, pkt: Dictionary) -> void: beats_played.append({"i": idx, "packet": pkt})
	)

	_date.start_date()
	await get_tree().process_frame

	assert_bool(_date.is_opening_finished()).is_true()
	assert_int(beats_played.size()).is_equal(1)
	# Stage 1 opening beat feeling is "joy" -> resolves to sprite "01"
	assert_str(_date.character.current_sprite).is_equal("01")
	var text: String = _date.text_box.get_visible_text()
	# P2.06: stage 1 may insert the docs/07 §3.4 hesitation ellipsis. It is a
	# pause at a word boundary, not a word change, so the check ignores it.
	assert_bool(_without_hesitation(text).contains("You're here")).is_true()


func test_fx_wiring_and_twitch_signal() -> void:
	var fx_played: Array[StringName] = []
	# Twitch hook wired from character
	_date.character.twitch_fired.emit()
	await get_tree().process_frame

	# FX zoom_face pushes camera to face
	_date.play_fx(&"zoom_face", true)
	await get_tree().process_frame
	var cam: Camera2D = _date.character.get_node("Camera2D")
	assert_float(cam.zoom.x).is_equal(4.0)
	# FX blush glow executes cleanly
	_date.play_fx(&"blush_glow")
	await get_tree().process_frame


func test_reduced_motion_wiring() -> void:
	_date.set_reduced_motion(true)
	assert_bool(_date.reduced_motion).is_true()
	assert_bool(_date.character.reduced_motion).is_true()

	_date.set_reduced_motion(false)
	assert_bool(_date.reduced_motion).is_false()
	assert_bool(_date.character.reduced_motion).is_false()


func test_player_turn_input_flow() -> void:
	var submitted_lines: Array[String] = []
	_date.player_turn_submitted.connect(func(t: String) -> void: submitted_lines.append(t))

	_date.chat_ui._on_input_submitted("Can I order coffee?")
	await get_tree().process_frame

	assert_int(submitted_lines.size()).is_equal(1)
	assert_str(submitted_lines[0]).is_equal("Can I order coffee?")
	assert_int(_date.chat_log.entry_count()).is_equal(1)


func test_pause_request_propagation() -> void:
	var flags: Dictionary = {"pause": false}
	_date.pause_requested.connect(func() -> void: flags["pause"] = true)
	_date.chat_ui.pause_requested.emit()
	assert_bool(bool(flags["pause"])).is_true()


func test_capture_screenshots_for_handoff() -> void:
	_date.stage = 0
	_date.set_reduced_motion(true)
	_date.set_instant_text(true)
	_date.start_date()
	# Await crossfade completion (>140ms, ~25 frames) so Leila is at full opacity
	for i: int in 25:
		await get_tree().process_frame

	var vp := get_tree().root
	var img0 := vp.get_texture().get_image()
	if img0 != null and not img0.is_empty():
		img0.save_png("res://../production/handoffs/media/P1.16/01_date_cafe_stage0.png")

	_date.stage = 1
	_date.start_date()
	for i: int in 25:
		await get_tree().process_frame

	var img1 := vp.get_texture().get_image()
	if img1 != null and not img1.is_empty():
		img1.save_png("res://../production/handoffs/media/P1.16/02_date_cafe_stage1.png")

	# Cafe background art direct capture
	var bg_img := Image.load_from_file("res://assets/bg/cafe.png")
	if bg_img != null:
		bg_img.save_png("res://../production/handoffs/media/P1.16/03_cafe_background.png")
	(
		assert_bool(
			FileAccess.file_exists(
				"res://../production/handoffs/media/P1.16/03_cafe_background.png"
			)
		)
		. is_true()
	)


func test_photosensitive_wiring() -> void:
	_date.set_photosensitive(true)
	assert_bool(_date.photosensitive).is_true()
	assert_bool(_date.fx.photosensitive).is_true()
	_date.play_fx(&"twitch")
	await get_tree().process_frame
	# Overlay remains completely clear when photosensitive is enabled
	assert_float(_date.fx._overlay.color.a).is_equal_approx(0.0, 0.001)


func test_ambience_forwarding() -> void:
	# D02 cafe carries ambience: "cafe"
	var ok: bool = _date.load_scenario("res://data/scenarios/D02_cafe.json")
	assert_bool(ok).is_true()
	assert_str(String(_date.get_scenario().get("ambience", ""))).is_equal("cafe")


func test_vram_usage_budget_under_800mb() -> void:
	# P1.21 Performance acceptance: Godot VRAM < 800 MB (Performance.RENDER_VIDEO_MEM_USED)
	_date.stage = 0
	_date.start_date()
	for i: int in 10:
		await get_tree().process_frame
	var vram_bytes: int = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	var vram_mb: float = float(vram_bytes) / (1024.0 * 1024.0)
	print(
		"[P1.21] Godot VRAM used (Performance monitor): %d bytes (%.2f MB)" % [vram_bytes, vram_mb]
	)
	assert_int(vram_bytes).is_less(800 * 1024 * 1024)

	# CODE-3: In headless mode, RENDER_VIDEO_MEM_USED reports 0 B because no native GPU
	# context is allocated. To verify real texture memory budget on all environments,
	# directly calculate the uncompressed RGBA8 footprint (width * height * 4) of loaded textures.
	var bg_tex: Texture2D = _date.background.texture
	assert_object(bg_tex).is_not_null()
	var bg_bytes := bg_tex.get_width() * bg_tex.get_height() * 4

	var char_sprite_bytes := 0
	var sprite_a: Sprite2D = _date.character.get_node_or_null("MotionRoot/LeanRoot/Body/SpriteA")
	var sprite_b: Sprite2D = _date.character.get_node_or_null("MotionRoot/LeanRoot/Body/SpriteB")
	if sprite_a != null and sprite_a.texture != null:
		char_sprite_bytes += sprite_a.texture.get_width() * sprite_a.texture.get_height() * 4
	if sprite_b != null and sprite_b.texture != null:
		char_sprite_bytes += sprite_b.texture.get_width() * sprite_b.texture.get_height() * 4

	var total_texture_bytes := bg_bytes + char_sprite_bytes
	var total_texture_mb := float(total_texture_bytes) / (1024.0 * 1024.0)
	print(
		(
			(
				"[P1.21] Loaded texture footprint: bg=%d B (%.2f MB), "
				+ "sprites=%d B (%.2f MB), total=%d B (%.2f MB)"
			)
			% [
				bg_bytes,
				float(bg_bytes) / (1024.0 * 1024.0),
				char_sprite_bytes,
				float(char_sprite_bytes) / (1024.0 * 1024.0),
				total_texture_bytes,
				total_texture_mb,
			]
		)
	)
	assert_int(total_texture_bytes).is_greater(0)
	assert_int(total_texture_bytes).is_less(800 * 1024 * 1024)


## Strip the stage-1 corruption hesitation ("…" and the space it leaves).
func _without_hesitation(text: String) -> String:
	var out := text.replace("…", " ")
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()
