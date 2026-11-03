class_name LlamaHttpClient
extends RefCounted
## Minimal HTTP/1.1 client with Server-Sent Events parsing for llama-server
## (docs/07 §3.1). Godot's HTTPRequest is a Node and main-thread only, so the
## backend speaks raw TCP on its worker thread instead. Everything here is
## blocking by design, every wait is bounded, and every poll checks the
## LLMCancelToken: a cancelled turn or a dead server can never hang the worker.
##
## What it handles: request head + JSON body, `Content-Length`, chunked
## transfer encoding (`hex[;ext]\r\n<bytes>\r\n...0\r\n`), SSE `data:` lines
## (multi-line, comments, CRLF or LF), llama-server's `data: [DONE]`, and the
## final `timings` object. Non-2xx responses are returned as `http_error`
## with the server's JSON `error.message` when present.

const DEFAULT_CONNECT_TIMEOUT_MS := 2000
const DEFAULT_READ_TIMEOUT_MS := 60000
const DEFAULT_TURN_TIMEOUT_MS := 180000
const MAX_HEADER_BYTES := 65536
const MAX_ERROR_BODY_BYTES := 65536
const READ_CHUNK_BYTES := 65536
const POLL_MS := 2
const HEADER_END := "\r\n\r\n"


## POST JSON to `url` and consume a text/event-stream body. `on_token` is
## called once per non-empty `choices[0].delta.content` with the raw chunk.
## Returns {ok, text, status, headers, metrics, raw_stream, capture_error} on
## success or {ok: false, status, error: {code, message}, metrics, text} on
## failure. Metrics: first_byte_ms, first_token_ms, total_ms, chunks, chars,
## timings.
func post_stream(
	url: String,
	body: Dictionary,
	on_token: Callable,
	cancel: LLMCancelToken,
	options: Dictionary = {}
) -> Dictionary:
	var opts := _resolve_options(options)
	var target := parse_http_url(url)
	var started := Time.get_ticks_msec()
	if not target["ok"]:
		return _failure(target["error"], 0, started)
	var peer := StreamPeerTCP.new()
	var connect_error := _connect(peer, target, opts, cancel)
	if not connect_error.is_empty():
		return _failure(connect_error, 0, started)
	var payload := _request_bytes(target, body)
	var write_error := _write_all(peer, payload, started, opts, cancel)
	if not write_error.is_empty():
		peer.disconnect_from_host()
		return _failure(write_error, 0, started)
	var session := _read_session(peer, on_token, cancel, opts, started)
	peer.disconnect_from_host()
	var result := _finish_session(session)
	var capture_error := _write_capture(opts["capture_path"], session["raw"])
	result["capture_error"] = capture_error
	return result


## Split "http://host:port/path" into {ok, host, port, path, host_header}.
## Only plain HTTP is supported: llama-server is local and unencrypted.
static func parse_http_url(url: String) -> Dictionary:
	if not url.begins_with("http://"):
		return {
			"ok": false,
			"error":
			{
				"code": "unsupported_scheme",
				"message": "only http:// URLs are supported, got: " + url,
			},
		}
	var rest := url.substr(7)
	var slash := rest.find("/")
	var authority := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	if path.is_empty():
		path = "/"
	var host := authority
	var port := 80
	var colon := authority.rfind(":")
	if colon >= 0:
		host = authority.substr(0, colon)
		var port_text := authority.substr(colon + 1)
		if not port_text.is_valid_int():
			return {
				"ok": false,
				"error": {"code": "bad_url", "message": "invalid port in URL: " + url},
			}
		port = port_text.to_int()
	if host.is_empty() or port <= 0 or port > 65535:
		return {
			"ok": false,
			"error": {"code": "bad_url", "message": "invalid host/port in URL: " + url},
		}
	return {
		"ok": true,
		"host": host,
		"port": port,
		"path": path,
		"host_header": authority,
		"error": {},
	}


