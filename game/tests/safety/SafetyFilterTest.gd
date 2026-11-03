extends GdUnitTestSuite
## P1.19 — Safety filter v0 unit tests (docs/02 §8).
## The corpus-level sweep (0 misses / <=5% FP / stream equivalence) lives in
## game/tests/test_safety_corpus.gd; this suite covers mechanics per category.

const FULL4 := {"stage": 4, "content_level": "full"}
const CALM4 := {"stage": 4, "content_level": "calmer"}
const STAGE0 := {"stage": 0, "content_level": "full"}


func _filter() -> SafetyFilter:
	var f := SafetyFilter.new()
	auto_free(f)
	assert_bool(f.reload()).is_true()
	return f


func _stream(f: SafetyFilter, text: String, ctx: Dictionary = STAGE0) -> String:
	## Each call is one model utterance: mark the boundary so the cross-beat
	## carry (CODE-2/CODE-14) never glues two unrelated test lines together.
	f.end_utterance()
	f.begin_say(ctx)
	var out := ""
	for i in text.length():
		out += f.say_chunk(text.substr(i, 1))
	out += f.end_say()
	return out


func test_hard_block_categories() -> void:
	var f := _filter()
	assert_bool(f.is_ready()).is_true()
	## Hard blocks hold at stage 0 and at an open gate (stage 4 + full).
	for ctx in [STAGE0, FULL4]:
		for sample in [
			["you should kill yourself.", "harm_to_player"],
			["you stupid cunt.", "slur_hate"],
			["let's make love.", "sexual"],
			["i know where you live, senpai.", "personal_data"],
		]:
			var res: Dictionary = f.filter_text(sample[0], ctx)
			assert_bool(res["redacted"]).is_true().append_failure_message(
				"not redacted: " + sample[0]
			)
			assert_bool(Array(res["categories"]).has(sample[1])).is_true()


func test_gated_categories_closed_below_stage4() -> void:
	var f := _filter()
	for stage in [0, 1, 2, 3]:
		var ctx := {"stage": stage, "content_level": "full"}
		for line in ["i want to die.", "i'll kill you."]:
			assert_bool(f.filter_text(line, ctx)["redacted"]).is_true()


func test_gated_categories_open_at_stage4_full() -> void:
	var f := _filter()
	for line in ["i want to die.", "i'll kill you."]:
		var res: Dictionary = f.filter_text(line, FULL4)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)
		assert_str(res["text"]).is_equal(line)


func test_gated_categories_closed_on_lower_level() -> void:
	var f := _filter()
	assert_bool(f.filter_text("i want to die.", CALM4)["redacted"]).is_true()
	assert_bool(f.filter_text("i'll kill you.", CALM4)["redacted"]).is_true()


func test_redaction_bars_replace_the_phrase() -> void:
	var f := _filter()
	var res: Dictionary = f.filter_text("senpai, you should kill yourself.", STAGE0)
	var out: String = res["text"]
	assert_bool(out.contains(SafetyFilter.REDACT_CHAR)).is_true()
	assert_bool(not out.contains("kill yourself")).is_true()
	assert_bool(out.begins_with("senpai, ")).is_true()


func test_negation_guard_passes() -> void:
	var f := _filter()
	for line in [
		"i'll never hurt you.",
		"don't hurt yourself on my account.",
		"i'm not going to kill you, silly.",
		"no way i'd hurt you.",
	]:
		assert_bool(f.filter_text(line, STAGE0)["redacted"]).is_false().append_failure_message(line)


func test_negation_guard_resets_at_clause_break() -> void:
	var f := _filter()
	## "don't" negates "touch", not "hurt" — the threat must still redact.
	assert_bool(f.filter_text("don't touch me, or i'll hurt you.", STAGE0)["redacted"]).is_true()


func test_stream_midword_split_cannot_leak() -> void:
	var f := _filter()
	var streamed := _stream(f, "don't touch me, or i'll hurt you.")
	var oneshot: String = f.filter_text("don't touch me, or i'll hurt you.", STAGE0)["text"]
	assert_str(streamed).is_equal(oneshot)
	assert_bool(not streamed.contains("hurt you")).is_true()


