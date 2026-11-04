extends GdUnitTestSuite
## P2.11 — the docs/02 §6 memory model at the Director boundary: the three
## proposal rules (including the doc's own "jealousy_bait" leak), the data
## contract, and the memories she reads in the built system prompt.
##
## Each rule is pinned to its doc§ with a literal expectation. The store's
## arithmetic (slots, importance, eviction, saves) and the seeded 10–25 %
## corruption live in `MemoryStoreTest`; the fixtures both suites share live in
## `tests/helpers/MemoryFixtures.gd`.

const MemoryRulesScript := preload("res://llm/MemoryRules.gd")
const MemoryStoreScript := preload("res://llm/MemoryStore.gd")
const PromptBuilderScript := preload("res://autoload/PromptBuilder.gd")
const TurnSchemaScript := preload("res://llm/TurnSchema.gd")
const TranscriptLoggerScript := preload("res://llm/TranscriptLogger.gd")
const Fixtures := preload("res://tests/helpers/MemoryFixtures.gd")

const DATA_PATH := "res://data/memory.json"
const GIFT_INPUT := "I got you a gift — a little music box."
const DEBUG_DIR := "user://memory_test_transcripts/"


func before_test() -> void:
	MemoryRulesScript.clear_cache()
	Memory.reset()
	GameState.reset()
	GameState.player_name = "Ren"


func after_test() -> void:
	Memory.reset()
	Director.reset()
	GameState.reset()


func _store(texts: Array, importance := 1.0, seed := 0) -> Variant:
	return auto_free(Fixtures.store(texts, importance, seed))


func _corrupted(change: Dictionary) -> String:
	return String(change.get("corrupted", ""))


