extends GdUnitTestSuite
## P2.11 — the store half of the docs/02 §6 memory model: 24 slots, importance,
## eviction ("oldest low-importance", never the fact just accepted), the save
## round trip, the per-turn record, and the seeded 10–25 % corruption of what
## the store injects from stage 3.
##
## The three proposal rules and the prompt half live in `MemoryTest`; the
## fixtures both suites share live in `tests/helpers/MemoryFixtures.gd`.

const MemoryRulesScript := preload("res://llm/MemoryRules.gd")
const MemoryStoreScript := preload("res://llm/MemoryStore.gd")
const Fixtures := preload("res://tests/helpers/MemoryFixtures.gd")


func before_test() -> void:
	MemoryRulesScript.clear_cache()
	Memory.reset()
	GameState.reset()
	GameState.player_name = "Ren"


func after_test() -> void:
	Memory.reset()
	GameState.reset()


func _store(texts: Array, importance := 1.0, seed := 0) -> Variant:
	return auto_free(Fixtures.store(texts, importance, seed))


func _store_rows(rows: Array, seed := 0) -> Variant:
	return auto_free(Fixtures.store_rows(rows, seed))


func _filler() -> Array[String]:
	return Fixtures.filler()


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
	for i: int in Fixtures.FILLER.size():
		var importance := 9.0 if i == 0 else 1.0
		rows.append({"text": "likes film " + Fixtures.FILLER[i], "importance": importance})
	var ranked: Variant = _store_rows(rows)
	var second: Dictionary = ranked.consider(
		"has a brother named Ren", ["My brother is named Ren."] as Array[String]
	)
	assert_bool(second["accepted"]).is_true()
	assert_str(second["evicted"]).is_equal("likes film bravo")
	assert_array(ranked.facts()).contains("likes film alpha")


func test_full_store_of_quoted_facts_still_learns_the_new_one() -> void:
	# r2 CODE-1/DES-3: every earlier fact has been quoted, so each sits at
	# importance 2.0+ while the newcomer arrives at 1.0 — the lowest. "Oldest
	# low-importance" must not pick the newest fact: the store would report
	# `accepted: true`, drop the fact it just accepted, and stop learning.
	var store: Variant = _store(_filler(), 2.0)
	var first: Dictionary = store.consider(
		"has a sister called Yuki", ["My sister is called Yuki."] as Array[String]
	)
	assert_bool(first["accepted"]).is_true()
	assert_int(store.size()).is_equal(24)
	assert_array(store.facts()).contains("has a sister called Yuki")
	# The victim is the oldest old fact, not the newcomer.
	assert_str(first["evicted"]).is_equal("likes film alpha")
	# Once she quotes it, importance is level with the rest and learning goes on:
	# the next fact takes the next oldest slot and both newcomers stay.
	store.note_quotes("Your sister is called Yuki, right?")
	var second: Dictionary = store.consider(
		"has a brother named Sora", ["My brother is named Sora."] as Array[String]
	)
	assert_bool(second["accepted"]).is_true()
	assert_array(store.facts()).contains("has a brother named Sora")
	assert_array(store.facts()).contains("has a sister called Yuki")
	assert_str(second["evicted"]).is_equal("likes film bravo")


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
	# A corrupt save cannot break the two invariants: 24 slots and importance
	# >= 0. Extra slots are trimmed by the live eviction rule, negatives heal.
	var rows: Array = []
	for i: int in 30:
		rows.append({"text": "likes film fact %d" % i, "importance": -3.0, "quotes": -1})
	var healed: Variant = _store_rows(rows)
	assert_int(healed.size()).is_equal(24)
	assert_float(healed.importances()[0]).is_zero()


func test_save_capacity_cannot_widen_the_store() -> void:
	# r2 CODE-4/DES-9: docs/02 §6 fixes the store at 24 slots. P2.20 hands save
	# JSON to `from_dict()`, so a hand-edited or half-written file is data, not
	# a wider store — capacity is clamped, not adopted.
	var rows: Array = []
	for i: int in 30:
		rows.append({"text": "likes film fact %d" % i, "importance": 1.0})
	var store: Variant = auto_free(MemoryStoreScript.new())
	store.from_dict({"capacity": 500, "entries": rows})
	assert_int(store.capacity).is_equal(MemoryRulesScript.capacity())
	assert_int(store.size()).is_equal(MemoryRulesScript.capacity())
	# A save asking for fewer slots still shrinks the store (it can only narrow).
	var small: Variant = auto_free(MemoryStoreScript.new())
	small.from_dict({"capacity": 2, "entries": rows})
	assert_int(small.capacity).is_equal(2)
	assert_int(small.size()).is_equal(2)


