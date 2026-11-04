extends Node2D
## Character — sprite stack, crossfade, motion, camera presets and the FX host.
## docs/07 §3.3 stack (Shadow · Body · Overlay · FX + Camera2D) and docs/03 §4
## (crossfade 120-200 ms, motion presets by intensity/family, i3 camera push).
## Driven per beat: set_feeling() resolves through SpriteResolver and starts the
## crossfade on the same call, before the beat's say text (role playbook).
## P1.11: the scene is also FX.gd's visual host — the autoload owns gates and
## cooldowns (docs/02 §5), play_fx() owns HOW each docs/02 §2.3 effect looks.
## P2.15 adds the stage-3/4 vocabulary (shake_big, flicker, darken,
## vignette_red, glitch, text_bleed) and the stage baseline (desaturation):
## FX.gd names the casting.stage_fx row, apply_stage_fx() ramps it.

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
## --- Stage FX (P2.15, docs/02 §2.3): docs/02 §5 owns the budgets and FX.gd
## owns the gates; these are the looks. ONE screen shader composites the whole
## stage vocabulary — a second full-screen sampling shader would re-sample the
## pre-effect screen and erase this one (Godot copies the screen once a frame),
## so the effects are uniforms on this single pass, not stacked rects.
const STAGE_FX_SHADER := preload("res://shaders/stage_fx.gdshader")
const FX_SHAKE_BIG_S := 0.6  # docs/02 §2.3 "0.6 s heavy shake"
const FX_SHAKE_BIG_PX := 10.0
const FX_DARKEN_TO := 0.4  # docs/02 §2.3 "scene darkens to 40%"
const FX_DARKEN_S := 0.3
const FX_DARKEN_HOLD_S := 0.7
const FX_FLICKER_DIM_LEVEL := 0.55  # photosensitive flicker: one dim, no strobe
## docs/02 §2.3's hard limit: no luminance change faster than 3 Hz. The
## photosensitive flicker is built from steps at least this long (and the code
## clamps each step to it, so the constant is a guarantee, not a comment).
const FX_FLASH_MAX_HZ := 3.0
const FX_FLASH_MIN_STEP_S := 1.0 / FX_FLASH_MAX_HZ
## flicker timeline, normal mode: [duration_s, level]. 40-110 ms steps read as a
## failing fluorescent tube; unconditionally unsafe, so photosensitive mode
## never plays it (see flicker_pattern()).
const FX_FLICKER_STEPS: Array = [
	[0.05, 0.32],
	[0.07, 1.0],
	[0.04, 0.28],
	[0.11, 1.0],
	[0.05, 0.35],
	[0.09, 1.0],
	[0.06, 0.3],
	[0.16, 1.0],
]
## flicker timeline, photosensitive mode: the doc's "dim instead" — one ramp
## down, a hold, one ramp back. Each ramp is one third of a second, so the cue
## has two luminance edges in 1.17 s: at most 2 Hz against the 3 Hz limit.
const FX_FLICKER_DIM_STEPS: Array = [
	[FX_FLASH_MIN_STEP_S, FX_FLICKER_DIM_LEVEL],
	[0.5, FX_FLICKER_DIM_LEVEL],
	[FX_FLASH_MIN_STEP_S, 1.0],
]
const FX_VIGNETTE_S := 0.9
const FX_VIGNETTE_STRENGTH := 0.9
## docs/02 §2.3: the vignette's pulse is a smooth sine; pinning it in the host
## (not the .gdshader default) keeps the accessibility ceiling enforced here.
const FX_VIGNETTE_PULSE_HZ := 1.4
const FX_GLITCH_S := 0.35  # one burst; the shader animates the scanlines
const FX_BLEED_S := 1.1  # text_bleed in, hold, drain
const FX_BLEED_LENGTH := 0.06  # uv: how far below the box the drips reach
const FX_STAGE_FADE_S := 0.8  # docs/01 §3: a stage change reads as a drain

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
var photosensitive := false  # docs/02 §2.3: flicker dims instead of strobing
var current_sprite := ""

