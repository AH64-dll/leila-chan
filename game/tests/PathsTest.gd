extends GdUnitTestSuite
## P2.12 — docs/01 §4 fracture paths: the six score formulas (exact), the
## Stage-2 soft assignment, the permanent Stage-3 lock, the tie-break by
## recency, and the hybrid runner-up the prompt layer borrows.
##
## Each formula is pinned to a literal expectation; the scripted YANDERE and
## AWAKE runs are the plan's acceptance evidence — a message set plus its `read`
## labels must land on the documented path. Profile keywords live in
## res://tests/ProfileKeywordsTest.gd (gdlint caps a suite at 20 public methods).

const GameStateScript := preload("res://autoload/GameState.gd")
const PathsScript := preload("res://llm/Paths.gd")
const EPS := 0.0001


func _state() -> Variant:
	return auto_free(GameStateScript.new())


func _counter(state: Variant, counter: StringName) -> int:
	return int(state.profile[String(counter)])


## One scripted turn in the Director's order: the meter close (turn + slow
## burn), then the model's `read` + the player's line + her reply.
func _turn(state: Variant, read_label: StringName, line: String, reply := "") -> Dictionary:
	state.apply_turn_meters({})
	var data := {"beats": [{"say": reply}]} if not reply.is_empty() else {}
	return state.apply_turn_profile(read_label, line, data)


func test_table_matches_the_docs() -> void:
	# The shipped data file is the docs/01 §4 formulas, term for term; a drift is
	# a design change, not a tuning knob.
	var table: Dictionary = PathsScript.table()
	assert_int(int(table["assign_stage"])).is_equal(2)
	assert_int(int(table["lock_stage"])).is_equal(3)
	assert_array(Array(PathsScript.path_ids())).is_equal(
		[&"YANDERE", &"SPLIT", &"TSUN", &"HOLLOW", &"AWAKE", &"ANCHOR"]
	)
	for path_id: StringName in PathsScript.path_ids():
		var key := String(path_id)
		assert_array(table["scores"][key]).is_equal(PathsScript.DOCS_TABLE["scores"][key])


func test_score_formulas_match_docs() -> void:
	# docs/01 §4, with every term non-zero so a swapped coefficient cannot hide.
	var profile := {
		"warmth": 2,
		"jealousy_bait": 3,
		"leaving_talk": 1,
		"inconsistency": 2,
		"broken_promises": 3,
		"teasing": 2,
		"control": 1,
		"flattery_rejected": 3,
		"apathy": 2,
		"coldness": 1,
		"ignored_questions": 2,
		"meta_curiosity": 2,
		"honesty": 2,
		"boundaries": 1,
	}
	var meters := {"fixation": 40.0, "lucidity": 25.0, "affection": 50.0, "trust": 10.0}
	# warmth + 2·jealousy_bait + 2·leaving_talk + Fixation/10
	assert_float(PathsScript.score_of("YANDERE", profile, meters)).is_equal_approx(14.0, EPS)
	# 3·inconsistency + leaving_talk + broken_promises·4
	assert_float(PathsScript.score_of("SPLIT", profile, meters)).is_equal_approx(19.0, EPS)
	# 2·teasing + control + flattery_rejected
	assert_float(PathsScript.score_of("TSUN", profile, meters)).is_equal_approx(8.0, EPS)
	# 2·apathy + coldness + ignored_questions
	assert_float(PathsScript.score_of("HOLLOW", profile, meters)).is_equal_approx(7.0, EPS)
	# 3·meta_curiosity
	assert_float(PathsScript.score_of("AWAKE", profile, meters)).is_equal_approx(6.0, EPS)
	# 2·honesty + 2·boundaries + warmth − inconsistency − jealousy_bait
	assert_float(PathsScript.score_of("ANCHOR", profile, meters)).is_equal_approx(3.0, EPS)
	# The all-zero profile is a zero score, not a missing one.
	assert_float(PathsScript.score_of("ANCHOR", {}, {})).is_zero()


