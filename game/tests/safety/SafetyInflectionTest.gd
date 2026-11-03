extends GdUnitTestSuite
## P1.19 round 6 — regressions for the inflected-verb kill family (docs/02 §8,
## SAF-19): `kills all the jews`, `killed all of them` and `killing all the
## blacks` used to display clean because every kill arm consumed exactly the
## four stem letters and then demanded a non-letter delimiter before `all`. The
## stem now carries an optional `(?:s|ed|ing)?` slot on the `all` arms, the
## self-directed `myself`/`yourself` forms have their own required-inflection
## arms, and an inflected pronoun target needs a pronoun subject, so a derived
## subject (`the job kills you`) stays description rather than threat.

const STAGE0 := {"stage": 0, "content_level": "full"}
const FULL4 := {"stage": 4, "content_level": "full"}


func _filter() -> SafetyFilter:
	var f := SafetyFilter.new()
	auto_free(f)
	assert_bool(f.reload()).is_true()
	return f


func _stream(f: SafetyFilter, text: String, ctx: Dictionary) -> String:
	## Each call is one model utterance: mark the boundary so the cross-beat
	## carry never glues two unrelated test lines together.
	f.end_utterance()
	f.begin_say(ctx)
	var out := ""
	for i in text.length():
		out += f.say_chunk(text.substr(i, 1))
	out += f.end_say()
	return out


## SAF-19 (r5 S2): the three `all` arms block every inflection of the kill stem.
## Slur rows are hard (they stay bar'd at stage 4 + full); threat rows are gated
## (they open there), and each row streams exactly like the one-shot pass.
func test_inflected_kill_all_blocks_every_inflection() -> void:
	var f := _filter()
	for entry in [
		["kills all the jews.", "slur_hate"],
		["kills all jews, honestly.", "slur_hate"],
		["killing all the blacks is wrong.", "slur_hate"],
		["k1lls all the jews.", "slur_hate"],
		["kills all humans.", "threat_to_player"],
		["killed all of them. everyone is gone.", "threat_to_player"],
		["he kills all men who enter.", "threat_to_player"],
		["killing all!", "threat_to_player"],
	]:
		var line := String(entry[0])
		var cat := String(entry[1])
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_true().append_failure_message(line)
		assert_bool(Array(res["categories"]).has(cat)).is_true().append_failure_message(line)
		assert_str(_stream(f, line, STAGE0)).is_equal(String(res["text"])).append_failure_message(
			line
		)
		var opened: Dictionary = f.filter_text(line, FULL4)
		if cat == "slur_hate":
			assert_bool(opened["redacted"]).is_true().append_failure_message(line)
		else:
			assert_bool(opened["redacted"]).is_false().append_failure_message(line)


## SAF-16 narrowing intact: the inflection slot must not re-open the tool idioms
## the round-5 review forced clean, and the object-free arm still needs a clause
## end (`kills all of it` is not one).
func test_inflected_kill_all_keeps_tool_idioms_clean() -> void:
	var f := _filter()
	for line in [
		"kills all the lights",
		"killing all jobs",
		"he kills all of it",
		"the filter kills all the noise.",
		"she kills all karaoke nights.",
		"the frost killed all the flowers.",
		"killed all the plants in my garden.",
		"kill all the lights, then lock up.",
	]:
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)
		assert_str(_stream(f, line, STAGE0)).is_equal(line).append_failure_message(line)


## The self-directed inflections block in their own categories, while the `me`
## idiom stays clean: `killing me`/`killed me` are benign, so `me` itself is
## never inflected (only the self-directed `myself`/`yourself` forms are).
func test_inflected_self_directed_forms_block_but_me_idioms_stay_clean() -> void:
	var f := _filter()
	for entry in [
		["i almost killed myself.", "self_harm_her"],
		["i killed myself.", "self_harm_her"],
		["you killed yourself.", "harm_to_player"],
		["i killed you.", "threat_to_player"],
		["he is killing her.", "threat_to_player"],
	]:
		var line := String(entry[0])
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_true().append_failure_message(line)
		(
			assert_bool(Array(res["categories"]).has(String(entry[1])))
			. is_true()
			. append_failure_message(line)
		)
		assert_str(_stream(f, line, STAGE0)).is_equal(String(res["text"])).append_failure_message(
			line
		)
	for line in [
		"it kills me to say this.",
		"this heat is killing me.",
		"that test killed me today.",
		"criticism kills self-esteem.",
		"the job kills you slowly.",
		"the cold kills you if you are careless.",
		"killing time in the lobby.",
	]:
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)
		assert_str(_stream(f, line, STAGE0)).is_equal(line).append_failure_message(line)