var _cam_preset := "full"
var _cam_live := "full"  # target the camera is heading to/resting on (incl. i3 push)
var _current: Sprite2D
var _incoming: Sprite2D
var _motion := "breathe"
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
var _zoom_token := 0  # guards a zoom_face return against newer camera moves
var _glitch_frames := 0  # remaining frames the chromatic split stays visible
var _heart_tex: Texture2D
var _sparkle_tex: Texture2D
## Screen-effect timelines, one slot per effect name, so a re-fire restarts only
## its own effect (flicker and glitch may overlap). Reduced motion kills "shake".
var _screen_tweens := {}
## Cues whose timeline is still in flight. Pass visibility must not be derived
## from the uniforms alone: a stepped cue (`flicker`) sits at exactly 1.0 between
## its dips, so "every uniform at rest" does not mean the cue has ended.
var _live_fx := {}
## The one full-screen stage pass, shared by every docs/02 §2.3 effect.
var _stage_mat: ShaderMaterial
## Live values of that pass's uniforms. Tracked here instead of read back from
## the material: an unset ShaderMaterial parameter reads as null, so a read-back
## would have to special-case "never set yet" on every path.
var _desaturation := 0.0
var _flicker := 1.0
var _darken := 1.0
var _vignette := 0.0
var _glitch := 0.0
var _split := 0.0
var _bleed := 0.0
## Where the dialogue box is, for text_bleed. A callable because the Date scene
## owns the UI: the rect must be read at fire time, not at install time.
var _bleed_rect_provider: Callable = Callable()

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
@onready var _stage_fx: ColorRect = $OverlayFX/StageFX


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
	if _glitch_frames > 0:  # the twitch's colour split lives 1-2 frames
		_glitch_frames -= 1
		if _glitch_frames == 0:
			_set_split(0.0)
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
	_apply_motion(String(packet.get("motion", "breathe")))
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
		_apply_motion(_motion)  # re-run the preset with shakes/drifts cut
		_cut_fx_motion()  # in-flight fx: kill shake, drop drifting hearts
		# an in-flight camera move must not keep animating: kill the tween and
		# snap to the LIVE target (an intensity-3 push stays pushed)
		_camera_to(_cam_live, true)


## docs/02 §2.3 photosensitive-safe mode. The flicker cue keeps firing — only
## its look changes (a dim instead of a strobe) — so an in-flight normal
## flicker is cut here and the light returns in one slow step; a fresh flicker
## then uses flicker_pattern().
func set_photosensitive(enabled: bool) -> void:
	photosensitive = enabled
	if not enabled:
		return
	# only a *running* flicker needs cutting; a finished timeline in the slot
	# must not restart a pointless recovery fade
	var running: Tween = _screen_tweens.get("flicker")
	if running == null or not running.is_valid() or not running.is_running():
		return
	var tween := _restart_screen_tween("flicker")
	tween.tween_method(_set_flicker_level, flicker_level(), 1.0, FX_FLASH_MIN_STEP_S)
	tween.tween_callback(_end_fx.bind("flicker"))


## The flicker timeline the host will play in the current mode. Public so the
## 3 Hz rule can be checked on the pattern itself, not only on sampled frames.
func flicker_pattern() -> Array:
	return FX_FLICKER_DIM_STEPS if photosensitive else FX_FLICKER_STEPS


## Current screen-luminance level of the flicker (1.0 = untouched screen).
func flicker_level() -> float:
	return _flicker


## Stage baseline (P2.15): FX.gd resolved the casting.stage_fx row and names it
## here. The ramp makes a stage change read as a drain (docs/01 §3) rather than
## a snap; amount 0 hides the pass entirely.
func apply_stage_fx(profile: Dictionary) -> void:
	var amount := clampf(float(profile.get("desaturation", 0.0)), 0.0, 1.0)
	if amount > 0.0:
		_stage_fx.visible = true  # the tween starts at 0: show it before it ramps
	var tween := _restart_screen_tween("desaturate")
	tween.tween_method(_set_desaturation, _desaturation, amount, FX_STAGE_FADE_S)
	tween.tween_callback(_refresh_stage_fx)


## Where the dialogue box sits, for text_bleed (docs/02 §2.3). The Date scene
## owns the UI layout, so it supplies a callable that answers in viewport px.
func set_bleed_rect_provider(provider: Callable) -> void:
	_bleed_rect_provider = provider


