extends Node
## P2.15 dev tool — renders the stage FX on the real Date scene and saves one
## PNG per effect for the handoff. Needs a display server (xvfb-run or a
## desktop; --headless renders a blank viewport). Usage:
##   xvfb-run -a ./tools/godot.sh --path game res://tools/FxShot.tscn -- <out_dir>
##
## The scene opens at stage 5 so the desaturation baseline is on, and a beat is
## typed into the text box so text_bleed has real text to bleed. Each capture
## starts from clear_screen_fx() and waits in real time for the effect's own
## peak: a fade gets its hold, glitch is caught in its first frames, and the
## normal flicker is captured twice (dip and lit) so both strobe states are in
## the handoff. The photosensitive dim is the accessibility evidence.

const DateScene := preload("res://scenes/Date.tscn")
const SAY := "You came back. I counted every second, you know. Every single one."

var _out := "user://fx_shots"
var _date  # the live Date scene the shots come from


func _ready() -> void:
	Engine.max_fps = 60  # frame pacing is the game's; captures then match it
	for arg: String in OS.get_cmdline_user_args():
		if arg.contains("/"):
			_out = arg
	DirAccess.make_dir_recursive_absolute(_out)
	_date = DateScene.instantiate()
	_date.stage = 5
	_date.auto_start = false
	add_child(_date)
	await _wait(1.0)  # the stage baseline ramps in over FX_STAGE_FADE_S
	_date.chat_ui.begin_beat(0)
	_date.chat_ui.say_chunk(0, SAY)
	_date.chat_ui.end_beat(0)
	await _wait(0.7)  # typewriter reveal
	_shot("00_stage5_baseline")

	await _capture("darken", 0.35)
	await _capture("vignette_red", 0.3)
	await _glitch_shot()
	await _capture("text_bleed", 0.4)
	await _capture("shake_big", 0.12)
	await _flicker_normal_shots()

	# flicker, photosensitive mode: one steady dim, no strobe
	_date.set_photosensitive(true)
	_date.character.play_fx("flicker")
	await _wait(0.55)
	_shot("08_flicker_photosensitive_dim")
	_date.set_photosensitive(false)
	_date.character.clear_screen_fx()

	# stage 0 for comparison: no desaturation pass at all
	FX.set_stage(0)
	await _wait(1.0)
	_shot("09_stage0_clean")
	print("fx_shot: done -> ", _out)
	_date.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


## Fires one cue from a neutral screen and captures it at `peak_s`.
func _capture(effect: String, peak_s: float) -> void:
	_date.character.clear_screen_fx()
	await _wait(0.1)
	_date.character.play_fx(effect)
	await _wait(peak_s)
	_shot(_name_for(effect))


func _glitch_shot() -> void:
	_date.character.clear_screen_fx()
	await _wait(0.1)
	_date.character.play_fx("glitch")  # full strength on the first frame
	await get_tree().process_frame
	_shot("03_glitch_full_screen")


## Normal flicker: the pattern opens on a dip, then lights back up at ~0.05 s.
func _flicker_normal_shots() -> void:
	_date.character.clear_screen_fx()
	await _wait(0.1)
	_date.character.play_fx("flicker")
	await _wait(0.02)
	_shot("06_flicker_normal_dip")
	await _wait(0.06)
	_shot("07_flicker_normal_lit")


func _name_for(effect: String) -> String:
	match effect:
		"darken":
			return "01_darken_40_percent"
		"vignette_red":
			return "02_vignette_red"
		"text_bleed":
			return "04_text_bleed"
		"shake_big":
			return "05_shake_big"
		_:
			return effect


## Real-time wait: an uncapped renderer (xvfb, vsync refused) runs far faster
## than 60 fps, so counting frames would under-wait and capture effects that
## should already have finished.
func _wait(seconds: float) -> void:
	var t := 0.0
	var last := Time.get_ticks_usec()
	while t < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		t += float(now - last) / 1_000_000.0
		last = now


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join(name + ".png")
	var err := img.save_png(path)
	print("fx_shot: saved ", path, " err=", err, " size=", img.get_size())
	# the uniforms at capture time — the handoff cites these, not impressions
	print("fx_shot:   ", name, " | ", _fx_state())


## Every screen uniform in one line; a capture is only evidence if the state
## that produced it is known.
func _fx_state() -> String:
	var mat: ShaderMaterial = _date.character._stage_mat
	return (
		(
			"desat=%.2f flicker=%.2f darken=%.2f vignette=%.2f glitch=%.2f bleed=%.2f"
			+ " | bleed_box=%s"
		)
		% [
			float(mat.get_shader_parameter("desaturation")),
			float(mat.get_shader_parameter("flicker")),
			float(mat.get_shader_parameter("darken")),
			float(mat.get_shader_parameter("vignette")),
			float(mat.get_shader_parameter("glitch")),
			float(mat.get_shader_parameter("bleed")),
			str(mat.get_shader_parameter("bleed_rect")),
		]
	)
