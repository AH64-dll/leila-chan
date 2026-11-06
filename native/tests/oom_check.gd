extends SceneTree

# oom_check (P4.06e): a real out-of-memory load falls back without a crash.
# Run from the repo root, with LEILA_MODEL set:
#   timeout 300 ./tools/godot.sh --headless --path game --script "<repo>/native/tests/oom_check.gd" -- --expect-fallback=0|1
# Prints "oom_check: PASS" (exit 0) or "oom_check: FAIL ..." (exit 1). With --expect-fallback=1
# the Loading screen's Fix text must mention "graphics card" and its first action must be "fast".
# Game scripts are loaded with load(), as device_check.gd does.

const NATIVE_BACKEND_PATH := "res://llm/backends/NativeBackend.gd"
const TURN_REQUEST_PATH := "res://llm/TurnRequest.gd"
const CANCEL_TOKEN_PATH := "res://llm/LLMCancelToken.gd"
const LOADING_SCENE_PATH := "res://scenes/Loading.tscn"
const MODEL_DATA_PATH := "res://data/model.json"
const PROMPT := "Describe a quiet harbour town at dawn in several sentences."
const GENERATE_TOKENS := 30
const SHOW_CHARS := 60
const LOAD_MAX_MS := 240000
const GENERATE_MAX_MS := 120000
const SCREEN_MAX_MS := 60000
const SAMPLING := {"temperature": 0.7, "top_p": 0.9, "repeat_penalty": 1.1, "seed": 42}
## NativeBackend.generate refuses an empty schema, so a minimal one stands in for a turn schema.
const SCHEMA := {"type": "object", "properties": {"say": {"type": "string"}}, "required": ["say"]}

