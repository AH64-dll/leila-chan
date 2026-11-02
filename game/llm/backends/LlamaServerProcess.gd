class_name LlamaServerProcess
extends RefCounted
## Owns (or attaches to) the prototype llama-server process (docs/07 §1,
## docs/06 §4). Runs on the LLM worker thread or the backend's watchdog, never
## on the main thread, and every wait is bounded.
##
## Start mode: launches the pinned llama-server with `--jinja`, full GPU
## offload, one slot and the configured control vectors, then waits for
## `/health` to report ok. Attach mode: never launches anything, only probes
## the URL. If a healthy server already answers on the port, it is adopted and
## never killed: another task's server is not ours to touch.
##
## A process we launched is `supervised`: if it dies, the backend watchdog
## restarts it. Restarts are a launch-flag operation (docs/06 §4).

const DEFAULT_STARTUP_TIMEOUT_MS := 30000
const DEFAULT_HEALTH_TIMEOUT_MS := 1500
const DEFAULT_STOP_TIMEOUT_MS := 5000
const DEFAULT_CONNECT_TIMEOUT_MS := 300
const POLL_MS := 20
const HEALTH_MAX_BYTES := 16384

var config := {}
var _pid := 0
var _owns := false
var _supervised := false
var _mutex := Mutex.new()
var _host := "127.0.0.1"
var _port := 8089


## Local-artifact defaults from the role playbook: LEILA_MODEL overrides the
## model path, LEILA_LLAMA_DIR/LEILA_LLAMA_BIN the binary directory. These are
## main-tree paths because binaries and weights never enter a worktree.
static func default_config() -> Dictionary:
	return {
		"base_url": "http://127.0.0.1:8089",
		"chat_path": "/v1/chat/completions",
		"auto_start": false,
		"watchdog": true,
		"watchdog_interval_ms": 1000,
		"server_exe": default_server_exe(),
		"model_path": default_model_path(),
		"ctx_size": 8192,
		"gpu_layers": 99,
		"parallel_slots": 1,
		"control_vectors": [],
		"extra_args": PackedStringArray(),
		"startup_timeout_ms": DEFAULT_STARTUP_TIMEOUT_MS,
		"health_timeout_ms": DEFAULT_HEALTH_TIMEOUT_MS,
		"stop_timeout_ms": DEFAULT_STOP_TIMEOUT_MS,
		"connect_timeout_ms": DEFAULT_CONNECT_TIMEOUT_MS,
	}


static func default_model_path() -> String:
	var env := OS.get_environment("LEILA_MODEL")
	if not env.is_empty():
		return env
	return "D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf"


static func default_server_exe() -> String:
	var dir := OS.get_environment("LEILA_LLAMA_DIR")
	if dir.is_empty():
		dir = OS.get_environment("LEILA_LLAMA_BIN")
	if dir.is_empty():
		dir = "D:/lila/tools/llama/llama-b12024"
	var name := "llama-server.exe" if OS.get_name() == "Windows" else "llama-server"
	return dir.path_join(name)


## Ask the OS for an unused localhost port. Tests and the demo use this so
## they never collide with a server another task is running.
static func find_free_port() -> int:
	var server := TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		return 0
	var port := server.get_local_port()
	server.stop()
	return port


func configure(updates: Dictionary) -> void:
	config = default_config().merged(updates, true)
	var target := LlamaHttpClient.parse_http_url(String(config["base_url"]))
	if target["ok"]:
		_host = target["host"]
		_port = target["port"]


## Make a server available for the next turn. Caller must not hold _mutex.
## Returns {ok, started, attached, pid, startup_ms, error}.
func ensure_running(cancel: LLMCancelToken = null) -> Dictionary:
	if not _lock(cancel):
		return _cancelled()
	var result := _ensure_locked(cancel)
	_mutex.unlock()
	return result


