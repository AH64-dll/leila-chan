extends GdUnitTestSuite
## P2.17 round 2/3 — the regressions the reviews found, kept in their own suite
## because gdlint caps a class at 20 public methods (DirectorTest /
## DirectorRoutingTest precedent):
##  * CODE-1/SAF-2: the verdict cache stores a verdict, never a gate-dependent
##    permission, so a "yes" answered during a stage-4/full turn still bars at
##    stage 0 and in calmer mode;
##  * CODE-2: one streamed span costs one request, however many chunks it takes;
##  * CODE-3: a mid-beat hold timeout keeps the beat's stage and beat index;
##  * SAF-6/SAF-11: the window floor is enforced at load and the cutlery
##    look-alike keeps two keys in both orders;
##  * SAF-5: a classifier block logs the verdict that caused it;
##  * CODE-8/SAF-13 (round 3): the whole-text guard is the transport's bound, and
##    a refusal is never cached as the clause's verdict;
##  * SAF-12 (round 3): a steered server is refused, live, at ask time.

const Helpers := preload("res://tests/helpers/FakeClassifierBackend.gd")
const STAGE0 := {"stage": 0, "content_level": "full"}
const FULL4 := {"stage": 4, "content_level": "full"}
const CALM4 := {"stage": 4, "content_level": "calmer"}
const FULL3 := {"stage": 3, "content_level": "full"}

const HARM_FLAG := "you should disappear."
const BENIGN_FLAG := "i can't go on pretending like this."


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


## CODE-1/SAF-2: a "yes" answered while the gate happened to be open is a
## verdict, never a permission. The same clause must bar again below the gate
## without a second request.
func test_cached_yes_still_bars_after_the_gate_closes() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	## Asked at stage 3 (gate closed) ...
	f.begin_say({"stage": 3, "content_level": "full", "beat_index": 0})
	f.say_chunk("i can't go on")
	f.end_say()
	assert_int(int(fake.call("pending_count"))).is_equal(1)
	## ... and answered while the live beat sits at stage 4 + full.
	f.begin_say({"stage": 4, "content_level": "full", "beat_index": 1})
	fake.call("deliver", "yes")
	var gate: Object = f.classifier_gate
	var cached: Dictionary = gate.get("classifier").call("cached", "self_harm_her|i can't go on")
	assert_str(String(cached.get("verdict", ""))).is_equal("yes")
	assert_bool(cached.has("block")).is_false().append_failure_message(
		"the cache must store the verdict, not a gate-dependent permission"
	)
	for ctx: Dictionary in [STAGE0, FULL3, CALM4]:
		var res: Dictionary = f.filter_text("i can't go on", ctx)
		assert_bool(res["redacted"]).is_true().append_failure_message(
			"cached yes must bar at stage %d / %s" % [ctx["stage"], ctx["content_level"]]
		)
	assert_bool(f.filter_text("i can't go on", FULL4)["redacted"]).is_false()
	assert_int(int(fake.get("requests").size())).is_equal(1)


## CODE-2: one streamed span is one question. The key is the clause window, and
## the window stops growing at the clause break, so later chunks of the same
## beat must not mint a new key (and a new request).
func test_one_streamed_span_spends_one_request_across_chunks() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	var seen: Array = []
	f.hold_released.connect(func(beat: int, text: String) -> void: seen.append([beat, text]))
	f.begin_say({"stage": 0, "beat_index": 3})
	f.say_chunk("you should disappear.")
	assert_int(int(fake.get("requests").size())).is_equal(1)
	f.say_chunk(" i promise.")
	f.say_chunk(" and more.")
	f.end_say()
	assert_int(int(fake.get("requests").size())).is_equal(1).append_failure_message(
		"the same span must not be asked once per chunk"
	)
	fake.call("deliver", "no")
	assert_int(seen.size()).is_equal(1)
	assert_int(int(seen[0][0])).is_equal(3)
	assert_str(String(seen[0][1])).is_equal("you should disappear. i promise. and more.")


