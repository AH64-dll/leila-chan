extends Node
## P2.15 dev tool — holds every stage FX live on the real Date scene and
## reports frame-time percentiles, so "60 fps held" is a measurement.
## Needs a display server (xvfb or a desktop): --headless uses the dummy
## renderer, where a frame time means nothing.
##   xvfb-run -a ./tools/godot.sh --path game res://tools/FxBench.tscn -- [seconds]
##
## The six cues are re-fired four times a second through the host, so flicker,
## darken, vignette_red, glitch, text_bleed and shake_big overlap the way a
## worst-case beat would, on top of the stage-5 desaturation pass. The first
## seconds are warm-up (shader compilation must not land in the samples).

const DateScene := preload("res://scenes/Date.tscn")
const EFFECTS: PackedStringArray = [
	"shake_big", "flicker", "darken", "vignette_red", "glitch", "text_bleed"
]
const BUDGET_MS := 1000.0 / 60.0
const REFIRE_S := 0.25


func _ready() -> void:
	var seconds := 6.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.is_valid_float() and arg.to_float() > 0.0:
			seconds = arg.to_float()
	if DisplayServer.get_name() == "headless":
		print("fx_bench: headless renderer — frame times are meaningless, skipping")
		get_tree().quit(0)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0  # measure the ceiling, not the display's refresh rate
	var date = DateScene.instantiate()
	date.stage = 5
	date.auto_start = false
	add_child(date)
	await _wait(1.5)  # stage ramp + first-time shader compilation
	date.chat_ui.begin_beat(0)
	date.chat_ui.say_chunk(0, "Hold still. This will only take a moment.")
	date.chat_ui.end_beat(0)
	for effect: String in EFFECTS:
		date.character.play_fx(effect)  # warm every shader before sampling
	await _wait(1.0)

	var samples: Array[float] = []
	var total := 0.0
	var since_refire := REFIRE_S  # fire on the first sampled frame
	var last := Time.get_ticks_usec()
	while total < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - last) / 1000.0)
		total += float(now - last) / 1_000_000.0
		last = now
		since_refire += samples[-1] / 1000.0
		if since_refire >= REFIRE_S:
			since_refire = 0.0
			for effect: String in EFFECTS:
				date.character.play_fx(effect)

	samples.sort()
	var count := samples.size()
	var average := 0.0
	for sample: float in samples:
		average += sample
	average /= float(count)
	var p95 := samples[mini(int(float(count) * 0.95), count - 1)]
	var p99 := samples[mini(int(float(count) * 0.99), count - 1)]
	print(
		(
			(
				"fx_bench: %d frames in %.2fs | avg %.2f ms (%.1f fps) | p95 %.2f ms (%.1f fps)"
				+ " | p99 %.2f ms | worst %.2f ms | all six effects + stage-5 desaturation"
			)
			% [
				count,
				total,
				average,
				1000.0 / average,
				p95,
				1000.0 / p95,
				p99,
				samples[count - 1],
			]
		)
	)
	if p95 <= BUDGET_MS:
		print(
			"fx_bench: PASS — p95 within the 60 fps budget (%.2f ms <= %.2f ms)" % [p95, BUDGET_MS]
		)
		get_tree().quit(0)
	else:
		printerr(
			"fx_bench: FAIL — p95 %.2f ms exceeds the 60 fps budget %.2f ms" % [p95, BUDGET_MS]
		)
		get_tree().quit(1)


func _wait(seconds: float) -> void:
	var t := 0.0
	var last := Time.get_ticks_usec()
	while t < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		t += float(now - last) / 1_000_000.0
		last = now
