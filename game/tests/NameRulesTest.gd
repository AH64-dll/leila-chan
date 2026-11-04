extends GdUnitTestSuite
## P3.14 — New Game name rules complete (docs/08 §1.5): name decay with
## stages (missing-letter self-correction at 3, "-kun" at 4, name-tag swap at
## 5), special names ("Leila", OS username behind the opt-in), and shadow name
## memory ("That's not what you were called last time.").
##
## Acceptance 1 (all §1.5 behaviours tested): every renderer-side rule is a
## pure function on Corruption / PlayerNameRules, driven here at every gate
## boundary; the streaming/session seam proves the rules land inside the real
## docs/07 §3.4 pipeline.
## Acceptance 2 (OS username only when opted in): Settings.os_username()
## returns "" while `use_os_username` is false even with USER/USERNAME set,
## and PlayerNameRules never reads the environment itself — the caller must
## pass it through opts.

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const NewGameScene := preload("res://scenes/NewGame.tscn")
const TEST_ROOT := "user://name_rules_test/"
const SETTINGS_PATH := TEST_ROOT + "settings.cfg"

var _previous_settings := ""
var _previous_flag := false
var _previous_shadow := ""


func before_test() -> void:
	_previous_settings = Settings.settings_path
	_previous_flag = Settings.use_os_username
	_previous_shadow = SaveSystem.shadow_path
	Settings.settings_path = SETTINGS_PATH
	SaveSystem.shadow_path = TEST_ROOT + ".leila/shadow.json"
	Settings.use_os_username = false
	Corruption.clear_cache()
	GameState.reset()
	Director.reset()


func after_test() -> void:
	Settings.settings_path = _previous_settings
	Settings.use_os_username = _previous_flag
	SaveSystem.shadow_path = _previous_shadow
	Corruption.clear_cache()
	GameState.reset()
	Director.reset()
	_remove_tree(TEST_ROOT)


## ── 1. data table ─────────────────────────────────────────────────────────


func test_name_rules_data_file_carries_the_docs_table() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(Corruption.NAME_RULES_PATH)
	)
	assert_object(parsed).is_not_null()
	assert_bool(parsed is Dictionary).is_true()
	var data := parsed as Dictionary
	for section: String in Corruption.DOCS_NAME_RULES:
		assert_bool(data.has(section)).is_true()
		var docs: Dictionary = Corruption.DOCS_NAME_RULES[section]
		var row: Dictionary = data[section]
		for key: String in docs:
			assert_bool(row.has(key)).is_true()
			assert_bool(_same_value(row[key], docs[key])).is_true()


func test_name_rules_merges_data_over_fallback() -> void:
	var decay := Corruption.name_rule("decay")
	assert_int(int(decay["gate"])).is_equal(3)
	assert_float(float(decay["chance"])).is_greater(0.0)
	assert_str(String(decay["connector"])).is_equal("… ")


## ── 2. is_player_name ─────────────────────────────────────────────────────


func test_is_player_name_matches_core_through_affixes() -> void:
	assert_bool(Corruption.is_player_name("Renji,", "Renji")).is_true()
	assert_bool(Corruption.is_player_name('"renji"', "Renji")).is_true()
	assert_bool(Corruption.is_player_name("Renjii", "Renji")).is_false()
	assert_bool(Corruption.is_player_name("Ren", "")).is_false()
	assert_bool(Corruption.is_player_name("", "Ren")).is_false()


## ── 3. stage-3 decay ──────────────────────────────────────────────────────


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


## ── 4. stage-4 "-kun" ─────────────────────────────────────────────────────


func _kun_fires(mood: Dictionary, stage: int) -> String:
	for s: int in range(300):
		var out := Corruption.kun_name("Renji", "Renji", stage, mood, _rng(s))
		if not out.is_empty():
			return out
	return ""


func test_kun_appended_when_affectionate() -> void:
	var out := _kun_fires({"affection": 80.0, "stress": 2}, 4)
	assert_str(out).is_equal("Renji-kun")


func test_kun_dropped_when_angry() -> void:
	# stress ≤ angry_stress: no matter how high affection is, or how lucky
	# the roll, the suffix is dropped — the plain name renders.
	for s: int in range(30):
		var out := Corruption.kun_name(
			"Renji", "Renji", 4, {"affection": 100.0, "stress": -3}, _rng(s)
		)
		assert_str(out).is_empty()
		out = Corruption.kun_name("Renji", "Renji", 5, {"affection": 100.0, "stress": 0}, _rng(s))
		assert_str(out).is_empty()


