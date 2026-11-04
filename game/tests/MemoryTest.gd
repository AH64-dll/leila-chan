extends GdUnitTestSuite
## P2.11 — the docs/02 §6 memory model: the three proposal rules (including the
## doc's own "jealousy_bait" leak), the 24-slot store with importance and
## eviction, and the seeded 10–25 % corruption from stage 3 that she then reads
## in the prompt.
##
## Each rule is pinned to its doc§ with a literal expectation. The corruption
## tests are seeded, so they assert an exact replay and a measured rate instead
## of "looks random". The prompt half goes through Director -> Memory ->
## PromptBuilder, i.e. the same path a real turn takes.

const MemoryRulesScript := preload("res://llm/MemoryRules.gd")
const MemoryStoreScript := preload("res://llm/MemoryStore.gd")
const PromptBuilderScript := preload("res://autoload/PromptBuilder.gd")
const TurnSchemaScript := preload("res://llm/TurnSchema.gd")
const TranscriptLoggerScript := preload("res://llm/TranscriptLogger.gd")

const DATA_PATH := "res://data/memory.json"
const GIFT_INPUT := "I got you a gift — a little music box."
const DEBUG_DIR := "user://memory_test_transcripts/"

## 24 distinct short facts: distinct content words, so none is a near-duplicate
## of another and every eviction assertion has a predictable victim.
const FILLER := [
	"alpha",
	"bravo",
	"charlie",
	"delta",
	"echo",
	"foxtrot",
	"golf",
	"hotel",
	"india",
	"juliet",
	"kilo",
	"lima",
	"mike",
	"november",
	"oscar",
	"papa",
	"quebec",
	"romeo",
	"sierra",
	"tango",
	"uniform",
	"victor",
	"whiskey",
	"xray",
]


func before_test() -> void:
	MemoryRulesScript.clear_cache()
	Memory.reset()
	GameState.reset()
	GameState.player_name = "Ren"


func after_test() -> void:
	Memory.reset()
	Director.reset()
	GameState.reset()


# ----------------------------------------------------------------- fixtures


func _store(texts: Array, importance := 1.0, seed := 0) -> Variant:
	var rows: Array = []
	for text: String in texts:
		rows.append({"text": text, "importance": importance, "quotes": 0})
	return _store_rows(rows, seed)


func _store_rows(rows: Array, seed := 0) -> Variant:
	var store: Variant = auto_free(MemoryStoreScript.new())
	store.from_dict({"entries": rows})
	store.set_rng_seed(seed)
	return store


func _filler() -> Array[String]:
	var facts: Array[String] = []
	for word: String in FILLER:
		facts.append("likes film " + word)
	return facts