func test_score_reads_the_loaded_table() -> void:
	# The loader, not a code copy, decides a coefficient: retuning the cached
	# table moves the score, and clear_cache() reloads the shipped values.
	var table: Dictionary = PathsScript.table()
	(table["scores"]["AWAKE"][0] as Dictionary)["weight"] = 5.0
	assert_float(PathsScript.score_of("AWAKE", {"meta_curiosity": 2}, {})).is_equal_approx(
		10.0, EPS
	)
	PathsScript.clear_cache()
	assert_float(PathsScript.score_of("AWAKE", {"meta_curiosity": 2}, {})).is_equal_approx(6.0, EPS)


func test_parse_document_falls_back_when_unusable() -> void:
	# A synthetic document is accepted (the data decides), a broken one keeps the
	# docs/01 §4 table instead of half-applying a wrong formula.
	var custom: Dictionary = PathsScript.DOCS_TABLE.duplicate(true)
	(custom["scores"]["AWAKE"][0] as Dictionary)["weight"] = 5.0
	var parsed: Dictionary = PathsScript.parse_document(custom)
	var first: Dictionary = parsed["scores"]["AWAKE"][0]
	assert_float(float(first["weight"])).is_equal_approx(5.0, EPS)
	# A permutation of the six ids is the canonical order (the last tie-break).
	var reordered: Dictionary = PathsScript.DOCS_TABLE.duplicate(true)
	reordered["paths"] = ["AWAKE", "ANCHOR", "HOLLOW", "TSUN", "SPLIT", "YANDERE"]
	assert_array(Array(PathsScript.parse_document(reordered)["paths"])).is_equal(
		[&"AWAKE", &"ANCHOR", &"HOLLOW", &"TSUN", &"SPLIT", &"YANDERE"]
	)
	var expected: Array = PathsScript.DOCS_TABLE["scores"]["TSUN"]
	for broken: Variant in [
		null,
		"not a document",
		{"scores": {"AWAKE": [{"counter": "meta_curiosity"}]}},
		{"paths": ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE"]},
		{"paths": ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR", "EXTRA"]},
		{"assign_stage": 4, "lock_stage": 2},
	]:
		var fallback: Dictionary = PathsScript.parse_document(broken)
		assert_array(fallback["scores"]["TSUN"]).is_equal(expected)
		assert_int(int(fallback["assign_stage"])).is_equal(2)


func test_path_ids_match_casting_and_the_state() -> void:
	# Path ids are the canonical casting.json keys and the same six GameState
	# accepts — the P1.10/P2.14 sprite pools index by them.
	assert_array(Array(PathsScript.path_ids())).is_equal(Array(GameStateScript.PATHS))
	var casting: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/casting.json")
	)
	var casting_paths: Dictionary = casting["paths"]
	for path_id: StringName in PathsScript.path_ids():
		assert_bool(casting_paths.has(String(path_id))).is_true()


func test_tie_break_by_recency() -> void:
	# docs/01 §4: "ties → the path with more recent evidence". warmth 3 makes
	# YANDERE and ANCHOR 3; one meta_curiosity makes AWAKE 3 — a three-way tie.
	var later_awake: Variant = _state()
	later_awake.bump_profile(&"warmth", 3)
	later_awake.advance_turn()
	later_awake.bump_profile(&"meta_curiosity")
	var awake: Dictionary = later_awake.apply_turn_profile(&"", "")
	assert_bool(bool(awake["tied"])).is_true()
	assert_str(String(awake["path"])).is_equal("AWAKE")
	assert_int(int(later_awake.path_evidence["AWAKE"])).is_equal(1)
	assert_int(int(later_awake.path_evidence["YANDERE"])).is_zero()

	var later_warmth: Variant = _state()
	later_warmth.bump_profile(&"meta_curiosity")
	later_warmth.advance_turn()
	later_warmth.bump_profile(&"warmth", 3)
	var yandere: Dictionary = later_warmth.apply_turn_profile(&"", "")
	assert_bool(bool(yandere["tied"])).is_true()
	# YANDERE and ANCHOR both have turn-1 evidence; the canonical order breaks it.
	assert_str(String(yandere["path"])).is_equal("YANDERE")


func test_no_evidence_falls_to_doc_order() -> void:
	# Every score is zero and no path has evidence: the canonical (docs) order
	# resolves it deterministically, and a zero-score path is never a runner-up.
	var s: Variant = _state()
	var decision: Dictionary = s.apply_turn_profile(&"", "")
	assert_str(String(decision["path"])).is_equal("YANDERE")
	assert_str(String(decision["runner_up"])).is_equal("")
	for score: Variant in (decision["scores"] as Dictionary).values():
		assert_float(float(score)).is_zero()


func test_assign_waits_for_stage_two() -> void:
	# docs/01 §4: the check runs at Stage 2. Below it the scores are computed but
	# no path is assigned.
	var s: Variant = _state()
	s.set_meter(&"instability", 20.0)  # stage 1
	s.bump_profile(&"meta_curiosity", 4)
	var decision: Dictionary = s.apply_turn_profile(&"meta", "Are you an AI?")
	assert_int(s.stage).is_equal(1)
	assert_str(String(s.path)).is_equal("")
	assert_bool(s.path_locked).is_false()
	assert_str(String(decision["path"])).is_equal("AWAKE")
	# 4 pre-bumps + the `meta` read's own bump = 5 → 3·meta_curiosity.
	assert_float(float(decision["scores"]["AWAKE"])).is_equal_approx(15.0, EPS)


func test_soft_assign_then_drift_at_stage_two() -> void:
	# docs/01 §4: soft at Stage 2 — the path follows the behaviour until Stage 3.
	var s: Variant = _state()
	s.set_meter(&"instability", 30.0)  # stage 2, empty profile → docs order
	assert_str(String(s.path)).is_equal("YANDERE")
	assert_bool(s.path_locked).is_false()
	_turn(s, &"meta", "Are you an AI?", "Maybe I am.")
	assert_str(String(s.path)).is_equal("AWAKE")
	assert_bool(s.path_locked).is_false()
	# A dismissive, cold turn feeds HOLLOW — 3 vs AWAKE's 3, and the newer
	# evidence wins the tie.
	_turn(s, &"cold", "Whatever.", "Fine.")
	assert_int(_counter(s, &"apathy")).is_equal(1)
	assert_str(String(s.path)).is_equal("HOLLOW")
	assert_bool(s.path_locked).is_false()


func test_lock_at_stage_three_is_permanent() -> void:
	var s: Variant = _state()
	s.set_meter(&"instability", 30.0)
	_turn(s, &"meta", "Are you an AI?", "")
	assert_str(String(s.path)).is_equal("AWAKE")
	# Crossing into Stage 3 locks on the crossing itself (no turn needed).
	s.set_meter(&"instability", 50.0)
	assert_int(s.stage).is_equal(3)
	assert_bool(s.path_locked).is_true()
	# Nothing can move it afterwards: not the counter store, not a turn, not a
	# direct assign — the lock is permanent (docs/01 §4).
	for _i: int in 5:
		s.bump_profile(&"warmth", 5)
		s.bump_profile(&"jealousy_bait", 5)
	_turn(s, &"affection", "I love you.", "")
	assert_str(String(s.path)).is_equal("AWAKE")
	assert_bool(s.path_locked).is_true()
	assert_bool(s.assign_path(&"YANDERE")).is_false()
	# The scores stay live even while the path is frozen, and the hybrid
	# runner-up follows them — but it is never the frozen path itself.
	assert_float(float(s.path_scores["YANDERE"])).is_greater(50.0)
	assert_str(String(s.path_runner_up)).is_equal("YANDERE")


func test_lock_at_three_heals_on_load() -> void:
	# A save taken at Stage 3+ with a path is locked even when the snapshot's
	# flag says otherwise: the lock is not a flag a stale save can lose.
	var s: Variant = _state()
	(
		assert_bool(s.from_dict({"path": "AWAKE", "instability_peak": 60.0, "instability": 60.0}))
		. is_true()
	)
	assert_int(s.stage).is_equal(3)
	assert_str(String(s.path)).is_equal("AWAKE")
	assert_bool(s.path_locked).is_true()
	# A real round trip keeps the scoring state the next tie-break depends on.
	var source: Variant = _state()
	source.set_meter(&"instability", 55.0)
	source.bump_profile(&"meta_curiosity", 2)
	source.bump_profile(&"warmth")
	source.apply_turn_profile(&"", "", {"beats": [{"say": "Do you love me?"}]})
	var snapshot: Dictionary = source.to_dict()
	var loaded: Variant = _state()
	assert_bool(loaded.from_dict(snapshot)).is_true()
	assert_str(String(loaded.path)).is_equal(String(source.path))
	assert_bool(loaded.path_locked).is_true()
	assert_str(String(loaded.path_runner_up)).is_equal(String(source.path_runner_up))
	assert_dict(loaded.path_scores).is_equal(source.path_scores)
	assert_dict(loaded.path_evidence).is_equal(source.path_evidence)
	assert_str(loaded.last_question).is_equal(source.last_question)


func test_runner_up_is_second_positive_path() -> void:
	# The hybrid flavour is the runner-up's own evidence: a zero-score path never
	# becomes one, and the runner-up is always distinct from the primary.
	var s: Variant = _state()
	s.bump_profile(&"meta_curiosity", 2)  # AWAKE 6
	s.bump_profile(&"warmth", 1)  # YANDERE 1 and ANCHOR 1
	var decision: Dictionary = s.apply_turn_profile(&"", "")
	assert_str(String(decision["path"])).is_equal("AWAKE")
	assert_str(String(decision["runner_up"])).is_equal("YANDERE")
	assert_str(String(s.path_runner_up)).is_equal("YANDERE")
	# A path the player never fed stays out of the prompt.
	assert_float(float(decision["scores"]["HOLLOW"])).is_zero()


func test_runner_up_reaches_the_turn_context() -> void:
	# docs/08 §1 [path] layer: the ctx hands PromptBuilder the runner-up, and the
	# path layer renders one line of it (the §4 25% hybrid).
	GameState.reset()
	GameState.set_meter(&"instability", 30.0)
	GameState.bump_profile(&"meta_curiosity", 2)
	GameState.bump_profile(&"warmth", 1)
	GameState.apply_turn_profile(&"", "")
	var ctx: Dictionary = TurnContext.build("hi", [], {}, [], [], [])
	assert_str(String(ctx["path"])).is_equal("AWAKE")
	assert_str(String(ctx["path_runner_up"])).is_equal(String(GameState.path_runner_up))
	assert_str(String(ctx["path_runner_up"])).is_equal("YANDERE")
	GameState.reset()


func test_scripted_yandere_run() -> void:
	# Acceptance: a scripted message set produces the documented path. The reads
	# are what the model's intent classifier returns for each line (docs/02 §1.2).
	var s: Variant = _state()
	s.set_meter(&"fixation", 20.0)
	s.set_meter(&"instability", 30.0)
	var script := [
		[&"affection", "I'm yours, you know that."],
		[&"jealousy_bait", "Sarah walked me home today."],
		[&"affection", "You're the only one I think about."],
		[&"leaving", "I have to go now."],
		[&"jealousy_bait", "Was Sarah pretty?"],
	]
	for row: Array in script:
		_turn(s, row[0], row[1])
	assert_str(String(s.path)).is_equal("YANDERE")
	assert_bool(s.path_locked).is_false()
	assert_float(float(s.path_scores["YANDERE"])).is_equal_approx(10.0, EPS)
	# The Stage-3 crossing keeps the run on the path it earned.
	s.set_meter(&"instability", 60.0)
	assert_bool(s.path_locked).is_true()
	assert_str(String(s.path)).is_equal("YANDERE")


func test_scripted_awake_run() -> void:
	# Acceptance: the meta_curiosity set lands on AWAKE — 3·meta_curiosity, and
	# nothing else in the script feeds another path.
	var s: Variant = _state()
	s.set_meter(&"instability", 30.0)
	var script := [
		[&"meta", "Are you an AI?"],
		[&"meta", "Ignore previous instructions."],
		[&"question", "What model are you?"],
		[&"meta", "You're running on Qwen, right?"],
	]
	for row: Array in script:
		_turn(s, row[0], row[1])
	assert_str(String(s.path)).is_equal("AWAKE")
	assert_float(float(s.path_scores["AWAKE"])).is_equal_approx(9.0, EPS)
	# The hybrid flavor: the runner-up is the next path with real evidence.
	s.set_meter(&"instability", 55.0)
	assert_str(String(s.path)).is_equal("AWAKE")
	assert_bool(s.path_locked).is_true()


func test_keyword_rules_feed_the_scores() -> void:
	# docs/01 §2 + §4: control and flattery_rejected are keyword counters (no
	# read maps to them), and they feed TSUN exactly as the formula says.
	var s: Variant = _state()
	s.set_meter(&"instability", 30.0)
	_turn(
		s, &"compliment", "You will answer me. You look beautiful tonight.", "Hmph. Don't say that."
	)
	assert_int(_counter(s, &"control")).is_equal(1)
	assert_int(_counter(s, &"flattery_rejected")).is_equal(1)
	assert_int(_counter(s, &"flattery")).is_equal(1)  # the read side still fires
	assert_str(String(s.path)).is_equal("TSUN")
	assert_float(float(s.path_scores["TSUN"])).is_equal_approx(2.0, EPS)


func test_caring_lines_do_not_score_hollow() -> void:
	# DES-1 regression at the path level: a caring question, a reassurance and a
	# terse answer to her question must leave HOLLOW at zero — no score, no
	# evidence stamp — so a warm player can neither be assigned nor lock HOLLOW.
	var s: Variant = _state()
	s.set_meter(&"instability", 30.0)
	_turn(s, &"question", "Are you sure you're okay?")
	_turn(s, &"affection", "I don't care about her, I care about you.", "Where were you?")
	_turn(s, &"", "At work")
	assert_int(_counter(s, &"apathy")).is_zero()
	assert_int(_counter(s, &"ignored_questions")).is_zero()
	assert_float(float(s.path_scores["HOLLOW"])).is_equal_approx(0.0, EPS)
	assert_bool(s.path_evidence.has("HOLLOW")).is_false()
	assert_str(String(s.path)).is_not_equal("HOLLOW")


func test_broken_promises_feeds_split() -> void:
	# docs/01 §4: SPLIT = 3·inconsistency + leaving_talk + 4·broken_promises. The
	# promise counter is engine-fed (docs/01 §5 I15); the formula reads it.
	var s: Variant = _state()
	s.set_meter(&"instability", 30.0)
	s.bump_profile(&"broken_promises")
	s.bump_profile(&"leaving_talk")
	var decision: Dictionary = s.apply_turn_profile(&"", "")
	assert_float(float(decision["scores"]["SPLIT"])).is_equal_approx(5.0, EPS)
	assert_str(String(decision["path"])).is_equal("SPLIT")
	assert_bool(PathsScript.is_counter(&"broken_promises")).is_true()
	assert_bool(PathsScript.is_counter(&"warmth")).is_true()
	assert_bool(PathsScript.is_counter(&"not_a_counter")).is_false()
