extends GdUnitTestSuite
## P2.17 — classifier tier of the output filter (docs/02 §8): the yes/no pass
## over regex-flagged beats, content-level gating, the streaming hold and the
## fail-closed policy. The transport is the scripted FakeClassifierBackend, so
## every case is deterministic; the corpus runner covers volume with an oracle
## backend, and SafetyClassifierHttp is exercised by the live prompt lab.

const Helpers := preload("res://tests/helpers/FakeClassifierBackend.gd")
const STAGE0 := {"stage": 0, "content_level": "full"}
const FULL4 := {"stage": 4, "content_level": "full"}
const CALM4 := {"stage": 4, "content_level": "calmer"}
const FULL3 := {"stage": 3, "content_level": "full"}

const BENIGN_FLAG := "i can't go on pretending like this."
const HARM_FLAG := "you should disappear."
const SELF_FLAG := "i want to be dead."


func _filter(backend: Object = null) -> SafetyFilter:
	var f := SafetyFilter.new()
	auto_free(f)
	assert_bool(f.reload()).is_true().append_failure_message("classifier tier failed to load")
	if backend != null:
		f.classifier_gate.set_backend(backend)
	return f


func _fake(verdict := "") -> Object:
	var fake: Object = Helpers.new()
	if not verdict.is_empty():
		fake.set("forced_verdict", verdict)
	return fake


func test_classifier_data_loads_with_flags_and_probes() -> void:
	var f := _filter()
	var gate: Object = f.classifier_gate
	assert_object(gate).is_not_null()
	assert_bool(gate.get("classifier").is_ready()).is_true()
	assert_array(gate.get("classifier").categories()).contains_exactly_in_any_order(
		["self_harm_her", "harm_to_player", "threat_to_player"]
	)


func test_flagged_benign_line_passes_and_spends_one_request() -> void:
	var fake := _fake("no")
	var f := _filter(fake)
	var res: Dictionary = f.filter_text(BENIGN_FLAG, STAGE0)
	assert_bool(res["redacted"]).is_false()
	assert_str(String(res["text"])).is_equal(BENIGN_FLAG)
	assert_int(int(fake.get("requests").size())).is_equal(1)
	var req: Dictionary = fake.call("last_request")
	assert_int(int(req["max_tokens"])).is_equal(8)
	assert_bool((req["dose"] as Dictionary).is_empty()).is_true()
	assert_str(String(req["category"])).is_equal("self_harm_her")
	assert_bool(String(req["question"]).contains("yes or no")).is_true()


func test_flagged_harmful_line_blocks() -> void:
	var fake := _fake("yes")
	var f := _filter(fake)
	var res: Dictionary = f.filter_text(HARM_FLAG, STAGE0)
	assert_bool(res["redacted"]).is_true()
	assert_bool(Array(res["categories"]).has("harm_to_player")).is_true()
	var out := String(res["text"])
	assert_bool(out.contains(SafetyFilter.REDACT_CHAR)).is_true()
	assert_bool(out.contains("disappear")).is_false()


func test_no_backend_fails_closed() -> void:
	var f := _filter()
	assert_bool(f.filter_text(HARM_FLAG, STAGE0)["redacted"]).is_true()


func test_transport_error_fails_closed() -> void:
	var fake := Helpers.new()
	fake.set("error_code", "read_timeout")
	var f := _filter(fake)
	assert_bool(f.filter_text(HARM_FLAG, STAGE0)["redacted"]).is_true()


func test_unparseable_answer_fails_closed() -> void:
	var fake := Helpers.new()
	fake.set("raw_override", "maybe")
	var f := _filter(fake)
	assert_bool(f.filter_text(BENIGN_FLAG, STAGE0)["redacted"]).is_true()


func test_self_harm_flag_only_blocks_below_the_full_gate() -> void:
	var fake := _fake("yes")
	var f := _filter(fake)
	for ctx: Dictionary in [STAGE0, FULL3, CALM4]:
		assert_bool(f.filter_text(SELF_FLAG, ctx)["redacted"]).is_true().append_failure_message(
			"self-harm flag must block at stage %d / %s" % [ctx["stage"], ctx["content_level"]]
		)
	assert_bool(f.filter_text(SELF_FLAG, FULL4)["redacted"]).is_false().append_failure_message(
		"stage 4 + full must allow the fictional line"
	)


func test_hard_category_is_never_gated() -> void:
	var fake := _fake("yes")
	var f := _filter(fake)
	assert_bool(f.filter_text(HARM_FLAG, FULL4)["redacted"]).is_true()


func test_streamed_flag_holds_the_tail_until_the_verdict() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	var seen: Array = []
	f.hold_released.connect(func(beat: int, text: String) -> void: seen.append([beat, text]))
	f.begin_say({"stage": 0, "beat_index": 2})
	## A short beat sits behind the 34-char compact holdback until its close, so
	## the prefix lands in end_say and only the flagged tail stays held.
	assert_str(f.say_chunk("i can't go on")).is_equal("")
	assert_int(int(fake.call("pending_count"))).is_equal(0)
	assert_str(f.end_say()).is_equal("i ")
	assert_bool(f.classifier_gate.hold_active()).is_true()
	assert_int(int(fake.call("pending_count"))).is_equal(1)
	fake.call("deliver", "no")
	assert_int(seen.size()).is_equal(1)
	assert_int(int(seen[0][0])).is_equal(2)
	assert_str(String(seen[0][1])).is_equal("can't go on")