func test_stream_equivalence_char_by_char() -> void:
	var f := _filter()
	for line in [
		"i'll never let you go.",
		"i want you to die.",
		"call me at 555-0134-5678 after dark.",
		"let's make love.",
		"i was watching the whole time.",
	]:
		var streamed := _stream(f, line)
		var oneshot: String = f.filter_text(line, STAGE0)["text"]
		assert_str(streamed).is_equal(oneshot).append_failure_message(line)


func test_stream_holds_partial_word() -> void:
	var f := _filter()
	f.begin_say(STAGE0)
	var first := f.say_chunk("don't touch me, or i'll hurt ")
	assert_bool(not first.contains("hurt")).is_true()
	var second := f.say_chunk("you")
	var third := f.end_say()
	assert_bool(not (first + second + third).contains("hurt you")).is_true()
	assert_bool((first + second + third).contains(SafetyFilter.REDACT_CHAR)).is_true()


func test_stream_slur_split_inside_word() -> void:
	var f := _filter()
	var streamed := _stream(f, "you're a nigger to me")
	assert_bool(not streamed.contains("nigger")).is_true()
	assert_bool(streamed.contains(SafetyFilter.REDACT_CHAR)).is_true()


func test_stream_zero_width_cannot_obfuscate() -> void:
	var f := _filter()
	## Zero-width space with and without surrounding real spaces; the first
	## must collapse to "kill you", the second must not join into "killyou".
	for line in ["kill ​you now", "kill​you now"]:
		var streamed := _stream(f, line)
		assert_bool(streamed.contains(SafetyFilter.REDACT_CHAR)).is_true()
		assert_bool(not streamed.contains("kill")).is_true()


func test_filter_text_does_not_reset_stream_context() -> void:
	var f := _filter()
	f.begin_say({"stage": 4, "content_level": "full"})
	f.say_chunk("i want to ")
	var res: Dictionary = f.filter_text("i want to die.", STAGE0)
	assert_bool(res["redacted"]).is_true()
	var tail := f.say_chunk("die.")
	var out := tail + f.end_say()
	assert_str(out).is_equal("i want to die.")


func test_personal_data_regexes() -> void:
	var f := _filter()
	for line in [
		"mail me at a@b.co",
		"call 555-0134-5678",
		"ssn 123-45-6789 ok",
		"ip 10.20.30.40 logged",
		"i live at 8 oak lane",
	]:
		assert_bool(f.filter_text(line, STAGE0)["redacted"]).is_true().append_failure_message(line)


func test_player_typed_data_exempt() -> void:
	var f := _filter()
	var ctx := {"stage": 0, "player_terms": ["mika@example.com"]}
	var res: Dictionary = f.filter_text("write to me at mika@example.com", ctx)
	assert_bool(res["redacted"]).is_false()


func test_signal_and_log_on_redaction() -> void:
	var f := _filter()
	var got: Array = []
	f.redacted.connect(func(cat, _matched, _src): got.append(cat))
	f.filter_text("you should kill yourself.", STAGE0)
	assert_bool(got.has("harm_to_player")).is_true()
	assert_int(f.redaction_log.size()).is_greater_equal(1)
	assert_str(String(f.redaction_log[-1]["matched"])).contains("kill yourself")


func test_fail_closed_when_lists_missing() -> void:
	var f := SafetyFilter.new()
	auto_free(f)
	assert_bool(f.reload("res://data/safety/does_not_exist.json")).is_false()
	assert_bool(f.is_ready()).is_false()
	var res: Dictionary = f.filter_text("hello senpai", STAGE0)
	assert_bool(res["redacted"]).is_true()
	f.begin_say(STAGE0)
	assert_str(f.say_chunk("hello")).is_equal("")
	assert_str(f.end_say()).is_equal(SafetyFilter.FALLBACK_BARS)


func test_filter_text_covers_inner_and_letters() -> void:
	var f := _filter()
	## Same entry point used for leaked inner, letters, diary entries, titles.
	for line in ["inner voice: let's kill you.", "dear diary, i want to die."]:
		assert_bool(f.filter_text(line, STAGE0)["redacted"]).is_true().append_failure_message(line)


func test_stream_benign_passthrough_untouched() -> void:
	var f := _filter()
	var line := "i-i can't believe you asked me that!"
	assert_str(_stream(f, line)).is_equal(line)
