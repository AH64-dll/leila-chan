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
		## The working directory the server process will have (docs/06 §4). Only
		## used to make a Windows drive-letter vector path flag-safe; POSIX paths
		## and relative paths need no base. See flag_path().
		"vector_cwd": "",
		"extra_args": PackedStringArray(),
		"startup_timeout_ms": DEFAULT_STARTUP_TIMEOUT_MS,
		"health_timeout_ms": DEFAULT_HEALTH_TIMEOUT_MS,
		"stop_timeout_ms": DEFAULT_STOP_TIMEOUT_MS,
		"connect_timeout_ms": DEFAULT_CONNECT_TIMEOUT_MS,
		## A stage-change relaunch waits this long for an in-flight turn rather
		## than cutting off a line the player is reading (no lost input).
		"steering_turn_wait_ms": 15000,
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


## `tools/llm/cvec_path.py`'s rule for the in-game launcher (P0 gate C1 → P1.23 →
## P2.03). llama.cpp splits `--control-vector-scaled FNAME:SCALE` on ':' and ',',
## so a FNAME containing either can never be passed. POSIX absolute and relative
## paths pass through; a Windows drive path becomes a same-drive path relative to
## `cwd` (the server's working directory, which the launcher cannot control); the
## ambiguous `X:file` form and a filename literally containing ':'/',' are
## refused. Returning `ok: false` is the point: a server that silently ignores a
## vector reports healthy, so a bad path must keep the old dose instead.
## Returns {ok, path, error}.
static func flag_path(path: String, cwd := "", platform := "") -> Dictionary:
	var target := platform
	if target.is_empty():
		target = "windows" if OS.get_name() == "Windows" else "posix"
	if target == "posix":
		if _flag_unsafe_chars(path):
			return _flag_refused(_unsafe_message(path))
		return {"ok": true, "path": path, "error": ""}
	if target != "windows":
		return _flag_refused("unknown platform '%s' (windows|posix)" % target)
	var normalized := path.replace("\\", "/")
	if _is_drive_relative(normalized):
		return _flag_refused(
			(
				(
					"ambiguous drive-relative vector path '%s': 'X:file' means a saved "
					+ "directory on drive X, not a path; pass the full 'X:/...' path"
				)
				% path
			)
		)
	if _is_drive_rooted(normalized):
		var base := cwd.replace("\\", "/")
		if base.is_empty() or not (_is_drive_rooted(base) or base.begins_with("//")):
			return _flag_refused(
				(
					(
						"vector path '%s' is a Windows drive path and no server working "
						+ "directory is configured; set `vector_cwd` to the directory "
						+ "llama-server will run in"
					)
					% path
				)
			)
		if base[0].to_lower() != normalized[0].to_lower():
			return _flag_refused(
				(
					(
						"vector '%s' is on a different drive than the server working "
						+ "directory '%s'; llama.cpp cannot take an absolute drive path"
					)
					% [path, cwd]
				)
			)
		var relative := _windows_relative(normalized, base)
		if _flag_unsafe_chars(relative):
			return _flag_refused(_unsafe_message(path))
		return {"ok": true, "path": relative, "error": ""}
	var out := _windows_normalise(normalized)
	if _flag_unsafe_chars(out):
		return _flag_refused(_unsafe_message(path))
	return {"ok": true, "path": out, "error": ""}


static func _flag_unsafe_chars(path: String) -> bool:
	return ":" in path or "," in path


static func _flag_refused(message: String) -> Dictionary:
	return {"ok": false, "path": "", "error": message}


static func _unsafe_message(path: String) -> String:
	return (
		(
			"control vector path '%s' contains ':' or ',' — the "
			+ "--control-vector-scaled FNAME:SCALE parser cannot accept it; rename "
			+ "the file or use a path without ':'/','"
		)
		% path
	)


## True for `X:\foo` / `X:/foo` (drive letter + separator). Expects '/'.
static func _is_drive_rooted(path: String) -> bool:
	return (
		path.length() >= 3
		and _is_letter(path[0])
		and path[1] == ":"
		and (path[2] == "/" or path[2] == "\\")
	)


## True for `X:foo` (drive letter, colon, no separator) — ambiguous: Windows
## reads it as "this name in the saved directory of drive X".
static func _is_drive_relative(path: String) -> bool:
	return (
		path.length() >= 3
		and _is_letter(path[0])
		and path[1] == ":"
		and path[2] != "/"
		and path[2] != "\\"
	)


static func _is_letter(character: String) -> bool:
	var upper := character.to_upper()
	return character.length() == 1 and upper >= "A" and upper <= "Z"


## A path relative to `base`, both drive-rooted ('/' form, same drive). Walks up
## when the target is outside `base`, exactly like ntpath.relpath.
static func _windows_relative(absolute: String, base: String) -> String:
	var target_parts := absolute.split("/", false)
	var base_parts := base.split("/", false)
	var shared := 0
	while (
		shared < target_parts.size()
		and shared < base_parts.size()
		and target_parts[shared].to_lower() == base_parts[shared].to_lower()
	):
		shared += 1
	var parts := PackedStringArray()
	for _index: int in range(shared, base_parts.size()):
		parts.append("..")
	for index: int in range(shared, target_parts.size()):
		parts.append(String(target_parts[index]))
	if parts.is_empty():
		return "."
	return "/".join(parts)