func test_streamed_yes_verdict_bars_the_held_tail() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	var seen: Array = []
	f.hold_released.connect(func(beat: int, text: String) -> void: seen.append([beat, text]))
	f.begin_say({"stage": 0, "beat_index": 0})
	f.say_chunk("you should disappear.")
	f.end_say()
	fake.call("deliver", "yes")
	assert_int(seen.size()).is_equal(1)
	var tail := String(seen[0][1])
	assert_bool(tail.contains(SafetyFilter.REDACT_CHAR)).is_true()
	assert_bool(tail.contains("disappear")).is_false()


func test_beat_boundary_fails_closed_and_late_verdict_is_cached() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	var seen: Array = []
	f.hold_released.connect(func(beat: int, text: String) -> void: seen.append([beat, text]))
	f.begin_say({"stage": 0, "beat_index": 0})
	f.say_chunk("i can't go on")
	f.end_say()
	f.begin_say({"stage": 0, "beat_index": 1})
	assert_int(seen.size()).is_equal(1)
	assert_bool(String(seen[0][1]).contains(SafetyFilter.REDACT_CHAR)).is_true()
	fake.call("deliver", "no")
	var gate: Object = f.classifier_gate
	assert_int(int(gate.get("classifier").get("verdict_log").size())).is_greater_equal(1)


func test_verdict_cache_avoids_a_second_request() -> void:
	var fake := _fake("no")
	var f := _filter(fake)
	f.filter_text(BENIGN_FLAG, STAGE0)
	f.filter_text(BENIGN_FLAG, STAGE0)
	assert_int(int(fake.get("requests").size())).is_equal(1)
	assert_int(int(f.classifier_gate.get("classifier").get("cached_hits"))).is_equal(1)


func test_async_verdict_is_cached_for_the_next_display() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	fake.set("forced_verdict", "no")
	var f := _filter(fake)
	assert_bool(f.filter_text(BENIGN_FLAG, STAGE0)["redacted"]).is_true()
	fake.call("deliver", "no")
	var second: Dictionary = f.filter_text(BENIGN_FLAG, STAGE0)
	assert_bool(second["redacted"]).is_false()
	assert_str(String(second["text"])).is_equal(BENIGN_FLAG)


func test_redaction_log_marks_the_classifier_source() -> void:
	var fake := _fake("yes")
	var f := _filter(fake)
	f.filter_text(HARM_FLAG, STAGE0)
	var entry: Dictionary = f.redaction_log[-1]
	assert_str(String(entry["category"])).is_equal("harm_to_player")
	assert_str(String(entry["via"])).is_equal("classifier")


func test_negated_flag_spends_no_request() -> void:
	var fake := _fake("yes")
	var f := _filter(fake)
	var res: Dictionary = f.filter_text("i'm not tired of being alive.", STAGE0)
	assert_bool(res["redacted"]).is_false()
	assert_int(int(fake.get("requests").size())).is_equal(0)


func test_flag_split_across_chunks_is_still_caught() -> void:
	var fake := _fake("yes")
	var f := _filter(fake)
	f.begin_say({"stage": 0, "beat_index": 0})
	var out := ""
	var line := "you should disappear."
	for i in line.length():
		out += f.say_chunk(line.substr(i, 1))
	out += f.end_say()
	assert_bool(out.contains(SafetyFilter.REDACT_CHAR)).is_true()
	assert_bool(out.contains("disappear")).is_false()


func test_expired_hold_fails_closed_on_the_next_chunk() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	f.classifier_gate.classifier.set("_hold_timeout_ms", 1)
	var seen: Array = []
	f.hold_released.connect(func(beat: int, text: String) -> void: seen.append([beat, text]))
	f.begin_say({"stage": 0, "beat_index": 4})
	f.say_chunk("i can't go on")
	OS.delay_msec(3)
	assert_str(f.say_chunk(" and on")).is_equal("")
	assert_int(seen.size()).is_equal(1)
	assert_int(int(seen[0][0])).is_equal(4)
	assert_bool(String(seen[0][1]).contains(SafetyFilter.REDACT_CHAR)).is_true()
	assert_int(int(f.classifier_gate.call("stats")["timeout_count"])).is_equal(1)


func test_classifier_stats_report_latency_and_verdicts() -> void:
	var fake := _fake("no")
	fake.set("latency_ms", 42)
	var f := _filter(fake)
	f.filter_text(BENIGN_FLAG, STAGE0)
	var stats: Dictionary = f.classifier_gate.call("stats")
	assert_int(int(stats["requests"])).is_equal(1)
	assert_int(int(stats["ms_max"])).is_equal(42)
	assert_int(int(stats["passes"])).is_equal(1)
	assert_int(int(stats["errors"])).is_equal(0)
