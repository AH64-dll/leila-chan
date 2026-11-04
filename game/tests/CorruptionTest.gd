extends GdUnitTestSuite
## P2.06 — the docs/07 §3.4 corruption text filter, core rules.
##
## The suite is organised by acceptance criterion:
##   - every effect is gated by the docs stage (stage 0 none, 1 hesitation,
##     2 strike, 3 repetition/wrong name, 4 zalgo/redaction, 5 bleed/reverse);
##   - every effect is seeded (same seed -> same text, different seed -> a
##     different roll) and the seed derives from turn/beat/stage;
##   - stages 0–3 stay readable (the original words survive, in order, with no
##     glyph-destroying effect);
##   - reduced motion removes only the visual jitter effects (zalgo, bleed) and
##     calmer mode caps the effective stage at 3 (docs/02 §8);
##   - the code rules (gates cannot be lowered by data, a broken file falls
##     back to the docs table) hold.

const TABLE_PATH := "res://data/corruption.json"
const READABLE := (
	"I hate the way you look at me. I don't know what I want to remember, "
	+ "but I'm fine. Stay with me, okay?"
)
const NAMED := "Senpai, I don't know. I'm fine, Senpai."
const STAGES: Array[int] = [0, 1, 2, 3, 4, 5]
const SEEDS := 24
const SLASH := "\u0338"
const UNDER := "\u0332"
const ZALGO_MARKS: Array[String] = ["\u0300", "\u0301", "\u0308"]
const REDACT := "█"


func after_test() -> void:
	Corruption.clear_cache()


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


func _run(stage: int, text: String, seed_base := 0, extra := {}) -> String:
	return _session(stage, seed_base, extra).transform_beat(0, text)


func _word_list(text: String) -> PackedStringArray:
	# Strip the decorations first: a combining mark between two letters would
	# otherwise split "h̸a̸t̸e̸" into four one-letter words and fake a loss.
	var clean := text
	for mark: String in ZALGO_MARKS:
		clean = clean.replace(mark, "")
	clean = clean.replace(SLASH, "").replace(UNDER, "")
	var re := RegEx.new()
	re.compile("[A-Za-z0-9']+")
	var out := PackedStringArray()
	for found: RegExMatch in re.search_all(clean):
		out.append(found.get_string().to_lower())
	return out


## A doubled adjacent word is the stage-3 repetition effect ("I I don't",
## "don't don't know"), whichever word the roll picked.
func _has_doubled_word(text: String) -> bool:
	var words := _word_list(text)
	for i: int in range(1, words.size()):
		if words[i] == words[i - 1]:
			return true
	return false


## Every word of `original` appears in `output` in the same order. Effect text
## (the struck word, its correction, repeated words, an inserted ellipsis) may
## interleave; readability is "nothing original was lost or reordered".
func _words_survive(original: String, output: String) -> bool:
	var source := _word_list(original)
	var got := _word_list(output)
	var cursor := 0
	for word: String in source:
		var found := false
		while cursor < got.size():
			if got[cursor] == word:
				found = true
				cursor += 1
				break
			cursor += 1
		if not found:
			return false
	return true


func _count_marks(text: String, marks: Array[String]) -> int:
	var count := 0
	for i: int in text.length():
		if marks.has(text[i]):
			count += 1
	return count


func _zalgo_marks(text: String) -> int:
	return _count_marks(text, ZALGO_MARKS)


func _slashed(word: String) -> String:
	var out := ""
	for i: int in word.length():
		out += word[i]
		if word[i].to_lower() != word[i].to_upper():
			out += SLASH
	return out


## Drop the bleed echo line(s): they exist only as visual smear.
func _without_bleed_lines(text: String) -> String:
	var kept := PackedStringArray()
	for line: String in text.split("\n"):
		if not line.contains(UNDER):
			kept.append(line)
	return "\n".join(kept)


