extends GdUnitTestSuite
## P3.14 — the renderer-side name rules themselves (docs/08 §1.5): the
## is_player_name gate (with the multi-word token), stage-3 decay, stage-4
## "-kun", the stage-5 log-tag swap, and the rules running inside the real
## docs/07 §3.4 corruptor (CorruptionSession).
##
## Sibling suites keep every file inside gdlint's max-public-methods:
## `NameRulesLoaderTest.gd` owns the data file and the reload seam,
## `NameRulesSpecialsTest.gd` the pure special-name lines,
## `NameRulesPipelineTest.gd` the CorruptionSession seam, and
## `NewGameNameRulesTest.gd` the New Game scene, opt-in gate and shadow memory.


func before_test() -> void:
	Corruption.clear_cache()


func after_test() -> void:
	Corruption.clear_cache()


## ── 1. is_player_name ─────────────────────────────────────────────────────


func test_is_player_name_matches_core_through_affixes() -> void:
	assert_bool(Corruption.is_player_name("Renji,", "Renji")).is_true()
	assert_bool(Corruption.is_player_name('"renji"', "Renji")).is_true()
	assert_bool(Corruption.is_player_name("Renjii", "Renji")).is_false()
	assert_bool(Corruption.is_player_name("Ren", "")).is_false()
	assert_bool(Corruption.is_player_name("", "Ren")).is_false()


func test_multi_word_name_matches_on_its_last_word() -> void:
	# The field accepts spaces ("Mary Jane"), but the pipeline is word-serial:
	# a rule can only decorate the token it sees, so it decorates the given
	# name — the last word. Round 1 compared the whole name and never fired.
	assert_str(Corruption.name_token("Mary Jane")).is_equal("Jane")
	assert_str(Corruption.name_token("  Renji  ")).is_equal("Renji")
	assert_bool(Corruption.is_player_name("Jane,", "Mary Jane")).is_true()
	assert_bool(Corruption.is_player_name("Mary", "Mary Jane")).is_false()


func test_multi_word_name_decays_and_takes_kun() -> void:
	var decayed := ""
	for s: int in range(200):
		decayed = Corruption.decay_name("Jane", "Mary Jane", 3, _rng(s))
		if not decayed.is_empty():
			break
	assert_str(decayed).ends_with("… Jane")
	var kuned := ""
	for s: int in range(300):
		kuned = Corruption.kun_name(
			"Jane", "Mary Jane", 4, {"affection": 90.0, "stress": 0}, _rng(s)
		)
		if not kuned.is_empty():
			break
	assert_str(kuned).is_equal("Jane-kun")


## ── 2. stage-3 decay ──────────────────────────────────────────────────────


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _decay_fires(word: String, stage: int) -> String:
	# chance 0.5: try a spread of seeds — the rule is seeded, not "always".
	for s: int in range(200):
		var out := Corruption.decay_name(word, "Renji", stage, _rng(s))
		if not out.is_empty():
			return out
	return ""


func test_decay_drops_one_letter_and_corrects_it() -> void:
	var out := _decay_fires("Renji", 3)
	assert_str(out).is_not_empty()
	var halves := out.split("… ")
	assert_int(halves.size()).is_equal(2)
	var short := halves[0]
	assert_int(short.length()).is_equal(4)
	# the slip is the name minus exactly one letter
	var removed := false
	for i: int in "Renji".length():
		if "Renji".substr(0, i) + "Renji".substr(i + 1) == short:
			removed = true
	assert_bool(removed).is_true()
	assert_str(halves[1]).is_equal("Renji")


func test_decay_preserves_surrounding_punctuation() -> void:
	for s: int in range(200):
		var out := Corruption.decay_name("Renji,", "Renji", 3, _rng(s))
		if not out.is_empty():
			assert_str(out).ends_with(",")
			return
	fail("decay never fired for punctuated name in 200 seeds")


func test_decay_gated_below_stage_3() -> void:
	for s: int in range(20):
		assert_str(Corruption.decay_name("Renji", "Renji", 2, _rng(s))).is_empty()
		assert_str(Corruption.decay_name("Renji", "Renji", 0, _rng(s))).is_empty()


func test_decay_leaves_other_words_and_one_letter_names_alone() -> void:
	for s: int in range(20):
		assert_str(Corruption.decay_name("Haru", "Renji", 3, _rng(s))).is_empty()
		assert_str(Corruption.decay_name("Q", "Q", 3, _rng(s))).is_empty()