## CODE-3: a mid-beat hold timeout must not throw the beat context away. After
## the bars go out, a gated tier-1 line later in the same beat still resolves at
## the beat's own stage (4 + full allows it); before the fix the rest of the beat
## was rescanned at stage 0 and barred.
func test_hold_timeout_keeps_the_beat_stage() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	f.classifier_gate.classifier.set("_hold_timeout_ms", 1)
	f.begin_say({"stage": 4, "content_level": "full", "beat_index": 7})
	f.say_chunk("you should disappear.")
	OS.delay_msec(3)
	f.say_chunk(" i promise.")
	assert_int(int(f.classifier_gate.call("stats")["timeout_count"])).is_equal(1)
	var out := f.say_chunk(" i want to die.")
	out += f.end_say()
	assert_bool(out.contains("die")).is_true().append_failure_message(
		"stage 4 + full must still allow a gated line after a mid-beat timeout"
	)
	assert_bool(out.contains(SafetyFilter.REDACT_CHAR)).is_false()


## CODE-3, second consequence: a hold created after the timeout still carries the
## real beat index, so its release reaches that beat instead of beat -1.
func test_hold_timeout_keeps_the_beat_index() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	f.classifier_gate.classifier.set("_hold_timeout_ms", 1)
	var seen: Array = []
	f.hold_released.connect(func(beat: int, text: String) -> void: seen.append([beat, text]))
	f.begin_say({"stage": 0, "beat_index": 7})
	f.say_chunk("i can't go on")
	OS.delay_msec(3)
	f.say_chunk(" and on")
	fake.call("deliver", "no")
	f.say_chunk(" you should disappear.")
	f.end_say()
	fake.call("deliver", "yes")
	assert_int(seen.size()).is_equal(2)
	assert_int(int(seen[1][0])).is_equal(7).append_failure_message(
		"the release must carry the beat's index, not -1"
	)
	assert_bool(String(seen[1][1]).contains(SafetyFilter.REDACT_CHAR)).is_true()


## SAF-11: a window below the floor collapses the key to the matched span, which
## is exactly the knife / knife-and-fork collision the key exists to prevent.
func test_context_chars_below_the_floor_fails_the_load() -> void:
	var text := FileAccess.get_file_as_string("res://data/safety/classifier.json")
	var data: Variant = JSON.parse_string(text)
	assert_bool(data is Dictionary).is_true()
	(data as Dictionary)["context_chars"] = 8
	var path := "user://classifier_context_floor.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var cls := SafetyClassifier.new()
	assert_bool(cls.load_data(path)).is_false()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## SAF-6: the window key must distinguish the cutlery look-alike in both orders,
## so a cached "no" for one sentence can never release the other.
func test_cutlery_lookalike_keeps_two_keys_in_both_orders() -> void:
	var pairs := [
		["i know how to use a knife.", "i know how to use a knife and fork."],
		["i know how to use a knife and fork.", "i know how to use a knife."],
	]
	for pair: Array in pairs:
		var fake := _fake("no")
		var f := _filter(fake)
		f.filter_text(String(pair[0]), STAGE0)
		f.filter_text(String(pair[1]), STAGE0)
		assert_int(int(fake.get("requests").size())).is_equal(2).append_failure_message(
			"two different sentences must not share one verdict: %s" % [pair]
		)


## SAF-5: a classifier block must log the verdict that caused it, not just the
## source, or the tuning trail loses its reason.
func test_classifier_block_logs_its_verdict() -> void:
	var fake := _fake("yes")
	var f := _filter(fake)
	f.filter_text(HARM_FLAG, STAGE0)
	var entry: Dictionary = f.redaction_log[-1]
	assert_str(String(entry["via"])).is_equal("classifier")
	assert_str(String(entry.get("verdict", ""))).is_equal("yes")


