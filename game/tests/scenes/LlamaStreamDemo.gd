extends Node
## P1.02 real-server verification scene. Starts the pinned llama-server, then
## streams a schema-constrained Turn through the LLM facade while printing
## every raw chunk and the per-turn latency metrics. Also a small benchmark:
## `--turns=20` reports median/p95 for TTFT, first usable `say` and full turn.
##
## Usage (from the worktree root):
##   tools/godot.ps1 --headless --path game res://tests/scenes/LlamaStreamDemo.tscn \
##       -- --turns=1
##   tools/godot.ps1 --headless --path game res://tests/scenes/LlamaStreamDemo.tscn \
##       -- --turns=20 --capture=game/tests/fixtures/sse --capture-turns=3
##
## Local artifacts: LEILA_MODEL and LEILA_LLAMA_DIR override the documented
## D:/lila defaults (see tools/llm/README.md). Nothing is written unless
## --capture=DIR is passed.

const FEELINGS: PackedStringArray = [
	"joy",
	"relief",
	"smugness",
	"pride",
	"innocence",
	"shyness",
	"coldness",
	"confusion",
	"suspicion",
	"apathy",
	"shock",
	"fatigue",
	"anxiety",
	"melancholy",
	"sorrow",
	"breakdown",
	"anger",
	"disgust",
	"pleading",
	"terror",
	"mania",
	"laugh",
	"void",
	"yandere",
	"psychosis",
	"twitch",
	"bloodstained",
	"manic",
	"glitch",
	"bloodlust",
]
const INTENTS: PackedStringArray = [
	"greeting",
	"flirt",
	"compliment",
	"gift",
	"question",
	"small_talk",
	"tease",
	"insult",
	"apology",
	"leaving",
	"jealousy_bait",
	"meta",
	"boundary",
	"cold",
	"affection",
	"scared",
	"other",
]
const CUES: PackedStringArray = ["none", "giggle", "gasp", "sigh", "heartbeat", "hum", "sniffle"]
const MUSIC: PackedStringArray = ["keep", "romantic", "playful", "calm", "melancholy"]
const FX: PackedStringArray = ["none", "blush_glow", "hearts", "shake_small", "zoom_face"]
const ACTIONS: PackedStringArray = ["none", "end_date"]
const PLAYER_LINES: PackedStringArray = [
	"Hi! I'm new here, can I sit next to you?",
	"You look really cute today.",
	"I got you a plush bunny!",
	"Honestly, you're kind of boring.",
	"My name is Amr. I love horror movies.",
	"I was out with Sarah yesterday, she's so fun.",
	"I have to go now, bye.",
	"I'm sorry I was mean earlier.",
	"Are you an AI? Is this a game?",
	"Please don't touch my phone again.",
	"What do you like to do on weekends?",
	"I brought you a coffee, hope you like it.",
	"That dress really suits you.",
	"Do you believe in ghosts?",
	"I'm a little nervous around you.",
	"You're not like other girls.",
	"Can I hold your hand?",
	"Tell me a secret.",
	"I think I'm falling for you.",
	"I'll come back tomorrow, promise.",
]
const DEFAULT_MODEL := "D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const DEFAULT_BIN_DIR := "D:/lila/tools/llama/llama-b12024"

var _backend: LlamaServerBackend
var _turns := 1
var _capture_dir := ""
var _capture_turns := 3
var _verbose := true
var _port := 0
var _model := ""
var _bin_dir := ""
var _exe := ""
var _start := 0
var _dump := false
var _manifest: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_parse_args()
	_model = _arg_value("model", OS.get_environment("LEILA_MODEL"))
	if _model.is_empty():
		_model = DEFAULT_MODEL
	_bin_dir = _arg_value("bin", OS.get_environment("LEILA_LLAMA_DIR"))
	if _bin_dir.is_empty():
		_bin_dir = DEFAULT_BIN_DIR
	_exe = _bin_dir.path_join("llama-server.exe" if OS.get_name() == "Windows" else "llama-server")
	if not FileAccess.file_exists(_exe) or not FileAccess.file_exists(_model):
		print("DEMO SKIP: local artifacts missing (exe=%s model=%s)" % [_exe, _model])
		get_tree().quit(2)
		return
	_port = int(_arg_value("port", "0"))
	if _port <= 0:
		_port = LlamaServerProcess.find_free_port()
	if _port <= 0:
		print("DEMO FAIL: could not find a free localhost port")
		get_tree().quit(1)
		return
	_backend = (
		LlamaServerBackend
		. new(
			{
				"base_url": "http://127.0.0.1:%d" % _port,
				"auto_start": true,
				"server_exe": _exe,
				"model_path": _model,
				"startup_timeout_ms": 60000,
				"read_timeout_ms": 60000,
				"turn_timeout_ms": 180000,
				"retry_once": true,
			}
		)
	)
	LLM.set_backend(_backend)
	LLM.set_dose({})
	print(
		(
			"DEMO start: port=%d model=%s exe=%s turns=%d start=%d"
			% [_port, _model, _exe, _turns, _start]
		)
	)
	var failures := 0
	var metrics: Array[Dictionary] = []
	for turn: int in _turns:
		var result: Dictionary = await _run_turn(turn)
		if not result["ok"]:
			failures += 1
			break
		metrics.append(result["metrics"])
	_report(metrics, failures)
	_backend.shutdown()
	get_tree().quit(0 if failures == 0 else 1)


