extends RefCounted
## Scriptable localhost HTTP/SSE server for LlamaServerBackend tests (P1.02).
## It listens on an ephemeral port, records each request body, and replays
## `deltas` as OpenAI-style `choices[0].delta.content` SSE frames. Modes cover
## the transport's hard paths: chunked vs Content-Length vs close-framed,
## byte-at-a-time writes (split chunk headers and UTF-8 characters), HTTP
## errors, truncated streams, stalls (read/turn timeout, cancellation) and a
## connection that works only on retry.

var port := 0
var deltas := PackedStringArray()
var timings := {"prompt_n": 12, "predicted_n": 34, "predicted_per_second": 42.5}
var include_done := true
var include_comment := false
var status := 200
var error_body := '{"error":{"message":"fake server error"}}'
var framing := "chunked"  # chunked | content_length | close
var split_writes := false
var byte_delay_ms := 0
var event_delay_ms := 0
var stall_after_events := -1
var truncate_after_events := -1
var truncate_connections := 0
var drop_connections := 0
var max_connections := 1

var _server := TCPServer.new()
var _thread: Thread
var _running := false
var _mutex := Mutex.new()
var _requests: Array[Dictionary] = []
var _connections := 0


func start() -> bool:
	if _server.listen(0, "127.0.0.1") != OK:
		return false
	port = _server.get_local_port()
	_running = true
	_thread = Thread.new()
	_thread.start(_serve)
	return true


func stop() -> void:
	_running = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_server.stop()


func base_url() -> String:
	return "http://127.0.0.1:%d" % port


func recorded_requests() -> Array[Dictionary]:
	_mutex.lock()
	var copy := _requests.duplicate(true)
	_mutex.unlock()
	return copy


func connection_count() -> int:
	_mutex.lock()
	var count := _connections
	_mutex.unlock()
	return count


func _serve() -> void:
	while _running and connection_count() < max_connections:
		if not _server.is_connection_available():
			OS.delay_msec(2)
			continue
		var peer := _server.take_connection()
		if peer == null:
			continue
		var request := _read_request(peer)
		if request.is_empty():
			peer.disconnect_from_host()
			continue
		if String(request["head"]).begins_with("GET /health"):
			_respond_health(peer)
			peer.disconnect_from_host()
			continue
		_mutex.lock()
		if _connections >= max_connections:
			_mutex.unlock()
			peer.disconnect_from_host()
			break
		_connections += 1
		var index := _connections - 1
		_mutex.unlock()
		_handle(peer, index, request)


func _handle(peer: StreamPeerTCP, index: int, request: Dictionary) -> void:
	_mutex.lock()
	_requests.append(request)
	_mutex.unlock()
	if status != 200:
		_write_error(peer)
		peer.disconnect_from_host()
		return
	var frames := _frames(index)
	var head := _response_head(frames)
	_write_raw(peer, head.to_utf8_buffer())
	var sent := 0
	for frame: PackedByteArray in frames:
		if not _running:
			break
		if stall_after_events >= 0 and sent >= stall_after_events:
			_stall()
			break
		_write(peer, frame)
		sent += 1
		if event_delay_ms > 0:
			OS.delay_msec(event_delay_ms)
	if framing == "chunked" and _running and not _truncated(index):
		_write_raw(peer, "0\r\n\r\n".to_utf8_buffer())
	peer.disconnect_from_host()


func _response_head(frames: Array[PackedByteArray]) -> String:
	if framing == "chunked":
		return (
			"HTTP/1.1 200 OK\r\n"
			+ "Content-Type: text/event-stream\r\n"
			+ "Transfer-Encoding: chunked\r\n"
			+ "Connection: close\r\n\r\n"
		)
	var length := 0
	for frame: PackedByteArray in frames:
		length += frame.size()
	return (
		(
			"HTTP/1.1 200 OK\r\n"
			+ "Content-Type: text/event-stream\r\n"
			+ "Content-Length: %d\r\n"
			+ "Connection: close\r\n\r\n"
		)
		% length
	)


func _frames(index: int) -> Array[PackedByteArray]:
	var frames: Array[PackedByteArray] = []
	if index < drop_connections:
		return frames
	if include_comment:
		frames.append(": keep-alive\n\n".to_utf8_buffer())
	var count := 0
	for delta: String in deltas:
		if truncate_after_events >= 0 and count >= truncate_after_events:
			return frames
		frames.append(_sse_event(delta))
		count += 1
	if _truncated(index):
		return frames
	frames.append(_final_event())
	if include_done:
		frames.append("data: [DONE]\n\n".to_utf8_buffer())
	return frames


