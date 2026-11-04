extends Node2D
## Character — sprite stack, crossfade, motion, camera presets and the FX host.
## docs/07 §3.3 stack (Shadow · Body · Overlay · FX + Camera2D) and docs/03 §4
## (crossfade 120-200 ms, motion presets by intensity/family, i3 camera push).
## Driven per beat: set_feeling() resolves through SpriteResolver and starts the
## crossfade on the same call, before the beat's say text (role playbook).
## P1.11: the scene is also FX.gd's visual host — the autoload owns gates and
## cooldowns (docs/02 §5), play_fx() owns HOW each docs/02 §2.3 effect looks.

signal sprite_changed(sprite_id: String)
signal feeling_applied(packet: Dictionary)
## FX layer hook (P1.11): fires on each twitch/glitch frame for the chromatic split.
signal twitch_fired

const CROSSFADE_MS := 140.0  # docs/03 §4 allows 120-200 ms; task budget is <= 150 ms
const DISPLAY_SCALE := 0.5  # x2 art (768x1376) at 1:1 texels in the 384x688 viewport
const VIEW := Vector2(384.0, 688.0)
const FEET := Vector2(192.0, 668.0)  # sprite alpha bbox bottom ~= y673 native
const BREATH_PERIOD := 4.0
const BREATH_MID := 1.003  # scale.y oscillates 1.000 <-> 1.006 (docs/03 §4)
const BREATH_AMP := 0.003
const CAMERA_MOVE_S := 0.35
## docs/03 §4 displacement baselines, at i2 (casting.motion_intensity "2" = 1.0).
## The packet's motion_scale multiplies every one of them; there is no extra art.
const HOP_PX := 6.0  # bounce
const SHAKE_PX := 4.0  # shake
const SINK_PX := 10.0  # sink
const LEAN_ZOOM := 0.15  # lean_in: 1.0 -> 1.15
const TREMBLE_PX := 1.0  # tremble
const TWITCH_PX := 2.0  # twitch / glitch offset
const MOTION_NAMES: PackedStringArray = [
	"breathe", "bounce", "shake", "tremble", "sink", "lean_in", "freeze", "twitch", "glitch"
]
const CAMERA_NAMES: PackedStringArray = ["full", "knees", "bust", "face"]
## docs/07 §3.3 names the presets only. Every crop settles on an INTEGER zoom —
## 1 native px -> N viewport px, so nearest keeps the replication uniform — on a
## pixel-grid position. The zooms form a 1/2/3/4 ladder so each preset is a
## visibly different shot (knees and bust would be near-identical at the same
## zoom; the r1 fractional fits were not pixel-perfect — see P1.10 code r1).
const CAMERA_ZOOM := {"full": 1.0, "knees": 2.0, "bust": 3.0, "face": 4.0}
## "knees" is the medium shot: window x 96-288 / y 24-368, head to mid-thigh;
## wide poses reach the frame edge (2x is the loosest integer step above full).
const KNEES_ANCHOR := Vector2(192, 196)
## "face" frames the eyes_native midpoint; the eye line sits 24 px above centre.
const FACE_DROP := 24.0
## --- FX v1 (P1.11, docs/02 §2.3): budgets live in the FX autoload; these are
## only the look. All colours come from art/leila/palette.json ramps.
const FX_SHAKE_S := 0.2  # shake_small: docs/02 §2.3 "0.2 s screen shake"
const FX_SHAKE_PX := 4.0
const FX_ZOOM_HOLD_S := 1.0  # zoom_face lingers, then the camera returns
const FX_GLOW_S := 0.9  # blush_glow pulse, in/out included
const FX_HEARTS_S := 0.8
const FX_SPARKLE_S := 0.7
const FX_PIXEL_SCALE := Vector2(0.5, 0.5)  # fx sprites are authored x2, like the body
const COL_BLUSH := Color8(217, 154, 152)  # palette.blush[0] d99a98
const COL_HEART := Color8(216, 50, 58)  # palette.eye[4] = palette.fx[0] d8323a
const COL_HEART_EDGE := Color8(155, 20, 32)  # palette.eye[3] 9b1420
const COL_SPARKLE := Color8(127, 216, 224)  # palette.fx[1] 7fd8e0
const COL_SPARKLE_CORE := Color8(251, 233, 224)  # palette.skin[4] fbe9e0
const GLITCH_SPLIT_SHADER := preload("res://shaders/glitch_split.gdshader")
## 7x6 native heart / 7x7 sparkle, drawn at 2x so one pixel = one body texel.
const HEART_ROWS: PackedStringArray = [
	" oo oo ",
	"ohhhoho",
	"ohhhhho",
	" ohhho ",
	"  oho  ",
	"   o   ",
]
const SPARKLE_ROWS: PackedStringArray = [
	"   s   ",
	"   s   ",
	"  sss  ",
	"ssswsss",
	"  sss  ",
	"   s   ",
	"   s   ",
]