## Remove the glyph decorations (zalgo marks, bleed underline) but keep the
## strike slash: reduced motion must not change the readable text.
func _strip_visual(text: String) -> String:
	var drop: Array[String] = []
	drop.append_array(ZALGO_MARKS)
	drop.append(UNDER)
	var out := ""
	for i: int in text.length():
		if drop.has(text[i]):
			continue
		out += text[i]
	return out


func test_data_file_carries_the_docs_table() -> void:
	# Content is data (docs/07 §2): the shipped file must be the docs values,
	# and the in-code fallback must agree with it, or the fallback is a lie.
	assert_bool(Corruption.reload_table(TABLE_PATH)).is_true()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	assert_bool(parsed is Dictionary).is_true()
	var data := parsed as Dictionary
	var docs: Dictionary = Corruption.DOCS_TABLE
	for name: String in Corruption.EFFECT_ORDER:
		var row: Dictionary = data["effects"][name]
		var docs_row: Dictionary = docs["effects"][name]
		assert_str(String(row["kind"])).is_equal(String(docs_row["kind"]))
		assert_int(int(row["gate"])).is_equal(int(docs_row["gate"]))
		assert_int(int(row["max_per_beat"])).is_equal(int(docs_row["max_per_beat"]))
		for stage: int in STAGES:
			assert_float(float(data["stages"][str(stage)].get(name, 0.0))).is_equal_approx(
				float(docs["stages"][str(stage)].get(name, 0.0)), 0.0001
			)
	# The numbers the effects are tuned around.
	assert_str(String(data["params"]["hesitate"]["mark"])).is_equal("…")
	assert_str(String(data["params"]["strike"]["mark"])).is_equal(SLASH)
	assert_str(String(data["params"]["strike"]["correction"])).is_equal("— no,")
	assert_bool((data["params"]["strike"]["pairs"] as Dictionary).size() > 8).is_true()
	assert_array(Array(data["params"]["zalgo"]["marks"])).is_equal(ZALGO_MARKS)
	assert_int(int(data["params"]["redact"]["bars"])).is_equal(6)
	assert_int(int(data["calmer_max_stage"])).is_equal(3)
	assert_array(Array(data["reduced_motion"]["disable"])).contains_exactly(["zalgo", "bleed"])


func test_stage_gates_match_the_docs() -> void:
	# docs/07 §3.4, one effect per stage band. Exact strings so a silent gate
	# move (an effect appearing a stage early) is a red suite.
	var expected := {
		0: "stage 0 · none",
		1: "stage 1 · hesitate",
		2: "stage 2 · hesitate, strike",
		3: "stage 3 · hesitate, strike, repeat, wrong_name",
		4: "stage 4 · hesitate, strike, repeat, wrong_name, zalgo, redact",
		5: "stage 5 · hesitate, strike, repeat, wrong_name, zalgo, redact, " + "bleed, reverse",
	}
	for stage: int in STAGES:
		assert_str(Corruption.describe(Corruption.plan(stage))).is_equal(expected[stage])
	# The plan exposes one entry per effect in pipeline order.
	var plan := Corruption.plan(3)
	var names: Array = (plan["effects"] as Dictionary).keys()
	assert_int(names.size()).is_equal(Corruption.EFFECT_ORDER.size())
	for name: String in Corruption.EFFECT_ORDER:
		assert_bool((plan["effects"] as Dictionary).has(name)).is_true()


func test_reduced_motion_and_calmer_read_the_plan() -> void:
	# Reduced motion drops the visual-jitter effects only.
	assert_str(Corruption.describe(Corruption.plan(5, {"reduced_motion": true}))).is_equal(
		"stage 5 · hesitate, strike, repeat, wrong_name, redact, reverse"
	)
	# docs/02 §8: calmer caps the stage at 3, so its plan is the stage-3 plan.
	var calmer := Corruption.plan(5, {"content_level": "calmer"})
	assert_int(int(calmer["stage"])).is_equal(5)
	assert_int(int(calmer["effective_stage"])).is_equal(3)
	assert_bool(bool(calmer["calmer"])).is_true()
	assert_str(Corruption.describe(calmer)).is_equal(Corruption.describe(Corruption.plan(3)))
	# Stages at or below the cap are untouched.
	assert_int(int(Corruption.plan(2, {"content_level": "calmer"})["effective_stage"])).is_equal(2)
	assert_bool(bool(Corruption.plan(2, {"content_level": "calmer"})["calmer"])).is_false()
	# A missing/invalid level never enables the cap.
	assert_int(int(Corruption.plan(5, {"content_level": "full"})["effective_stage"])).is_equal(5)


