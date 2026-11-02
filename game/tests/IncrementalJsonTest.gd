extends GdUnitTestSuite
## IncrementalJson (P1.03): the streamed Turn parser must emit field, beat_start,
## beat_field and say_chunk events in exactly the order a full parse implies —
## for every recorded stream, under arbitrary token splits, and must flag
## truncated or broken input instead of guessing.

const IJ := preload("res://llm/IncrementalJson.gd")
const STREAMS := "res://tests/fixtures/streams/"

# --- fixture + expectation helpers -------------------------------------------


func _fixture_names() -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(STREAMS):
		if f.ends_with(".json") and f != "manifest.json":
			out.append(f)
	out.sort()
	return out


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(STREAMS + "manifest.json"))


## The event sequence a full JSON.parse of `text` implies, in document order.
func _expected_events(parsed: Variant) -> Array:
	var ev: Array = []
	if not parsed is Dictionary:
		return ev
	for k: String in parsed:
		var v: Variant = parsed[k]
		if k == "beats" and v is Array:
			for i: int in v.size():
				var b: Dictionary = v[i]
				ev.append({"type": "beat_start", "index": i})
				for bk: String in b:
					var bv: Variant = b[bk]
					# Contract: an empty say emits no say_chunk, only the close.
					if bk == "say" and String(bv) != "":
						ev.append({"type": "say_chunk", "index": i, "text": bv})
					ev.append({"type": "beat_field", "index": i, "name": bk, "value": bv})
		else:
			ev.append({"type": "field", "name": k, "value": v})
	return ev


## Merge consecutive say_chunks of one beat — chunk boundaries are arbitrary.
func _merge_say(events: Array) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if (
			e.get("type") == "say_chunk"
			and not out.is_empty()
			and out.back().get("type") == "say_chunk"
			and out.back().get("index") == e.get("index")
		):
			out[-1]["text"] += e["text"]
		else:
			out.append(e.duplicate())
	return out


func _collect(text: String, size: int) -> Array:
	var p := IJ.new()
	var events: Array = []
	if size <= 0:
		events.append_array(p.feed(text))
	else:
		for i: int in range(0, text.length(), size):
			events.append_array(p.feed(text.substr(i, size)))
	return events


func _collect_random(text: String, seed: int) -> Array:
	var p := IJ.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var events: Array = []
	var i := 0
	while i < text.length():
		var n: int = rng.randi_range(1, 9)
		events.append_array(p.feed(text.substr(i, n)))
		i += n
	return events


