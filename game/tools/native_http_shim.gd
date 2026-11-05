extends Node
## P4.04c dev tool, never part of the game flow. Serves the in-process
## NativeBackend (P4.02) over the llama-server routes the prompt lab uses, so the
## unchanged tools/promptlab/run.py can drive it: GET /health, GET /props and
## POST /v1/chat/completions (non-stream). Binds 127.0.0.1 only and runs one
## generation at a time. The model loads on a Thread and generation runs on a
## Thread, polled from _process so the main loop stays live. Run from the repo root:
##   ./tools/godot.sh --headless --path game res://tools/NativeHttpShim.tscn --
##     --port=8097 --dose=malice:4.5,possessive:0.3 --gpu=99
## Driven by tools/promptlab/native_parity.py. Needs LEILA_MODEL or --model.

const HOST := "127.0.0.1"
const DEFAULT_MAX_TOKENS := 600
const MAX_HEAD_BYTES := 65536
const MAX_BODY_BYTES := 8388608
## Body keys copied into TurnRequest.sampling. These are the keys that
## leila_llm.cpp apply_sampling_dict reads, except stop and repeat_last_n, which
## the prompt lab never sends.
const SAMPLING_KEYS := [
	"temperature",
	"top_p",
	"top_k",
	"min_p",
	"repeat_penalty",
	"seed",
	"presence_penalty",
	"frequency_penalty",
]
const INT_SAMPLING_KEYS := ["top_k", "seed"]
const REASONS := {
	200: "OK",
	400: "Bad Request",
	404: "Not Found",
	413: "Payload Too Large",
	431: "Request Header Fields Too Large",
	500: "Internal Server Error",
	503: "Service Unavailable",
}

var _port := 8097
var _dose := {}
var _gpu_layers := 99
var _threads := -1
var _model := ""
var _seed := -1
var _server := TCPServer.new()
var _backend: NativeBackend = null
var _loaded := false
var _load_info := {}
var _load_thread: Thread = null
var _gen_thread: Thread = null
var _gen_result := {}
var _active := {}
var _clients := []
var _closed := false


func _ready() -> void:
	if not _parse_args(OS.get_cmdline_user_args()):
		_fail(
			"usage: --port=N --dose=name:scale,... [--gpu=N] [--threads=N] [--model=PATH] [--seed=N]"
		)
		return
	var err := _server.listen(_port, HOST)
	if err != OK:
		_fail("cannot listen on %s:%d (error %d)" % [HOST, _port, err])
		return
	_backend = NativeBackend.new(
		{"n_gpu_layers": _gpu_layers, "n_threads": _threads, "model_path": _model}
	)
	_load_thread = Thread.new()
	_load_thread.start(_load_worker)
	print("native_http_shim: listening on %s:%d, loading model" % [HOST, _port])


func _process(_delta: float) -> void:
	_finish_load()
	_accept_clients()
	for client: Dictionary in _clients:
		_advance(client)
	_clients = _clients.filter(_is_open)
	_finish_generation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()
		get_tree().quit()


func _exit_tree() -> void:
	_shutdown()


func _shutdown() -> void:
	if _closed:
		return
	_closed = true
	if _load_thread != null:
		_load_thread.wait_to_finish()
	if _gen_thread != null:
		_gen_thread.wait_to_finish()
	_server.stop()
	if _backend != null:
		_backend.shutdown()


func _fail(message: String) -> void:
	push_error("native_http_shim: " + message)
	set_process(false)
	get_tree().quit(1)


func _parse_args(args: PackedStringArray) -> bool:
	for arg in args:
		var eq := arg.find("=")
		var key := arg if eq < 0 else arg.substr(0, eq)
		var value := "" if eq < 0 else arg.substr(eq + 1)
		match key:
			"--port":
				_port = int(value)
			"--gpu":
				_gpu_layers = int(value)
			"--threads":
				_threads = int(value)
			"--model":
				_model = value
			"--seed":
				_seed = int(value)
			"--dose":
				var parsed: Variant = parse_dose(value)
				if parsed == null:
					return false
				_dose = parsed
	return _port > 0