func test_decay_chance_is_a_roll_not_a_certainty() -> void:
	var fired := 0
	for s: int in range(40):
		if not Corruption.decay_name("Renji", "Renji", 3, _rng(s)).is_empty():
			fired += 1
	# "occasionally": with chance 0.5 over 40 seeds this is 0 or 40 only when
	# the roll is broken.
	assert_int(fired).is_greater(0)
	assert_int(fired).is_less(40)


## ── 3. stage-4 "-kun" ─────────────────────────────────────────────────────


func _kun_fires(mood: Dictionary, stage: int) -> String:
	for s: int in range(300):
		var out := Corruption.kun_name("Renji", "Renji", stage, mood, _rng(s))
		if not out.is_empty():
			return out
	return ""


func test_kun_appended_when_affectionate() -> void:
	# docs/02 §1.1: a POSITIVE stress suggestion is the turn that raised
	# Instability — the angry one. The affectionate turn is the calm one.
	var out := _kun_fires({"affection": 80.0, "stress": 0}, 4)
	assert_str(out).is_equal("Renji-kun")
	# A negative suggestion (she calmed down) is affectionate too.
	assert_str(_kun_fires({"affection": 80.0, "stress": -3}, 4)).is_equal("Renji-kun")


func test_kun_dropped_when_angry() -> void:
	# stress > angry_stress is the angry turn: no matter how high affection is,
	# or how lucky the roll, the suffix is dropped — the plain name renders.
	for s: int in range(30):
		for stress: int in [1, 3]:
			var angry := Corruption.kun_name(
				"Renji", "Renji", 4, {"affection": 100.0, "stress": stress}, _rng(s)
			)
			assert_str(angry).is_empty()
		var late := Corruption.kun_name(
			"Renji", "Renji", 5, {"affection": 100.0, "stress": 3}, _rng(s)
		)
		assert_str(late).is_empty()


func test_kun_follows_the_mood_sign_not_the_roll() -> void:
	# The regression pin for the inverted sign (round 1 appended it exactly on
	# the turns her stress rose). At affection 100 over 200 seeds the calm
	# turns fire on roughly the data chance (0.6) and the angry turns never do.
	var calm := 0
	var angry := 0
	for s: int in range(200):
		if not (
			Corruption
			. kun_name("Renji", "Renji", 4, {"affection": 100.0, "stress": 0}, _rng(s))
			. is_empty()
		):
			calm += 1
		if not (
			Corruption
			. kun_name("Renji", "Renji", 4, {"affection": 100.0, "stress": 3}, _rng(s))
			. is_empty()
		):
			angry += 1
	assert_int(angry).is_equal(0)
	assert_int(calm).is_greater(60)
	assert_int(calm).is_less(200)


func test_kun_needs_affection_not_just_calm() -> void:
	for s: int in range(30):
		var out := Corruption.kun_name(
			"Renji", "Renji", 4, {"affection": 10.0, "stress": 0}, _rng(s)
		)
		assert_str(out).is_empty()


func test_kun_gated_below_stage_4_and_only_on_the_name() -> void:
	for s: int in range(30):
		(
			assert_str(
				Corruption.kun_name("Renji", "Renji", 3, {"affection": 100.0, "stress": 0}, _rng(s))
			)
			. is_empty()
		)
		(
			assert_str(
				Corruption.kun_name("Leila", "Renji", 4, {"affection": 100.0, "stress": 0}, _rng(s))
			)
			. is_empty()
		)


func test_kun_preserves_punctuation() -> void:
	for s: int in range(300):
		var out := Corruption.kun_name(
			"Renji!", "Renji", 4, {"affection": 90.0, "stress": 0}, _rng(s)
		)
		if not out.is_empty():
			assert_str(out).is_equal("Renji-kun!")
			return
	fail("kun never fired in 300 seeds")


## ── 4. stage-5 name-tag swap ──────────────────────────────────────────────


func test_tag_swap_gated_below_stage_5() -> void:
	for turn: int in range(1, 20):
		assert_bool(Corruption.should_swap_name_tag(4, turn, 0)).is_false()
		assert_bool(Corruption.should_swap_name_tag(0, turn, 0)).is_false()


func test_tag_swap_rolls_per_turn_and_is_replayable() -> void:
	var fired := 0
	for turn: int in range(1, 40):
		var yes := Corruption.should_swap_name_tag(5, turn, 0)
		if yes:
			fired += 1
		# deterministic: same inputs, same answer
		assert_bool(Corruption.should_swap_name_tag(5, turn, 0)).is_equal(yes)
	assert_int(fired).is_greater(0)
	assert_int(fired).is_less(39)