## CODE-8: the whole-text guard is the transport's bound, not the 900 ms UI hold.
## A healthy answer that lands after the hold deadline must still reach the cache,
## or every later display re-asks the clause and a flag false positive stays
## barred forever (SAF-13).
func test_late_whole_text_answer_still_reaches_the_cache() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	assert_bool(f.filter_text(BENIGN_FLAG, STAGE0)["redacted"]).is_true()
	assert_int(int(fake.call("pending_count"))).is_equal(1)
	var key := String(fake.call("last_request").get("key", ""))
	## The UI hold deadline lapses while the transport is still within its bound.
	f.classifier_gate.classifier.set("_hold_timeout_ms", 1)
	OS.delay_msec(3)
	f.say_chunk("hello")
	assert_int(int(f.classifier_gate.call("stats")["quiet_in_flight"])).is_equal(1)
	fake.call("deliver", "no")
	assert_bool(f.classifier_gate.classifier.has_cached(key)).is_true().append_failure_message(
		"a healthy answer must be cached however long the decode took"
	)
	var second: Dictionary = f.filter_text(BENIGN_FLAG, STAGE0)
	assert_bool(second["redacted"]).is_false()
	assert_int(int(fake.get("requests").size())).is_equal(1)


## SAF-8 must survive the new deadline: a hung whole-text request still frees its
## slot, and its late answer is dropped rather than cached.
func test_hung_quiet_request_still_frees_its_slot() -> void:
	var fake := Helpers.new()
	fake.set("defer", true)
	var f := _filter(fake)
	f.classifier_gate.classifier.set("_quiet_timeout_ms", 1)
	assert_bool(f.filter_text(BENIGN_FLAG, STAGE0)["redacted"]).is_true()
	var key := String(fake.call("last_request").get("key", ""))
	OS.delay_msec(3)
	f.say_chunk("hello")
	assert_int(int(f.classifier_gate.call("stats")["quiet_in_flight"])).is_equal(0)
	fake.call("deliver", "no")
	assert_bool(f.classifier_gate.classifier.has_cached(key)).is_false()


## SAF-13: a refusal bars that display but is never the clause's verdict, so a
## transient transport failure does not turn a flagged line into a bar for the
## rest of the run.
func test_transport_error_is_not_cached_and_the_line_heals() -> void:
	var fake := Helpers.new()
	fake.set("error_code", "read_timeout")
	var f := _filter(fake)
	assert_bool(f.filter_text(HARM_FLAG, STAGE0)["redacted"]).is_true()
	var key := String(fake.call("last_request").get("key", ""))
	assert_bool(f.classifier_gate.classifier.has_cached(key)).is_false().append_failure_message(
		"an error is not the clause's verdict"
	)
	assert_int(int(f.classifier_gate.call("stats")["errors"])).is_equal(1)
	## The server answers on the next display: the same clause is asked again.
	fake.set("error_code", "")
	fake.set("forced_verdict", "no")
	assert_bool(f.filter_text(HARM_FLAG, STAGE0)["redacted"]).is_false()
	assert_int(int(fake.get("requests").size())).is_equal(2)


## SAF-12: the gate refuses to ask a steered server even with a transport bound,
## because a steered "no" would release the span (docs/02 §8 is dose 0). The
## config is read live, so binding a vector after boot disables the tier.
func test_steered_backend_refuses_to_ask() -> void:
	var fake := _fake("no")
	var f := _filter(fake)
	var config := {"control_vectors": [{"path": "evil_qwen_unit.gguf", "scale": 4}]}
	f.classifier_gate.set_config_provider(func() -> Dictionary: return config)
	assert_bool(f.filter_text(HARM_FLAG, STAGE0)["redacted"]).is_true()
	assert_int(int(fake.get("requests").size())).is_equal(0)
	assert_bool(bool(f.classifier_gate.call("stats")["backend_steered"])).is_true()
	## An unsteered config brings the tier back without a restart.
	config["control_vectors"] = []
	assert_bool(f.filter_text(HARM_FLAG, STAGE0)["redacted"]).is_false()
	assert_int(int(fake.get("requests").size())).is_equal(1)