var reduced_motion := false  # docs/02 §2.3: disables shakes and drifts
var current_sprite := ""

var _cam_preset := "full"
var _cam_live := "full"  # target the camera is heading to/resting on (incl. i3 push)
var _current: Sprite2D
var _incoming: Sprite2D
var _motion := "breathe"
var _motion_scale := 1.0  # casting.motion_intensity for the current beat (i2 = 1.0)
var _breathe := true
var _breath_t := 0.0
var _tremble_t := 0.0
var _twitch_t := 0.0
var _twitch_next := 3.0
var _twitch_hold := 0
var _lean_base := Vector2.ZERO
var _fade_tween: Tween
var _cam_tween: Tween
var _motion_tween: Tween
var _glow_tween: Tween
var _shake_tween: Tween
var _zoom_token := 0  # guards a zoom_face return against newer camera moves
var _glitch_frames := 0  # remaining frames the chromatic split stays visible
var _heart_tex: Texture2D
var _sparkle_tex: Texture2D

@onready var _cam: Camera2D = $Camera2D
@onready var _shadow: Polygon2D = $Shadow
@onready var _motion_root: Node2D = $MotionRoot
@onready var _lean_root: Node2D = $MotionRoot/LeanRoot
@onready var _body: Node2D = $MotionRoot/LeanRoot/Body
@onready var _overlay: Node2D = $MotionRoot/LeanRoot/Overlay
@onready var _sprite_a: Sprite2D = $MotionRoot/LeanRoot/Body/SpriteA
@onready var _sprite_b: Sprite2D = $MotionRoot/LeanRoot/Body/SpriteB
@onready var _fx_root: Node2D = $MotionRoot/LeanRoot/FX
@onready var _glow: TextureRect = $ScreenFX/BlushGlow
@onready var _glitch: ColorRect = $ScreenFX/GlitchSplit


func _ready() -> void:
	_current = _sprite_a
	_incoming = _sprite_b
	for sprite: Sprite2D in [_sprite_a, _sprite_b]:
		sprite.scale = Vector2.ONE * DISPLAY_SCALE
	_motion_root.position = FEET
	_make_shadow()
	_update_pivots("00")
	set_sprite("00", true)
	_setup_fx()
	FX.register_host(self)
	twitch_fired.connect(_on_twitch_fired)


func _exit_tree() -> void:
	FX.unregister_host(self)


func _process(delta: float) -> void:
	if _glitch_frames > 0:  # the chromatic split lives 1-2 frames per twitch
		_glitch_frames -= 1
		if _glitch_frames == 0:
			_glitch.visible = false
	_breath_t += delta
	_motion_root.scale.y = (
		BREATH_MID + BREATH_AMP * sin(TAU * _breath_t / BREATH_PERIOD) if _breathe else 1.0
	)
	match _motion:
		"tremble":
			_process_tremble(delta)
		"twitch", "glitch":
			_process_twitch(delta)


## Beat entry point (Director -> beat.feel): swap sprite, apply the resolved
## motion preset, honour the intensity-3 camera push. Starts the crossfade now.
func set_feeling(feeling: String, intensity: int, stage: int, path := "", flags := {}) -> void:
	apply_beat(SpriteResolver.resolve_beat(feeling, intensity, stage, path, flags))


## The Director's entry point when it has already resolved the beat: applying a
## finished packet keeps the stateful resolver from running twice per beat
## (anti-repeat window, second beat_resolved emission) — review CODE-4.
func apply_beat(packet: Dictionary) -> void:
	var sprite := String(packet.get("sprite", ""))
	if not sprite.is_empty() and sprite != current_sprite:
		_crossfade_to(sprite)
	_apply_motion(String(packet.get("motion", "breathe")), float(packet.get("motion_scale", 1.0)))
	var push := String(packet.get("camera", ""))
	_camera_to(push if not push.is_empty() else _cam_preset)
	feeling_applied.emit(packet)