func _truncated(index: int) -> bool:
	return (
		truncate_after_events >= 0
		or index < drop_connections
		or (index < truncate_connections and truncate_connections > 0)
	)


func _sse_event(delta: String) -> PackedByteArray:
	var event := {"choices": [{"index": 0, "delta": {"content": delta}, "finish_reason": null}]}
	return ("data: " + JSON.stringify(event) + "\n\n").to_utf8_buffer()


func _final_event() -> PackedByteArray:
	var event := {
		"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
		"timings": timings,
	}
	return ("data: " + JSON.stringify(event) + "\n\n").to_utf8_buffer()


func _respond_health(peer: StreamPeerTCP) -> void:
	var body := '{"status":"ok"}'
	var head := (
		(
			"HTTP/1.1 200 OK\r\n"
			+ "Content-Type: application/json\r\n"
			+ "Content-Length: %d\r\n"
			+ "Connection: close\r\n\r\n"
		)
		% body.to_utf8_buffer().size()
	)
	_write_raw(peer, head.to_utf8_buffer() + body.to_utf8_buffer())


func _write_error(peer: StreamPeerTCP) -> void:
	var head := (
		(
			"HTTP/1.1 %d Error\r\n"
			+ "Content-Type: application/json\r\n"
			+ "Content-Length: %d\r\n"
			+ "Connection: close\r\n\r\n"
		)
		% [status, error_body.to_utf8_buffer().size()]
	)
	_write_raw(peer, head.to_utf8_buffer() + error_body.to_utf8_buffer())


func _write(peer: StreamPeerTCP, data: PackedByteArray) -> void:
	if data.is_empty():
		return
	if framing == "chunked":
		data = ("%x\r\n" % data.size()).to_utf8_buffer() + data + "\r\n".to_utf8_buffer()
	_write_raw(peer, data)


func _write_raw(peer: StreamPeerTCP, data: PackedByteArray) -> void:
	if data.is_empty():
		return
	if split_writes:
		for i: int in data.size():
			if not _running:
				return
			_put(peer, data.slice(i, i + 1))
			if byte_delay_ms > 0:
				OS.delay_msec(byte_delay_ms)
		return
	_put(peer, data)


func _put(peer: StreamPeerTCP, data: PackedByteArray) -> void:
	var offset := 0
	var deadline := Time.get_ticks_msec() + 5000
	while offset < data.size() and Time.get_ticks_msec() < deadline and _running:
		peer.poll()
		var res: Array = peer.put_partial_data(data.slice(offset))
		if res[0] != OK:
			return
		offset += int(res[1])
		if int(res[1]) == 0:
			OS.delay_msec(1)


func _stall() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while _running and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)


func _read_request(peer: StreamPeerTCP) -> Dictionary:
	var buffer := PackedByteArray()
	var head_end := -1
	var deadline := Time.get_ticks_msec() + 5000
	while head_end < 0 and Time.get_ticks_msec() < deadline and _running:
		peer.poll()
		if peer.get_available_bytes() <= 0:
			OS.delay_msec(1)
			continue
		var res: Array = peer.get_partial_data(65536)
		if res[0] != OK:
			return {}
		buffer.append_array(res[1])
		head_end = _find(buffer, "\r\n\r\n")
	if head_end < 0:
		return {}
	var head := buffer.slice(0, head_end).get_string_from_utf8()
	var body := buffer.slice(head_end + 4)
	var content_length := _content_length(head)
	while body.size() < content_length and Time.get_ticks_msec() < deadline and _running:
		peer.poll()
		if peer.get_available_bytes() <= 0:
			OS.delay_msec(1)
			continue
		var res: Array = peer.get_partial_data(65536)
		if res[0] != OK:
			return {}
		body.append_array(res[1])
	var body_text := body.slice(0, content_length).get_string_from_utf8()
	var parsed: Variant = null
	if not body_text.strip_edges().is_empty():
		parsed = JSON.parse_string(body_text)
	return {
		"head": head,
		"body_text": body_text,
		"body": parsed if typeof(parsed) == TYPE_DICTIONARY else {},
	}


func _content_length(head: String) -> int:
	for line: String in head.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			var value := line.substr(line.find(":") + 1).strip_edges()
			return value.to_int() if value.is_valid_int() else 0
	return 0


func _find(buffer: PackedByteArray, needle: String) -> int:
	var pattern := needle.to_utf8_buffer()
	if buffer.size() < pattern.size():
		return -1
	for i: int in range(buffer.size() - pattern.size() + 1):
		var matched := true
		for j: int in pattern.size():
			if buffer[i + j] != pattern[j]:
				matched = false
				break
		if matched:
			return i
	return -1