## Every distinct mutation `corrupt()` produces for `fact` over `tries` seeds.
func _mutations(fact: String, tries: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seed: int in tries:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var change := MemoryRulesScript.corrupt(fact, rng)
		if not change.is_empty():
			out.append(change)
	return out


func _kind(change: Dictionary) -> String:
	return String(change.get("kind", ""))


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


# -------------------------------------------------- slots, importance, saves


func test_store_holds_24_slots_and_evicts_the_oldest_low_importance() -> void:
	var store: Variant = _store(_filler(), 1.0)
	assert_int(store.size()).is_equal(24)
	# A 25th fact evicts the oldest of the lowest importance — "oldest
	# low-importance evicted" is old-then-important, not importance alone.
	var result: Dictionary = store.consider(
		"has a sister called Yuki", ["My sister is called Yuki."] as Array[String]
	)
	assert_bool(result["accepted"]).is_true()
	assert_int(store.size()).is_equal(24)
	assert_str(result["evicted"]).is_equal("likes film alpha")
	# Raise slot 0 high: the next eviction takes slot 1, the oldest of the rest.
	var rows: Array = []
	for i: int in FILLER.size():
		rows.append({"text": "likes film " + FILLER[i], "importance": 9.0 if i == 0 else 1.0})
	var ranked: Variant = _store_rows(rows)
	var second: Dictionary = ranked.consider(
		"has a brother named Ren", ["My brother is named Ren."] as Array[String]
	)
	assert_bool(second["accepted"]).is_true()
	assert_str(second["evicted"]).is_equal("likes film bravo")
	assert_array(ranked.facts()).contains("likes film alpha")


func test_importance_increments_when_she_quotes_the_fact() -> void:
	var store: Variant = _store(["gave me a music box"], 1.0)
	assert_array([1.0]).is_equal(store.importances())
	# 3 of 3 content words back at her: a quote, so importance +1 (docs/02 §6).
	var quoted: Array = store.note_quotes("You gave me a music box, remember?")
	assert_array(quoted).is_equal(["gave me a music box"])
	assert_array([2.0]).is_equal(store.importances())
	# Each turn she quotes it is +1 (not each word, not each mention).
	store.note_quotes("a music box, my music box")
	assert_array([3.0]).is_equal(store.importances())
	# A single coincidental word is 1 of 3 = 0.333, under the threshold.
	var bumps: Array = store.note_quotes("I found a box in the attic")
	assert_array(bumps).is_empty()
	assert_array([3.0]).is_equal(store.importances())


func test_store_save_round_trip_keeps_importance_and_seed() -> void:
	var store: Variant = _store(["likes coffee", "gave me a music box"], 1.0, 42)
	store.note_quotes("You gave me a music box.")
	var saved: Dictionary = store.to_dict()
	var restored: Variant = auto_free(MemoryStoreScript.new())
	restored.from_dict(saved)
	assert_array(restored.facts()).is_equal(store.facts())
	assert_array(restored.importances()).is_equal(store.importances())
	assert_int(restored.rng_seed()).is_equal(42)
	# And the restored store replays the same corruption as the original.
	assert_array(restored.prompt_facts({"stage": 5})).is_equal(store.prompt_facts({"stage": 5}))


# ------------------------------------------------------- docs/02 §6 corruption


func test_corruption_chance_matches_the_documented_band() -> void:
	# "from stage 3 … 10–25% are subtly altered" and nothing before it.
	assert_float(MemoryRulesScript.corruption_chance(0)).is_zero()
	assert_float(MemoryRulesScript.corruption_chance(2)).is_zero()
	assert_float(MemoryRulesScript.corruption_chance(3)).is_equal_approx(0.10, 0.0001)
	assert_float(MemoryRulesScript.corruption_chance(4)).is_equal_approx(0.175, 0.0001)
	assert_float(MemoryRulesScript.corruption_chance(5)).is_equal_approx(0.25, 0.0001)
	# Measured, not just declared: 800 rolls at stage 5 land near 25 %.
	var store: Variant = _store(_filler(), 1.0, 21)
	var rolls := 0
	var hits := 0
	for i: int in 100:
		store.prompt_facts({"stage": 5})
		rolls += 8
		hits += (store.last_corruptions as Array).size()
	var rate := float(hits) / float(rolls)
	assert_float(rate).override_failure_message("measured %.3f" % rate).is_greater(0.18)
	assert_float(rate).is_less(0.32)


func test_corruption_mutations_cover_the_docs_examples() -> void:
	# docs/02 §6: "a name swapped, a number off by one, 'you told me you'd never
	# leave'". Each example is reachable and keeps the rest of the fact intact.
	var saw_name := false
	for change: Dictionary in _mutations("was with Sarah today", 24):
		if _kind(change) == "name_swap":
			saw_name = true
			assert_bool(_corrupted(change).contains("Sarah")).is_false()
			assert_bool(_corrupted(change).contains("today")).is_true()
	assert_bool(saw_name).is_true()

	var saw_number := false
	for change: Dictionary in _mutations("has 3 cats", 24):
		if _kind(change) == "number_off_by_one":
			saw_number = true
			assert_bool(["has 2 cats", "has 4 cats"].has(_corrupted(change))).is_true()
	assert_bool(saw_number).is_true()
	var saw_word := false
	for change: Dictionary in _mutations("has three cats", 24):
		if _kind(change) == "number_off_by_one":
			saw_word = true
			assert_bool(["has two cats", "has four cats"].has(_corrupted(change))).is_true()
	assert_bool(saw_word).is_true()

	# No name and no number: the invented promise is the only kind that applies.
	for change: Dictionary in _mutations("gave me a music box", 24):
		assert_str(_kind(change)).is_equal("false_promise")
		assert_bool(_corrupted(change).contains("you told me you'd never leave")).is_true()


func test_corruption_is_seeded_and_logged() -> void:
	var texts: Array[String] = ["was with Sarah today", "has 3 cats", "gave me a music box"]
	var left: Variant = _store(texts, 1.0, 11)
	var right: Variant = _store(texts, 1.0, 11)
	var before: Array = left.facts()
	var kinds: Array = MemoryRulesScript.DOCS_TABLE["corruption"]["kinds"]
	var logged := 0
	for i: int in 40:
		var left_facts: Array = left.prompt_facts({"stage": 5})
		# Same seed, same store -> the same prompt facts, every turn.
		assert_array(left_facts).is_equal(right.prompt_facts({"stage": 5}))
		for change: Dictionary in left.last_corruptions:
			logged += 1
			assert_bool(kinds.has(_kind(change))).is_true()
			assert_bool(_corrupted(change) != String(change["original"])).is_true()
			assert_bool(before.has(String(change["original"]))).is_true()
			assert_bool(left_facts.has(_corrupted(change))).is_true()
	assert_int(logged).is_greater(0)
	# Corruption is a display lie: the stored facts never change.
	assert_array(left.facts()).is_equal(before)


func test_no_corruption_below_stage_3() -> void:
	var store: Variant = _store(_filler(), 1.0, 9)
	for stage: int in [0, 1, 2]:
		for i: int in 40:
			store.prompt_facts({"stage": stage})
			var message := "corruption leaked into stage %d" % stage
			assert_array(store.last_corruptions).override_failure_message(message).is_empty()


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


func _rm_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