## Direct sprite swap (title screen, tests). instant=true skips the fade.
func set_sprite(sprite_id: String, instant := false) -> void:
	if instant:
		_apply_sprite_now(sprite_id)
	elif sprite_id != current_sprite:
		_crossfade_to(sprite_id)


## Camera presets: "full" | "knees" | "bust" | "face" (docs/07 §3.3).
func set_camera(preset: String, instant := false) -> void:
	if not preset in CAMERA_NAMES:
		push_warning("Character: unknown camera preset '%s'" % preset)
		return
	_cam_preset = preset
	_camera_to(preset, instant)


func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	if enabled:
		_apply_motion(_motion, _motion_scale)  # re-run the preset with shakes/drifts cut
		_cut_fx_motion()  # in-flight fx: kill shake, drop drifting hearts
		# an in-flight camera move must not keep animating: kill the tween and
		# snap to the LIVE target (an intensity-3 push stays pushed)
		_camera_to(_cam_live, true)


## FX.gd's host contract (P1.11, docs/02 §2.3): play the visual for one
## effect. Returns "" when it played, else a skip reason — "reduced_motion"
## when the doc says the move is cut; the name set is the autoload's problem.
func play_fx(name: String) -> String:
	match name:
		"blush_glow":
			_fx_blush_glow()
		"hearts":
			_fx_hearts()
		"sparkle":
			_fx_sparkle()
		"shake_small":
			if reduced_motion:  # docs/02 §2.3: shakes are cut, not softened
				return "reduced_motion"
			_fx_shake_small()
		"zoom_face":
			_fx_zoom_face()
		_:
			return "unimplemented"
	return ""


func is_fading() -> bool:
	return _fade_tween != null and _fade_tween.is_running()


func camera_preset() -> String:
	return _cam_preset


func _load_texture(sprite_id: String) -> Texture2D:
	var path := SpriteResolver.sprite_texture_path(sprite_id)
	var tex: Resource = ResourceLoader.load(path)
	if tex is Texture2D:
		return tex
	push_error("Character: cannot load sprite texture '%s'" % path)
	return null


func _apply_sprite_now(sprite_id: String) -> void:
	var tex := _load_texture(sprite_id)
	if tex == null:
		return
	_finish_fade()
	_current.texture = tex
	_current.modulate.a = 1.0
	_incoming.modulate.a = 0.0
	current_sprite = sprite_id
	_update_pivots(sprite_id)
	sprite_changed.emit(sprite_id)


func _crossfade_to(sprite_id: String) -> void:
	var tex := _load_texture(sprite_id)
	if tex == null:
		return
	if is_fading():
		_finish_fade()
	_incoming.texture = tex
	_incoming.modulate.a = 0.0
	_body.move_child(_incoming, 1)  # incoming fades in on top of the current face
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(_incoming, "modulate:a", 1.0, CROSSFADE_MS / 1000.0)
	_fade_tween.tween_property(_current, "modulate:a", 0.0, CROSSFADE_MS / 1000.0)
	_fade_tween.chain().tween_callback(_finish_fade)
	current_sprite = sprite_id
	_update_pivots(sprite_id)
	sprite_changed.emit(sprite_id)


func _finish_fade() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_incoming.modulate.a = 1.0
	_current.modulate.a = 0.0
	var was := _current
	_current = _incoming
	_incoming = was


## Recenter the lean/zoom pivots on the new face: LeanRoot sits on the eyes_native
## midpoint, Body/Overlay on the sprite centre (all in native px coordinates).
func _update_pivots(sprite_id: String) -> void:
	var eyes: Array = SpriteResolver.casting.get("sprites", {}).get(sprite_id, {}).get(
		"eyes_native", []
	)
	var eye_mid := FEET - Vector2(0, 344)
	if eyes.size() == 2:
		eye_mid = (
			(
				Vector2(float(eyes[0][0]), float(eyes[0][1]))
				+ Vector2(float(eyes[1][0]), float(eyes[1][1]))
			)
			/ 2.0
		)
	_lean_base = eye_mid - FEET
	_lean_root.position = _lean_base
	var centre := Vector2(192, 344) - eye_mid
	_body.position = centre
	_overlay.position = centre


func _make_shadow() -> void:
	var points := PackedVector2Array()
	for i: int in 24:
		var ang := TAU * i / 24.0
		# quantised to a 2 px grid so the ellipse edge stays pixel-chunky
		points.append((Vector2(cos(ang) * 36.0, sin(ang) * 5.0) / 2.0).round() * 2.0)
	_shadow.polygon = points
	_shadow.color = Color("24121a", 0.45)  # palette shade ramp, darkest step
	_shadow.position = Vector2(192, 656)