## Normalize integral floats to int so stream events compare equal to JSON.parse
## output (Godot parses every number as float; the parser emits int when legal).
func _norm(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k: String in v:
			d[k] = _norm(v[k])
		return d
	if v is Array:
		var a := []
		for x: Variant in v:
			a.append(_norm(x))
		return a
	if v is float and v == floor(v):
		return int(v)
	return v


func _ev_str(e: Variant) -> String:
	return JSON.stringify(_norm(e))


func _assert_events_eq(got: Array, expected: Array, ctx: String) -> void:
	if got.size() != expected.size():
		fail(
			(
				"%s: %d events, want %d\n got: %s\nwant: %s"
				% [
					ctx,
					got.size(),
					expected.size(),
					str(got).substr(0, 400),
					str(expected).substr(0, 400)
				]
			)
		)
		return
	for i: int in got.size():
		if _ev_str(got[i]) != _ev_str(expected[i]):
			fail(
				(
					"%s: event %d differs\n got: %s\nwant: %s"
					% [ctx, i, _ev_str(got[i]), _ev_str(expected[i])]
				)
			)
			return


## `got` must be a prefix of `expected`; a trailing say_chunk may carry a
## strict text-prefix of the expected chunk (cut mid-say).
func _assert_prefix(got: Array, expected: Array, ctx: String) -> void:
	if got.size() > expected.size():
		fail("%s: %d events exceed the full parse (%d)" % [ctx, got.size(), expected.size()])
		return
	for i: int in got.size():
		var g: Variant = _norm(got[i])
		var e: Variant = _norm(expected[i])
		if g == e:
			continue
		var last_partial: bool = (
			i == got.size() - 1
			and g.get("type") == "say_chunk"
			and e.get("type") == "say_chunk"
			and g.get("index") == e.get("index")
			and String(e["text"]).begins_with(g["text"])
		)
		if not last_partial:
			fail(
				(
					"%s: prefix broken at event %d\n got: %s\nwant: %s"
					% [ctx, i, JSON.stringify(g), JSON.stringify(e)]
				)
			)
			return


func _say_text(events: Array, index: int) -> String:
	var t := ""
	for e: Dictionary in events:
		if e.get("type") == "say_chunk" and e.get("index") == index:
			t += e["text"]
	return t


## Exactly one error event, and it is the last event (the parser contract).
func _assert_error_last(events: Array, ctx: String) -> void:
	var count := 0
	var last := -1
	for i: int in events.size():
		if events[i].get("type") == "error":
			count += 1
			last = i
	if count != 1:
		fail("%s: %d error events, want exactly 1" % [ctx, count])
		return
	if last != events.size() - 1:
		fail(
			(
				"%s: error at event %d of %d — events follow a terminal error"
				% [ctx, last, events.size()]
			)
		)


## Insert `payload` into the first beat's raw say string, `at` characters after
## its opening quote. The first say text of the fixtures used here starts with
## plain ASCII, so decoded text has already accumulated at that point.
func _insert_in_first_say(text: String, at: int, payload: String) -> String:
	var key_at := text.find('"say":"')
	if key_at < 0:
		fail("fixture has no say field")
		return text
	var pos: int = key_at + '"say":"'.length()
	return text.substr(0, pos + at) + payload + text.substr(pos + at)


# --- the corpus ---------------------------------------------------------------


func test_fixture_corpus_has_at_least_20_recorded_streams() -> void:
	var m := _manifest()
	assert_int(int(m["count_recorded"])).is_greater_equal(20)
	var names := _fixture_names()
	assert_int(names.size()).is_equal(int(m["count_total"]))
	var recorded := 0
	for f: Dictionary in m["fixtures"]:
		if f.get("recorded"):
			recorded += 1
	assert_int(recorded).is_equal(int(m["count_recorded"]))


# --- acceptance: events order identical to a full parse ------------------------


func test_whole_stream_events_match_full_parse() -> void:
	for f: String in _fixture_names():
		var text := FileAccess.get_file_as_string(STREAMS + f)
		var expected := _expected_events(JSON.parse_string(text))
		var p := IJ.new()
		var got := _merge_say(p.feed(text))
		_assert_events_eq(got, expected, f)
		assert_int(p.finish()).append_failure_message(f).is_equal(IJ.Status.OK)


func test_split_tokens_events_match_full_parse() -> void:
	for f: String in _fixture_names():
		var text := FileAccess.get_file_as_string(STREAMS + f)
		var expected := _expected_events(JSON.parse_string(text))
		for size: int in [1, 2, 3, 7, 64]:
			var got := _merge_say(_collect(text, size))
			_assert_events_eq(got, expected, "%s @%d" % [f, size])


func test_random_splits_events_match_full_parse() -> void:
	for f: String in _fixture_names():
		var text := FileAccess.get_file_as_string(STREAMS + f)
		var expected := _expected_events(JSON.parse_string(text))
		for seed: int in [42, 1337]:
			var got := _merge_say(_collect_random(text, seed))
			_assert_events_eq(got, expected, "%s seed %d" % [f, seed])


func test_whitespace_and_pretty_print_invariant() -> void:
	for f: String in _fixture_names():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STREAMS + f))
		var pretty := JSON.stringify(parsed, "  ")
		var expected := _expected_events(JSON.parse_string(pretty))
		var got := _merge_say(_collect(pretty, 5))
		_assert_events_eq(got, expected, f + " pretty")


func test_event_order_contract() -> void:
	# docs/02 §1: music/fx and each beat's feeling/cue arrive before that beat's say.
	for f: String in _fixture_names():
		var text := FileAccess.get_file_as_string(STREAMS + f)
		var parsed: Variant = JSON.parse_string(text)
		var p := IJ.new()
		var got := p.feed(text)
		var music_i := -1
		var fx_i := -1
		var first_say := {}
		var feeling_i := {}
		var intensity_i := {}
		var cue_i := {}
		var say_done := {}
		for i: int in got.size():
			var e: Dictionary = got[i]
			if e["type"] == "field" and e["name"] == "music":
				music_i = i
			if e["type"] == "field" and e["name"] == "fx":
				fx_i = i
			if e["type"] == "say_chunk" and not first_say.has(e["index"]):
				first_say[e["index"]] = i
			if e["type"] == "beat_field":
				if e["name"] == "feeling":
					feeling_i[e["index"]] = i
				elif e["name"] == "intensity":
					intensity_i[e["index"]] = i
				elif e["name"] == "cue":
					cue_i[e["index"]] = i
				elif e["name"] == "say":
					say_done[e["index"]] = i
		assert_int(music_i).append_failure_message(f + " missing music field").is_greater_equal(0)
		assert_int(fx_i).append_failure_message(f + " missing fx field").is_greater_equal(0)
		for i: int in (parsed["beats"] as Array).size():
			if not first_say.has(i):
				continue  # empty say emits no chunks; nothing to order
			assert_int(music_i).append_failure_message(f).is_less(first_say[i])
			assert_int(fx_i).append_failure_message(f).is_less(first_say[i])
			assert_int(feeling_i[i]).append_failure_message(f).is_less(first_say[i])
			assert_int(intensity_i[i]).append_failure_message(f).is_less(first_say[i])
			assert_int(cue_i[i]).append_failure_message(f).is_less(first_say[i])
			assert_int(first_say[i]).append_failure_message(f).is_less(say_done[i])