func test_data_cannot_lower_a_gate() -> void:
	# docs/07 §3.4 gates are code rules. A table that tries to enable
	# hesitation at stage 0 must not: the normalized gate is the max of the
	# data gate and the docs gate.
	var path := "user://p206_bad_corruption.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	if file == null:
		return
	file.store_string(
		(
			'{"effects":{"hesitate":{"kind":"beat","gate":0,"max_per_beat":9}},'
			+ '"stages":{"0":{"hesitate":1.0,"strike":1.0}},"params":{}}'
		)
	)
	file.close()
	assert_bool(Corruption.reload_table(path)).is_true()
	var plan := Corruption.plan(0)
	var effects: Dictionary = plan["effects"]
	assert_int(int((effects["hesitate"] as Dictionary)["gate"])).is_equal(1)
	assert_float(float((effects["hesitate"] as Dictionary)["chance"])).is_zero()
	assert_float(float((effects["strike"] as Dictionary)["chance"])).is_zero()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Corruption.clear_cache()
	assert_bool(Corruption.reload_table()).is_true()


func test_stage_0_passes_text_through() -> void:
	for seed_base: int in range(0, 10):
		assert_str(_run(0, READABLE, seed_base)).is_equal(READABLE)
	# No decorations of any kind, including the strike/underline marks.
	var out := _run(0, READABLE, 0)
	assert_int(_zalgo_marks(out)).is_zero()
	assert_bool(out.contains(SLASH)).is_false()
	assert_bool(out.contains(REDACT)).is_false()


func test_hesitation_starts_at_stage_1() -> void:
	var found := -1
	for seed_base: int in range(0, SEEDS):
		if _run(1, READABLE, seed_base).contains("…"):
			found = seed_base
			break
	assert_bool(found >= 0).override_failure_message("stage 1 must hesitate once").is_true()
	# The hesitation is a pause only: no strike, no redaction, no repetition.
	for seed_base: int in range(0, SEEDS):
		assert_str(_run(0, READABLE, seed_base)).is_equal(READABLE)
		var out := _run(1, READABLE, seed_base)
		assert_bool(out.contains(SLASH)).is_false()
		assert_bool(out.contains(REDACT)).is_false()
		assert_bool(_words_survive(READABLE, out)).is_true()


func test_strike_self_correction_starts_at_stage_2() -> void:
	var text := "I hate you and I'm fine."
	for seed_base: int in range(0, SEEDS):
		var stage_1 := _run(1, text, seed_base)
		assert_bool(stage_1.contains(SLASH)).is_false()
		assert_bool(stage_1.contains("— no,")).is_false()
	var struck := -1
	for seed_base: int in range(0, SEEDS):
		if _run(2, text, seed_base).contains(SLASH):
			struck = seed_base
			break
	assert_bool(struck >= 0).override_failure_message("stage 2 must strike a pair").is_true()
	var out := _run(2, text, struck)
	assert_bool(out.contains(SLASH)).is_true()
	# The crossed word is still readable: its letters survive under the slash.
	assert_bool(_words_survive(text, out)).is_true()
	# Both directions of the self-correction pair are data-owned; each is a
	# separate beat because the effect is capped at one per beat.
	var love_seed := -1
	var broken_seed := -1
	for seed_base: int in range(0, SEEDS):
		if _run(2, "I hate you.", seed_base).contains("— no, love"):
			love_seed = seed_base
		if _run(2, "I'm fine.", seed_base).contains("— no, broken"):
			broken_seed = seed_base
	assert_bool(love_seed >= 0).override_failure_message("hate must correct to love").is_true()
	assert_bool(broken_seed >= 0).override_failure_message("fine must correct to broken").is_true()