func _resolve_options(options: Dictionary) -> Dictionary:
	return {
		"connect_timeout_ms": int(options.get("connect_timeout_ms", DEFAULT_CONNECT_TIMEOUT_MS)),
		"read_timeout_ms": int(options.get("read_timeout_ms", DEFAULT_READ_TIMEOUT_MS)),
		"turn_timeout_ms": int(options.get("turn_timeout_ms", DEFAULT_TURN_TIMEOUT_MS)),
		"capture_path": String(options.get("capture_path", "")),
	}


func _connect(
	peer: StreamPeerTCP, target: Dictionary, opts: Dictionary, cancel: LLMCancelToken
) -> Dictionary:
	var err := peer.connect_to_host(target["host"], target["port"])
	if err != OK and err != ERR_BUSY:
		return {
			"code": "server_unreachable",
			"message":
			(
				"connect_to_host(%s:%d) failed: %s"
				% [target["host"], target["port"], error_string(err)]
			),
		}
	var deadline: int = Time.get_ticks_msec() + int(opts["connect_timeout_ms"])
	while Time.get_ticks_msec() < deadline:
		if cancel.is_cancelled():
			return {"code": "cancelled", "message": "cancelled while connecting"}
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			return {}
		if status == StreamPeerTCP.STATUS_ERROR:
			return {
				"code": "server_unreachable",
				"message": "connection to %s:%d failed" % [target["host"], target["port"]],
			}
		OS.delay_msec(POLL_MS)
	return {
		"code": "connect_timeout",
		"message":
		(
			"no connection to %s:%d within %d ms"
			% [target["host"], target["port"], opts["connect_timeout_ms"]]
		),
	}


func _request_bytes(target: Dictionary, body: Dictionary) -> PackedByteArray:
	var json := JSON.stringify(body, "", false)
	var head := (
		(
			"POST %s HTTP/1.1\r\n"
			+ "Host: %s\r\n"
			+ "Content-Type: application/json\r\n"
			+ "Accept: text/event-stream\r\n"
			+ "Cache-Control: no-cache\r\n"
			+ "Connection: close\r\n"
			+ "Content-Length: %d\r\n"
			+ "\r\n"
		)
		% [target["path"], target["host_header"], json.to_utf8_buffer().size()]
	)
	return head.to_utf8_buffer() + json.to_utf8_buffer()


func _write_all(
	peer: StreamPeerTCP,
	payload: PackedByteArray,
	started: int,
	opts: Dictionary,
	cancel: LLMCancelToken
) -> Dictionary:
	var offset := 0
	var deadline: int = started + int(opts["turn_timeout_ms"])
	while offset < payload.size():
		if cancel.is_cancelled():
			return {"code": "cancelled", "message": "cancelled while writing request"}
		if Time.get_ticks_msec() >= deadline:
			return {"code": "turn_timeout", "message": "request write exceeded the turn timeout"}
		peer.poll()
		var res: Array = peer.put_partial_data(payload.slice(offset))
		if res[0] != OK:
			return {
				"code": "read_failed",
				"message": "socket write failed: %s" % error_string(res[0]),
			}
		offset += int(res[1])
		if int(res[1]) == 0:
			OS.delay_msec(POLL_MS)
	return {}