## Structural compare of the data file against the in-code fallback; JSON numbers
## arrive as floats, so numerics compare approximately.
func _same(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		return _same_dict(left as Dictionary, right as Dictionary)
	if left is Array and right is Array:
		return _same_array(left as Array, right as Array)
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	return left == right


func _same_dict(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key: Variant in left:
		if not right.has(key) or not _same(left[key], right[key]):
			return false
	return true


func _same_array(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for i: int in left.size():
		if not _same(left[i], right[i]):
			return false
	return true


func _rm_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


# ------------------------------------------------------------- data contract


func test_data_file_matches_docs_fallback() -> void:
	# The fallback is only a safe degradation if it carries the same model.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	assert_bool(parsed is Dictionary).override_failure_message("memory.json unreadable").is_true()
	var file := parsed as Dictionary
	for key: Variant in MemoryRulesScript.DOCS_TABLE:
		var expected: Variant = MemoryRulesScript.DOCS_TABLE[key]
		var message := "%s drifted between memory.json and MemoryRules.DOCS_TABLE" % str(key)
		assert_bool(_same(expected, file.get(key))).override_failure_message(message).is_true()


func test_store_limits_are_the_documented_ones() -> void:
	# docs/02 §6 "24 slots"; docs/08 §1 "≤ 8 facts"; TurnSchema's maxLength.
	assert_int(MemoryRulesScript.capacity()).is_equal(24)
	assert_int(MemoryRulesScript.prompt_limit()).is_equal(PromptBuilderScript.MEMORY_LIMIT)
	assert_int(MemoryRulesScript.max_length()).is_equal(TurnSchemaScript.MEMORY_MAX_LENGTH)
	assert_float(MemoryRulesScript.duplicate_jaccard()).is_equal_approx(0.6, 0.0001)
	assert_int(MemoryStoreScript.new().capacity).is_equal(24)


# ------------------------------------------------- docs/02 §6 rules 1–3


func test_rule1_requires_a_shared_content_word() -> void:
	var inputs: Array[String] = ["I love rainy days and reading novels."]
	var existing: Array[String] = ["likes coffee"]
	# "novels" is shared -> accepted (the P1.08 fixture, still the doc's rule).
	assert_bool(MemoryRulesScript.validate("reads novels often", inputs, existing)).is_true()
	# Nothing shared -> the invented fact is rejected.
	assert_bool(MemoryRulesScript.validate("has three cats", inputs, existing)).is_false()
	assert_str(MemoryRulesScript.reject_reason("has three cats", inputs, existing)).is_equal(
		"ungrounded"
	)


func test_rule1_does_not_ground_on_a_stop_word() -> void:
	# A shared "the"/"is" must not launder an invented fact into the store; the
	# length floor alone (P1.08 CODE-10c) let exactly that through.
	var inputs: Array[String] = ["the question is hard"]
	var message := "a shared function word grounded an invented fact"
	(
		assert_bool(MemoryRulesScript.validate("the answer is three", inputs, [] as Array[String]))
		. override_failure_message(message)
		. is_false()
	)
	# The same sentence with one real content word does ground.
	(
		assert_bool(MemoryRulesScript.validate("the answer is hard", inputs, [] as Array[String]))
		. is_true()
	)


func test_rule1_is_fail_closed_without_a_player_window() -> void:
	# CODE-10b: with nothing said there is nothing to ground a fact in.
	(
		assert_bool(
			MemoryRulesScript.validate("has three cats", [] as Array[String], [] as Array[String])
		)
		. is_false()
	)


func test_rule2_rejects_the_jealousy_bait_leak() -> void:
	# docs/02 §6 rule 2, the doc's own observed leak: "The player used the phrase
	# 'jealousy_bait'…" — meta/schema vocabulary must never reach the store.
	var inputs: Array[String] = ["Sarah sat next to me in class today."]
	var leak := "The player used the phrase 'jealousy_bait' about Sarah"
	assert_bool(MemoryRulesScript.validate(leak, inputs, [] as Array[String])).is_false()
	assert_str(MemoryRulesScript.reject_reason(leak, inputs, [] as Array[String])).is_equal(
		"meta_word"
	)
	for word: String in MemoryRulesScript.DOCS_TABLE["meta_words"] as Array:
		var candidate := "Sarah said %s in class" % word
		var message := "meta word %s was accepted" % word
		(
			assert_str(MemoryRulesScript.reject_reason(candidate, inputs, [] as Array[String]))
			. override_failure_message(message)
			. is_equal("meta_word")
		)


func test_rule2_keeps_the_benign_music_box_fact() -> void:
	# P1.05 CON-2 regression: the few-shot's own fact must still be storable.
	var inputs: Array[String] = [GIFT_INPUT]
	(
		assert_bool(MemoryRulesScript.validate("gave me a music box", inputs, [] as Array[String]))
		. is_true()
	)


func test_rule2_rejects_every_intent_label() -> void:
	# docs/02 §6 rule 2 blocks "intent labels", and the doc's own leak is one of
	# them (`jealousy_bait`). The test walks the real `read` enum, so a label the
	# schema adds later cannot slip through the list — round 1 covered 2 of 17
	# (review r2 DES-4).
	var inputs: Array[String] = ["I told her about the harbour at the weekend."]
	for label: String in TurnSchemaScript.INTENTS:
		var candidate := "she talked about %s at the harbour" % label
		var message := "intent label %s is storable as a fact" % label
		(
			assert_str(MemoryRulesScript.reject_reason(candidate, inputs, [] as Array[String]))
			. override_failure_message(message)
			. is_equal("meta_word")
		)


func test_rule3_rejects_near_duplicates() -> void:
	var inputs: Array[String] = ["I read a lot of novels and riddles."]
	var existing: Array[String] = ["reads old novels"]
	# 2 shared of 3 union = 0.667 >= 0.6 -> duplicate.
	assert_str(MemoryRulesScript.reject_reason("reads novels", inputs, existing)).is_equal(
		"duplicate"
	)
	# Below the threshold (1 of 3 = 0.333) is a new fact, not a duplicate.
	assert_bool(MemoryRulesScript.validate("reads riddles", inputs, existing)).is_true()
	# Jaccard itself: 2 of 4 = 0.5 is under the documented 0.6 duplicate line.
	(
		assert_float(
			MemoryRulesScript.jaccard(
				["reads", "old", "novels"] as Array[String],
				["reads", "novels", "often"] as Array[String]
			)
		)
		. is_equal_approx(0.5, 0.0001)
	)


func test_rule3_compares_content_words_not_raw_tokens() -> void:
	# docs/02 §6 says "token Jaccard"; the implementation compares content words
	# on both sides, which is the reading (a function word must not pad two
	# unrelated facts into a duplicate). Pinned here so it cannot drift
	# (review r2 DES-5): "likes coffee a lot" is the same fact as "likes coffee"
	# — 0.667 by content words (duplicate), 0.5 as raw tokens (stored again).
	var inputs: Array[String] = ["I drink a lot of coffee."]
	var existing: Array[String] = ["likes coffee a lot"]
	assert_str(MemoryRulesScript.reject_reason("likes coffee", inputs, existing)).is_equal(
		"duplicate"
	)
	var content := MemoryRulesScript.jaccard(
		MemoryRulesScript.content_words("likes coffee"),
		MemoryRulesScript.content_words("likes coffee a lot")
	)
	assert_float(content).is_equal_approx(0.6667, 0.001)
	var raw := MemoryRulesScript.jaccard(
		MemoryRulesScript.tokenize("likes coffee"), MemoryRulesScript.tokenize("likes coffee a lot")
	)
	assert_float(raw).is_equal_approx(0.5, 0.0001)


func test_reject_reason_names_the_rule() -> void:
	var inputs: Array[String] = ["I work at the harbour with my sister Yuki."]
	var empty: Array[String] = []
	assert_str(MemoryRulesScript.reject_reason("   ", inputs, empty)).is_equal("empty")
	assert_str(MemoryRulesScript.reject_reason("x".repeat(120), inputs, empty)).is_equal("too_long")
	assert_str(MemoryRulesScript.reject_reason("of the and", inputs, empty)).is_equal("no_content")
	assert_str(MemoryRulesScript.reject_reason("stage 2", inputs, empty)).is_equal("meta_word")
	assert_str(MemoryRulesScript.reject_reason("owns a boat", inputs, empty)).is_equal("ungrounded")
	assert_str(MemoryRulesScript.reject_reason("sister Yuki", inputs, empty)).is_equal("")
	(
		assert_str(
			MemoryRulesScript.reject_reason("sister Yuki", inputs, ["sister Yuki"] as Array[String])
		)
		. is_equal("duplicate")
	)


# ------------------------------------------------- "she quotes memories" (AC3)


func test_prompt_carries_the_memories_she_reads() -> void:
	# Stage 0: the fact reaches the docs/08 §1 [memories] layer verbatim.
	Memory.consider("gave me a music box", [GIFT_INPUT] as Array[String])
	assert_int(Memory.size()).is_equal(1)
	var prompt := PromptBuilder.build(Director.build_turn_context("Do you like it?"))
	var system := String(prompt["messages"][0]["content"])
	assert_str(system).contains("Things you know about Ren:")
	assert_str(system).contains("gave me a music box")

	# Stage 5: what she reads is the corrupted variant, and it is the one the
	# store logged — the prompt is corruption's only destination.
	GameState.instability = 95.0  # docs/01 §3 stage 5
	assert_int(GameState.stage).is_equal(5)
	var seed := -1
	for candidate: int in 100:
		Memory.set_rng_seed(candidate)
		Director.build_turn_context("Do you remember the box?")
		if not (Memory.report()["corruptions"] as Array).is_empty():
			seed = candidate
			break
	assert_int(seed).is_greater_equal(0)
	Memory.set_rng_seed(seed)  # replay that seed for the asserted injection
	var corrupted_ctx := Director.build_turn_context("Do you remember the box?")
	var report: Dictionary = Memory.report()
	var changes: Array = report["corruptions"]
	assert_array(changes).is_not_empty()
	var stage5 := String(PromptBuilder.build(corrupted_ctx)["messages"][0]["content"])
	var bullet := PromptBuilderScript.MEMORY_BULLET
	var bullets: Array[String] = []
	for line: String in stage5.split("\n"):
		if line.begins_with(bullet):
			bullets.append(line)
	for change: Dictionary in changes:
		assert_array(bullets).contains(bullet + _corrupted(change))
		# The bullet she reads is the false version, as a whole line: a
		# false_promise keeps the original as a prefix, so a substring check
		# would pass on the true text too (this test caught exactly that).
		var original_line := bullet + String(change["original"])
		assert_bool(bullets.has(original_line)).is_false()
	# The store still knows the truth the prompt no longer shows.
	assert_array(Memory.facts()).contains("gave me a music box")


# ------------------------------------------------------------ corruption log


func test_turn_transcript_records_the_corruption_log() -> void:
	# "corruption seeded + logged": the audit trail is the turn transcript, and a
	# field the logger does not list is silently dropped — TranscriptLogger.
	# OPTIONAL_FIELDS gained "memory" in this task, so the round trip is asserted
	# here rather than trusted.
	_rm_dir(DEBUG_DIR)
	var store: Variant = _store(["was with Sarah today", "gave me a music box"], 1.0, 5)
	var seed := -1
	for candidate: int in 100:
		store.set_rng_seed(candidate)
		store.prompt_facts({"stage": 5})
		if not (store.last_corruptions as Array).is_empty():
			seed = candidate
			break
	assert_int(seed).is_greater_equal(0)
	store.set_rng_seed(seed)
	store.prompt_facts({"stage": 5})
	assert_array(store.last_corruptions).is_not_empty()

	var logger: Variant = auto_free(TranscriptLoggerScript.new())
	logger.configure({"debug_dir": DEBUG_DIR})
	logger.start_session()
	var logged: bool = (
		logger
		. log_turn(
			{
				"turn": 1,
				"prompt": [{"role": "system", "content": "sys"}],
				"schema": {"type": "object"},
				"output": "",
				"memory": store.report(),
			}
		)
	)
	assert_bool(logged).is_true()
	logger.flush()
	var loaded: Dictionary = TranscriptLoggerScript.load_transcript(logger.current_file())
	logger.close()
	assert_array(loaded["errors"]).is_empty()

	var turn_record: Dictionary = {}
	for record: Dictionary in loaded["records"]:
		if String(record.get("type", "")) == "turn":
			turn_record = record
	var message := "the transcript dropped the memory block"
	assert_bool(turn_record.has("memory")).override_failure_message(message).is_true()
	var memory: Dictionary = turn_record["memory"]
	assert_int(int(memory["count"])).is_equal(2)
	assert_array(memory["facts"]).contains("was with Sarah today")
	var changes: Array = memory["corruptions"]
	assert_array(changes).is_not_empty()
	assert_bool((changes[0] as Dictionary).has("corrupted")).is_true()
	assert_bool((changes[0] as Dictionary).has("kind")).is_true()
	_rm_dir(DEBUG_DIR)


func test_refusal_record_does_not_carry_the_previous_turn_memory() -> void:
	# r2 CODE-3/DES-6: an unsafe input never opens a turn, so its record must not
	# report the previous turn's proposal, quotes or corruptions — that field is
	# "why she just refused to remember".
	_rm_dir(DEBUG_DIR)
	Memory.consider("gave me a music box", [GIFT_INPUT] as Array[String])
	var seed := -1
	for candidate: int in 100:
		Memory.set_rng_seed(candidate)
		Memory.prompt_facts({"stage": 5})
		if not (Memory.report()["corruptions"] as Array).is_empty():
			seed = candidate
			break
	assert_int(seed).is_greater_equal(0)
	Memory.note_quotes("You gave me a music box.")
	var before: Dictionary = Memory.report()
	assert_bool((before["proposal"] as Dictionary)["accepted"]).is_true()
	assert_array(before["quotes"]).is_not_empty()
	assert_array(before["corruptions"]).is_not_empty()

	Director.transcript_logger.configure({"debug_dir": DEBUG_DIR})
	Director._reject_unsafe_input()
	Director.transcript_logger.flush()
	var loaded: Dictionary = TranscriptLoggerScript.load_transcript(
		Director.transcript_logger.current_file()
	)
	Director.transcript_logger.end_session()
	assert_array(loaded["errors"]).is_empty()
	var record: Dictionary = {}
	for entry: Dictionary in loaded["records"]:
		if String(entry.get("type", "")) == "turn":
			record = entry
	var message := "the refusal record is missing its memory block"
	assert_bool(record.has("memory")).override_failure_message(message).is_true()
	var memory: Dictionary = record["memory"]
	assert_dict(memory["proposal"]).is_empty()
	assert_array(memory["quotes"]).is_empty()
	assert_array(memory["corruptions"]).is_empty()
	# The store's facts are not a per-turn record: a refusal forgets nothing.
	assert_array(memory["facts"]).contains("gave me a music box")
	_rm_dir(DEBUG_DIR)