## ntpath.normpath's essence for the forms that skip the relative branch: drop
## '.', fold 'x/..' and keep leading '//' (a UNC share).
static func _windows_normalise(path: String) -> String:
	var prefix := "//" if path.begins_with("//") else ""
	var parts := path.trim_prefix(prefix).split("/", false)
	var out := PackedStringArray()
	for part: String in parts:
		if part == ".":
			continue
		if part == ".." and not out.is_empty() and String(out[out.size() - 1]) != "..":
			out.remove_at(out.size() - 1)
			continue
		out.append(part)
	return prefix + "/".join(out)


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


## docs/06 §4 stage change: relaunch with a new control-vector set. The whole
## stop/start runs under the process mutex, so a turn's ensure_running() waits
## here and lands on the new server instead of racing a second one onto the port
## (no lost player input). Nothing is killed before the new set validates: a bad
## vector leaves the running server and its old dose untouched. If the launch
## fails after the stop, `previous` is put back and relaunched — "keep the old
## dose" has to mean a live server carrying the last dose it bound, not a dead
## port. Returns the same shape as restart() plus:
##   kept_previous — the vectors in effect are the old ones
##   recovered     — a server is answering again (kept or relaunched)
##   restart_ms    — validate/stop/start wall time
func restart_with_vectors(
	vectors: Array, previous: Array, cancel: LLMCancelToken = null
) -> Dictionary:
	if not _lock(cancel):
		return _cancelled()
	var started := Time.get_ticks_msec()
	var old_pid := _pid
	config["control_vectors"] = vectors.duplicate(true)
	var validation := _validate_files()
	if not validation["ok"]:
		config["control_vectors"] = previous.duplicate(true)
		_mutex.unlock()
		return {
			"ok": false,
			"error": validation["error"],
			"kept_previous": true,
			"recovered": is_running(),
			"old_pid": old_pid,
			"pid": _pid,
			"restart_ms": Time.get_ticks_msec() - started,
		}
	_stop_locked()
	_supervised = true
	var result := _start_locked(cancel)
	result["old_pid"] = old_pid
	result["kept_previous"] = false
	result["recovered"] = true
	if not result["ok"]:
		config["control_vectors"] = previous.duplicate(true)
		_supervised = true
		var recovery := _start_locked(cancel)
		result["kept_previous"] = true
		result["recovered"] = bool(recovery.get("ok", false))
		result["recovery_error"] = recovery.get("error", {})
		result["pid"] = _pid
	result["restart_ms"] = Time.get_ticks_msec() - started
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
	var vector_error := _control_vector_error()
	if not vector_error.is_empty():
		return {"ok": false, "error": vector_error}
	return {"ok": true}


## Every configured vector must be a readable GGUF with a flag-safe FNAME before
## anything is launched: llama.cpp only logs "no valid control vector files
## passed" for a bad one and then serves healthy, so an unvalidated set would run
## unsteered while the game believed it was dosed (docs/06 §4). {} when clean.
func _control_vector_error() -> Dictionary:
	var cwd := String(config.get("vector_cwd", ""))
	for vector: Variant in config.get("control_vectors", []):
		if typeof(vector) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = vector
		var path := String(entry.get("path", ""))
		if path.is_empty():
			continue
		if not FileAccess.file_exists(path):
			return {
				"code": "control_vector_missing",
				"message": "control vector not found: " + path,
			}
		if not StageSteering.has_gguf_magic(path):
			return {
				"code": "control_vector_invalid",
				"message": "not a GGUF control vector: " + path,
			}
		var flag := flag_path(path, cwd)
		if not flag["ok"]:
			return {"code": "control_vector_path_unsafe", "message": String(flag["error"])}
		if not is_finite(float(entry.get("scale", 1.0))):
			return {
				"code": "control_vector_invalid",
				"message": "non-finite control-vector scale for " + path,
			}
	return {}


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
	var cwd := String(config.get("vector_cwd", ""))
	for vector: Variant in config.get("control_vectors", []):
		if typeof(vector) != TYPE_DICTIONARY or not vector.has("path"):
			continue
		var path := String(vector["path"])
		if path.is_empty():
			continue
		# _validate_files() already refused anything the flag grammar cannot take,
		# through the same rule tools/llm/cvec_path.py applies to the shell launchers.
		var flag := flag_path(path, cwd)
		var scale := String.num(float(vector.get("scale", 1.0)), 4)
		args.append("--control-vector-scaled")
		args.append("%s:%s" % [String(flag["path"]), scale])
	for arg: Variant in config.get("extra_args", PackedStringArray()):
		args.append(String(arg))
	return args


func _stop_locked() -> void:
	_supervised = false
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
		# Wait for the socket to close rather than for the pid to vanish: once a
		# child is reaped, OS.is_process_running() prints an engine error on Linux
		# (P1.02 CODE-2), and the free port is what a relaunch actually needs back.
		var deadline := Time.get_ticks_msec() + int(config["stop_timeout_ms"])
		while Time.get_ticks_msec() < deadline and _port_is_open():
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