## Probe GET /health. {ok, status, body, loading, error}. Safe to call from
## any thread: it opens its own socket and never touches process state.
func probe_health(timeout_ms := -1) -> Dictionary:
	var budget := int(config.get("health_timeout_ms", DEFAULT_HEALTH_TIMEOUT_MS))
	if timeout_ms >= 0:
		budget = timeout_ms
	var peer := StreamPeerTCP.new()
	var err := peer.connect_to_host(_host, _port)
	if err != OK and err != ERR_BUSY:
		return {"ok": false, "status": 0, "body": {}, "loading": false, "error": error_string(err)}
	var deadline := Time.get_ticks_msec() + budget
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		if peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			peer.disconnect_from_host()
			return {
				"ok": false, "status": 0, "body": {}, "loading": false, "error": "connect failed"
			}
		OS.delay_msec(POLL_MS)
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()
		return {"ok": false, "status": 0, "body": {}, "loading": false, "error": "connect timeout"}
	var request := (
		"GET /health HTTP/1.1\r\nHost: %s:%d\r\nConnection: close\r\n\r\n" % [_host, _port]
	)
	peer.put_data(request.to_utf8_buffer())
	var body := PackedByteArray()
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if peer.get_available_bytes() > 0:
				var chunk: Array = peer.get_partial_data(4096)
				if chunk[0] == OK:
					body.append_array(chunk[1])
			else:
				OS.delay_msec(2)
		elif peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			break
		else:
			break
		if body.size() > HEALTH_MAX_BYTES:
			break
	peer.disconnect_from_host()
	var parsed := _parse_health(body.get_string_from_utf8())
	if not parsed["ok"] and parsed["status"] == 0:
		parsed["error"] = "no health response within %d ms" % budget
	return parsed


func start(cancel: LLMCancelToken = null) -> Dictionary:
	if not _lock(cancel):
		return _cancelled()
	_supervised = true
	var result := _start_locked(cancel)
	_mutex.unlock()
	return result


func stop() -> void:
	_mutex.lock()
	_stop_locked()
	_mutex.unlock()


func restart(cancel: LLMCancelToken = null) -> Dictionary:
	if not _lock(cancel):
		return _cancelled()
	var old_pid := _pid
	_stop_locked()
	_supervised = true
	var result := _start_locked(cancel)
	result["restart_ms"] = result.get("startup_ms", 0)
	result["old_pid"] = old_pid
	_mutex.unlock()
	return result


func server_pid() -> int:
	return _pid


func owns_process() -> bool:
	return _owns and _pid > 0


func is_supervised() -> bool:
	return _supervised


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


func is_healthy(timeout_ms := -1) -> bool:
	return probe_health(timeout_ms)["ok"]


func _ensure_locked(cancel: LLMCancelToken) -> Dictionary:
	if _owns and is_running():
		return _running_result(false, 0)
	var health := probe_health()
	if health["ok"]:
		return _running_result(false, 0)
	if _port_is_open():
		return {
			"ok": false,
			"error":
			{
				"code": "port_in_use",
				"message": "port %d answers but is not a healthy llama-server" % _port,
			},
		}
	if not bool(config.get("auto_start", false)):
		return {
			"ok": false,
			"error":
			{
				"code": "server_unreachable",
				"message":
				(
					"no llama-server at %s (health: %s)"
					% [config["base_url"], String(health.get("error", "not ok"))]
				),
			},
		}
	_supervised = true
	return _start_locked(cancel)


func _start_locked(cancel: LLMCancelToken) -> Dictionary:
	var validation := _validate_files()
	if not validation["ok"]:
		_supervised = false
		return validation
	var pid := OS.create_process(String(config["server_exe"]), _build_args(), false)
	if pid <= 0:
		_supervised = false
		return {
			"ok": false,
			"error":
			{
				"code": "server_start_failed",
				"message": "OS.create_process failed for " + String(config["server_exe"]),
			},
		}
	_pid = pid
	_owns = true
	var started := Time.get_ticks_msec()
	var budget := int(config["startup_timeout_ms"])
	while Time.get_ticks_msec() - started < budget:
		if cancel != null and cancel.is_cancelled():
			_stop_locked()
			return _cancelled()
		if not OS.is_process_running(pid):
			_pid = 0
			_owns = false
			_supervised = false
			return {
				"ok": false,
				"error":
				{
					"code": "server_exited",
					"message": "llama-server exited during startup (pid %d)" % pid,
				},
			}
		if probe_health(400)["ok"]:
			return _running_result(true, Time.get_ticks_msec() - started)
		OS.delay_msec(POLL_MS)
	_stop_locked()
	return {
		"ok": false,
		"error":
		{
			"code": "server_start_timeout",
			"message": "llama-server did not become healthy within %d ms" % budget,
		},
	}