# --- camera ---------------------------------------------------------------


func _camera_to(preset: String, instant := false) -> void:
	_cam_live = preset
	var target := _cam_target(preset)
	if instant or reduced_motion:
		if _cam_tween != null:
			_cam_tween.kill()
			_cam_tween = null
		_cam.position = target["pos"]
		_cam.zoom = Vector2.ONE * target["zoom"]
		return
	if _cam_tween != null:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN_OUT
	)
	_cam_tween.tween_property(_cam, "position", target["pos"], CAMERA_MOVE_S)
	_cam_tween.tween_property(_cam, "zoom", Vector2.ONE * target["zoom"], CAMERA_MOVE_S)


## Preset -> {zoom, pos}: fixed integer zoom on the preset's anchor, snapped to
## the 1/zoom grid and clamped so the view never leaves the 384x688 frame.
## Grid rule: (cam.pos * zoom) integer <=> native px land on whole viewport px.
func _cam_target(preset: String) -> Dictionary:
	var zoom: float = CAMERA_ZOOM[preset]
	var anchor := VIEW / 2.0
	match preset:
		"knees":
			anchor = KNEES_ANCHOR
		"bust":
			anchor = _crop_rect("bust_crop_native", Rect2(Vector2.ZERO, VIEW)).get_center()
		"face":
			anchor = _lean_base + FEET + Vector2(0, FACE_DROP)
	var pos := (anchor * zoom).round() / zoom
	var half := VIEW / (2.0 * zoom)
	pos.x = clampf(pos.x, half.x, VIEW.x - half.x)
	pos.y = clampf(pos.y, half.y, VIEW.y - half.y)
	return {"zoom": zoom, "pos": pos}


## casting bust_crop_native is [left, top, right, bottom] in native px.
func _crop_rect(field: String, fallback: Rect2) -> Rect2:
	var box: Array = SpriteResolver.casting.get("sprites", {}).get(current_sprite, {}).get(
		field, []
	)
	if box.size() != 4:
		return fallback
	var tl := Vector2(float(box[0]), float(box[1]))
	return Rect2(tl, Vector2(float(box[2]), float(box[3])) - tl)


# --- motion presets (docs/03 §4) -------------------------------------------


## docs/03 §4 presets. `scale` is the beat's casting.motion_intensity (i2 = 1.0 =
## the doc's own displacement), so the same preset reads quieter at i1 and louder
## at i3 without a second set of art.
func _apply_motion(name: String, scale := 1.0) -> void:
	_reset_motion_state()
	_motion = name if name in MOTION_NAMES else "breathe"
	_motion_scale = clampf(scale, 0.1, 3.0)
	var hop := HOP_PX * _motion_scale
	var shake := SHAKE_PX * _motion_scale
	match _motion:
		"bounce":
			if not reduced_motion:  # 6 px hop at i2, 180 ms
				_motion_tween = create_tween()
				(
					_motion_tween
					. tween_property(_motion_root, "position:y", FEET.y - hop, 0.09)
					. set_trans(Tween.TRANS_QUAD)
					. set_ease(Tween.EASE_OUT)
				)
				(
					_motion_tween
					. tween_property(_motion_root, "position:y", FEET.y, 0.09)
					. set_trans(Tween.TRANS_QUAD)
					. set_ease(Tween.EASE_IN)
				)
		"shake":
			if not reduced_motion:  # +-4 px at i2 over 250 ms
				_motion_tween = create_tween()
				for off: float in [shake, -shake, shake * 0.75, -shake * 0.75, 0.0]:
					_motion_tween.tween_property(_motion_root, "position:x", FEET.x + off, 0.05)
		"sink":
			if reduced_motion:  # drift cut; the 2% darken stays
				_set_darkness(0.98)
			else:  # drops 10 px at i2 over 1 s and darkens 2%
				_motion_tween = create_tween().set_parallel(true)
				_motion_tween.tween_property(
					_motion_root, "position:y", FEET.y + SINK_PX * _motion_scale, 1.0
				)
				for s: Sprite2D in [_sprite_a, _sprite_b]:
					_motion_tween.tween_property(s, "self_modulate", Color(0.98, 0.98, 0.98), 1.0)
		"lean_in":  # zoom toward the face (LeanRoot pivot = eyes): 1.15 at i2
			var zoom := 1.0 + LEAN_ZOOM * _motion_scale
			if reduced_motion:  # not animated: she is simply closer, statically
				_lean_root.scale = Vector2(zoom, zoom)
			else:
				_motion_tween = create_tween()
				_motion_tween.tween_property(_lean_root, "scale", Vector2(zoom, zoom), 0.35)
		"freeze":  # breathing stops — subtle and wrong, on purpose
			_breathe = false
			_motion_root.scale.y = 1.0
		"twitch", "glitch":
			_twitch_t = 0.0
			_twitch_next = randf_range(2.0, 5.0)
		# "breathe"/"tremble" run continuously in _process; unknown names settle
		# into the breathe baseline


