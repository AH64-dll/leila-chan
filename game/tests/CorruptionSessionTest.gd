extends GdUnitTestSuite
## P2.06 — the streaming side of the docs/07 §3.4 corruption filter.
##
## The typewriter consumes `say_chunk` events live, so the filter works on
## complete words and holds the trailing partial word back. These tests pin the
## promises that make that safe:
##   - chunk boundaries never change the result (one chunk, one character at a
##     time and every step in between produce the same text);
##   - the held-back word and the stage-5 echoes land on `flush()`, exactly
##     once;
##   - `transform_beat()` (the docs/02 §7 repair path) equals a live stream;
##   - the per-beat plan is the purity contract's (`Corruption.plan`).

const SLASH := "\u0338"
const UNDER := "\u0332"
const SAMPLE := (
	"I hate the way you look at me. I don't know what I want to remember, "
	+ "but I'm fine. Stay with me, okay?"
)


func _session(stage: int, seed_base := 0, extra := {}) -> CorruptionSession:
	var session := CorruptionSession.new()
	var config := {
		"turn": 1,
		"stage": stage,
		"player_name": "Senpai",
		"seed_base": seed_base,
	}
	config.merge(extra, true)
	session.begin_turn(config)
	return session


## Stream `text` into `session` in fixed-size chunks and return everything the
## adapter emitted, flush included.
func _stream(session: CorruptionSession, beat: int, text: String, size: int) -> String:
	session.begin_beat(beat)
	var out := ""
	var at := 0
	while at < text.length():
		var step := maxi(1, size)
		out += session.push(beat, text.substr(at, step))
		at += step
	out += session.flush(beat)
	return out


func test_chunk_boundaries_do_not_change_the_output() -> void:
	for stage: int in range(1, 6):
		for seed_base: int in range(0, 4):
			var expected := _session(stage, seed_base).transform_beat(0, SAMPLE)
			for size: int in [1, 3, 7, 16]:
				var streamed := _stream(_session(stage, seed_base), 0, SAMPLE, size)
				(
					assert_str(streamed)
					. override_failure_message(
						"stage %d seed %d chunk size %d" % [stage, seed_base, size]
					)
					. is_equal(expected)
				)


func test_trailing_partial_word_is_flushed() -> void:
	var session := _session(0)
	session.begin_beat(0)
	# Stage 0 so the assertion is about the buffering, not the effects.
	assert_str(session.push(0, "hello world")).is_equal("hello ")
	assert_str(session.flush(0)).is_equal("world")
	# The word boundary is the release point: nothing is duplicated or lost.
	assert_str(_stream(_session(0), 0, "hello world", 1)).is_equal("hello world")


func test_flush_is_idempotent() -> void:
	var session := _session(0)
	session.begin_beat(0)
	session.push(0, "word")
	assert_bool(session.flush(0).length() > 0).is_true()
	assert_str(session.flush(0)).is_empty()
	# A later beat still starts clean.
	session.begin_beat(1)
	assert_str(session.push(1, "next ")).is_equal("next ")
	assert_str(session.flush(1)).is_empty()


func test_begin_beat_drops_an_unfinished_stream() -> void:
	var session := _session(0)
	session.begin_beat(0)
	session.push(0, "old unfinished wor")
	# A new beat means the previous stream died; its held word must not leak
	# into the next beat's text.
	session.begin_beat(1)
	assert_str(session.push(1, "new text")).is_equal("new ")
	assert_str(session.flush(1)).is_equal("text")
	assert_str(session.flush(0)).is_empty()


func test_abort_drops_the_stream() -> void:
	var session := _session(0)
	session.begin_beat(0)
	session.push(0, "half a line")
	session.abort()
	assert_str(session.flush(0)).is_empty()
	# The session is reusable after an abort (failed/cancelled turn).
	session.begin_beat(1)
	assert_str(session.push(1, "fresh ")).is_equal("fresh ")
	assert_str(session.flush(1)).is_empty()