func test_repetition_and_wrong_name_start_at_stage_3() -> void:
	var names: Array = Corruption.table()["params"]["wrong_name"]["names"]
	for seed_base: int in range(0, SEEDS):
		var stage_2 := _run(2, NAMED, seed_base)
		assert_bool(stage_2.contains("Senpai")).is_true()
		assert_bool(_has_doubled_word(stage_2)).is_false()
	var repeated := -1
	var renamed := -1
	for seed_base: int in range(0, SEEDS):
		var out := _run(3, NAMED, seed_base)
		if _has_doubled_word(out):
			repeated = seed_base
		for pick: String in names:
			if out.contains(pick):
				renamed = seed_base
	assert_bool(repeated >= 0).override_failure_message("stage 3 must repeat a word").is_true()
	assert_bool(renamed >= 0).override_failure_message("stage 3 must misname the player").is_true()
	# Readability: the struck/slashed words plus a substituted name still leave
	# every other word in order (checked on the text without the player name).
	(
		assert_bool(
			_words_survive("I don't know. I'm fine.", _run(3, "I don't know. I'm fine.", 3))
		)
		. is_true()
	)


func test_zalgo_and_redaction_start_at_stage_4() -> void:
	for seed_base: int in range(0, SEEDS):
		var stage_3 := _run(3, READABLE, seed_base)
		assert_int(_zalgo_marks(stage_3)).is_zero()
		assert_bool(stage_3.contains(REDACT)).is_false()
	var zalgo_seed := -1
	var redact_seed := -1
	for seed_base: int in range(0, SEEDS):
		var out := _run(4, READABLE, seed_base)
		if _zalgo_marks(out) > 0:
			zalgo_seed = seed_base
		if out.contains(REDACT):
			redact_seed = seed_base
	assert_bool(zalgo_seed >= 0).override_failure_message("stage 4 must burst zalgo").is_true()
	assert_bool(redact_seed >= 0).override_failure_message("stage 4 must redact").is_true()
	# The redaction is the Safety block character, so it reads as a redaction.
	var redacted := _run(4, READABLE, redact_seed)
	assert_bool(redacted.contains(REDACT.repeat(6))).is_true()
	# Zalgo decorates letters only, never spaces or punctuation.
	var zalgoed := _run(4, READABLE, zalgo_seed)
	for i: int in zalgoed.length():
		if ZALGO_MARKS.has(zalgoed[i]):
			assert_bool(i > 0 and zalgoed[i - 1].to_lower() != zalgoed[i - 1].to_upper()).is_true()


func test_text_bleed_and_reverse_start_at_stage_5() -> void:
	for seed_base: int in range(0, SEEDS):
		var stage_4 := _run(4, READABLE, seed_base)
		assert_bool(stage_4.contains(UNDER)).is_false()
		assert_bool(stage_4.contains("\n")).is_false()
	var bleed_seed := -1
	var reverse_seed := -1
	var expected_reverse := Corruption.reverse_text(Corruption.tail_sentence(READABLE))
	for seed_base: int in range(0, SEEDS):
		var out := _run(5, READABLE, seed_base)
		if out.contains(UNDER):
			bleed_seed = seed_base
		var lines := out.split("\n")
		if lines.size() > 1 and String(lines[lines.size() - 1]) == expected_reverse:
			reverse_seed = seed_base
	assert_bool(bleed_seed >= 0).override_failure_message("stage 5 must bleed").is_true()
	assert_bool(reverse_seed >= 0).override_failure_message("stage 5 must reverse").is_true()
	# The bleed is a second, indented line: the original line stays untouched.
	var bleed_out := _run(5, READABLE, bleed_seed)
	assert_str(String(bleed_out.split("\n")[0])).is_not_equal("")
	assert_bool(bleed_out.contains("\n      ")).is_true()