## "malice:4.5,possessive:0.3" -> {"malice": 4.5, "possessive": 0.3}. Null when a
## pair is malformed. A zero scale stays in the map; StageSteering skips it.
static func parse_dose(text: String) -> Variant:
	var dose := {}
	for part in text.split(",", false):
		var pair := part.strip_edges().split(":", false)
		if pair.size() != 2 or not pair[1].is_valid_float():
			return null
		dose[pair[0].strip_edges()] = float(pair[1])
	return dose


func _load_worker() -> void:
	_load_info = _backend.ensure_loaded()


func _finish_load() -> void:
	if _load_thread == null or _load_thread.is_alive():
		return
	_load_thread.wait_to_finish()
	_load_thread = null
	if not bool(_load_info.get("ok", false)):
		_fail("model load failed: %s" % JSON.stringify(_load_info.get("error", {})))
		return
	_loaded = true
	print(
		(
			"native_http_shim: model loaded, load_ms=%s gpu_offload=%s"
			% [str(_load_info.get("load_ms", -1)), str(_load_info.get("gpu_offload", false))]
		)
	)


func _accept_clients() -> void:
	while _server.is_connection_available():
		_clients.append(
			{"peer": _server.take_connection(), "state": "reading", "buf": PackedByteArray()}
		)


func _is_open(client: Dictionary) -> bool:
	return client["state"] != "done"


func _advance(client: Dictionary) -> void:
	if client["state"] != "reading":
		return
	var peer: StreamPeerTCP = client["peer"]
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		client["state"] = "done"
		return
	var available := peer.get_available_bytes()
	if available > 0:
		var got: Array = peer.get_partial_data(available)
		if int(got[0]) != OK:
			client["state"] = "done"
			return
		var buf: PackedByteArray = client["buf"]
		buf.append_array(got[1])
		client["buf"] = buf
	_parse(client)


## Waits until the headers and the full Content-Length body have arrived. A body
## may come in several reads, so nothing is routed before it is complete.
func _parse(client: Dictionary) -> void:
	var buf: PackedByteArray = client["buf"]
	var head_end := _header_end(buf)
	if head_end < 0:
		if buf.size() > MAX_HEAD_BYTES:
			_respond(client, 431, {"error": {"message": "request headers too large"}})
		return
	var head := _parse_head(buf.slice(0, head_end).get_string_from_utf8())
	if head.is_empty():
		_respond(client, 400, {"error": {"message": "malformed request line"}})
		return
	var length := int(head["length"])
	if length < 0 or length > MAX_BODY_BYTES:
		_respond(client, 413, {"error": {"message": "body length %d not accepted" % length}})
		return
	var start := head_end + 4
	if buf.size() < start + length:
		return
	var body := buf.slice(start, start + length).get_string_from_utf8()
	_route(client, String(head["method"]), String(head["path"]), body)


