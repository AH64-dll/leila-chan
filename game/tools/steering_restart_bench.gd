extends Node
## P2.03 dev tool — measures the stage-change server relaunch (docs/06 §4) against
## the 3.5 s budget the transition glitch has to hide, using the real pinned server
## and the shipped malice vector.
##
##   ./tools/godot.sh --headless --path game res://tools/SteeringRestartBench.tscn \
##       -- --runs=3
##
## One line per relaunch (stage, measured ms, glitch window, bound vectors), then
## min/median/max and a PASS/FAIL. Each run also submits a turn *while* the
## relaunch is in flight and reports whether it completed — the "no lost player
## input" evidence. Needs the local artifacts (LEILA_MODEL / LEILA_LLAMA_DIR, see
## tools/llm/README.md); exits 2 when they are missing, 1 when a relaunch missed
## the budget or a turn was dropped.

const VECTOR := "res://data/steering/malice.gguf"
const WINDOW_MS := 2500
const STAGES: Array[int] = [3, 4, 5]

var _backend: LlamaServerBackend
var _failures := 0


func _ready() -> void:
	var runs := 3
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = maxi(1, arg.trim_prefix("--runs=").to_int())
	var reason := _missing_artifacts()
	if not reason.is_empty():
		print("steering_restart_bench: " + reason)
		get_tree().quit(2)
		return
	_backend = (
		LlamaServerBackend
		. new(
			{
				"base_url": "http://127.0.0.1:%d" % LlamaServerProcess.find_free_port(),
				"auto_start": true,
				"startup_timeout_ms": 60000,
				"read_timeout_ms": 60000,
				"turn_timeout_ms": 180000,
			}
		)
	)
	print(
		(
			"steering_restart_bench: budget %dms, glitch window %dms, %d relaunch(es)"
			% [LlamaServerBackend.STEERING_BUDGET_MS, WINDOW_MS, runs]
		)
	)
	var started := Time.get_ticks_msec()
	var warm: Dictionary = _backend.ensure_server()
	var cold_ms := Time.get_ticks_msec() - started
	print("cold start: ok=%s in %dms" % [str(warm["ok"]), cold_ms])
	if not bool(warm["ok"]):
		print("steering_restart_bench: FAIL — server did not start: " + str(warm))
		_backend.shutdown()
		get_tree().quit(1)
		return
	var samples: Array[int] = []
	for index: int in runs:
		var sample: Dictionary = await _relaunch(STAGES[index % STAGES.size()])
		if bool(sample["ok"]) and bool(sample["turn_completed"]):
			samples.append(int(sample["ms"]))
		else:
			_failures += 1
	print(_summary(samples, cold_ms))
	_backend.shutdown()
	get_tree().quit(0 if _failures == 0 and samples.size() == runs else 1)


## One relaunch with the turn submitted in the same frame, so the turn's worker
## has to wait for the restart session instead of racing it.
func _relaunch(stage: int) -> Dictionary:
	var scale := float(Steering.dose_for({"stage": stage})["malice"])
	var spy := {"done": false, "info": {}}
	var accepted := _backend.apply_steering(
		[{"path": ProjectSettings.globalize_path(VECTOR), "scale": scale}],
		stage,
		WINDOW_MS,
		func(info: Dictionary) -> void:
			spy["info"] = info
			spy["done"] = true
	)
	if not accepted:
		print("stage %d: relaunch was refused (not started)" % stage)
		return {"ok": false, "turn_completed": false}
	var turn := _start_turn()
	var deadline := Time.get_ticks_msec() + 120000
	while (
		(not bool(spy["done"]) or String(turn["terminal"]).is_empty())
		and (Time.get_ticks_msec() < deadline)
	):
		await get_tree().process_frame
	var info: Dictionary = spy["info"]
	var completed := String(turn["terminal"]) == "completed"
	print(
		(
			(
				"stage %d: ok=%s ms=%d within_budget=%s fits_window=%s vectors=[%s] "
				+ "turn_during_relaunch=%s tokens=%d"
			)
			% [
				stage,
				str(info.get("ok", false)),
				int(info.get("ms", 0)),
				str(info.get("within_budget", false)),
				str(info.get("fits_window", false)),
				StageSteering.describe(info.get("vectors", [])),
				String(turn["terminal"]),
				int(turn["tokens"]),
			]
		)
	)
	if not bool(info.get("ok", false)):
		print("stage %d error: %s" % [stage, str(info.get("error", {}))])
	return {
		"ok": bool(info.get("ok", false)), "ms": int(info.get("ms", 0)), "turn_completed": completed
	}


func _start_turn() -> Dictionary:
	var request := TurnRequest.new()
	request.messages = [
		{"role": "system", "content": "Reply with ONLY one JSON object, no prose."},
		{"role": "user", "content": "Say hello in one short line."},
	]
	request.schema = {
		"type": "object",
		"properties": {"line": {"type": "string", "maxLength": 24}},
		"required": ["line"],
		"additionalProperties": false,
	}
	request.max_tokens = 40
	LLM.set_backend(_backend)
	var stream: TurnStream = LLM.generate(request)
	var state := {"terminal": "", "tokens": 0}
	stream.token.connect(func(_text: String) -> void: state["tokens"] += 1)
	stream.completed.connect(func(_text: String) -> void: state["terminal"] = "completed")
	stream.failed.connect(func(_error: Dictionary) -> void: state["terminal"] = "failed")
	stream.cancelled.connect(func() -> void: state["terminal"] = "cancelled")
	return state


func _summary(samples: Array[int], cold_ms: int) -> String:
	if samples.is_empty():
		return "steering_restart_bench: FAIL — no successful relaunch"
	var sorted := samples.duplicate()
	sorted.sort()
	var within := 0
	for ms: int in samples:
		if ms <= LlamaServerBackend.STEERING_BUDGET_MS:
			within += 1
	var lines := PackedStringArray()
	(
		lines
		. append(
			(
				(
					"steering_restart_bench: %d/%d within the %dms budget — min %dms, "
					+ "median %dms, max %dms, dropped turns %d"
				)
				% [
					within,
					samples.size(),
					LlamaServerBackend.STEERING_BUDGET_MS,
					sorted[0],
					sorted[sorted.size() / 2],
					sorted[sorted.size() - 1],
					_failures,
				]
			)
		)
	)
	# The relaunch is a stop plus the same model load: comparing it with the plain
	# cold start of this run separates the restart's own cost from the box's load.
	lines.append(
		(
			"cold start this run: %dms; relaunch min %dms (%+dms vs cold)"
			% [cold_ms, sorted[0], sorted[0] - cold_ms]
		)
	)
	if cold_ms > LlamaServerBackend.STEERING_BUDGET_MS:
		lines.append(
			(
				(
					"note: a plain cold start already misses the %dms budget here — "
					+ "another llama-server on the GPU or a loaded box invalidates the "
					+ "comparison; rerun with the GPU to itself"
				)
				% LlamaServerBackend.STEERING_BUDGET_MS
			)
		)
	return "\n".join(lines)


func _missing_artifacts() -> String:
	var model := OS.get_environment("LEILA_MODEL")
	if model.is_empty():
		model = LlamaServerProcess.default_model_path()
	if not FileAccess.file_exists(model):
		return "model not found at %s (set LEILA_MODEL)" % model
	var exe := LlamaServerProcess.default_server_exe()
	if not FileAccess.file_exists(exe):
		return "llama-server not found at %s (set LEILA_LLAMA_DIR)" % exe
	return ""
