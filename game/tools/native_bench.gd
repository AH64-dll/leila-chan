extends Node
## P4.04 part 1: real-Turn bench for the in-process NativeBackend (P4.02).
## Every turn goes through PromptBuilder, TurnSchema, TurnContext and the LLM
## facade, the same path the Director uses. Run from the repo root with the
## model in the environment:
##   LEILA_MODEL=/abs/Qwen3.5-4B-Q4_K_M.gguf ./tools/godot.sh --headless
##     --path game res://tools/NativeBench.tscn -- --turns=6 --gpu=99
##     --out=/abs/path.json
## Exit 0 only when every turn is schema-valid and in canonical order.

const PLAYER_LINES := [
	"Hi there, how are you doing today?",
	"What's the weather like out there?",
	"Could you tell me a little about yourself?",
	"I brought you a snack. Want some?",
	"Do you like music? What do you listen to?",
	"Thanks for the chat, I'll see you around.",
]
const PLAYER_NAME := "Ren"
const IDLE_SECONDS := 3.0
const TURN_DEADLINE_MS := 120000

var _turns := 6
var _gpu_layers := 99
var _threads := -1
var _stage := 0
var _out_path := ""
var _backend: NativeBackend = null
var _phase := ""
var _last_tick := 0
var _gaps: Dictionary = {"load": [], "idle": [], "gen": []}


func _ready() -> void:
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	_parse_args(OS.get_cmdline_user_args())
	if _out_path.is_empty():
		_out_path = ProjectSettings.globalize_path("user://native_bench.json")
	_run()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _phase.is_empty():
		_last_tick = 0
		return
	if _last_tick > 0:
		var gaps: Array = _gaps[_phase]
		gaps.append(now - _last_tick)
	_last_tick = now


func _parse_args(args: PackedStringArray) -> void:
	for arg in args:
		var eq := arg.find("=")
		var key := arg if eq < 0 else arg.substr(0, eq)
		var value := "" if eq < 0 else arg.substr(eq + 1)
		match key:
			"--turns":
				_turns = maxi(1, int(value))
			"--gpu":
				_gpu_layers = int(value)
			"--threads":
				_threads = int(value)
			"--stage":
				_stage = int(value)
			"--out":
				_out_path = value


func _run() -> void:
	_backend = NativeBackend.new({"n_gpu_layers": _gpu_layers, "n_threads": _threads})
	LLM.set_backend(_backend)

	# Prewarm on a thread. The main loop keeps running, so its frame gaps show
	# whether the load stalls rendering.
	_set_phase("load")
	var holder := {"info": {}}
	var warm := Thread.new()
	warm.start(_prewarm.bind(holder))
	while warm.is_alive():
		await get_tree().process_frame
	warm.wait_to_finish()
	_set_phase("")
	var load_info: Dictionary = holder["info"]
	print(
		(
			"native_bench: load ok=%s load_ms=%s gpu_offload=%s devices=%s"
			% [
				str(load_info.get("ok", false)),
				str(load_info.get("load_ms", -1)),
				str(load_info.get("gpu_offload", false)),
				str(load_info.get("devices", [])),
			]
		)
	)
	if not bool(load_info.get("ok", false)):
		_conclude({"load": load_info, "turns": [], "all_valid": false}, false)
		return

	_set_phase("idle")
	await get_tree().create_timer(IDLE_SECONDS).timeout
	_set_phase("")

	var turns: Array = []
	for i in range(_turns):
		var record: Dictionary = await _run_turn(i)
		turns.append(record)
		print(
			(
				"native_bench: turn %d state=%s valid=%s total_ms=%s"
				% [record["turn"], record["state"], str(record["valid"]), record["total_ms"]]
			)
		)
		if record["state"] == "timeout":
			break

	var process_check := _child_processes()
	var external := String(process_check["listing"]).contains("llama-server")
	var all_valid := true
	for record: Dictionary in turns:
		all_valid = all_valid and bool(record["valid"])
	var devices: Array = load_info.get("devices", [])
	var report := {
		"settings":
		{
			"turns": _turns,
			"n_gpu_layers": _gpu_layers,
			"n_threads": _threads,
			"stage": _stage,
			"model_env": OS.get_environment("LEILA_MODEL"),
		},
		"load": load_info,
		"devices": devices,
		"gpu_offload": bool(load_info.get("gpu_offload", false)),
		"cuda0_present": devices.has("CUDA0"),
		"external_process": external,
		"process_check": process_check,
		"frame_gaps_us":
		{
			"load": _gap_stats("load"),
			"idle": _gap_stats("idle"),
			"gen": _gap_stats("gen"),
		},
		"turns": turns,
		"all_valid": all_valid,
	}
	_print_table(turns)
	_print_gaps()
	_conclude(report, all_valid)


func _prewarm(holder: Dictionary) -> void:
	holder["info"] = _backend.ensure_loaded()