var _started := false
var _expect := -1
## Threads that outlived their wait are kept alive here, so Godot does not destroy them mid-run.
var _threads: Array = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	_expect = _parse_expect()
	if _expect < 0:
		_quit_fail("missing or bad --expect-fallback=0|1")
		return
	print("oom_check: expect_fallback=%d LEILA_MODEL=%s" % [_expect, OS.get_environment("LEILA_MODEL")])

	# 1. VRAM before the load.
	print("oom_check: vram_before=%s" % _vram())

	# 2. A default NativeBackend (fallback chain on), installed with LLM.set_backend, loaded on a Thread.
	# The LLM autoload is looked up at run time: a --script outside res:// does not compile
	# against the autoload name.
	var llm = root.get_node_or_null("/root/LLM")
	if llm == null:
		_quit_fail("LLM autoload not found under /root")
		return
	var backend = load(NATIVE_BACKEND_PATH).new({})
	llm.set_backend(backend)
	var t0 := Time.get_ticks_msec()
	var loaded: Dictionary = await _on_thread(backend.ensure_loaded, LOAD_MAX_MS)
	var elapsed := Time.get_ticks_msec() - t0
	var ok := bool(loaded.get("ok", false))
	var fell_back := bool(loaded.get("fell_back", false))
	print("oom_check: load ok=%s device=%s device_type=%s gpu_layers=%s fell_back=%s fallback_from=%s load_ms=%s elapsed_ms=%d" % [
		ok, _str(loaded, "device"), _str(loaded, "device_type"), _str(loaded, "gpu_layers"),
		fell_back, JSON.stringify(loaded.get("fallback_from", {})), _str(loaded, "load_ms"), elapsed,
	])
	if not ok:
		print("oom_check: load result=%s" % JSON.stringify(loaded))

	# 3. On success, a 30-token generate through the engine, on a Thread.
	var gen_ok := false
	if ok:
		var request = load(TURN_REQUEST_PATH).new()
		request.messages.append({"role": "user", "content": PROMPT})
		request.schema = SCHEMA.duplicate(true)
		request.sampling = SAMPLING.duplicate()
		request.max_tokens = GENERATE_TOKENS
		var pieces: Array = []
		var on_token := func(piece: String) -> void:
			pieces.append(piece)
		var cancel = load(CANCEL_TOKEN_PATH).new()
		var gen: Dictionary = await _on_thread(
			backend.generate.bind(request, on_token, cancel), GENERATE_MAX_MS
		)
		var metrics: Dictionary = gen.get("metrics", {}) if gen.get("metrics", {}) is Dictionary else {}
		var text := String(gen.get("text", ""))
		if text.is_empty():
			for piece in pieces:
				text += String(piece)
		gen_ok = bool(gen.get("ok", false)) and not text.is_empty()
		print("oom_check: generate ok=%s completion_tokens=%s tok/s=%s metrics=%s" % [
			gen_ok, _str(metrics, "completion_tokens"), _str(metrics, "tok_per_s"), JSON.stringify(metrics),
		])
		if not bool(gen.get("ok", false)):
			print("oom_check: generate error=%s" % JSON.stringify(gen.get("error", {})))
		print("oom_check: text60=\"%s\"" % text.substr(0, SHOW_CHARS).replace("\n", " "))

	# 4. The Loading screen, with navigate_on_finish off and the real model.json values.
	var screen = load(LOADING_SCENE_PATH).instantiate()
	screen.navigate_on_finish = false
	screen.expected_override = _model_expected()
	root.add_child(screen)
	var s0 := Time.get_ticks_msec()
	var reason := "timeout"
	while Time.get_ticks_msec() - s0 < SCREEN_MAX_MS:
		await process_frame
		if String(screen.finished_scene) != "":
			reason = "finished"
			break
		if not screen.current_actions().is_empty():
			reason = "error_actions_shown"
			break
	var line_text := String(screen.get_node("Margin/Column/Line").text)
	var fix_text := String(screen.get_node("Margin/Column/Fix").text)
	var actions: Array = screen.current_actions()
	print("oom_check: screen reason=%s after_ms=%d finished_scene=%s" % [
		reason, Time.get_ticks_msec() - s0, String(screen.finished_scene),
	])
	print("oom_check: screen Line=\"%s\"" % line_text)
	print("oom_check: screen Fix=\"%s\"" % fix_text)
	print("oom_check: screen actions=%s" % str(actions))

	# 5. Shut the backend down, then judge the run.
	screen.queue_free()
	await process_frame
	backend.shutdown()
	var failures: Array = []
	if not ok:
		failures.append("load not ok")
	if ok and not gen_ok:
		failures.append("generate did not work")
	if int(fell_back) != _expect:
		failures.append("fell_back=%s, expected %d" % [fell_back, _expect])
	if _expect == 1:
		if not fix_text.contains("graphics card"):
			failures.append("Fix text lacks 'graphics card'")
		if actions.is_empty() or not String(actions[0]).begins_with("fast"):
			failures.append("actions do not start with fast")
	if failures.is_empty():
		print("oom_check: PASS")
		quit(0)
		return
	var reasons := ""
	for item in failures:
		reasons += "; " + String(item)
	_quit_fail(reasons.trim_prefix("; "))


## Runs work on a Thread and waits without blocking the frame loop, so the Loading screen's own
## job keeps running. Returns the work's result, or {"timeout": true} when max_ms passes first.
func _on_thread(work: Callable, max_ms: int) -> Variant:
	var thread := Thread.new()
	_threads.append(thread)
	thread.start(work)
	var started := Time.get_ticks_msec()
	while thread.is_alive():
		if Time.get_ticks_msec() - started > max_ms:
			print("oom_check: thread still running after %d ms" % max_ms)
			return {"timeout": true}
		await process_frame
	return thread.wait_to_finish()


func _parse_expect() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expect-fallback="):
			var value := arg.trim_prefix("--expect-fallback=")
			if value == "0" or value == "1":
				return int(value)
	return -1


## The nvidia-smi memory.used line, or why it could not be read.
func _vram() -> String:
	var out: Array = []
	var code := OS.execute("nvidia-smi", ["--query-gpu=memory.used", "--format=csv,noheader"], out, true)
	if code != 0 or out.is_empty():
		return "unavailable(exit %d)" % code
	return String(out[0]).strip_edges().replace("\n", " ")


func _model_expected() -> Dictionary:
	var file := FileAccess.open(MODEL_DATA_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _quit_fail(message: String) -> void:
	print("oom_check: FAIL %s" % message)
	quit(1)


static func _str(data: Dictionary, key: String) -> String:
	return str(data.get(key, ""))
