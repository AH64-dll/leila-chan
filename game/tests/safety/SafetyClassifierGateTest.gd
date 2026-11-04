extends GdUnitTestSuite
## P2.17 round 2 — the regressions the round-1 reviews found, kept in their own
## suite because gdlint caps a class at 20 public methods (DirectorTest /
## DirectorRoutingTest precedent):
##  * CODE-1/SAF-2: the verdict cache stores a verdict, never a gate-dependent
##    permission, so a "yes" answered during a stage-4/full turn still bars at
##    stage 0 and in calmer mode;
##  * CODE-2: one streamed span costs one request, however many chunks it takes;
##  * CODE-3: a mid-beat hold timeout keeps the beat's stage and beat index;
##  * SAF-6/SAF-11: the window floor is enforced at load and the cutlery
##    look-alike keeps two keys in both orders;
##  * SAF-5: a classifier block logs the verdict that caused it.

const Helpers := preload("res://tests/helpers/FakeClassifierBackend.gd")
const STAGE0 := {"stage": 0, "content_level": "full"}
const FULL4 := {"stage": 4, "content_level": "full"}
const CALM4 := {"stage": 4, "content_level": "calmer"}
const FULL3 := {"stage": 3, "content_level": "full"}

const HARM_FLAG := "you should disappear."


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
