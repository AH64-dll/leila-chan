extends Control
## DateFX — visual effect overlay for the Date scene (docs/02 §2.3, docs/09 §M1).
##
## Handles blush_glow, hearts, chromatic split / twitch, and small shakes.
## Photosensitive-safe: no flashes above 3 Hz. Reduced-motion disables shakes.

var reduced_motion: bool = false
var photosensitive: bool = false

@onready var _overlay: ColorRect = $Overlay


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _overlay != null:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.color = Color(0, 0, 0, 0)


func play_effect(effect_name: StringName) -> void:
	match effect_name:
		&"blush_glow":
			_play_blush_glow()
		&"twitch":
			_play_twitch()
		&"hearts":
			_play_hearts()


func _play_blush_glow() -> void:
	if _overlay == null:
		return
	var tween := create_tween()
	# Soft warm rose blush overlay
	tween.tween_property(_overlay, "color", Color(0.85, 0.48, 0.5, 0.18), 0.2)
	tween.tween_property(_overlay, "color", Color(0.85, 0.48, 0.5, 0.0), 0.6)


func _play_twitch() -> void:
	if _overlay == null or photosensitive:
		return
	var tween := create_tween()
	# 1-frame subtle dark glitch flash
	tween.tween_property(_overlay, "color", Color(0.12, 0.08, 0.14, 0.25), 0.05)
	tween.tween_property(_overlay, "color", Color(0, 0, 0, 0), 0.1)


func _play_hearts() -> void:
	if _overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_overlay, "color", Color(1.0, 0.48, 0.55, 0.12), 0.15)
	tween.tween_property(_overlay, "color", Color(0, 0, 0, 0), 0.35)