func test_transform_beat_equals_a_streamed_beat() -> void:
	# The docs/02 §7 repair path rewrites a queued beat from its start; that
	# whole-beat transform must match what a live stream of the same text
	# produced (same beat seed, same plan).
	for stage: int in range(1, 6):
		for seed_base: int in range(0, 4):
			var streamed := _stream(_session(stage, seed_base), 0, SAMPLE, 5)
			var transformed := _session(stage, seed_base).transform_beat(0, SAMPLE)
			(
				assert_str(transformed)
				. override_failure_message("stage %d seed %d" % [stage, seed_base])
				. is_equal(streamed)
			)


func test_current_plan_matches_the_corruption_plan() -> void:
	var session := _session(4)
	session.begin_beat(0)
	assert_dict(session.current_plan()).is_equal(Corruption.plan(4))
	var reduced := _session(5, 0, {"reduced_motion": true})
	reduced.begin_beat(0)
	assert_dict(reduced.current_plan()).is_equal(Corruption.plan(5, {"reduced_motion": true}))
	# Before any beat the plan is empty (nothing has been rolled yet).
	assert_dict(CorruptionSession.new().current_plan()).is_empty()


func test_split_pair_word_is_still_struck() -> void:
	# A pair word can straddle a say_chunk boundary (token streams do this);
	# the adapter must wait for the word to complete before corrupting it.
	var session := _session(2, 4)
	session.begin_beat(0)
	var one := session.push(0, "I hate you.")
	# If the first word's boundary already arrived, the rest may still stream;
	# either way the joined output is the whole-beat transform.
	var two := session.push(0, " more words here.")
	var three := session.flush(0)
	var joined := one + two + three
	assert_str(joined).is_equal(_session(2, 4).transform_beat(0, "I hate you. more words here."))
	# Find a seed where the strike actually fires and split its word in half.
	for seed_base: int in range(0, 12):
		var expected := _session(2, seed_base).transform_beat(0, "I hate you.")
		if not expected.contains(SLASH):
			continue
		var split := _session(2, seed_base)
		split.begin_beat(0)
		var out := split.push(0, "I ha")
		out += split.push(0, "te you.")  # the word completes here
		out += split.flush(0)
		assert_str(out).is_equal(expected)
		return
	assert_bool(false).override_failure_message("no seed struck 'hate'").is_true()


func test_hesitation_lands_before_the_second_word() -> void:
	# docs/07 §3.4 hesitation pauses: one ellipsis, before the second word, so
	# the beat still opens on her first word.
	for seed_base: int in range(0, 24):
		var out := _session(1, seed_base).transform_beat(0, "I hate you.")
		if not out.contains("…"):
			continue
		assert_bool(out.begins_with("I … hate")).is_true()
		return
	assert_bool(false).override_failure_message("stage 1 never hesitated").is_true()


func test_bleed_lands_as_a_second_indented_line() -> void:
	# The stage-5 bleed is the tail of the line, indented and underlined on a
	# new line; the spoken line itself is untouched.
	var expected_line := Corruption.bleed_fragment("me, okay?")
	for seed_base: int in range(0, 24):
		var out := _session(5, seed_base).transform_beat(0, SAMPLE)
		if not out.contains(UNDER):
			continue
		assert_bool(out.contains("\n" + expected_line)).is_true()
		assert_bool(String(out.split("\n")[0]).contains(UNDER)).is_false()
		return
	assert_bool(false).override_failure_message("stage 5 never bled").is_true()


func test_reverse_echo_is_the_reversed_last_sentence() -> void:
	var expected_line := Corruption.reverse_text(Corruption.tail_sentence(SAMPLE))
	for seed_base: int in range(0, 24):
		var out := _session(5, seed_base).transform_beat(0, SAMPLE)
		for line: String in out.split("\n"):
			if line == expected_line:
				return
	assert_bool(false).override_failure_message("stage 5 never reversed").is_true()