## Reads and decodes one response. Errors are recorded in the session, never
## returned early, so partial text and timing metrics survive a failure.
func _read_session(
	peer: StreamPeerTCP, on_token: Callable, cancel: LLMCancelToken, opts: Dictionary, started: int
) -> Dictionary:
	var session := {
		"error": {},
		"started": started,
		"status": 0,
		"headers": {},
		"head_done": false,
		"head_buf": PackedByteArray(),
		"body_mode": "",
		"content_length": -1,
		"received": 0,
		"body_complete": false,
		"done": false,
		"error_body": PackedByteArray(),
		"sse": SseParser.new(),
		"chunked": ChunkedDecoder.new(),
		"raw": PackedByteArray(),
		"text": "",
		"chunks": 0,
		"first_byte_ms": -1,
		"first_token_ms": -1,
		"timings": {},
		"finish_reason": "",
		"last_read_ms": started,
	}
	var deadline: int = started + int(opts["turn_timeout_ms"])
	while not session["done"] and not session["body_complete"]:
		if not session["error"].is_empty():
			break
		if cancel.is_cancelled():
			session["error"] = {"code": "cancelled", "message": "cancelled by caller"}
			break
		var now := Time.get_ticks_msec()
		if now >= deadline:
			session["error"] = {
				"code": "turn_timeout",
				"message": "turn exceeded %d ms" % opts["turn_timeout_ms"],
			}
			break
		if now - int(session["last_read_ms"]) > opts["read_timeout_ms"]:
			session["error"] = {
				"code": "read_timeout",
				"message": "no data for %d ms" % opts["read_timeout_ms"],
			}
			break
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_read_eof(session)
			break
		if peer.get_available_bytes() > 0:
			var read_error := _read_available(peer, session, on_token)
			if not read_error.is_empty():
				session["error"] = read_error
		else:
			OS.delay_msec(POLL_MS)
		if session["error"].is_empty() and session["body_mode"] == "length":
			if int(session["received"]) >= int(session["content_length"]):
				session["body_complete"] = true
		if session["error"].is_empty() and session["body_mode"] == "chunked":
			if session["chunked"].finished:
				session["body_complete"] = true
	if session["error"].is_empty() and not session["head_done"]:
		session["error"] = {
			"code": "bad_response",
			"message": "connection closed before response headers",
		}
	if (
		session["error"].is_empty()
		and (int(session["status"]) < 200 or int(session["status"]) > 299)
	):
		_apply_http_error(session)
	return session


func _read_available(peer: StreamPeerTCP, session: Dictionary, on_token: Callable) -> Dictionary:
	var res: Array = peer.get_partial_data(READ_CHUNK_BYTES)
	if res[0] != OK:
		return {"code": "read_failed", "message": "socket read failed: %s" % error_string(res[0])}
	var data: PackedByteArray = res[1]
	var error: Dictionary = {}
	session["last_read_ms"] = Time.get_ticks_msec()
	if int(session["first_byte_ms"]) < 0:
		session["first_byte_ms"] = Time.get_ticks_msec() - int(session["started"])
	if not session["head_done"]:
		session["head_buf"].append_array(data)
		var head_end := _find_sequence(session["head_buf"], HEADER_END)
		if head_end < 0:
			if session["head_buf"].size() > MAX_HEADER_BYTES:
				error = {"code": "bad_response", "message": "response headers too large"}
			data = PackedByteArray()
		else:
			error = _parse_head(session, head_end)
			if error.is_empty():
				data = session["head_buf"].slice(head_end + HEADER_END.length())
				session["head_buf"] = PackedByteArray()
	if not error.is_empty():
		return error
	if data.is_empty():
		return {}
	return _consume_body(session["body_mode"], data, session, on_token)


func _parse_head(session: Dictionary, head_end: int) -> Dictionary:
	var head_bytes: PackedByteArray = session["head_buf"].slice(0, head_end)
	var lines := head_bytes.get_string_from_utf8().split("\r\n")
	if lines.is_empty() or not lines[0].begins_with("HTTP/"):
		return {"code": "bad_response", "message": "malformed HTTP status line"}
	var parts := lines[0].split(" ", false)
	if parts.size() < 2 or not parts[1].is_valid_int():
		return {"code": "bad_response", "message": "malformed HTTP status code"}
	session["status"] = parts[1].to_int()
	var headers := {}
	for i: int in range(1, lines.size()):
		var line: String = lines[i]
		var colon := line.find(":")
		if colon <= 0:
			continue
		var key := line.substr(0, colon).strip_edges().to_lower()
		var value := line.substr(colon + 1).strip_edges()
		headers[key] = value if not headers.has(key) else headers[key] + ", " + value
	session["headers"] = headers
	session["head_done"] = true
	if int(session["status"]) < 200 or int(session["status"]) > 299:
		session["body_mode"] = "error"
	elif String(headers.get("transfer-encoding", "")).to_lower().contains("chunked"):
		session["body_mode"] = "chunked"
	elif String(headers.get("content-length", "")).is_valid_int():
		session["content_length"] = String(headers["content-length"]).to_int()
		session["body_mode"] = "length"
	else:
		session["body_mode"] = "eof"
	return {}