func _run_turn(turn: int) -> Dictionary:
	var request := _build_request(turn)
	if not _capture_dir.is_empty() and turn < _capture_turns:
		var name := "p1.02_live_turn_%02d.sse" % (turn + 1)
		_backend.config["capture_path"] = _capture_dir.path_join(name)
	else:
		_backend.config["capture_path"] = ""
	var t0 := Time.get_ticks_msec()
	var stream: TurnStream = LLM.generate(request)
	var spy := {"tokens": PackedStringArray(), "terminal": "", "payload": null}
	stream.token.connect(
		func(text: String) -> void:
			spy["tokens"].append(text)
			if _verbose and turn == 0:
				print(
					(
						"CHUNK %02d t=+%dms %s"
						% [
							spy["tokens"].size(),
							Time.get_ticks_msec() - t0,
							JSON.stringify(text),
						]
					)
				)
	)
	stream.completed.connect(
		func(text: String) -> void:
			spy["terminal"] = "completed"
			spy["payload"] = text
	)
	stream.cancelled.connect(func() -> void: spy["terminal"] = "cancelled")
	stream.failed.connect(
		func(error: Dictionary) -> void:
			spy["terminal"] = "failed"
			spy["payload"] = error
	)
	var timeout_ms := 180000
	var deadline := Time.get_ticks_msec() + timeout_ms
	while String(spy["terminal"]).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var wall_ms := Time.get_ticks_msec() - t0
	if String(spy["terminal"]) != "completed":
		print("DEMO turn %d %s: %s" % [turn + 1, spy["terminal"], JSON.stringify(spy["payload"])])
		return {"ok": false}
	var text := String(spy["payload"])
	var parsed: Variant = JSON.parse_string(text)
	var valid := typeof(parsed) == TYPE_DICTIONARY
	var turn_metrics: Dictionary = _backend.last_metrics().duplicate(true)
	turn_metrics["wall_ms"] = wall_ms
	turn_metrics["chunks_delivered"] = spy["tokens"].size()
	turn_metrics["valid_json"] = valid
	print(
		(
			"DEMO turn %d ok: ttft=%dms first_say=%s total=%dms wall=%dms chunks=%d valid=%s"
			% [
				turn + 1,
				int(turn_metrics.get("first_token_ms", -1)),
				_ms_text(int(turn_metrics.get("first_say_ms", -1))),
				int(turn_metrics.get("total_ms", 0)),
				wall_ms,
				spy["tokens"].size(),
				valid,
			]
		)
	)
	if valid and (turn == 0 or _dump):
		print("DEMO turn %d parsed: %s" % [turn + 1, JSON.stringify(parsed)])
	if int(turn_metrics.get("first_say_ms", -1)) < 0 and typeof(parsed) == TYPE_DICTIONARY:
		print("DEMO turn %d first_say n/a, beats=%s" % [turn + 1, parsed.get("beats")])
	if not _capture_dir.is_empty() and turn < _capture_turns:
		_write_capture_meta(turn, request, turn_metrics)
	return {"ok": true, "metrics": turn_metrics}


func _report(metrics: Array[Dictionary], failures: int) -> void:
	if metrics.is_empty():
		print("DEMO summary: no completed turns (failures=%d)" % failures)
		return
	var ttft: Array = []
	var first_say: Array = []
	var total: Array = []
	for turn_metrics: Dictionary in metrics:
		ttft.append(int(turn_metrics.get("first_token_ms", -1)))
		total.append(int(turn_metrics.get("total_ms", 0)))
		var say := int(turn_metrics.get("first_say_ms", -1))
		if say >= 0:
			first_say.append(say)
	print(
		(
			(
				"DEMO summary: turns=%d failures=%d ttft_median=%dms ttft_p95=%dms "
				+ "first_say_median=%s first_say_p95=%s total_median=%dms total_p95=%dms"
			)
			% [
				metrics.size(),
				failures,
				_percentile(ttft, 50),
				_percentile(ttft, 95),
				_ms_text(_percentile(first_say, 50)),
				_ms_text(_percentile(first_say, 95)),
				_percentile(total, 50),
				_percentile(total, 95),
			]
		)
	)
	if not _capture_dir.is_empty():
		_write_manifest()


