extends GdUnitTestSuite
## P1.01 — LLM facade contract (docs/07 §3.1). All tests drive the facade with
## the scripted FakeLLMBackend; the real transport lands in P1.02.

const LLMScript := preload("res://autoload/LLM.gd")
const FakeBackend := preload("res://tests/helpers/FakeLLMBackend.gd")


func _new_request() -> TurnRequest:
	var request := TurnRequest.new()
	request.messages = [{"role": "user", "content": "hi"}]
	request.schema = {"type": "object"}
	request.sampling = {"temperature": 0.75}
	request.max_tokens = 64
	return request


func _new_llm(transport: Variant) -> Node:
	var llm: Node = auto_free(LLMScript.new())
	add_child(llm)
	if transport != null:
		llm.set_backend(transport)
	return llm


## Collects every stream emission; also records whether token callbacks ran
## on the main thread (the docs/07 §3.1 call_deferred requirement).
func _spy(stream: TurnStream) -> Dictionary:
	var spy := {
		"tokens": PackedStringArray(),
		"terminal": &"",
		"payload": null,
		"tokens_on_main": true,
	}
	stream.token.connect(
		func(text: String) -> void:
			spy["tokens"].append(text)
			if OS.get_thread_caller_id() != OS.get_main_thread_id():
				spy["tokens_on_main"] = false
	)
	stream.completed.connect(
		func(text: String) -> void:
			spy["terminal"] = &"completed"
			spy["payload"] = text
	)
	stream.cancelled.connect(func() -> void: spy["terminal"] = &"cancelled")
	stream.failed.connect(
		func(err: Dictionary) -> void:
			spy["terminal"] = &"failed"
			spy["payload"] = err
	)
	return spy


func _await_terminal(spy: Dictionary, timeout_ms := 5000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while spy["terminal"] == &"" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_bool(spy["terminal"] != &"").is_true().append_failure_message(
		"timed out waiting for a terminal signal"
	)


func test_api_surface_matches_docs_07_3_1() -> void:
	var request := TurnRequest.new()
	assert_array(request.messages).is_empty()
	assert_dict(request.schema).is_empty()
	assert_dict(request.sampling).is_empty()
	assert_dict(request.dose).is_empty()
	assert_int(request.max_tokens).is_equal(600)

	var stream := TurnStream.new()
	for sig: String in ["token", "completed", "cancelled", "failed"]:
		assert_bool(stream.has_signal(sig)).is_true().append_failure_message(
			"TurnStream missing signal " + sig
		)
	assert_bool(stream.is_finished()).is_false()
	assert_bool(stream.is_cancelled()).is_false()

	var llm := _new_llm(FakeBackend.new())
	assert_bool(llm.has_signal("token")).is_true()
	assert_bool(llm.has_method("generate")).is_true()
	assert_bool(llm.has_method("set_dose")).is_true()
	assert_bool(llm.has_method("cancel")).is_true()
	assert_bool(llm.is_busy()).is_false()

	var autoload_llm := get_node("/root/LLM")
	assert_bool(autoload_llm.has_signal("token")).is_true()
	assert_bool(autoload_llm.has_method("generate")).is_true()
	assert_bool(autoload_llm.has_method("set_dose")).is_true()


func test_stream_completes_in_order_on_main_thread() -> void:
	var fake := FakeBackend.new()
	fake.chunks = PackedStringArray(['{"a":', "1", "}"])
	var llm := _new_llm(fake)
	var main_thread_id := OS.get_thread_caller_id()

	var mirror: PackedStringArray = []
	llm.token.connect(func(text: String) -> void: mirror.append(text))

	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	await _await_terminal(spy)

	assert_str(String(spy["terminal"])).is_equal("completed")
	assert_str(String(spy["payload"])).is_equal('{"a":1}')
	assert_array(Array(spy["tokens"])).contains_exactly(['{"a":', "1", "}"])
	assert_array(Array(mirror)).contains_exactly(Array(spy["tokens"]))
	assert_bool(spy["tokens_on_main"]).is_true()
	assert_int(fake.worker_thread_id).is_not_equal(main_thread_id)
	assert_bool(stream.is_finished()).is_true()
	assert_bool(stream.is_cancelled()).is_false()
	assert_bool(llm.is_busy()).is_false()

	# The spent worker must be joined without ever blocking the main thread.
	var deadline := Time.get_ticks_msec() + 2000
	while not llm._pending_join.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_array(llm._pending_join).is_empty()


func test_cancel_blocked_backend() -> void:
	var fake := FakeBackend.new()
	fake.chunks = PackedStringArray(["one", "two"])
	fake.block_until_cancel = true
	var llm := _new_llm(fake)

	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)

	var deadline := Time.get_ticks_msec() + 5000
	while spy["tokens"].size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_int(spy["tokens"].size()).is_equal(2)

	var t0 := Time.get_ticks_msec()
	stream.cancel()
	var cancel_call_ms := Time.get_ticks_msec() - t0
	assert_int(cancel_call_ms).is_less(100)
	assert_bool(stream.is_cancelled()).is_true()

	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("cancelled")
	assert_bool(fake.saw_cancel).is_true()
	assert_bool(stream.is_finished()).is_true()
	assert_bool(llm.is_busy()).is_false()
	assert_array(Array(spy["tokens"])).contains_exactly(["one", "two"])