func _consume_body(
	mode: String, data: PackedByteArray, session: Dictionary, on_token: Callable
) -> Dictionary:
	var decoded := data
	if mode == "chunked":
		decoded = session["chunked"].feed(data)
		if not session["chunked"].error.is_empty():
			return {"code": "bad_chunked_body", "message": session["chunked"].error}
	elif mode == "length":
		session["received"] = int(session["received"]) + data.size()
	if mode == "error":
		if session["error_body"].size() < MAX_ERROR_BODY_BYTES:
			session["error_body"].append_array(decoded)
		return {}
	session["raw"].append_array(decoded)
	for payload: String in session["sse"].feed_bytes(decoded):
		var event_error := _consume_event(payload, session, on_token)
		if not event_error.is_empty():
			return event_error
		if session["done"]:
			break
	return {}


func _consume_event(payload: String, session: Dictionary, on_token: Callable) -> Dictionary:
	if payload.strip_edges().is_empty():
		return {}
	if payload.strip_edges() == "[DONE]":
		session["done"] = true
		session["body_complete"] = true
		return {}
	var parsed: Variant = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"code": "malformed_sse", "message": "SSE data is not a JSON object"}
	var event: Dictionary = parsed
	if event.has("error"):
		return {
			"code": "server_error",
			"message": _error_message(event["error"], "llama-server reported an error"),
		}
	if event.get("timings") is Dictionary:
		session["timings"] = event["timings"]
	var choices: Variant = event.get("choices")
	if typeof(choices) != TYPE_ARRAY or choices.is_empty() or typeof(choices[0]) != TYPE_DICTIONARY:
		return {}
	var choice: Dictionary = choices[0]
	var delta: Variant = choice.get("delta", {})
	if typeof(delta) == TYPE_DICTIONARY:
		var content: Variant = delta.get("content")
		if typeof(content) == TYPE_STRING and not content.is_empty():
			session["text"] += content
			session["chunks"] = int(session["chunks"]) + 1
			if int(session["first_token_ms"]) < 0:
				session["first_token_ms"] = (Time.get_ticks_msec() - int(session["started"]))
			on_token.call(content)
	if choice.get("finish_reason") is String:
		session["finish_reason"] = choice["finish_reason"]
	return {}


func _read_eof(session: Dictionary) -> void:
	if not session["head_done"]:
		session["error"] = {
			"code": "bad_response",
			"message": "connection closed before response headers",
		}
		return
	if session["body_mode"] == "eof" or session["body_mode"] == "error":
		session["body_complete"] = true
		return
	if not session["done"]:
		session["error"] = {
			"code": "stream_truncated",
			"message": "connection closed before the SSE stream finished",
		}


func _apply_http_error(session: Dictionary) -> void:
	var message := "HTTP %d" % int(session["status"])
	var body_bytes: PackedByteArray = session["error_body"]
	var body := body_bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
		message = _error_message(parsed["error"], message)
	session["error"] = {"code": "http_error", "message": message, "status": session["status"]}


func _error_message(value: Variant, fallback: String) -> String:
	if typeof(value) == TYPE_DICTIONARY and value.get("message") is String:
		return value["message"]
	if typeof(value) == TYPE_STRING:
		return value
	return fallback


func _failure(error: Dictionary, status: int, started: int) -> Dictionary:
	return {
		"ok": false,
		"status": status,
		"error": error,
		"text": "",
		"raw_stream": PackedByteArray(),
		"capture_error": "",
		"metrics": {"total_ms": Time.get_ticks_msec() - started},
	}


## Turns the session into the public result. A cancelled turn is a failure
## here; the facade reports it as `cancelled` because the token is set.
func _finish_session(session: Dictionary) -> Dictionary:
	var text: String = session["text"]
	var metrics := {
		"first_byte_ms": int(session["first_byte_ms"]),
		"first_token_ms": int(session["first_token_ms"]),
		"total_ms": Time.get_ticks_msec() - int(session["started"]),
		"chunks": int(session["chunks"]),
		"chars": text.length(),
		"timings": session["timings"],
		"finish_reason": session["finish_reason"],
	}
	var result := {
		"ok": session["error"].is_empty() and (session["done"] or session["body_complete"]),
		"status": int(session["status"]),
		"headers": session["headers"],
		"text": text,
		"metrics": metrics,
		"raw_stream": session["raw"],
		"error": session["error"],
	}
	if result["ok"]:
		return result
	if result["error"].is_empty():
		result["error"] = {
			"code": "stream_incomplete",
			"message": "response ended without a complete SSE body",
		}
	return result


