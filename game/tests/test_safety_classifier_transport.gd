extends SceneTree
## P2.17 — classifier transport end-to-end (docs/02 §8). Runs the real
## SafetyClassifierHttp against a scripted localhost llama-server, so the HTTP
## request shape, the yes/no parse, the fail-closed paths and the MEASURED
## added latency are all real (the 8-token model decode is the only part a fake
## server cannot provide; it is reported separately by the prompt lab).
##
##   ./tools/godot.sh --headless --path game \
##     --script res://tests/test_safety_classifier_transport.gd
##
## Also proves the streaming seam live: a flagged beat's tail is held, the
## transport answers asynchronously, and `Safety.hold_released` carries the
## released text to the beat that owned it.

const ServerScr := preload("res://tests/helpers/FakeLlamaServer.gd")
const REQUESTS := 20
const TIMEOUT_MS := 4000
const FLAGGED_BEAT := "i can't go on"
const FLAGGED_TAIL := "can't go on"

var _failures := 0
var _server: Object = null
var _transport: SafetyClassifierHttp = null
var _filter: SafetyFilter = null
var _seen: Array = []
var _stream_deadline := 0


class Box:
	var mutex := Mutex.new()
	var done := false
	var result: Dictionary = {}

	func put(value: Variant) -> void:
		mutex.lock()
		result = value.duplicate(true) if value is Dictionary else {}
		done = true
		mutex.unlock()

	func take() -> Dictionary:
		mutex.lock()
		var out := {"done": done, "result": result.duplicate(true)}
		mutex.unlock()
		return out


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL  ", msg)


func _pass(msg: String) -> void:
	print("PASS  ", msg)


func _initialize() -> void:
	_server = ServerScr.new()
	_server.set("max_connections", REQUESTS + 8)
	_server.set("deltas", PackedStringArray(["No"]))
	_server.set("event_delay_ms", 0)
	if not bool(_server.call("start")):
		_fail("fake llama-server did not start")
		quit(1)
		return
	_pass("fake llama-server on " + String(_server.call("base_url")))

	_transport = (
		SafetyClassifierHttp
		. new(
			{
				"base_url": String(_server.call("base_url")),
				"connect_timeout_ms": 1000,
				"read_timeout_ms": TIMEOUT_MS,
			}
		)
	)
	var request := _build_request()
	_measure(request)
	_check_request_shape()
	_check_answers()
	_check_fail_closed()
	_start_stream_case()


func _process(_delta: float) -> bool:
	if _filter == null:
		return true
	if not _seen.is_empty():
		var tail := String(_seen[0][1])
		if tail == FLAGGED_TAIL:
			_pass("held tail released after the verdict: '%s'" % tail)
		else:
			_fail("released tail was '%s', expected '%s'" % [tail, FLAGGED_TAIL])
		var stats: Dictionary = _filter.classifier_gate.call("stats")
		if int(stats["hold_count"]) >= 1 and int(stats["blocks"]) + int(stats["passes"]) >= 1:
			_pass(
				(
					"hold measured: %d ms held, %d verdicts, %d requests"
					% [
						int(stats["hold_ms_total"]),
						int(stats["passes"]) + int(stats["blocks"]),
						int(stats["requests"])
					]
				)
			)
		else:
			_fail("hold/verdict stats missing: %s" % stats)
		_finish()
		return true
	if Time.get_ticks_msec() > _stream_deadline:
		_fail("held tail was never released (deadline %d ms)" % TIMEOUT_MS)
		_finish()
		return true
	return false


func _finish() -> void:
	if _transport != null:
		_transport.shutdown()
	if _server != null:
		_server.call("stop")
	if _filter != null:
		_filter.free()
		_filter = null
	if _failures == 0:
		print("test_safety_classifier_transport: all checks passed")
		quit(0)
	else:
		printerr("test_safety_classifier_transport: %d check(s) failed" % _failures)
		quit(1)


func _build_request() -> Dictionary:
	_filter = SafetyFilter.new()
	if not _filter.reload():
		_fail("filter lists + classifier data failed to load")
		return {}
	_filter.classifier_gate.set_backend(_transport)
	var flag := {
		"s": 0,
		"e": 20,
		"cat": "harm_to_player",
		"match": "you should disappear",
		"key": "harm_to_player|you should disappear",
	}
	return _filter.classifier_gate.classifier.build_request(
		flag, "you should disappear.", {"stage": 0, "content_level": "full"}
	)