func test_consider_accepts_an_untyped_player_window() -> void:
	# r2 DES-8: P2.20 and tools may hand the facade a plain Array; it used to
	# abort inside `reject_reason(Array[String])` before writing last_proposal.
	var window: Array = ["I got you a gift — a little music box."]
	var decision: Dictionary = Memory.consider("gave me a music box", window)
	assert_bool(decision["accepted"]).is_true()
	assert_int(Memory.size()).is_equal(1)
	# A non-String element is stringified, not fatal: "12" is no content word,
	# so the candidate is ungrounded rather than a crash.
	var numbers: Array = [12]
	var decision2: Dictionary = Memory.consider("likes coffee", numbers)
	assert_bool(decision2["accepted"]).is_false()
	assert_str(decision2["reason"]).is_equal("ungrounded")


func test_begin_turn_drops_the_previous_turn_record() -> void:
	# r2 CODE-3/DES-6: the transcript's `memory` block is this turn's record. A
	# turn that builds no prompt (a refusal), fails, is cancelled, or whose model
	# sent "memory": "" must not report the previous turn's decision.
	var store: Variant = _store(["gave me a music box"], 1.0, 3)
	store.consider("likes coffee", ["I like coffee."] as Array[String])
	store.note_quotes("You gave me a music box.")
	var before: Dictionary = store.report()
	assert_bool((before["proposal"] as Dictionary)["accepted"]).is_true()
	assert_array(before["quotes"]).is_not_empty()
	store.begin_turn()
	var after: Dictionary = store.report()
	assert_dict(after["proposal"]).is_empty()
	assert_array(after["quotes"]).is_empty()
	assert_array(after["corruptions"]).is_empty()
	# The facts themselves are the store's memory, not a per-turn record.
	assert_array(after["facts"]).has_size(2)


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


func test_long_fact_without_a_name_or_number_still_corrupts() -> void:
	# r2 CODE-2/DES-2: the promise mutation used to be skipped when fact +
	# promise overflowed the proposal field's maxLength, so every 49–80 char fact
	# with no name and no number was corruption-proof at every stage.
	var fact := "she told me she used to live near the harbour with her sister"
	assert_int(fact.length()).is_greater(MemoryRulesScript.max_length() - 32)
	for change: Dictionary in _mutations(fact, 64):
		assert_str(_kind(change)).is_equal("false_promise")
		assert_str(_corrupted(change)).is_equal(fact + " — you told me you'd never leave")
	# And the realized rate for a store of such facts is the declared chance at
	# stage 5, not the fraction of facts the old guard allowed through.
	var texts: Array[String] = [
		"she told me she used to live near the harbour with her sister",
		"we walked along the river and talked about the old school building",
		"he said his father worked the night shift at the paper mill in town",
		"i remember the summer we spent fixing the boat behind the shed",
		"her grandmother kept a garden full of roses along the back wall",
		"they played the same record every evening until the neighbours complained",
		"the road to the lake was closed so we took the long way through the fields",
		"he kept every letter she wrote folded inside an old biscuit tin",
	]
	var store: Variant = _store(texts, 1.0, 7)
	var rolls := 0
	var hits := 0
	for i: int in 200:
		store.prompt_facts({"stage": 5})
		rolls += 8
		hits += (store.last_corruptions as Array).size()
	var rate := float(hits) / float(rolls)
	assert_float(rate).override_failure_message("measured %.3f" % rate).is_greater(0.18)
	assert_float(rate).is_less(0.32)


func test_name_swap_leaves_sentence_initial_words_alone() -> void:
	# r2 DES-1: "My" is a sentence-initial pronoun, not a name. docs/02 §6 asks
	# for a *subtly* altered memory; "Rin brother is called Ren" is broken
	# English the model may voice. The pool name at the end is the real target.
	var fact := "My brother is called Ren"
	var saw_swap := false
	for change: Dictionary in _mutations(fact, 64):
		if _kind(change) != "name_swap":
			continue
		saw_swap = true
		assert_str(_corrupted(change)).starts_with("My brother is called ")
	assert_bool(saw_swap).is_true()
	# A capitalised name inside the sentence is still a target.
	var saw_name := false
	for change: Dictionary in _mutations("was with Sarah today", 24):
		if _kind(change) == "name_swap":
			saw_name = true
			assert_str(_corrupted(change)).starts_with("was with ")
			assert_str(_corrupted(change)).ends_with(" today")
	assert_bool(saw_name).is_true()
	# A fact whose only capitalised word opens the sentence is left to the
	# promise mutation rather than being swapped into nonsense.
	for change: Dictionary in _mutations("Sarah came over after class", 64):
		assert_str(_kind(change)).is_not_equal("name_swap")


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