func test_backend_error_after_partial_stream() -> void:
	var fake := FakeBackend.new()
	fake.chunks = PackedStringArray(["a", "b", "c"])
	fake.fail_after = 1
	fake.error = {"code": "http_error", "message": "connection reset"}
	var llm := _new_llm(fake)

	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	await _await_terminal(spy)

	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("http_error")
	assert_str(String(spy["payload"]["message"])).is_equal("connection reset")
	assert_array(Array(spy["tokens"])).contains_exactly(["a"])
	assert_bool(stream.is_finished()).is_true()
	assert_bool(stream.is_cancelled()).is_false()


func test_malformed_backend_result_fails() -> void:
	var fake := FakeBackend.new()
	# Backend returns garbage: the facade must still answer with failed().
	fake.raw_result = {"nope": 1}
	var llm := _new_llm(fake)
	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("malformed_result")


func test_busy_second_turn_fails() -> void:
	var fake := FakeBackend.new()
	fake.block_until_cancel = true
	var llm := _new_llm(fake)

	var first: TurnStream = llm.generate(_new_request())
	var first_spy := _spy(first)
	var second: TurnStream = llm.generate(_new_request())
	var second_spy := _spy(second)

	await _await_terminal(second_spy)
	assert_str(String(second_spy["terminal"])).is_equal("failed")
	assert_str(String(second_spy["payload"]["code"])).is_equal("busy")
	var deadline := Time.get_ticks_msec() + 2000
	while fake.calls < 1 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_int(fake.calls).is_equal(1)
	first.cancel()
	await _await_terminal(first_spy)
	assert_str(String(first_spy["terminal"])).is_equal("cancelled")


func test_no_backend_fails() -> void:
	var llm := _new_llm(null)
	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("no_backend")
	assert_bool(llm.is_busy()).is_false()


func test_invalid_request_fails() -> void:
	var llm := _new_llm(FakeBackend.new())
	var stream: TurnStream = llm.generate(null)
	var spy := _spy(stream)
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("invalid_request")


func test_set_dose_fills_empty_request_dose() -> void:
	var fake := FakeBackend.new()
	var llm := _new_llm(fake)
	llm.set_dose({"malice": 4.5, "possessive": 3.0})

	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	await _await_terminal(spy)
	assert_dict(fake.seen_request.dose).is_equal({"malice": 4.5, "possessive": 3.0})

	# An explicit per-request dose wins over the facade default.
	var request := _new_request()
	request.dose = {"malice": 9.0}
	stream = llm.generate(request)
	spy = _spy(stream)
	await _await_terminal(spy)
	assert_dict(fake.seen_request.dose).is_equal({"malice": 9.0})

	# Later set_dose() changes are frozen per request.
	request = _new_request()
	llm.set_dose({"malice": 1.0})
	stream = llm.generate(request)
	spy = _spy(stream)
	await _await_terminal(spy)
	assert_dict(fake.seen_request.dose).is_equal({"malice": 1.0})
	assert_dict(llm.get_dose()).is_equal({"malice": 1.0})


func test_generate_and_cancel_never_block_main() -> void:
	var fake := FakeBackend.new()
	fake.chunks = PackedStringArray(["early"])
	fake.block_until_cancel = true
	var llm := _new_llm(fake)

	var t0 := Time.get_ticks_msec()
	var stream: TurnStream = llm.generate(_new_request())
	var generate_ms := Time.get_ticks_msec() - t0
	assert_int(generate_ms).is_less(50).append_failure_message(
		"generate() blocked %d ms on a parked backend" % generate_ms
	)
	assert_bool(llm.is_busy()).is_true()

	var spy := _spy(stream)
	var deadline := Time.get_ticks_msec() + 5000
	while spy["tokens"].is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_array(Array(spy["tokens"])).contains_exactly(["early"])

	t0 = Time.get_ticks_msec()
	llm.cancel()
	var cancel_ms := Time.get_ticks_msec() - t0
	assert_int(cancel_ms).is_less(50).append_failure_message(
		"cancel() blocked %d ms on a parked backend" % cancel_ms
	)
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("cancelled")