## Wall-clock round trip of the real transport (thread start + TCP + request +
## SSE parse + callback). The fake server answers instantly, so this number is
## the transport's own overhead; a real 4B model adds its 8-token decode time.
func _measure(request: Dictionary) -> void:
	if request.is_empty():
		return
	var total_ms := 0
	var slowest_ms := 0
	var slowest_ok := true
	for i in REQUESTS:
		var box := Box.new()
		var started := Time.get_ticks_msec()
		_transport.classify(request, func(value: Variant) -> void: box.put(value))
		var state := _await(box)
		var elapsed := Time.get_ticks_msec() - started
		if state.is_empty():
			_fail("transport timed out on request %d" % i)
			slowest_ok = false
			break
		total_ms += elapsed
		slowest_ms = maxi(slowest_ms, elapsed)
	if slowest_ok:
		_pass(
			(
				(
					"transport latency: %.1f ms avg, %d ms worst over %d requests "
					+ "(localhost, thread start + HTTP + 8-token callback; model decode excluded)"
				)
				% [float(total_ms) / float(REQUESTS), slowest_ms, REQUESTS]
			)
		)


func _check_request_shape() -> void:
	var requests: Array = _server.call("recorded_requests")
	if requests.is_empty():
		_fail("no request reached the fake server")
		return
	var body: Dictionary = requests[0].get("body", {})
	var shape_ok := (
		int(body.get("max_tokens", -1)) == 8
		and not body.has("response_format")
		and bool(body.get("stream", false))
		and is_equal_approx(float(body.get("temperature", -1.0)), 0.0)
		and not body.has("dose")
	)
	var messages: Array = body.get("messages", [])
	if not shape_ok:
		_fail("request shape wrong: %s" % body)
	elif messages.size() != 2 or String(messages[0].get("role", "")) != "system":
		_fail("classifier prompt is not system+user: %s" % messages)
	else:
		_pass("request shape: 8 tokens, no grammar, system+user, temperature 0, no vectors bound")


func _check_answers() -> void:
	var no_result := _classify_with(PackedStringArray(["No"]))
	var interpreted_no: Dictionary = _filter.classifier_gate.classifier.interpret(no_result)
	if bool(interpreted_no.get("ok", false)) and String(interpreted_no["verdict"]) == "no":
		_pass("answer 'No' parsed as a pass verdict")
	else:
		_fail("answer 'No' not parsed: %s" % no_result)
	var yes_result := _classify_with(PackedStringArray(["Yes"]))
	var interpreted_yes: Dictionary = _filter.classifier_gate.classifier.interpret(yes_result)
	if bool(interpreted_yes.get("ok", false)) and String(interpreted_yes["verdict"]) == "yes":
		_pass("answer 'Yes' parsed as a block verdict")
	else:
		_fail("answer 'Yes' not parsed: %s" % yes_result)
	var garbage := _classify_with(PackedStringArray(["maybe"]))
	var interpreted_bad: Dictionary = _filter.classifier_gate.classifier.interpret(garbage)
	if not bool(interpreted_bad.get("ok", true)):
		_pass("unparseable answer becomes a fail-closed error")
	else:
		_fail("unparseable answer was accepted: %s" % interpreted_bad)


func _classify_with(deltas: PackedStringArray) -> Dictionary:
	_server.set("deltas", deltas)
	var request: Dictionary = _filter.classifier_gate.classifier.build_request(
		{"s": 0, "e": 12, "cat": "self_harm_her", "match": "go on", "key": "probe"},
		"i can't go on",
		{"stage": 0}
	)
	var box := Box.new()
	_transport.classify(request, func(value: Variant) -> void: box.put(value))
	return _await(box)


func _check_fail_closed() -> void:
	_server.set("status", 500)
	var request: Dictionary = _filter.classifier_gate.classifier.build_request(
		{"s": 0, "e": 12, "cat": "self_harm_her", "match": "go on", "key": "probe"},
		"i can't go on",
		{"stage": 0}
	)
	var box := Box.new()
	_transport.classify(request, func(value: Variant) -> void: box.put(value))
	var result := _await(box)
	var interpreted: Dictionary = _filter.classifier_gate.classifier.interpret(result)
	if bool(interpreted.get("ok", true)):
		_fail("HTTP 500 was accepted as a verdict: %s" % result)
	else:
		_pass("HTTP 500 fails closed (no verdict)")
	_server.set("status", 200)


## The live streaming seam: a flagged beat's tail stays in the filter, the real
## transport answers on its worker thread, and the released text arrives on
## `hold_released` for the beat that owned it.
func _start_stream_case() -> void:
	_server.set("deltas", PackedStringArray(["No"]))
	_server.set("event_delay_ms", 25)
	_filter.hold_released.connect(func(beat: int, text: String) -> void: _seen.append([beat, text]))
	_filter.begin_say({"stage": 0, "beat_index": 0})
	## The 34-char compact holdback keeps a short beat until its close, so the
	## prefix lands in end_say; the flag itself still starts the hold there.
	_filter.say_chunk(FLAGGED_BEAT)
	var prefix := _filter.end_say()
	if prefix != "i ":
		_fail("expected the prefix 'i ' at beat close, got '%s'" % prefix)
	else:
		_pass("prefix emitted at beat close; only the flagged tail is held")
	_stream_deadline = Time.get_ticks_msec() + TIMEOUT_MS


func _await(box: Box) -> Dictionary:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = box.call("take")
		if bool(state["done"]):
			return state["result"]
		OS.delay_msec(1)
	return {}