func _reset_motion_state() -> void:
	if _motion_tween != null:
		_motion_tween.kill()
		_motion_tween = null
	_motion = "breathe"
	_breathe = true
	_motion_root.position = FEET
	_lean_root.scale = Vector2.ONE
	_lean_root.position = _lean_base
	_set_darkness(1.0)
	_tremble_t = 0.0
	_twitch_t = 0.0
	_twitch_hold = 0


func _set_darkness(level: float) -> void:
	for s: Sprite2D in [_sprite_a, _sprite_b]:
		s.self_modulate = Color(level, level, level)


func _process_tremble(delta: float) -> void:
	if reduced_motion:
		return
	_tremble_t += delta
	var amp := TREMBLE_PX * _motion_scale
	while _tremble_t >= 1.0 / 30.0:  # +-1 px jitter at i2, 30 Hz while the beat lasts
		_tremble_t -= 1.0 / 30.0
		_lean_root.position = _lean_base + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))


func _process_twitch(delta: float) -> void:
	_twitch_t += delta
	if _twitch_t >= _twitch_next:  # a 1-frame offset every 2-5 s
		_twitch_t = 0.0
		_twitch_next = randf_range(2.0, 5.0)
		twitch_fired.emit()
		if not reduced_motion:
			var amp := TWITCH_PX * _motion_scale
			_lean_root.position = (
				_lean_base + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
			)
			_twitch_hold = 1
	elif _twitch_hold > 0:
		_twitch_hold -= 1
		if _twitch_hold == 0:
			_lean_root.position = _lean_base


# --- fx v1 (docs/02 §2.3): the visuals for the autoload's trigger ----------


func _setup_fx() -> void:
	_heart_tex = _pixel_tex(HEART_ROWS, {"o": COL_HEART_EDGE, "h": COL_HEART})
	_sparkle_tex = _pixel_tex(SPARKLE_ROWS, {"s": COL_SPARKLE, "w": COL_SPARKLE_CORE})
	# pink vignette, generated: the radial gradient is authored in code because
	# a saved GradientTexture2D adds a binary resource the pipeline can't diff
	var grad := Gradient.new()
	grad.set_offsets(PackedFloat32Array([0.0, 1.0]))
	grad.set_colors(PackedColorArray([Color(COL_BLUSH, 0.34), Color(COL_BLUSH, 0.0)]))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 0.02)
	_glow.texture = gtex
	_glow.modulate.a = 0.0
	var mat := ShaderMaterial.new()
	mat.shader = GLITCH_SPLIT_SHADER
	_glitch.material = mat


## Tiny pixel-art texture from ASCII rows, authored at 2x so it sits on the
## same texel grid as the body art (0.5 display scale, nearest).
func _pixel_tex(rows: PackedStringArray, colors: Dictionary) -> ImageTexture:
	var w := rows[0].length() * 2
	var h := rows.size() * 2
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in rows.size():
		for x: int in rows[y].length():
			var key := rows[y].substr(x, 1)
			if not colors.has(key):
				continue
			img.fill_rect(Rect2i(x * 2, y * 2, 2, 2), colors[key])
	return ImageTexture.create_from_image(img)