func test_cancel_after_completed_is_noop() -> void:
	var fake := FakeBackend.new()
	fake.chunks = PackedStringArray(["done"])
	var llm := _new_llm(fake)

	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("completed")

	stream.cancel()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(stream.is_cancelled()).is_false()
	assert_str(String(spy["terminal"])).is_equal("completed")


func test_malformed_error_dictionary_normalizes() -> void:
	var fake := FakeBackend.new()
	var llm := _new_llm(fake)

	# 1. Empty error dictionary falls back to malformed_result.
	fake.raw_result = {"ok": false, "error": {}}
	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("malformed_result")

	# 2. Error dictionary with non-string code falls back to malformed_result.
	fake.raw_result = {"ok": false, "error": {"code": 500, "message": "server error"}}
	stream = llm.generate(_new_request())
	spy = _spy(stream)
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("malformed_result")

	# 3. Valid string code with missing message is normalized with empty string.
	fake.raw_result = {"ok": false, "error": {"code": "custom_error"}}
	stream = llm.generate(_new_request())
	spy = _spy(stream)
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("custom_error")
	assert_str(String(spy["payload"]["message"])).is_equal("")


func test_cancel_between_worker_return_and_terminal_delivery() -> void:
	var fake := FakeBackend.new()
	fake.chunks = PackedStringArray(["almost", " done"])
	var llm := _new_llm(fake)

	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)

	# Spin without processing main-thread frames until worker_main exits.
	var deadline := Time.get_ticks_msec() + 5000
	while llm._thread != null and llm._thread.is_alive() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
	assert_bool(llm._thread == null or not llm._thread.is_alive()).is_true()

	# Worker has returned and queued _deliver_terminal, but deferred call has not run.
	assert_bool(stream.is_finished()).is_false()
	stream.cancel()
	assert_bool(stream.is_cancelled()).is_true()

	# Flush frames and verify cancelled wins over completed.
	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("cancelled")
	assert_bool(stream.is_cancelled()).is_true()
	assert_bool(stream.is_finished()).is_true()
	assert_bool(llm.is_busy()).is_false()


func test_cancel_between_worker_return_and_terminal_delivery_on_error() -> void:
	var fake := FakeBackend.new()
	fake.raw_result = {
		"ok": false, "error": {"code": "upstream_timeout", "message": "gateway timeout"}
	}
	var llm := _new_llm(fake)

	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)

	var deadline := Time.get_ticks_msec() + 5000
	while llm._thread != null and llm._thread.is_alive() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
	assert_bool(llm._thread == null or not llm._thread.is_alive()).is_true()

	assert_bool(stream.is_finished()).is_false()
	stream.cancel()
	assert_bool(stream.is_cancelled()).is_true()

	await _await_terminal(spy)
	assert_str(String(spy["terminal"])).is_equal("cancelled")
	assert_bool(stream.is_cancelled()).is_true()
	assert_bool(stream.is_finished()).is_true()
	assert_bool(llm.is_busy()).is_false()


## P2.17 SAF-12: Boot asks the facade for the installed backend's launch config
## so the safety classifier never talks to a server that carries a control
## vector. A backend that publishes none says so with an empty dictionary — that
## is "unknown", not "dose 0". The getter returns a copy: a caller cannot edit the
## transport's live config by mutating it.
func test_backend_config_exposes_the_installed_transport_config() -> void:
	var llm := _new_llm(null)
	assert_bool(llm.get_backend_config().is_empty()).is_true()
	llm.set_backend(FakeBackend.new())
	assert_bool(llm.get_backend_config().is_empty()).is_true()
	var backend := LlamaServerBackend.new({"base_url": "http://127.0.0.1:9099"})
	llm.set_backend(backend)
	var config: Dictionary = llm.get_backend_config()
	assert_str(String(config.get("base_url", ""))).is_equal("http://127.0.0.1:9099")
	config["base_url"] = "http://elsewhere"
	assert_str(String(backend.config.get("base_url", ""))).is_equal("http://127.0.0.1:9099")