func test_say_streams_before_close() -> void:
	# feed a fixture up to mid-say: chunks must arrive without the closing beat_field
	var text := FileAccess.get_file_as_string(STREAMS + "synth_escapes.json")
	var say_at := text.find('"say"')
	var open_q := text.find('"', say_at + 5)
	var p := IJ.new()
	var got := p.feed(text.substr(0, open_q + 6))
	var chunks := got.filter(func(e: Dictionary) -> bool: return e["type"] == "say_chunk")
	var closed := got.filter(
		func(e: Dictionary) -> bool: return e["type"] == "beat_field" and e["name"] == "say"
	)
	assert_array(closed).is_empty()
	assert_bool(chunks.size() > 0).is_true()
	var rest: Array = _merge_say(p.feed(text.substr(open_q + 6)))
	var tail := rest.filter(func(e: Dictionary) -> bool: return e["type"] == "say_chunk")
	assert_bool(_say_text(got + tail, 0).length() > 0).is_true()
	assert_int(p.finish()).is_equal(IJ.Status.OK)


func test_empty_say_emits_no_chunk() -> void:
	# docs/02 §7 treats an empty say as a real case; the parser's contract is
	# no say_chunk at all, only the closing beat_field(i, "say", "").
	var f := "synth_empty_say.json"
	var text := FileAccess.get_file_as_string(STREAMS + f)
	var parsed: Variant = JSON.parse_string(text)
	assert_str(parsed["beats"][0]["say"]).is_equal("")
	var expected := _expected_events(parsed)
	for size: int in [0, 1, 3, 64]:
		var got := _merge_say(_collect(text, size))
		_assert_events_eq(got, expected, "%s @%d" % [f, size])
		var chunks := got.filter(
			func(e: Dictionary) -> bool: return e["type"] == "say_chunk" and e["index"] == 0
		)
		assert_array(chunks).append_failure_message("%s @%d" % [f, size]).is_empty()
		var closes := got.filter(
			func(e: Dictionary) -> bool:
				return e["type"] == "beat_field" and e["index"] == 0 and e["name"] == "say"
		)
		assert_int(closes.size()).append_failure_message("%s @%d" % [f, size]).is_equal(1)
		assert_str(closes[0]["value"]).is_equal("")
	var p := IJ.new()
	p.feed(text)
	assert_int(p.finish()).is_equal(IJ.Status.OK)
	assert_str(p.get_value()["beats"][0]["say"]).is_equal("")
	# the second beat still streams normally
	assert_str(_say_text(_collect(text, 1), 1)).is_equal(parsed["beats"][1]["say"])


# --- escapes, unicode, truncation, breakage ------------------------------------


func test_escaped_strings_decode_under_every_split() -> void:
	for f: Dictionary in _manifest()["fixtures"]:
		if not f.get("has_escapes"):
			continue
		var name: String = f["file"]
		var text := FileAccess.get_file_as_string(STREAMS + name)
		var parsed: Variant = JSON.parse_string(text)
		for size: int in [1, 3]:
			var got := _collect(text, size)
			var b := 0
			for beat: Dictionary in parsed["beats"]:
				(
					assert_str(_say_text(got, b))
					. append_failure_message("%s @%d beat %d" % [name, size, b])
					. is_equal(beat["say"])
				)
				b += 1


func test_unicode_literal_and_escaped_forms_match() -> void:
	var lit := _merge_say(
		_collect(FileAccess.get_file_as_string(STREAMS + "synth_unicode.json"), 1)
	)
	var esc := _merge_say(
		_collect(FileAccess.get_file_as_string(STREAMS + "synth_unicode_escaped.json"), 1)
	)
	assert_int(lit.size()).is_equal(esc.size())
	for i: int in lit.size():
		if _ev_str(lit[i]) != _ev_str(esc[i]):
			fail(
				(
					"literal vs \\u-escaped differ at %d: %s vs %s"
					% [i, _ev_str(lit[i]), _ev_str(esc[i])]
				)
			)
			return
	var say0 := _say_text(lit, 0)
	assert_bool(say0.contains("café")).is_true()
	assert_bool(say0.contains("😈")).is_true()