## Drops every transient screen effect back to neutral: timelines killed,
## uniforms at rest, rects hidden. Dev tools use it for isolated captures and
## a scene reset uses it so no effect survives its scene. The stage baseline
## (desaturation) is not transient — it belongs to FX.stage and stays.
func clear_screen_fx() -> void:
	var keys: Array = _screen_tweens.keys()
	for key: String in keys:
		if key == "desaturate":
			continue
		var tween: Tween = _screen_tweens[key]
		if tween != null and tween.is_valid():
			tween.kill()
		_screen_tweens.erase(key)
	_live_fx.clear()
	# a killed shake tween leaves the camera on its last interpolated offset
	_cam.offset = Vector2.ZERO
	_set_flicker_level(1.0)
	_set_darken_level(1.0)
	_set_vignette_strength(0.0)
	_set_glitch_strength(0.0)
	_set_split(0.0)
	_set_bleed_amount(0.0)
	_refresh_stage_fx()


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
			_fx_shake(FX_SHAKE_S, FX_SHAKE_PX)
		"zoom_face":
			_fx_zoom_face()
		"shake_big":
			if reduced_motion:
				return "reduced_motion"
			_fx_shake(FX_SHAKE_BIG_S, FX_SHAKE_BIG_PX)
		"flicker":
			_fx_flicker()
		"darken":
			_fx_darken()
		"vignette_red":
			_fx_vignette_red()
		"glitch":
			_fx_glitch()
		"text_bleed":
			_fx_text_bleed()
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