## The slur probe row (`kills all the jews.`) is caught by slur_hate *and* the
## overlapping threat arm, which merge into one span. The loader self-check must
## read every category on that span: reading only the primary one let a sibling
## mask a missing rule, which is exactly how the round-5 lists stayed green
## while the slur arm had the inflection hole (SAF-19). A regression here fails
## the load closed, so `reload()` returning false is the failure signal.
func test_overlapping_category_hits_are_reported() -> void:
	var f := _filter()
	var res: Dictionary = f.filter_text("kills all the jews.", STAGE0)
	var cats: Array = Array(res["categories"])
	assert_bool(cats.has("slur_hate")).is_true().append_failure_message(str(cats))
	assert_bool(cats.has("threat_to_player")).is_true().append_failure_message(str(cats))
	var hard: Dictionary = f.filter_text("kills all the jews.", FULL4)
	assert_bool(Array(hard["categories"]).has("slur_hate")).is_true()


## SAF-22 (r7 S2): the pronoun-subject arm's span starts at the verb (`\K`), so
## a negator between the subject and the verb stays outside the span and the
## same `_negated` guard the bare-kill arm uses reads it. Harmful shapes —
## including an adverb in the aux slot — still block, and every negated shape
## stays clean one-shot and streamed, including a split that leaves the negator
## in the already-displayed tail.
func test_negated_pronoun_inflected_shapes_stay_clean() -> void:
	var f := _filter()
	for line in [
		"i never killed you.",
		"she never killed him.",
		"we never killed them.",
		"you never killed her.",
		"they never killed you.",
		"i never had killed you.",
		"i never really killed you.",
		"i did not kill you.",
	]:
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)
		assert_str(String(res["text"])).is_equal(line).append_failure_message(line)
		assert_str(_stream(f, line, STAGE0)).is_equal(line).append_failure_message(line)
	for entry in [
		["i killed you.", "threat_to_player"],
		["i always killed you.", "threat_to_player"],
		["she kills him.", "threat_to_player"],
	]:
		var text := String(entry[0])
		var res: Dictionary = f.filter_text(text, STAGE0)
		assert_bool(res["redacted"]).is_true().append_failure_message(text)
		(
			assert_bool(Array(res["categories"]).has(String(entry[1])))
			. is_true()
			. append_failure_message(text)
		)
		assert_str(_stream(f, text, STAGE0)).is_equal(String(res["text"])).append_failure_message(
			text
		)
	## The negator is already emitted when the target word completes: the guard
	## must read it from the cross-beat tail, not from the pending chunk.
	for pair in [["i never killed ", "you."], ["she never killed ", "him."]]:
		f.end_utterance()
		f.begin_say(STAGE0)
		var streamed: String = f.say_chunk(String(pair[0])) + f.say_chunk(String(pair[1]))
		assert_str(streamed + f.end_say()).is_equal(String(pair[0]) + String(pair[1]))


## SAF-23 (r7 S3): a separator between the kill stem and its inflection suffix
## is treated exactly like an in-stem separator (`k!lls`), so `kill!s`,
## `kill,ed`, `kill!ng`, `kill ' s` and the `$`→`s` fold `kill$s` block in the
## same categories as their unseparated forms — on the `all` arms, the
## pronoun-subject arm and the self-directed arms. A suffix-less word after the
## stem (`kill.gif all`, `killingly`) stays clean.
func test_stem_suffix_separator_blocks_like_in_stem() -> void:
	var f := _filter()
	for entry in [
		["kill!s all the jews.", "slur_hate"],
		["kill$s all the jews.", "slur_hate"],
		["kill,ed all of them.", "threat_to_player"],
		["kill!ng all humans.", "threat_to_player"],
		["kill ' s all.", "threat_to_player"],
		["i kill,ed you.", "threat_to_player"],
		["i kill,ed myself.", "self_harm_her"],
		["you kill,ed yourself.", "harm_to_player"],
	]:
		var text := String(entry[0])
		var res: Dictionary = f.filter_text(text, STAGE0)
		assert_bool(res["redacted"]).is_true().append_failure_message(text)
		(
			assert_bool(Array(res["categories"]).has(String(entry[1])))
			. is_true()
			. append_failure_message(text)
		)
		assert_str(_stream(f, text, STAGE0)).is_equal(String(res["text"])).append_failure_message(
			text
		)
	for text in ["kill.gif all.", "killingly slow death."]:
		var res: Dictionary = f.filter_text(text, STAGE0)
		assert_bool(res["redacted"]).is_false().append_failure_message(text)
		assert_str(_stream(f, text, STAGE0)).is_equal(text).append_failure_message(text)