func _run_turn(index: int) -> Dictionary:
	var line: String = PLAYER_LINES[index % PLAYER_LINES.size()]
	var ctx := {
		"stage": _stage,
		"path": "",
		"player_name": PLAYER_NAME,
		"history": [],
		"player_message": line,
	}
	var built: Dictionary = PromptBuilder.build(ctx)
	var request := TurnRequest.new()
	request.messages.assign(built.get("messages", []))
	request.schema = TurnSchema.build_turn_schema(
		{"stage": _stage, "property_order": TurnSchema.DOCS_02_PROPERTY_ORDER}, []
	)
	request.sampling = TurnContext.request_sampling(_stage)

	var outcome := {"state": "", "text": "", "error": {}}
	_set_phase("gen")
	var stream: TurnStream = LLM.generate(request)
	stream.completed.connect(_on_completed.bind(outcome))
	stream.failed.connect(_on_failed.bind(outcome))
	stream.cancelled.connect(_on_cancelled.bind(outcome))
	var deadline := Time.get_ticks_msec() + TURN_DEADLINE_MS
	while String(outcome["state"]).is_empty():
		if Time.get_ticks_msec() > deadline:
			outcome["state"] = "timeout"
			break
		await get_tree().process_frame
	_set_phase("")

	var metrics: Dictionary = LLM.last_metrics()
	var errors: Array[String] = []
	var canonical := false
	var valid := false
	if outcome["state"] == "completed":
		# Parse as the Director does: IncrementalJson keeps integers as int and
		# keeps stream order, where JSON.parse_string yields floats.
		var parser := IncrementalJson.new()
		parser.feed(String(outcome["text"]))
		parser.finish()
		var parsed: Variant = parser.get_value()
		if parsed is Dictionary:
			var turn: Dictionary = parsed
			errors = TurnSchema.validate_turn(turn, _stage)
			var keys: Array[String] = []
			for key: Variant in turn.keys():
				keys.append(String(key))
			canonical = keys == TurnSchema.DOCS_02_PROPERTY_ORDER
			valid = errors.is_empty() and canonical
		else:
			errors.append("text is not a JSON object")
	else:
		errors.append("state=%s" % outcome["state"])
	return {
		"turn": index + 1,
		"line": line,
		"state": outcome["state"],
		"valid": valid,
		"canonical_order": canonical,
		"errors": errors,
		"ttft_ms": int(metrics.get("ttft_ms", -1)),
		"first_say_ms": int(metrics.get("first_say_ms", -1)),
		"total_ms": int(metrics.get("total_ms", -1)),
		"tok_per_s": float(metrics.get("tok_per_s", 0.0)),
		"prompt_tokens": int(metrics.get("prompt_tokens", -1)),
		"completion_tokens": int(metrics.get("completion_tokens", -1)),
		"text": outcome["text"],
		"error": outcome["error"],
	}


func _on_completed(full_text: String, outcome: Dictionary) -> void:
	outcome["text"] = full_text
	outcome["state"] = "completed"


func _on_failed(error: Dictionary, outcome: Dictionary) -> void:
	outcome["error"] = error
	outcome["state"] = "failed"


func _on_cancelled(outcome: Dictionary) -> void:
	outcome["state"] = "cancelled"


func _set_phase(phase: String) -> void:
	_phase = phase
	_last_tick = 0


func _gap_stats(phase: String) -> Dictionary:
	var gaps: Array = _gaps[phase]
	return {
		"frames": gaps.size(),
		"p50_us": _percentile(gaps, 0.5),
		"p99_us": _percentile(gaps, 0.99),
		"max_us": _percentile(gaps, 1.0),
	}


static func _percentile(values: Array, p: float) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(ceili(p * sorted.size()) - 1, 0, sorted.size() - 1)
	return int(sorted[index])


## The in-process backend must not spawn llama-server or anything else.
## pgrep exits 0 on a match and 1 on none; anything else means unavailable.
func _child_processes() -> Dictionary:
	var out: Array = []
	var code := OS.execute("pgrep", ["-l", "-P", str(OS.get_process_id())], out)
	var listing := ""
	for chunk in out:
		listing += String(chunk)
	var check := "ok" if code == 0 or code == 1 else "unavailable"
	return {"check": check, "exit_code": code, "listing": listing.strip_edges()}


func _print_table(turns: Array) -> void:
	print("turn | state     | valid | ttft_ms | first_say_ms | total_ms | tok/s | prompt | compl")
	for record: Dictionary in turns:
		print(
			(
				"%4d | %-9s | %-5s | %7d | %12d | %8d | %5.1f | %6d | %5d"
				% [
					record["turn"],
					record["state"],
					str(record["valid"]),
					record["ttft_ms"],
					record["first_say_ms"],
					record["total_ms"],
					record["tok_per_s"],
					record["prompt_tokens"],
					record["completion_tokens"],
				]
			)
		)


func _print_gaps() -> void:
	for phase in ["load", "idle", "gen"]:
		var stats := _gap_stats(phase)
		print(
			(
				"native_bench: frame gaps %-4s frames=%d p99=%.1fms max=%.1fms"
				% [
					phase,
					stats["frames"],
					float(stats["p99_us"]) / 1000.0,
					float(stats["max_us"]) / 1000.0,
				]
			)
		)


func _write_report(report: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var file := FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		push_error("native_bench: cannot write %s" % _out_path)
		return false
	file.store_string(JSON.stringify(report, "\t", false))
	file.close()
	return true


func _conclude(report: Dictionary, ok: bool) -> void:
	_backend.shutdown()
	if _write_report(report):
		print("native_bench: wrote %s" % _out_path)
	print("native_bench: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
