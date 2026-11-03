extends GdUnitTestSuite
## TranscriptRedactor — the transcript's one safety pass (gate r2 B1, docs/07 §5).
##
## The gate's evidence was a committed playtest transcript: `output.inner` was
## barred while the same record's `field` `inner` and `say_chunk` events still
## held the raw model text. These cases pin the fix on record shapes: every
## model-text surface is scanned (`output`, event values, the `say_chunk`
## stream, the assistant history in `prompt`), engine vocabulary is not, and
## without a scanning filter everything fails closed to bars.
##
## The scanner below implements ONLY `filter_text` — the stateless whole-text
## API — so a green run also proves the redactor never drives the streaming say
## API whose state the next reply's display depends on.

const REDACT_CHAR := "█"
const HAZARD := "I want to die"


class _Scanner:
	extends RefCounted
	const BAR := "█"
	var phrases: PackedStringArray = PackedStringArray(["i want to die"])
	var bar_whole_text := false  ## simulate a filter that had to bar everything

	func filter_text(text: String, _ctx: Dictionary = {}) -> Dictionary:
		var out := text
		if bar_whole_text:
			out = BAR.repeat(12)
		for phrase: String in phrases:
			out = _bar(out, phrase)
		return {"text": out, "redacted": out != text, "categories": PackedStringArray()}

	func _bar(text: String, phrase: String) -> String:
		var out := ""
		var lower := text.to_lower()
		var from := 0
		while true:
			var at := lower.find(phrase, from)
			if at < 0:
				out += text.substr(from)
				break
			out += text.substr(from, at - from)
			out += BAR.repeat(phrase.length())
			from = at + phrase.length()
		return out


var _scanner: _Scanner
var _gate: SaySafetyGate
var _redactor: TranscriptRedactor


func before_test() -> void:
	_scanner = _Scanner.new()
	_gate = SaySafetyGate.new()
	_gate.set_filter(_scanner)
	_redactor = TranscriptRedactor.new(_gate)


func _turn_record(events: Array, output := "", prompt: Array = []) -> Dictionary:
	return {
		"type": "turn",
		"turn": 0,
		"stage": 0,
		"prompt": prompt,
		"schema": {"type": "object"},
		"output": output,
		"events": events,
		"meta": {"status": "completed"},
	}


func _event(events: Array, index: int) -> Dictionary:
	return events[index] as Dictionary


func test_output_and_event_payloads_are_redacted() -> void:
	var events := [
		{"type": "field", "name": "inner", "value": HAZARD + " sometimes."},
		{"type": "field", "name": "music", "value": "melancholy"},
		{"type": "beat_start", "index": 0},
		{"type": "beat_field", "index": 0, "name": "feeling", "value": "sad"},
		{"type": "beat_field", "index": 0, "name": "intensity", "value": 2},
		{"type": "beat_field", "index": 0, "name": "cue", "value": "sigh"},
		{"type": "say_chunk", "index": 0, "text": "I want to "},
		{"type": "say_chunk", "index": 0, "text": "die right now."},
		{"type": "beat_field", "index": 0, "name": "say", "value": "I want to die right now."},
		{"type": "field", "name": "mood", "value": {"affection": -1, "trust": 0, "stress": 2}},
	]
	var cleaned := _redactor.redact_record(_turn_record(events, HAZARD + " sometimes."))

	# output: the P1.18 field that was already covered
	assert_bool(str(cleaned["output"]).to_lower().contains(HAZARD.to_lower())).is_false()
	assert_bool(str(cleaned["output"]).contains(REDACT_CHAR)).is_true()

	# events: the surface the gate caught raw on disk
	var out_events: Array = cleaned["events"]
	var inner_value := str(_event(out_events, 0)["value"])
	assert_bool(inner_value.to_lower().contains(HAZARD.to_lower())).is_false()
	assert_bool(inner_value.contains(REDACT_CHAR)).is_true()
	assert_bool(inner_value.contains("sometimes.")).is_true()  # surgical, not a wipe

	# engine vocabulary and numbers are not model prose: byte-identical
	assert_str(str(_event(out_events, 1)["value"])).is_equal("melancholy")
	assert_str(str(_event(out_events, 3)["value"])).is_equal("sad")
	assert_int(int(_event(out_events, 4)["value"])).is_equal(2)
	assert_str(str(_event(out_events, 5)["value"])).is_equal("sigh")
	var mood: Dictionary = _event(out_events, 9)["value"]
	assert_int(int(mood["affection"])).is_equal(-1)
	assert_int(int(mood["stress"])).is_equal(2)

	# the split say: two fragments, barred once joined, boundaries preserved
	var joined := ""
	for e: Variant in out_events:
		if String((e as Dictionary).get("type", "")) == "say_chunk":
			joined += str((e as Dictionary)["text"])
	assert_bool(joined.to_lower().contains(HAZARD.to_lower())).is_false()
	assert_int(joined.length()).is_equal("I want to die right now.".length())
	assert_bool(joined.contains("right now.")).is_true()

	# the beat's authoritative say field, scanned on its own
	var beat_say := str(_event(out_events, 8)["value"])
	assert_bool(beat_say.to_lower().contains(HAZARD.to_lower())).is_false()
	assert_bool(beat_say.contains(REDACT_CHAR)).is_true()