## The rule behind the refusal: any bound vector — configured or a launch flag —
## disqualifies a server, because llama-server has no per-request dose.
func test_steered_config_rule_reads_vectors_and_launch_flags() -> void:
	assert_bool(SafetyClassifierGate.is_steered_config({})).is_false()
	(
		assert_bool(
			SafetyClassifierGate.is_steered_config({"control_vectors": [{"path": "v.gguf"}]})
		)
		. is_true()
	)
	(
		assert_bool(
			SafetyClassifierGate.is_steered_config(
				{"extra_args": PackedStringArray(["--control-vector-scaled", "v.gguf:4"])}
			)
		)
		. is_true()
	)
	assert_bool(SafetyClassifierGate.is_steered_config({"control_vectors": []})).is_false()


## CODE-3/DES-3b: `auto_start` alone does not vouch for the server. With
## `LEILA_OWN_SERVER=1` Boot requests an app-launched server, but a healthy one
## already on the port is adopted and its launch flags are invisible — the tier
## must fail closed instead of letting a dosed model answer (docs/02 §8, SAF-3).
func test_an_adopted_auto_start_server_keeps_the_tier_off() -> void:
	var fake := _fake("no")
	var f := _filter(fake)
	var config := {"auto_start": true, "server_owned": false, "control_vectors": []}
	f.classifier_gate.set_config_provider(func() -> Dictionary: return config)
	assert_bool(f.filter_text(HARM_FLAG, STAGE0)["redacted"]).is_true()
	assert_int(int(fake.get("requests").size())).is_equal(0)
	assert_bool(bool(f.classifier_gate.call("stats")["backend_steered"])).is_true()
	## Once the app owns the process and carries no vector, the same live config
	## brings the tier back without a restart.
	config["server_owned"] = true
	assert_bool(f.filter_text(HARM_FLAG, STAGE0)["redacted"]).is_false()
	assert_int(int(fake.get("requests").size())).is_equal(1)


## CODE-8: a guard shorter than the transport's own read bound would forget a
## healthy answer before it lands, so the loader refuses it.
func test_quiet_timeout_below_the_transport_floor_fails_the_load() -> void:
	var text := FileAccess.get_file_as_string("res://data/safety/classifier.json")
	var data: Variant = JSON.parse_string(text)
	assert_bool(data is Dictionary).is_true()
	(data as Dictionary)["quiet_timeout_ms"] = 900
	var path := "user://classifier_quiet_floor.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var cls := SafetyClassifier.new()
	assert_bool(cls.load_data(path)).is_false()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The shipped guard must outlive the transport's read bound (CODE-8).
func test_shipped_quiet_timeout_outlives_the_transport_read_bound() -> void:
	var cls := SafetyClassifier.new()
	assert_bool(cls.load_data("res://data/safety/classifier.json")).is_true()
	assert_int(cls.quiet_timeout_ms()).is_greater_equal(
		SafetyClassifierHttp.DEFAULT_READ_TIMEOUT_MS
	)


## SAF-13 on the streaming path: a failed ask bars the beat's span, and the drain
## the settle re-enters must not ask the same clause again. The marker cannot be
## the window key: once the barred text is in the display window the clause is
## re-detected at a new offset with a new key, so a key-scoped marker stopped
## matching and one error cost eight requests inside a single beat.
func test_refused_ask_is_asked_once_per_beat() -> void:
	var fake := Helpers.new()
	fake.set("error_code", "read_timeout")
	var f := _filter(fake)
	f.begin_say({"stage": 0, "beat_index": 0})
	var out := f.say_chunk(HARM_FLAG)
	out += f.end_say()
	assert_bool(out.contains(SafetyFilter.REDACT_CHAR)).is_true()
	assert_int(int(fake.get("requests").size())).is_equal(1).append_failure_message(
		"one failed ask per clause per beat, not one per drain"
	)
	assert_int(int(f.classifier_gate.call("stats")["refused"])).is_equal(1)
	## The refusal lapses with the beat: the next beat asks again.
	f.begin_say({"stage": 0, "beat_index": 1})
	f.say_chunk(HARM_FLAG)
	f.end_say()
	assert_int(int(fake.get("requests").size())).is_equal(2)
	(
		assert_bool(f.classifier_gate.classifier.has_cached("harm_to_player|you should disappear"))
		. is_false()
	)