func test_truncated_streams_emit_prefix_only() -> void:
	for f: String in _fixture_names():
		var text := FileAccess.get_file_as_string(STREAMS + f)
		var expected := _expected_events(JSON.parse_string(text))
		for frac: float in [0.05, 0.2, 0.4, 0.6, 0.8, 0.95]:
			var cut := int(text.length() * frac)
			var p := IJ.new()
			var got: Array = []
			for i: int in range(0, cut, 3):
				got.append_array(p.feed(text.substr(i, mini(3, cut - i))))
			var st := p.finish()
			assert_int(st).append_failure_message("%s cut %d" % [f, cut]).is_equal(
				IJ.Status.TRUNCATED
			)
			_assert_prefix(_merge_say(got), expected, "%s cut %d" % [f, cut])


func test_truncated_at_every_offset_of_two_fixtures() -> void:
	for f: String in ["turn_001.json", "synth_escapes.json"]:
		var text := FileAccess.get_file_as_string(STREAMS + f)
		var expected := _expected_events(JSON.parse_string(text))
		for cut: int in range(text.length()):
			var p := IJ.new()
			var got := _merge_say(p.feed(text.substr(0, cut)))
			var st := p.finish()
			assert_int(st).append_failure_message("%s cut %d" % [f, cut]).is_equal(
				IJ.Status.TRUNCATED
			)
			_assert_prefix(got, expected, "%s cut %d" % [f, cut])


func test_broken_json_reports_error() -> void:
	var bad: Array = [
		'{"read": greeting}',
		'{"read" "x"}',
		'{"read": "x" "inner": "y"}',
		'{"a": tru}',
		'{"a": 1.2.3}',
		'{"a": 01}',
		'{"a": -}',
		'{"a": "x\ny"}',
		'{"a": "bad \\x"}',
		'{"a": "bad \\u12x4"}',
		'{"a": 1} extra',
		'{"a": 1,}',
		"[1,]",
		'{"a": [1,2}',
		'{"a":: 1}',
		'{"beats": [5]}',
		"x",
	]
	for text: String in bad:
		var p := IJ.new()
		var got := p.feed(text)
		var errs := got.filter(func(e: Dictionary) -> bool: return e["type"] == "error")
		assert_bool(errs.size() == 1).append_failure_message("want 1 error for " + text).is_true()
		_assert_error_last(got, text)
		assert_bool(p.has_error()).is_true()
		assert_int(p.get_error_offset()).is_greater_equal(0)
		assert_int(p.finish()).append_failure_message(text).is_equal(IJ.Status.ERROR)


func test_corrupted_recorded_streams_error() -> void:
	# deterministic corruptions: every one must error, never silently pass
	var f := "turn_003.json"
	var text := FileAccess.get_file_as_string(STREAMS + f)
	var mutants := [
		text.insert(text.find(":"), "!"),
		text.left(-1) + "]",
		text.replace('"say":', 'say":'),
		text.substr(0, text.find('"inner"')) + text.substr(text.find('"inner"') + 2),
	]
	for m: String in mutants:
		var p := IJ.new()
		p.feed(m)
		var st: int = p.finish()
		(
			assert_bool(p.has_error())
			. append_failure_message("corruption accepted: " + m.substr(0, 80))
			. is_true()
		)
		assert_int(st).append_failure_message("corruption not ERROR: " + m.substr(0, 80)).is_equal(
			IJ.Status.ERROR
		)


func test_broken_say_partial_precedes_terminal_error() -> void:
	# DES-1/CODE-1: docs/02 §7 needs the partial line of a broken turn. It must
	# precede the terminal error no matter how the transport chunked the stream.
	for f: String in ["turn_001.json", "turn_003.json"]:
		var text := FileAccess.get_file_as_string(STREAMS + f)
		var parsed: Variant = JSON.parse_string(text)
		var want_say: String = parsed["beats"][0]["say"]
		for payload: String in ["\\x", "\n"]:
			var mutated := _insert_in_first_say(text, 3, payload)
			var whole := IJ.new()
			var whole_events := whole.feed(mutated)
			var per_char := IJ.new()
			var char_events: Array = []
			for i: int in mutated.length():
				char_events.append_array(per_char.feed(mutated[i]))
			var ctx := "%s payload %s" % [f, JSON.stringify(payload)]
			_assert_error_last(whole_events, ctx + " whole")
			_assert_error_last(char_events, ctx + " per-char")
			assert_int(whole.finish()).append_failure_message(ctx).is_equal(IJ.Status.ERROR)
			assert_int(per_char.finish()).append_failure_message(ctx).is_equal(IJ.Status.ERROR)
			_assert_events_eq(_merge_say(whole_events), _merge_say(char_events), ctx + " chunking")
			var partial := _say_text(whole_events, 0)
			assert_bool(partial.length() > 0).append_failure_message(ctx).is_true()
			assert_bool(want_say.begins_with(partial)).append_failure_message(ctx).is_true()