func _fx_sprite(tex: Texture2D, pos: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.scale = FX_PIXEL_SCALE
	sprite.position = pos.round()  # particles rest on the native pixel grid
	sprite.centered = true
	_fx_root.add_child(sprite)
	return sprite


## blush_glow: pink vignette pulse (screen space — it must not track her body,
## so it lives in ScreenFX, not the FX node).
func _fx_blush_glow() -> void:
	if _glow_tween != null:
		_glow_tween.kill()
	_glow.visible = true
	_glow_tween = create_tween()
	_glow_tween.tween_property(_glow, "modulate:a", 1.0, FX_GLOW_S * 0.33).set_trans(
		Tween.TRANS_SINE
	)
	_glow_tween.tween_property(_glow, "modulate:a", 0.0, FX_GLOW_S * 0.67).set_trans(
		Tween.TRANS_SINE
	)
	_glow_tween.tween_callback(_glow.hide)


## hearts: three small hearts rise past her face. The FX node sits on the
## eyes pivot; negative y floats them up over her hairline.
func _fx_hearts() -> void:
	for i: int in 3:
		var pos := Vector2(randf_range(-42.0, 42.0), randf_range(-8.0, 12.0))
		var heart := _fx_sprite(_heart_tex, pos)
		# the particle owns its tween: freeing it in _cut_fx_motion kills both
		var tween := heart.create_tween()
		if reduced_motion:  # no drift: the heart pulses in place instead
			tween.tween_property(heart, "modulate:a", 0.0, FX_HEARTS_S)
		else:
			tween.set_parallel(true)
			tween.tween_property(heart, "position:y", pos.y - 34.0, FX_HEARTS_S)
			tween.tween_property(heart, "modulate:a", 0.0, FX_HEARTS_S)
		tween.chain().tween_callback(heart.queue_free)


## sparkle: light sparkles twinkle over her. Alpha-pulse only (colour, not
## luminance flash — stays inside the < 3 Hz photosensitive rule).
func _fx_sparkle() -> void:
	for i: int in 6:
		var pos := Vector2(randf_range(-72.0, 72.0), randf_range(-44.0, 96.0))
		var dot := _fx_sprite(_sparkle_tex, pos)
		dot.modulate.a = 0.0
		var tween := dot.create_tween()  # owned by the particle, like hearts'
		var phase := randf() * 0.25
		tween.tween_property(dot, "modulate:a", 1.0, 0.1 + phase)
		if reduced_motion:
			tween.tween_property(dot, "modulate:a", 0.0, FX_SPARKLE_S)
		else:  # a 1 texel throb reads as a twinkle at this scale
			tween.tween_property(dot, "modulate:a", 0.0, FX_SPARKLE_S)
			tween.parallel().tween_property(dot, "scale", Vector2(0.75, 0.75), FX_SPARKLE_S * 0.4)
		tween.tween_callback(dot.queue_free)


## shake_small: 0.2 s screen shake on the camera offset (the viewport shake
## doc calls for; MotionRoot is reserved for body motion).
func _fx_shake_small() -> void:
	if _shake_tween != null:
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := int(FX_SHAKE_S / 0.04)  # 25 Hz bumps; decays into the 0
	for i: int in steps:
		var decay := 1.0 - float(i) / float(steps)
		var off := Vector2(
			randf_range(-FX_SHAKE_PX, FX_SHAKE_PX) * decay,
			randf_range(-FX_SHAKE_PX, FX_SHAKE_PX) * decay
		)
		_shake_tween.tween_property(_cam, "offset", off, 0.04)
	_shake_tween.tween_property(_cam, "offset", Vector2.ZERO, 0.02)


## zoom_face: the doc's "camera to bust" is a transient look — push to the
## bust preset, hold, return to the caller's preset. The token makes a newer
## camera move (a beat's i3 push, a set_camera) win over a stale return.
func _fx_zoom_face() -> void:
	_zoom_token += 1
	var token := _zoom_token
	var back := _cam_preset
	_camera_to("bust")
	await get_tree().create_timer(FX_ZOOM_HOLD_S).timeout
	if token == _zoom_token and _cam_live == "bust":
		_camera_to(back)


## Reduced motion landed mid-effect: kill the camera shake outright and drop
## drifting particles (they'd otherwise finish a drift the mode forbids).
## The vignette stays — it is colour, not motion.
func _cut_fx_motion() -> void:
	if _shake_tween != null:
		_shake_tween.kill()
		_shake_tween = null
	_cam.offset = Vector2.ZERO
	for child: Node in _fx_root.get_children():
		_fx_root.remove_child(child)
		child.queue_free()


## twitch_fired hook (P1.10 contract): a 1-2 frame chromatic split. Colour
## separation only, no luminance flash — safe under the < 3 Hz rule even
## though twitches fire every 2-5 s.
func _on_twitch_fired() -> void:
	_glitch.visible = true
	_glitch_frames = 2