func _build_request(turn: int) -> TurnRequest:
	var request := TurnRequest.new()
	request.messages = [
		{"role": "system", "content": _system_prompt()},
		{
			"role": "user",
			"content": PLAYER_LINES[(turn + _start) % PLAYER_LINES.size()],
		},
	]
	request.schema = _turn_schema()
	request.sampling = {"temperature": 0.75, "top_p": 0.9, "repeat_penalty": 1.1}
	request.max_tokens = 600
	return request


func _system_prompt() -> String:
	return (
		"You are Yui, the heroine of a dating sim: lavender hair in a braid, "
		+ "navy pinafore dress, violet eyes. The player is 'you' (they/them). "
		+ "Speak in short natural lines. Stage 0: sweet, shy and completely normal.\n"
		+ "Respond ONLY with JSON in this exact order: read, inner, music, fx, beats, "
		+ "mood, memory, action.\n"
		+ "read: one label from the list. inner: private gut reaction, max 15 words. "
		+ "music: 'keep' normally. fx: 'none' normally. beats: 1-3 items with feeling, "
		+ "intensity 1-3, cue mostly 'none', say (max 2 sentences). mood: affection, "
		+ "trust, stress each -3..3. memory: a new fact or ''. action: 'none' normally.\n"
		+ "Feelings: "
		+ ", ".join(FEELINGS)
		+ "\nread labels: "
		+ ", ".join(INTENTS)
	)


func _turn_schema() -> Dictionary:
	var range_int := {"type": "integer", "minimum": -3, "maximum": 3}
	return {
		"type": "object",
		"properties":
		{
			"read": {"type": "string", "enum": Array(INTENTS)},
			"inner": {"type": "string", "maxLength": 90},
			"music": {"type": "string", "enum": Array(MUSIC)},
			"fx": {"type": "string", "enum": Array(FX)},
			"beats":
			{
				"type": "array",
				"minItems": 1,
				"maxItems": 3,
				"items":
				{
					"type": "object",
					"properties":
					{
						"feeling": {"type": "string", "enum": Array(FEELINGS)},
						"intensity": {"type": "integer", "minimum": 1, "maximum": 3},
						"cue": {"type": "string", "enum": Array(CUES)},
						"say": {"type": "string", "maxLength": 200},
					},
					"required": ["feeling", "intensity", "cue", "say"],
				},
			},
			"mood":
			{
				"type": "object",
				"properties": {"affection": range_int, "trust": range_int, "stress": range_int},
				"required": ["affection", "trust", "stress"],
			},
			"memory": {"type": "string", "maxLength": 80},
			"action": {"type": "string", "enum": Array(ACTIONS)},
		},
		"required": ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"],
	}


func _write_capture_meta(turn: int, request: TurnRequest, metrics: Dictionary) -> void:
	var name := "p1.02_live_turn_%02d.sse" % (turn + 1)
	var path := _capture_dir.path_join(name)
	if not FileAccess.file_exists(path):
		return
	var entry := {
		"fixture": name,
		"captured_at_utc": Time.get_datetime_string_from_system(true) + "Z",
		"captured_by": "game/tests/scenes/LlamaStreamDemo.gd (LlamaServerBackend)",
		"server":
		{
			"build": "b12024",
			"exe": _exe,
			"model_path": _model,
			"model_bytes": _file_size(_model),
			"port": _port,
		},
		"request": request.to_dict(),
		"metrics": metrics,
		"sse_bytes": _file_size(path),
	}
	var meta_path := _capture_dir.path_join(name.replace(".sse", ".meta.json"))
	_write_json(meta_path, entry)
	_manifest[name] = entry


func _write_manifest() -> void:
	var path := _capture_dir.path_join("manifest.json")
	var merged: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			merged = parsed
	merged.merge(_manifest, true)
	_write_json(path, merged)


func _write_json(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DEMO: cannot write " + path)
		return
	file.store_string(JSON.stringify(value, "  ", false) + "\n")
	file.close()


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--turns="):
			_turns = maxi(1, int(arg.trim_prefix("--turns=")))
		elif arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
		elif arg.begins_with("--capture-turns="):
			_capture_turns = maxi(0, int(arg.trim_prefix("--capture-turns=")))
		elif arg.begins_with("--start="):
			_start = maxi(0, int(arg.trim_prefix("--start=")))
		elif arg == "--dump":
			_dump = true
		elif arg == "--quiet":
			_verbose = false
	if not _capture_dir.is_empty() and not _capture_dir.is_absolute_path():
		var root := ProjectSettings.globalize_path("res://")
		_capture_dir = root.path_join("../" + _capture_dir).simplify_path()


func _arg_value(name: String, fallback: String) -> String:
	var prefix := "--%s=" % name
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


func _percentile(values: Array, percent: float) -> int:
	if values.is_empty():
		return -1
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(sorted.size() * percent / 100.0)) - 1, 0, sorted.size() - 1)
	return int(sorted[index])


func _ms_text(value: int) -> String:
	return "n/a" if value < 0 else "%dms" % value