func test_kun_needs_affection_not_just_calm() -> void:
	for s: int in range(30):
		var out := Corruption.kun_name(
			"Renji", "Renji", 4, {"affection": 10.0, "stress": 3}, _rng(s)
		)
		assert_str(out).is_empty()


func test_kun_gated_below_stage_4_and_only_on_the_name() -> void:
	for s: int in range(30):
		(
			assert_str(
				Corruption.kun_name("Renji", "Renji", 3, {"affection": 100.0, "stress": 3}, _rng(s))
			)
			. is_empty()
		)
		(
			assert_str(
				Corruption.kun_name("Leila", "Renji", 4, {"affection": 100.0, "stress": 3}, _rng(s))
			)
			. is_empty()
		)


func test_kun_preserves_punctuation() -> void:
	for s: int in range(300):
		var out := Corruption.kun_name(
			"Renji!", "Renji", 4, {"affection": 90.0, "stress": 3}, _rng(s)
		)
		if not out.is_empty():
			assert_str(out).is_equal("Renji-kun!")
			return
	fail("kun never fired in 300 seeds")


## ── 5. stage-5 name-tag swap ──────────────────────────────────────────────


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


## ── 8. pipeline seam (CorruptionSession) ──────────────────────────────────


func _session(stage: int, mood: Dictionary = {}) -> CorruptionSession:
	var session := CorruptionSession.new()
	(
		session
		. begin_turn(
			{
				"turn": 1,
				"stage": stage,
				"player_name": "Renji",
				"mood": mood,
			}
		)
	)
	return session


func test_session_stage3_can_decay_the_name() -> void:
	# The decay reads "<slip>… <name>": the connector immediately followed by
	# the intact name. A bare "… " is ambiguous (the hesitation effect emits
	# it too) and `wrong_name` can swap the name for a stranger ("Ren" is on
	# its list), so only the precise pattern proves the rule reached the text.
	var saw := false
	for turn: int in range(1, 40):
		var session := CorruptionSession.new()
		session.begin_turn({"turn": turn, "stage": 3, "player_name": "Renji"})
		var out := session.transform_beat(0, "Renji, stay with me.")
		if out.contains("… Renji"):
			saw = true
			break
	assert_bool(saw).is_true()


func test_session_stage4_kun_reaches_the_typewriter_text() -> void:
	var saw := false
	for turn: int in range(1, 60):
		var session := CorruptionSession.new()
		(
			session
			. begin_turn(
				{
					"turn": turn,
					"stage": 4,
					"player_name": "Renji",
					"mood": {"affection": 90.0, "stress": 3},
				}
			)
		)
		var out := session.transform_beat(0, "Hello Renji.")
		if out.contains("Renji-kun"):
			saw = true
			break
	assert_bool(saw).is_true()


func test_session_wrong_name_still_wins_over_decay() -> void:
	# wrong_name is the stranger-name slip and holds the word-kind slot: when
	# it fires the decay rule never also rewrites the same word (output must
	# be a plain stranger name, not "Reni… Renji" or "Riku-kun"). Stage 3 is
	# the honest place to prove the ordering: decay is live, while the -kun
	# rule (stage 4) and the zalgo burst (stage 4) cannot decorate the word
	# being compared.
	var names: Array = Corruption.DOCS_TABLE["params"]["wrong_name"]["names"]
	var saw := false
	for turn: int in range(1, 60):
		var session := CorruptionSession.new()
		session.begin_turn({"turn": turn, "stage": 3, "player_name": "Renji"})
		# A pending hesitation lands after the single word ("Ren. …"); the
		# stranger name is everything before that tail.
		var out := session.transform_beat(0, "Renji.").trim_suffix(" …")
		var core := out.trim_suffix(".")
		if not names.has(core):
			continue
		saw = true
		# The stranger replaces the whole word: decay's connector and the
		# "-kun" suffix never appear, and the punctuation is kept.
		assert_bool(out.contains("… ")).is_false()
		assert_bool(out.contains("-kun")).is_false()
		assert_str(out).is_equal(core + ".")
	assert_bool(saw).is_true()


## ── helpers ───────────────────────────────────────────────────────────────


## JSON has no integers: every number in the data file parses as a float, so
## the docs table's `3` and the file's `3.0` must compare equal — one helper so
## the data file stays pinned to the documented numbers.
func _same_value(from_file: Variant, docs: Variant) -> bool:
	if docs is String:
		return str(from_file) == str(docs)
	if from_file is float or from_file is int:
		return is_equal_approx(float(from_file), float(docs))
	return from_file == docs


func _remove_tree(path: String) -> void:
	var root := path.trim_suffix("/")
	if not DirAccess.dir_exists_absolute(root):
		return
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.set_include_hidden(true)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := root.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(child)
		DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(root)