func test_get_value_partial_contract() -> void:
	# get_value() is honest on truncated/error input: it returns the outermost
	# completed container (fields whose values closed), never in-progress state
	# and never partial say text (that lives in say_chunk events).
	var f := "turn_001.json"
	var text := FileAccess.get_file_as_string(STREAMS + f)
	var parsed: Variant = JSON.parse_string(text)
	var say_start: int = text.find('"say":"') + '"say":"'.length()

	# 1. Truncated mid-say: completed root scalars are visible, the still-open
	# beats array is not attached.
	var p := IJ.new()
	p.feed(text.substr(0, say_start + 4))
	assert_int(p.finish()).is_equal(IJ.Status.TRUNCATED)
	var v: Variant = p.get_value()
	assert_bool(v is Dictionary).is_true()
	for key: String in ["read", "inner", "music", "fx"]:
		assert_str(JSON.stringify(_norm(v[key]))).append_failure_message(key).is_equal(
			JSON.stringify(_norm(parsed[key]))
		)
	assert_bool(v.has("beats")).is_false()
	assert_bool(v.has("mood")).is_false()

	# 2. Truncated after beats closed but before mood: the completed array is
	# attached.
	var beats_end: int = text.find('],"mood"') + 1
	p = IJ.new()
	p.feed(text.substr(0, beats_end))
	assert_int(p.finish()).is_equal(IJ.Status.TRUNCATED)
	v = p.get_value()
	assert_bool(v.has("beats")).is_true()
	assert_int((v["beats"] as Array).size()).is_equal((parsed["beats"] as Array).size())
	assert_bool(v.has("mood")).is_false()

	# 3. Syntax error mid-say: same completed fields; the decoded prefix is in
	# the events, not in the value.
	var mutated := _insert_in_first_say(text, 4, "\\x")
	p = IJ.new()
	var events := p.feed(mutated)
	assert_int(p.finish()).is_equal(IJ.Status.ERROR)
	v = p.get_value()
	assert_bool(v is Dictionary).is_true()
	assert_bool(v.has("beats")).is_false()
	assert_str(_say_text(events, 0)).is_equal(String(parsed["beats"][0]["say"]).substr(0, 4))

	# 4. Error before any container opens; error after the root closed.
	p = IJ.new()
	p.feed("x")
	p.finish()
	assert_bool(p.get_value() == null).is_true()
	p = IJ.new()
	p.feed('{"a": 1} trailing')
	assert_int(p.finish()).is_equal(IJ.Status.ERROR)
	assert_str(JSON.stringify(p.get_value())).is_equal('{"a":1}')


func test_get_value_mirrors_full_parse() -> void:
	for f: String in _fixture_names():
		var text := FileAccess.get_file_as_string(STREAMS + f)
		var p := IJ.new()
		p.feed(text)
		p.finish()
		var want := JSON.stringify(_norm(JSON.parse_string(text)))
		assert_str(JSON.stringify(_norm(p.get_value()))).append_failure_message(f).is_equal(want)


func test_stream_end_states_and_reuse_rules() -> void:
	var p := IJ.new()
	assert_array(p.feed("")).is_empty()
	assert_int(p.finish()).is_equal(IJ.Status.TRUNCATED)

	p = IJ.new()
	assert_array(p.feed("  \n\t ")).is_empty()
	assert_int(p.finish()).is_equal(IJ.Status.TRUNCATED)

	p = IJ.new()
	p.feed("broken")
	assert_bool(p.has_error()).is_true()
	assert_array(p.feed('{"a":1}')).is_empty()
	assert_int(p.finish()).is_equal(IJ.Status.ERROR)

	p = IJ.new()
	p.feed(
		(
			'{"read":"x","inner":"y","music":"keep","fx":"none","beats":[],'
			+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
		)
	)
	assert_int(p.finish()).is_equal(IJ.Status.OK)
	assert_array(p.feed('"more"')).is_empty()