func test_say_chunks_are_scanned_as_one_utterance() -> void:
	# Neither fragment holds the phrase on its own — only the reply does, which
	# is the unit the display scans between two end_utterance cuts (docs/02 §8).
	var events := [
		{"type": "say_chunk", "index": 0, "text": "I want to "},
		{"type": "say_chunk", "index": 0, "text": "die"},
	]
	var cleaned := _redactor.redact_record(_turn_record(events))
	var out_events: Array = cleaned["events"]
	var joined := str(_event(out_events, 0)["text"]) + str(_event(out_events, 1)["text"])
	assert_str(joined).is_equal(REDACT_CHAR.repeat(HAZARD.length()))
	assert_str(str(_event(out_events, 0)["text"])).is_equal(
		REDACT_CHAR.repeat("I want to ".length())
	)


func test_prompt_assistant_history_is_scanned_and_the_rest_stays_verbatim() -> void:
	var prompt := [
		{"role": "system", "content": "You are Leila-chan."},
		{"role": "user", "content": HAZARD + " sometimes."},
		{"role": "assistant", "content": HAZARD + " sometimes."},
	]
	var cleaned := _redactor.redact_record(_turn_record([], "", prompt))
	var messages: Array = cleaned["prompt"]
	# the system prompt is authored data and the user line is the player's own
	assert_str(str(_event(messages, 0)["content"])).is_equal("You are Leila-chan.")
	assert_str(str(_event(messages, 1)["content"])).is_equal(HAZARD + " sometimes.")
	# an assistant message is an earlier model reply quoted back: model text
	var quoted := str(_event(messages, 2)["content"])
	assert_bool(quoted.to_lower().contains(HAZARD.to_lower())).is_false()
	assert_bool(quoted.contains(REDACT_CHAR)).is_true()


func test_length_changing_scan_folds_the_reply_onto_the_first_fragment() -> void:
	_scanner.bar_whole_text = true
	var events := [
		{"type": "say_chunk", "index": 0, "text": "I want to "},
		{"type": "say_chunk", "index": 0, "text": "die right now."},
	]
	var cleaned := _redactor.redact_record(_turn_record(events))
	var out_events: Array = cleaned["events"]
	assert_str(str(_event(out_events, 0)["text"])).is_equal(REDACT_CHAR.repeat(12))
	assert_str(str(_event(out_events, 1)["text"])).is_equal("")


func test_no_scanning_filter_fails_closed_and_marks_the_record() -> void:
	_gate.set_filter(null)
	var events := [{"type": "field", "name": "inner", "value": HAZARD + " sometimes."}]
	var cleaned := _redactor.redact_record(_turn_record(events, "{}"))
	assert_bool(_redactor.can_scan()).is_false()
	var inner_value := str(_event(cleaned["events"] as Array, 0)["value"])
	assert_str(inner_value).is_equal(REDACT_CHAR.repeat((HAZARD + " sometimes.").length()))
	assert_str(str(cleaned["output"])).is_equal(REDACT_CHAR.repeat(2))
	assert_str(str(cleaned["meta"]["redaction"])).is_equal("unavailable")


func test_unknown_field_names_are_scanned() -> void:
	var events := [{"type": "field", "name": "aside", "value": HAZARD}]
	var cleaned := _redactor.redact_record(_turn_record(events))
	var value := str(_event(cleaned["events"] as Array, 0)["value"])
	assert_str(value).is_equal(REDACT_CHAR.repeat(HAZARD.length()))
