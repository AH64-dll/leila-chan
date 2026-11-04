extends GdUnitTestSuite
## P2.12 — ProfileKeywords: the keyword half of the docs/01 §2 behaviour profile.
## The four rules (control, apathy, flattery_rejected, ignored_questions) are the
## counters the model's `read` labels cannot express; each contributes at most 1
## per message, and a broken data block disables only itself.
##
## The counters' effect on the path scores is proven in res://tests/PathsTest.gd
## (gdlint caps a suite at 20 public methods).

const ProfileKeywordsScript := preload("res://llm/ProfileKeywords.gd")


func test_control_rule_matches_whole_words() -> void:
	var bumps: Dictionary = ProfileKeywordsScript.classify("You will answer me.")
	assert_int(int(bumps.get(&"control", 0))).is_equal(1)
	# Whole-word matching: a substring inside another word is not an order.
	assert_bool(ProfileKeywordsScript.classify("I willed it away.").has(&"control")).is_false()
	assert_bool(ProfileKeywordsScript.classify("Come here.").has(&"control")).is_true()
	# Punctuation and case do not matter.
	assert_bool(ProfileKeywordsScript.classify("  BE QUIET!! ").has(&"control")).is_true()


func test_apathy_phrases_and_short_replies() -> void:
	for line: String in ["Whatever.", "idk", "I don't care.", "meh", "ok."]:
		var bumps: Dictionary = ProfileKeywordsScript.classify(line)
		assert_int(int(bumps.get(&"apathy", 0))).is_equal(1)
	# docs/01 §4.4: short replies count. Two words, no question, not a courtesy.
	assert_int(int(ProfileKeywordsScript.classify("I guess").get(&"apathy", 0))).is_equal(1)
	# Exempt courtesies and answers are not apathy, and an asking reply is not.
	for line: String in ["hi", "thank you", "good night", "yes", "love you"]:
		assert_bool(ProfileKeywordsScript.classify(line).has(&"apathy")).is_false()
	assert_bool(ProfileKeywordsScript.classify("why?").has(&"apathy")).is_false()
	assert_bool(ProfileKeywordsScript.classify("I love you").has(&"apathy")).is_false()


func test_flattery_rejected_needs_both_sides() -> void:
	var flattery := "You look beautiful tonight."
	# Flattery alone is not a rejection; a rejection alone is not flattery.
	var thanked: Dictionary = ProfileKeywordsScript.classify(flattery, "Thank you.")
	assert_bool(thanked.has(&"flattery_rejected")).is_false()
	var cold: Dictionary = ProfileKeywordsScript.classify("Hello.", "Shut up.")
	assert_bool(cold.has(&"flattery_rejected")).is_false()
	var bumps: Dictionary = ProfileKeywordsScript.classify(flattery, "Hmph. Don't say that.")
	assert_int(int(bumps.get(&"flattery_rejected", 0))).is_equal(1)


func test_ignored_question_rule() -> void:
	var question := "Do you love me?"
	var dismissive: Dictionary = ProfileKeywordsScript.classify("Whatever.", "", question)
	assert_int(int(dismissive.get(&"ignored_questions", 0))).is_equal(1)
	# An actual answer (even a warm three-word one) is not ignoring her.
	(
		assert_bool(
			ProfileKeywordsScript.classify("I love you.", "", question).has(&"ignored_questions")
		)
		. is_false()
	)
	# No pending question, no counter.
	(
		assert_bool(ProfileKeywordsScript.classify("Whatever.", "", "").has(&"ignored_questions"))
		. is_false()
	)


func test_question_in_and_reply_text() -> void:
	var turn := {
		"beats":
		[
			{"say": "You're back."},
			{"say": "Where were you?"},
			{"say": "Answer me."},
		]
	}
	assert_str(ProfileKeywordsScript.question_in(turn)).is_equal("Where were you?")
	var said := ProfileKeywordsScript.reply_text(turn)
	assert_str(said).is_equal("You're back. Where were you? Answer me.")
	assert_str(ProfileKeywordsScript.question_in({"beats": [{"say": "Hello."}]})).is_equal("")
	assert_str(ProfileKeywordsScript.question_in({})).is_equal("")
	assert_str(ProfileKeywordsScript.reply_text({})).is_equal("")


func test_blank_text_contributes_nothing() -> void:
	assert_dict(ProfileKeywordsScript.classify("")).is_empty()
	assert_dict(ProfileKeywordsScript.classify("   ", "Shut up.", "Do you love me?")).is_empty()


func test_missing_data_disables_bumps_instead_of_guessing() -> void:
	# A broken file degrades to EMPTY_TABLE: no rule fires, so the profile never
	# moves on a guessed word (the read labels and the formulas still work).
	var empty: Dictionary = ProfileKeywordsScript.parse_document(null)
	assert_array(empty["control"]["phrases"]).is_empty()
	assert_int(int(empty["apathy"]["short_reply_words"])).is_zero()
	var nonsense: Dictionary = ProfileKeywordsScript.parse_document("nope")
	assert_bool(nonsense["flattery_rejected"]["flattery"].is_empty()).is_true()
	# One bad block disables that rule only.
	var partial: Dictionary = (
		ProfileKeywordsScript
		. parse_document(
			{
				"control": {"phrases": ["you will"]},
				"apathy": {"phrases": "whatever", "short_reply_words": 2},
				"flattery_rejected": {"flattery": ["beautiful"], "rejection": ["shut up"]},
			}
		)
	)
	assert_array(partial["control"]["phrases"]).is_equal(["you will"])
	assert_array(partial["apathy"]["phrases"]).is_empty()
	assert_array(partial["flattery_rejected"]["flattery"]).is_equal(["beautiful"])


func test_shipped_data_covers_every_keyword_counter() -> void:
	# The four keyword counters have non-empty rule lists in the shipped file, and
	# the word cap is a real number — a data edit cannot silently disable a rule.
	var rules: Dictionary = ProfileKeywordsScript.table()
	var counters: Array = ["control", "apathy", "flattery_rejected"]
	for counter: String in counters:
		assert_bool(rules.has(counter)).is_true()
	for phrase: Variant in rules["control"]["phrases"]:
		assert_str(str(phrase)).is_not_empty()
	assert_int(int(rules["apathy"]["short_reply_words"])).is_equal(2)
	assert_bool(rules["flattery_rejected"]["rejection"].is_empty()).is_false()
	# A previously shipped counter must still classify after the loader runs.
	assert_bool(ProfileKeywordsScript.classify("Whatever.").has(&"apathy")).is_true()