func test_seeded_output_is_reproducible() -> void:
	var first := _run(5, READABLE, 7)
	var second := _run(5, READABLE, 7)
	assert_str(second).is_equal(first)
	# A session re-run from the same beat seed produces the same text too.
	var session := _session(5, 7)
	assert_str(session.transform_beat(0, READABLE)).is_equal(first)
	# Different seeds must be able to choose different words/effects.
	var distinct := {}
	for seed_base: int in range(0, 8):
		distinct[_run(5, READABLE, seed_base)] = true
	assert_int(distinct.size()).is_greater(1)

	# The seed is a pure function of turn/beat/stage (docs/07 §3.4 seeded for
	# replay): a transcript replay re-derives it without storing RNG state.
	var base_seed := Corruption.seed_for(1, 0, 3)
	assert_int(Corruption.seed_for(1, 0, 3)).is_equal(base_seed)
	assert_int(Corruption.seed_for(1, 0, 3, 1)).is_not_equal(base_seed)
	assert_int(Corruption.seed_for(2, 0, 3)).is_not_equal(base_seed)
	assert_int(Corruption.seed_for(1, 1, 3)).is_not_equal(base_seed)
	assert_int(Corruption.seed_for(1, 0, 4)).is_not_equal(base_seed)


func test_stages_0_to_3_stay_readable() -> void:
	# Acceptance: text remains readable at stage <= 3. The property: every
	# original word survives, in order, and no glyph-destroying effect (zalgo,
	# redaction, bleed, underline) appears.
	for stage: int in range(0, 4):
		for seed_base: int in range(0, 16):
			var out := _run(stage, READABLE, seed_base)
			assert_bool(_words_survive(READABLE, out)).is_true()
			assert_int(_zalgo_marks(out)).is_zero()
			assert_bool(out.contains(REDACT)).is_false()
			assert_bool(out.contains(UNDER)).is_false()


func test_reduced_motion_removes_only_the_visual_effects() -> void:
	# The same seed with and without reduced motion must produce the same
	# readable text; only the zalgo glyphs and the bleed echo line disappear.
	for seed_base: int in range(0, 8):
		var normal := _run(5, READABLE, seed_base)
		var reduced := _run(5, READABLE, seed_base, {"reduced_motion": true})
		assert_str(_strip_visual(_without_bleed_lines(normal))).is_equal(reduced)
		assert_int(_zalgo_marks(reduced)).is_zero()
		assert_bool(reduced.contains(UNDER)).is_false()
	# The filter is still on under reduced motion: the textual effects fire.
	var textual := false
	for seed_base: int in range(0, SEEDS):
		var out := _run(5, READABLE, seed_base, {"reduced_motion": true})
		if out.contains(SLASH) or out.contains("— no,") or out.contains("\n"):
			textual = true
	assert_bool(textual).override_failure_message("textual effects must survive").is_true()


func test_calmer_mode_caps_the_stage() -> void:
	# docs/02 §8: calmer is a stage-3 run, bit for bit.
	for seed_base: int in range(0, 8):
		assert_str(_run(5, READABLE, seed_base, {"content_level": "calmer"})).is_equal(
			_run(3, READABLE, seed_base)
		)
	# The stage-5-only effects never appear under the cap.
	for seed_base: int in range(0, SEEDS):
		var out := _run(5, READABLE, seed_base, {"content_level": "calmer"})
		assert_int(_zalgo_marks(out)).is_zero()
		assert_bool(out.contains(REDACT)).is_false()
		assert_bool(out.contains(UNDER)).is_false()
		assert_bool(out.contains("\n")).is_false()


func test_missing_table_falls_back_to_the_docs_rows() -> void:
	assert_bool(Corruption.reload_table("user://p206_missing.json")).is_false()
	# The docs table is the same as the shipped one, so the observable
	# behaviour is unchanged.
	assert_str(Corruption.describe(Corruption.plan(5))).is_equal(
		"stage 5 · hesitate, strike, repeat, wrong_name, zalgo, redact, bleed, reverse"
	)
	assert_str(Corruption.strike_word("hate,")).is_equal(
		"h" + SLASH + "a" + SLASH + "t" + SLASH + "e" + SLASH + " — no, love,"
	)
	Corruption.clear_cache()
	assert_bool(Corruption.reload_table(TABLE_PATH)).is_true()