func _validate_files() -> Dictionary:
	var exe := String(config["server_exe"])
	if not FileAccess.file_exists(exe):
		return {
			"ok": false,
			"error":
			{
				"code": "server_files_missing",
				"message": "llama-server not found: " + exe,
			},
		}
	var model := String(config["model_path"])
	if not FileAccess.file_exists(model):
		return {
			"ok": false,
			"error":
			{
				"code": "server_files_missing",
				"message": "model not found: " + model,
			},
		}
	return {"ok": true}


func _build_args() -> PackedStringArray:
	var args := PackedStringArray(
		[
			"-m",
			String(config["model_path"]),
			"-ngl",
			str(int(config["gpu_layers"])),
			"-c",
			str(int(config["ctx_size"])),
			"--jinja",
			"--host",
			_host,
			"--port",
			str(_port),
			"-np",
			str(int(config["parallel_slots"])),
		]
	)
	for vector: Variant in config.get("control_vectors", []):
		if typeof(vector) != TYPE_DICTIONARY or not vector.has("path"):
			continue
		var path := String(vector["path"])
		if path.is_empty():
			continue
		args.append("--control-vector-scaled")
		args.append("%s:%s" % [path, String.num(float(vector.get("scale", 1.0)), 4)])
	for arg: Variant in config.get("extra_args", PackedStringArray()):
		args.append(String(arg))
	return args


func _stop_locked() -> void:
	_supervised = false
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
		var deadline := Time.get_ticks_msec() + int(config["stop_timeout_ms"])
		while OS.is_process_running(_pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(POLL_MS)
	_pid = 0
	_owns = false


func _running_result(started: bool, startup_ms: int) -> Dictionary:
	return {
		"ok": true,
		"started": started,
		"attached": not _owns,
		"pid": _pid,
		"startup_ms": startup_ms,
		"error": {},
	}


func _cancelled() -> Dictionary:
	return {"ok": false, "error": {"code": "cancelled", "message": "cancelled by caller"}}


func _lock(cancel: LLMCancelToken) -> bool:
	while not _mutex.try_lock():
		if cancel != null and cancel.is_cancelled():
			return false
		OS.delay_msec(5)
	return true


func _port_is_open() -> bool:
	var peer := StreamPeerTCP.new()
	var err := peer.connect_to_host(_host, _port)
	if err != OK and err != ERR_BUSY:
		return false
	var deadline := Time.get_ticks_msec() + int(config["connect_timeout_ms"])
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			return true
		if peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			return false
		OS.delay_msec(5)
	return false


func _parse_health(response: String) -> Dictionary:
	var parts := response.split("\r\n\r\n", false, 1)
	if parts.is_empty() or not parts[0].begins_with("HTTP/"):
		return {"ok": false, "status": 0, "body": {}, "loading": false, "error": ""}
	var status_parts := parts[0].split("\r\n")[0].split(" ", false)
	var status := 0
	if status_parts.size() >= 2 and status_parts[1].is_valid_int():
		status = status_parts[1].to_int()
	var body: Variant = {}
	if parts.size() > 1 and not parts[1].strip_edges().is_empty():
		body = JSON.parse_string(parts[1])
	if typeof(body) != TYPE_DICTIONARY:
		body = {}
	var ok := status == 200 and String(body.get("status", "")) == "ok"
	var loading := status == 503 or String(body.get("status", "")) == "loading model"
	return {
		"ok": ok,
		"status": status,
		"body": body,
		"loading": loading,
		"error": "" if ok else "health status %d" % status,
	}