static func _header_end(buf: PackedByteArray) -> int:
	for i in range(buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


static func _parse_head(text: String) -> Dictionary:
	var lines := text.split("\r\n")
	var request_line := lines[0].split(" ")
	if request_line.size() < 2:
		return {}
	var head := {"method": request_line[0], "path": request_line[1].split("?")[0], "length": 0}
	for line in lines.slice(1):
		var colon := line.find(":")
		if colon > 0 and line.substr(0, colon).to_lower() == "content-length":
			head["length"] = int(line.substr(colon + 1).strip_edges())
	return head


func _route(client: Dictionary, method: String, path: String, body: String) -> void:
	if method == "GET" and path == "/health":
		if _loaded:
			_respond(client, 200, {"status": "ok"})
		else:
			_respond(client, 503, {"status": "loading"})
	elif method == "GET" and path == "/props":
		_respond(client, 200, {"model_path": _backend._resolve_model_path(), "transport": "native"})
	elif method == "POST" and path == "/v1/chat/completions":
		_chat(client, body)
	else:
		_respond(client, 404, {"error": {"message": "no route for %s %s" % [method, path]}})


func _chat(client: Dictionary, body: String) -> void:
	if not _loaded:
		_respond(client, 503, {"error": {"message": "model not loaded"}})
		return
	if _gen_thread != null:
		_respond(client, 503, {"error": {"message": "busy: one request at a time"}})
		return
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		_respond(client, 400, {"error": {"message": "body is not a JSON object"}})
		return
	var req: Dictionary = parsed
	if bool(req.get("stream", false)):
		_respond(client, 400, {"error": {"message": "stream is not supported by the native shim"}})
		return
	var request := _build_request(req)
	if request == null:
		_respond(
			client,
			400,
			{"error": {"message": "messages and response_format.json_schema.schema are required"}}
		)
		return
	client["state"] = "generating"
	_active = client
	_gen_result = {}
	_gen_thread = Thread.new()
	_gen_thread.start(_generate_worker.bind(request))


## Builds the turn from the body. JSON.parse_string keeps key order, and the
## schema's property order is what the grammar follows, so it is not re-sorted.
func _build_request(req: Dictionary) -> TurnRequest:
	var messages: Variant = req.get("messages", [])
	var response_format: Variant = req.get("response_format", {})
	var json_schema: Variant = {}
	if response_format is Dictionary:
		json_schema = response_format.get("json_schema", {})
	var schema: Variant = {}
	if json_schema is Dictionary:
		schema = json_schema.get("schema", {})
	if not (messages is Array) or messages.is_empty() or not (schema is Dictionary):
		return null
	if schema.is_empty():
		return null
	for message: Variant in messages:
		if not (message is Dictionary):
			return null
	var request := TurnRequest.new()
	request.messages.assign(messages)
	request.schema = _integral(schema)
	request.sampling = _sampling(req)
	request.max_tokens = int(req.get("max_tokens", DEFAULT_MAX_TOKENS))
	request.dose = _dose.duplicate()
	print(
		(
			"native_http_shim: turn messages=%d schema_order=%s"
			% [messages.size(), ",".join(_property_names(schema))]
		)
	)
	return request


func _sampling(req: Dictionary) -> Dictionary:
	var out := {}
	for key: String in SAMPLING_KEYS:
		var value: Variant = req.get(key)
		if value is int or value is float:
			out[key] = int(value) if key in INT_SAMPLING_KEYS else float(value)
	## As the server's --seed: the default for a request that names none.
	if _seed >= 0 and not out.has("seed"):
		out["seed"] = _seed
	return out


## JSON.parse_string makes every number a float, and the schema converter rejects
## "minLength": 1.0 ("must be a non-negative integer"). Integral floats go back to
## int. Dictionaries are rebuilt in the same key order.
static func _integral(value: Variant) -> Variant:
	if value is float and roundf(value) == value:
		return int(value)
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _integral(value[key])
		return out
	if value is Array:
		var items := []
		for item: Variant in value:
			items.append(_integral(item))
		return items
	return value


static func _property_names(schema: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	var properties: Variant = schema.get("properties", {})
	if properties is Dictionary:
		for key: Variant in properties:
			names.append(String(key))
	return names


func _generate_worker(request: TurnRequest) -> void:
	_gen_result = _backend.generate(request, Callable(), LLMCancelToken.new())


func _finish_generation() -> void:
	if _gen_thread == null or _gen_thread.is_alive():
		return
	_gen_thread.wait_to_finish()
	_gen_thread = null
	var client := _active
	_active = {}
	if bool(_gen_result.get("ok", false)):
		var metrics: Dictionary = _gen_result.get("metrics", {})
		var text := String(_gen_result.get("text", ""))
		var message := {"role": "assistant", "content": text}
		var usage := {
			"prompt_tokens": int(metrics.get("prompt_tokens", 0)),
			"completion_tokens": int(metrics.get("completion_tokens", 0)),
		}
		_respond(
			client,
			200,
			{"choices": [{"message": message, "finish_reason": "stop"}], "usage": usage}
		)
		print(
			(
				"native_http_shim: turn ok chars=%d generate_ms=%s"
				% [text.length(), str(metrics.get("generate_ms", -1))]
			)
		)
	else:
		var error: Dictionary = _gen_result.get("error", {})
		_respond(client, 500, {"error": error})
		push_error("native_http_shim: turn failed: %s" % JSON.stringify(error))


func _respond(client: Dictionary, code: int, payload: Dictionary) -> void:
	client["state"] = "done"
	var peer: StreamPeerTCP = client["peer"]
	var body := JSON.stringify(payload, "", false).to_utf8_buffer()
	var template := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\n"
	template += "Content-Length: %d\r\nConnection: close\r\n\r\n"
	var head := template % [code, REASONS.get(code, "Error"), body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()