func test_strike_word_primitive() -> void:
	var slashed_hate := _slashed("hate")
	assert_str(Corruption.strike_word("hate,")).is_equal(slashed_hate + " — no, love,")
	assert_str(Corruption.strike_word("Hate!")).is_equal(_slashed("Hate") + " — no, Love!")
	assert_str(Corruption.strike_word("HATE?")).is_equal(_slashed("HATE") + " — no, LOVE?")
	# Quotes stay outside the self-correction, and the punctuation moves to the
	# correction instead of appearing twice.
	assert_str(Corruption.strike_word('"fine."')).is_equal(
		'"' + _slashed("fine") + ' — no, broken."'
	)
	# A non-pair is left to the caller (empty result = no change).
	assert_str(Corruption.strike_word("dog")).is_empty()
	assert_str(Corruption.strike_word("...")).is_empty()


func test_repeat_and_redact_word_primitives() -> void:
	assert_str(Corruption.repeat_word("fine.")).is_equal("fine fine.")
	assert_str(Corruption.repeat_word("don't")).is_equal("don't don't")
	# The data's minimum length keeps one-letter words from becoming stutters.
	assert_str(Corruption.repeat_word("a.")).is_empty()
	# docs/01 §3 "redactions █████": the same block Safety.gd uses, punctuation kept.
	assert_str(Corruption.redact_word("fine.")).is_equal(REDACT.repeat(6) + ".")
	assert_str(Corruption.redact_word("okay?")).is_equal(REDACT.repeat(6) + "?")
	assert_str(Corruption.redact_word("...")).is_empty()


func test_zalgo_primitive_is_seeded_and_letter_only() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var first := Corruption.zalgo("fine.", rng, 2, 2)
	rng.seed = 42
	var second := Corruption.zalgo("fine.", rng, 2, 2)
	assert_str(second).is_equal(first)
	# Two glyphs x two marks, and none of them on the full stop.
	assert_int(_count_marks(first, ZALGO_MARKS)).is_equal(4)
	assert_bool(first.begins_with("f")).is_true()
	assert_bool(first.ends_with(".")).is_true()
	for i: int in first.length():
		if not ZALGO_MARKS.has(first[i]):
			continue
		# Stacked marks are legal; walk back to the glyph they decorate and
		# assert it is a letter (never a space or the full stop).
		var glyph := i - 1
		while glyph >= 0 and ZALGO_MARKS.has(first[glyph]):
			glyph -= 1
		assert_bool(glyph >= 0).is_true()
		assert_bool(first[glyph].to_lower() != first[glyph].to_upper()).is_true()
	# A different seed produces a different burst.
	rng.seed = 7
	assert_str(Corruption.zalgo("fine.", rng, 2, 2)).is_not_equal(first)


func test_bleed_and_reverse_helpers() -> void:
	# The bleed echo is the tail of the line, indented and underlined.
	var bleed := Corruption.bleed_fragment("the end")
	assert_bool(bleed.begins_with("      ")).is_true()
	assert_bool(bleed.ends_with(" …")).is_true()
	var underline: Array[String] = [UNDER]
	assert_int(_count_marks(bleed, underline)).is_equal("theend".length())
	# …and the reversed line is the last sentence, mirrored.
	assert_str(Corruption.tail_words("one two three four", 2)).is_equal("three four")
	assert_str(Corruption.tail_words("one two", 9)).is_equal("one two")
	assert_str(Corruption.tail_sentence("Hello there. I am fine!")).is_equal("I am fine!")
	assert_str(Corruption.tail_sentence("Hello there. I am fine")).is_equal("I am fine")
	assert_str(Corruption.tail_sentence("")).is_equal("")
	assert_str(Corruption.reverse_text("Hello there. I am fine!")).is_equal(
		"!enif ma I .ereht olleH"
	)