func _write_capture(path: String, bytes: PackedByteArray) -> String:
	if path.is_empty() or bytes.is_empty():
		return ""
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write capture %s (error %d)" % [path, FileAccess.get_open_error()]
	file.store_buffer(bytes)
	file.close()
	return ""


func _find_sequence(buf: PackedByteArray, needle: String) -> int:
	var pattern := needle.to_utf8_buffer()
	if pattern.is_empty() or buf.size() < pattern.size():
		return -1
	var last := buf.size() - pattern.size()
	for i: int in range(last + 1):
		var matched := true
		for j: int in pattern.size():
			if buf[i + j] != pattern[j]:
				matched = false
				break
		if matched:
			return i
	return -1


## Byte-oriented SSE parser. It keeps raw bytes until a complete line is
## available, so a UTF-8 character split across TCP reads is decoded intact.
class SseParser:
	var _buffer := PackedByteArray()
	var _data_lines := PackedStringArray()

	func feed_bytes(data: PackedByteArray) -> PackedStringArray:
		_buffer.append_array(data)
		var events := PackedStringArray()
		while true:
			var newline := _buffer.find(10)
			if newline < 0:
				break
			var line_bytes := _buffer.slice(0, newline)
			_buffer = _buffer.slice(newline + 1)
			if not line_bytes.is_empty() and line_bytes[line_bytes.size() - 1] == 13:
				line_bytes = line_bytes.slice(0, line_bytes.size() - 1)
			_dispatch_line(line_bytes.get_string_from_utf8(), events)
		return events

	func _dispatch_line(line: String, events: PackedStringArray) -> void:
		if line.is_empty():
			if not _data_lines.is_empty():
				events.append("\n".join(_data_lines))
				_data_lines.clear()
			return
		if line.begins_with(":"):
			return
		if not line.begins_with("data:"):
			return
		var value := line.substr(5)
		if value.begins_with(" "):
			value = value.substr(1)
		_data_lines.append(value)


## Incremental HTTP/1.1 chunked decoder. `feed()` returns decoded body bytes
## for whatever fragments are complete; `finished` flips at the zero chunk.
class ChunkedDecoder:
	var error := ""
	var finished := false
	var _buffer := PackedByteArray()
	var _remaining := 0
	var _state := 0  # 0 size line, 1 data, 2 data CRLF, 3 done

	func feed(data: PackedByteArray) -> PackedByteArray:
		_buffer.append_array(data)
		var out := PackedByteArray()
		while error.is_empty():
			if _state == 0:
				if not _parse_size():
					break
			elif _state == 1:
				_copy_data(out)
				if _remaining > 0 or not error.is_empty():
					break
				_state = 2
			elif _state == 2:
				if _buffer.size() < 2:
					break
				_buffer = _buffer.slice(2)
				_state = 0
			else:
				break
		return out

	func _parse_size() -> bool:
		var newline := _buffer.find(10)
		if newline < 0:
			return false
		var line := _buffer.slice(0, newline).get_string_from_utf8().strip_edges()
		_buffer = _buffer.slice(newline + 1)
		var size_text := line.split(";")[0].strip_edges()
		if not size_text.is_valid_hex_number(false):
			error = "invalid chunk size: " + line
			return false
		_remaining = size_text.hex_to_int()
		if _remaining == 0:
			finished = true
			_state = 3
			return false
		_state = 1
		return true

	func _copy_data(out: PackedByteArray) -> void:
		var take := mini(_remaining, _buffer.size())
		if take > 0:
			out.append_array(_buffer.slice(0, take))
			_buffer = _buffer.slice(take)
			_remaining -= take
