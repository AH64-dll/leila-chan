extends Node2D
## Character — sprite stack, crossfade, motion and camera presets.
## docs/07 §3.3 stack (Shadow · Body · Overlay · FX + Camera2D) and docs/03 §4
## (crossfade 120-200 ms, motion presets by intensity/family, i3 camera push).
## Driven per beat: set_feeling() resolves through SpriteResolver and starts the
## crossfade on the same call, before the beat's say text (role playbook).

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

var reduced_motion := false  # docs/02 §2.3: disables shakes and drifts
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

@onready var _cam: Camera2D = $Camera2D
@onready var _shadow: Polygon2D = $Shadow
@onready var _motion_root: Node2D = $MotionRoot
@onready var _lean_root: Node2D = $MotionRoot/LeanRoot
@onready var _body: Node2D = $MotionRoot/LeanRoot/Body
@onready var _overlay: Node2D = $MotionRoot/LeanRoot/Overlay
@onready var _sprite_a: Sprite2D = $MotionRoot/LeanRoot/Body/SpriteA
@onready var _sprite_b: Sprite2D = $MotionRoot/LeanRoot/Body/SpriteB


func _ready() -> void:
	_current = _sprite_a
	_incoming = _sprite_b
	for sprite: Sprite2D in [_sprite_a, _sprite_b]:
		sprite.scale = Vector2.ONE * DISPLAY_SCALE
	_motion_root.position = FEET
	_make_shadow()
	_update_pivots("00")
	set_sprite("00", true)


func _process(delta: float) -> void:
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
	var packet := SpriteResolver.resolve_beat(feeling, intensity, stage, path, flags)
	var sprite := String(packet["sprite"])
	if sprite != current_sprite:
		_crossfade_to(sprite)
	_apply_motion(String(packet["motion"]))
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
		# an in-flight camera move must not keep animating: kill the tween and
		# snap to the LIVE target (an intensity-3 push stays pushed)
		_camera_to(_cam_live, true)


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