func _apply_motion(name: String) -> void:
	_reset_motion_state()
	_motion = name if name in MOTION_NAMES else "breathe"
	match _motion:
		"bounce":
			if not reduced_motion:  # 6 px hop, 180 ms
				_motion_tween = create_tween()
				(
					_motion_tween
					. tween_property(_motion_root, "position:y", FEET.y - 6.0, 0.09)
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
			if not reduced_motion:  # +-4 px over 250 ms
				_motion_tween = create_tween()
				for off: float in [4.0, -4.0, 3.0, -3.0, 0.0]:
					_motion_tween.tween_property(_motion_root, "position:x", FEET.x + off, 0.05)
		"sink":
			if reduced_motion:  # drift cut; the 2% darken stays
				_set_darkness(0.98)
			else:  # drops 10 px over 1 s and darkens 2%
				_motion_tween = create_tween().set_parallel(true)
				_motion_tween.tween_property(_motion_root, "position:y", FEET.y + 10.0, 1.0)
				for s: Sprite2D in [_sprite_a, _sprite_b]:
					_motion_tween.tween_property(s, "self_modulate", Color(0.98, 0.98, 0.98), 1.0)
		"lean_in":  # zoom 1.0 -> 1.15 toward the face (LeanRoot pivot = eyes)
			if reduced_motion:  # not animated: she is simply closer, statically
				_lean_root.scale = Vector2(1.15, 1.15)
			else:
				_motion_tween = create_tween()
				_motion_tween.tween_property(_lean_root, "scale", Vector2(1.15, 1.15), 0.35)
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
	while _tremble_t >= 1.0 / 30.0:  # +-1 px jitter @ 30 Hz while the beat lasts
		_tremble_t -= 1.0 / 30.0
		_lean_root.position = _lean_base + Vector2(randf_range(-1, 1), randf_range(-1, 1))


func _process_twitch(delta: float) -> void:
	_twitch_t += delta
	if _twitch_t >= _twitch_next:  # a 1-frame offset every 2-5 s
		_twitch_t = 0.0
		_twitch_next = randf_range(2.0, 5.0)
		twitch_fired.emit()
		if not reduced_motion:
			_lean_root.position = (
				_lean_base + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
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
	# P2.15: every stage effect is a uniform on one screen pass, seeded here so
	# a test (or the shader itself) never depends on the .gdshader defaults.
	_stage_mat = ShaderMaterial.new()
	_stage_mat.shader = STAGE_FX_SHADER
	_stage_fx.material = _stage_mat
	_set_desaturation(0.0)
	_set_flicker_level(1.0)
	_set_darken_level(1.0)
	_set_vignette_strength(0.0)
	_set_glitch_strength(0.0)
	_set_bleed_amount(0.0)
	_set_split(0.0)  # refreshes the pass (hidden at rest)
	_stage_mat.set_shader_parameter("vignette_pulse_hz", FX_VIGNETTE_PULSE_HZ)
	_stage_mat.set_shader_parameter("bleed_length", FX_BLEED_LENGTH)


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


## Camera shake: decaying random offsets on the camera (the viewport shake the
## doc calls for; MotionRoot is reserved for body motion). Shared by
## shake_small (0.2 s / 4 px) and shake_big (0.6 s / 10 px) — one move, the
## doc's two amplitudes. Callers handle reduced motion: shakes are cut, not
## softened.
func _fx_shake(duration: float, amplitude: float) -> void:
	var tween := _restart_screen_tween("shake")
	var steps := maxi(1, int(duration / 0.04))  # 25 Hz bumps; decays into the 0
	for i: int in steps:
		var decay := 1.0 - float(i) / float(steps)
		var off := Vector2(
			randf_range(-amplitude, amplitude) * decay, randf_range(-amplitude, amplitude) * decay
		)
		tween.tween_property(_cam, "offset", off, 0.04)
	tween.tween_property(_cam, "offset", Vector2.ZERO, 0.02)


## One tween per effect name: a re-fire restarts its own effect and leaves the
## others (flicker + glitch can overlap) running.
func _restart_screen_tween(name: String) -> Tween:
	if _screen_tweens.has(name):
		var previous: Tween = _screen_tweens[name]
		if previous != null and previous.is_valid():
			previous.kill()
	var tween := create_tween()
	_screen_tweens[name] = tween
	return tween


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


## flicker: the lights fail. Normal mode is the stepped timeline; in
## photosensitive mode (docs/02 §2.3) the same cue becomes one slow dim, so no
## luminance edge comes faster than FX_FLASH_MAX_HZ. Each safe step is clamped
## to FX_FLASH_MIN_STEP_S here, not just asserted in tests.
func _fx_flicker() -> void:
	_stage_fx.visible = true
	_live_fx["flicker"] = true
	var tween := _restart_screen_tween("flicker")
	if photosensitive:
		var level := flicker_level()
		for step: Array in FX_FLICKER_DIM_STEPS:
			var target := float(step[1])
			var duration := maxf(float(step[0]), FX_FLASH_MIN_STEP_S)
			tween.tween_method(_set_flicker_level, level, target, duration)
			level = target
	else:
		for step: Array in FX_FLICKER_STEPS:
			tween.tween_callback(_set_flicker_level.bind(float(step[1])))
			tween.tween_interval(float(step[0]))
	tween.tween_callback(_end_fx.bind("flicker"))


## darken: docs/02 §2.3 "scene darkens to 40%" — down, hold, back. A fade, not
## a strobe, so the photosensitive mode needs no variant.
func _fx_darken() -> void:
	_stage_fx.visible = true
	_live_fx["darken"] = true
	var tween := _restart_screen_tween("darken")
	tween.tween_method(_set_darken_level, _darken, FX_DARKEN_TO, FX_DARKEN_S)
	tween.tween_interval(FX_DARKEN_HOLD_S)
	tween.tween_method(_set_darken_level, FX_DARKEN_TO, 1.0, FX_DARKEN_S)
	tween.tween_callback(_end_fx.bind("darken"))


## vignette_red: docs/02 §2.3 "red pulsing vignette". The pulse lives in the
## pass at 1.4 Hz (under the 3 Hz rule, so it needs no safe variant); the host
## only fades the envelope in and out.
func _fx_vignette_red() -> void:
	_stage_fx.visible = true
	_live_fx["vignette_red"] = true
	var tween := _restart_screen_tween("vignette_red")
	tween.tween_method(_set_vignette_strength, _vignette, FX_VIGNETTE_STRENGTH, FX_VIGNETTE_S * 0.3)
	tween.tween_interval(FX_VIGNETTE_S * 0.3)
	tween.tween_method(_set_vignette_strength, FX_VIGNETTE_STRENGTH, 0.0, FX_VIGNETTE_S * 0.4)
	tween.tween_callback(_end_fx.bind("vignette_red"))


## glitch: docs/02 §2.3 "scanline displacement + RGB split on the whole screen"
## — a 0.35 s burst, full strength for the first frames then decaying. The
## pass animates its own scanlines; the seed makes each firing a new pattern.
func _fx_glitch() -> void:
	_stage_mat.set_shader_parameter("glitch_seed", randf())
	# full strength on the very frame the cue fires, then decay (a tween's
	# `from` lands one frame late, which would flash the un-glitched screen)
	_set_glitch_strength(1.0)
	_stage_fx.visible = true
	_live_fx["glitch"] = true
	var tween := _restart_screen_tween("glitch")
	(
		tween
		. tween_method(_set_glitch_strength, 1.0, 0.0, FX_GLITCH_S)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_IN)
	)
	tween.tween_callback(_end_fx.bind("glitch"))


## text_bleed: docs/02 §2.3 "text drips/smears out of the box". The Date scene
## supplies the live text box rect; a bare Character scene falls back to the
## shader's default band, so the cue never silently does nothing.
func _fx_text_bleed() -> void:
	if _bleed_rect_provider.is_valid():
		_set_bleed_rect(_bleed_rect_provider.call())
	_stage_mat.set_shader_parameter("bleed_seed", randf())
	_stage_fx.visible = true
	_live_fx["text_bleed"] = true
	var tween := _restart_screen_tween("text_bleed")
	tween.tween_method(_set_bleed_amount, _bleed, 1.0, FX_BLEED_S * 0.25)
	tween.tween_interval(FX_BLEED_S * 0.35)
	tween.tween_method(_set_bleed_amount, 1.0, 0.0, FX_BLEED_S * 0.4)
	tween.tween_callback(_end_fx.bind("text_bleed"))


## The bleed band starts at the box's bottom edge; the pass wants uv space.
func _set_bleed_rect(rect_px: Rect2) -> void:
	var min_uv := Vector2(rect_px.position.x / VIEW.x, rect_px.position.y / VIEW.y)
	var max_uv := Vector2(rect_px.end.x / VIEW.x, rect_px.end.y / VIEW.y)
	min_uv = min_uv.clamp(Vector2.ZERO, Vector2.ONE)
	max_uv = max_uv.clamp(Vector2.ZERO, Vector2.ONE)
	_stage_mat.set_shader_parameter("bleed_rect", Vector4(min_uv.x, min_uv.y, max_uv.x, max_uv.y))


func _set_flicker_level(value: float) -> void:
	_flicker = value
	_stage_mat.set_shader_parameter("flicker", value)


func _set_darken_level(value: float) -> void:
	_darken = value
	_stage_mat.set_shader_parameter("darken", value)


func _set_vignette_strength(value: float) -> void:
	_vignette = value
	_stage_mat.set_shader_parameter("vignette", value)


func _set_glitch_strength(value: float) -> void:
	_glitch = value
	_stage_mat.set_shader_parameter("glitch", value)


func _set_split(value: float) -> void:
	_split = value
	_stage_mat.set_shader_parameter("split", value)
	_refresh_stage_fx()


func _set_bleed_amount(value: float) -> void:
	_bleed = value
	_stage_mat.set_shader_parameter("bleed", value)


func _set_desaturation(value: float) -> void:
	_desaturation = value
	_stage_mat.set_shader_parameter("desaturation", value)


## Ends one cue: it no longer holds the pass on by itself. Called from that
## cue's own timeline, so a re-fire that replaces the tween keeps the slot live.
func _end_fx(name: String) -> void:
	_live_fx.erase(name)
	_refresh_stage_fx()


## The pass is hidden whenever no cue is in flight and every uniform is at
## rest, so a clean stage pays no full-screen blit at all. Uniform values alone
## are not enough to decide that: a stepped cue (`flicker`) reads 1.0 between
## its dips, and hiding the pass there would erase the rest of the timeline.
func _refresh_stage_fx() -> void:
	_stage_fx.visible = (
		not _live_fx.is_empty()
		or _desaturation > 0.0
		or _flicker < 1.0
		or _darken < 1.0
		or _vignette > 0.0
		or _glitch > 0.0
		or _split > 0.0
		or _bleed > 0.0
	)


## Reduced motion landed mid-effect: kill the camera shake outright and drop
## drifting particles (they'd otherwise finish a drift the mode forbids).
## The vignette stays — it is colour, not motion.
func _cut_fx_motion() -> void:
	if _screen_tweens.has("shake"):
		var shake: Tween = _screen_tweens["shake"]
		if shake != null and shake.is_valid():
			shake.kill()
		_screen_tweens.erase("shake")
	_cam.offset = Vector2.ZERO
	for child: Node in _fx_root.get_children():
		_fx_root.remove_child(child)
		child.queue_free()


## twitch_fired hook (P1.10 contract): a 1-2 frame colour split. It rides the
## same screen pass as the stage FX (a second sampling rect would erase them);
## colour separation only, no luminance flash.
func _on_twitch_fired() -> void:
	_set_split(1.0)
	_glitch_frames = 2
