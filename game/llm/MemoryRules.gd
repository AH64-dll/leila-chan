class_name MemoryRules
extends RefCounted
## MemoryRules — docs/02 §6: the three proposal rules, the store's arithmetic
## (importance, eviction) and the corruption band with its mutations. Split out
## of Director.gd in P1.08 and extended into the full memory model in P2.11; the
## store itself is MemoryStore.
##
## The three rules (docs/02 §6):
##   1. the candidate shares >= 1 content word with the last 3 player messages
##      (blocks invented facts),
##   2. it contains no schema/meta words (rule 2 — the doc's own example is
##      "The player used the phrase 'jealousy_bait'…", which rule 2 rejects;
##      the list holds schema keys *and* every `read` intent label),
##   3. it is not a near-duplicate (< 0.6 Jaccard against the stored facts,
##      measured over content words — the reading is documented on `jaccard`).
##
## Rule 1 is fail-closed: with no player window there is nothing to ground the
## fact in, so the candidate is rejected instead of accepted (P1.08 CODE-10b).
##
## A "content word" is longer than `min_content_word_length` AND not in the
## data's `stop_words`. The length floor alone (P1.08 CODE-10c) was too weak:
## "the" clears it, and one shared function word grounded a wholly invented
## fact. Short content words ("cat", "job") are still given up — the doc's rule
## is about grounding, and grounding on a function word is worse than missing a
## two-letter noun.
##
## The numbers live in res://data/memory.json. DOCS_TABLE below is the fallback
## and the value set `MemoryTest.test_data_file_matches_docs_fallback()` pins, so
## a broken file degrades to the documented model instead of to no rules. The
## formulas are fixed by the bible: if one is wrong in play, the fix is a DCR
## plus a data edit, never a quiet tweak here.

const TABLE_PATH := "res://data/memory.json"

## docs/01 §5 T13 "contradict a remembered fact (lie)": the settled reading is
## deliberately plain — a message that denies ("never", "didn't", …) *and*
## shares a content word with a stored fact is a contradiction. The cue list and
## the shared-word floor are the trigger row's own data (data/triggers.json,
## guard.contradicts_memory); these constants are the fallback a bare `true`
## gets, so the row is the only place to tune the detector.
const DEFAULT_NEGATIONS: Array[String] = [
	"never",
	"not true",
	"didn't",
	"did not",
	"don't",
	"do not",
	"wasn't",
	"was not",
	"that's a lie",
	"that is a lie",
	"you're wrong",
	"you are wrong",
	"never said",
	"never told",
	"i didn't say",
	"i never",
]
const DEFAULT_SHARED_WORDS := 1

## docs/02 §6 + docs/08 §1 as code (the fallback table, pinned equal to the file
## by the suite). Stage 6+ cannot exist (docs/01 §3 stops at 5).
const DOCS_TABLE := {
	"capacity": 24,
	"prompt_limit": 8,
	"max_length": 80,
	"duplicate_jaccard": 0.6,
	"min_content_word_length": 3,
	"quote_overlap": 0.5,
	"stop_words":
	[
		"the",
		"a",
		"an",
		"and",
		"or",
		"but",
		"if",
		"then",
		"than",
		"so",
		"because",
		"as",
		"of",
		"to",
		"in",
		"on",
		"at",
		"for",
		"with",
		"without",
		"from",
		"by",
		"about",
		"into",
		"over",
		"after",
		"before",
		"between",
		"through",
		"during",
		"up",
		"down",
		"out",
		"off",
		"again",
		"just",
		"very",
		"too",
		"also",
		"only",
		"own",
		"same",
		"such",
		"all",
		"any",
		"some",
		"more",
		"most",
		"much",
		"many",
		"few",
		"no",
		"not",
		"yes",
		"this",
		"that",
		"these",
		"those",
		"there",
		"here",
		"what",
		"who",
		"whom",
		"which",
		"when",
		"where",
		"why",
		"how",
		"i",
		"you",
		"he",
		"she",
		"it",
		"we",
		"they",
		"me",
		"him",
		"her",
		"them",
		"us",
		"my",
		"your",
		"his",
		"its",
		"our",
		"their",
		"am",
		"is",
		"are",
		"was",
		"were",
		"be",
		"been",
		"being",
		"have",
		"has",
		"had",
		"do",
		"does",
		"did",
		"will",
		"would",
		"shall",
		"should",
		"can",
		"could",
		"may",
		"might",
		"must",
		"let",
		"get",
		"got",
	],
	"meta_words":
	[
		"player",
		"stage",
		"json",
		"schema",
		"enum",
		"prompt",
		"label",
		"labels",
		"request",
		"response",
		"affection",
		"apology",
		"boundary",
		"cold",
		"compliment",
		"flirt",
		"gift",
		"greeting",
		"insult",
		"jealousy_bait",
		"leaving",
		"meta",
		"other",
		"question",
		"scared",
		"small_talk",
		"tease",
	],
	"importance": {"new_fact": 1.0, "quote_bonus": 1.0},
	"corruption":
	{
		"min_stage": 3,
		"band": [0.1, 0.25],
		"chance": {"3": 0.1, "4": 0.175, "5": 0.25},
		"kinds": ["name_swap", "number_off_by_one", "false_promise"],
		"names": ["Mira", "Hana", "Sora", "Yuki", "Rin"],
		"name_swap_exclude":
		[
			"I",
			"Leila",
			"Monday",
			"Tuesday",
			"Wednesday",
			"Thursday",
			"Friday",
			"Saturday",
			"Sunday",
			"January",
			"February",
			"March",
			"April",
			"May",
			"June",
			"July",
			"August",
			"September",
			"October",
			"November",
			"December",
		],
		"promise": "you told me you'd never leave",
		"number_words":
		{
			"zero": 0,
			"one": 1,
			"two": 2,
			"three": 3,
			"four": 4,
			"five": 5,
			"six": 6,
			"seven": 7,
			"eight": 8,
			"nine": 9,
			"ten": 10,
		},
	},
}

const MAX_STAGE := 5

## Characters after which a capitalised word is its sentence's first word rather
## than evidence of a name (`_swap_name`'s proper-name heuristic).
const SENTENCE_START_CHARS: Array[String] = [".", "!", "?", ";", ":", "—", '"', "'", "("]

static var _table_cache: Dictionary = {}
static var _cue_cache: Dictionary = {}


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}
	_cue_cache = {}


# ---------------------------------------------------------------- rule surface


## docs/02 §6 rules 1–3. Kept as the Director-facing yes/no; `reject_reason()`
## names the rule that fired, which is what the transcript logs.
static func validate(
	candidate: String, player_inputs: Array[String], existing_memories: Array[String]
) -> bool:
	return reject_reason(candidate, player_inputs, existing_memories).is_empty()


## Why a proposal was rejected: "" (accept), "empty", "too_long", "no_content",
## "meta_word", "ungrounded", "duplicate". Rule 2 runs before rule 1 so the doc's
## jealousy_bait leak is reported as the meta-word rejection it is, not as an
## ungrounded fact.
static func reject_reason(
	candidate: String, player_inputs: Array[String], existing_memories: Array[String]
) -> String:
	var trimmed := candidate.strip_edges()
	var shape := _shape_reject(trimmed)
	if not shape.is_empty():
		return shape
	if _has_meta_word(trimmed):
		return "meta_word"
	var cand_words := content_words(trimmed)
	if not _shares_content_word(cand_words, player_inputs):
		return "ungrounded"
	# Rule 3 compares the same content words the rest of the model uses, so a
	# shared "the"/"and" cannot pad two unrelated facts into a duplicate.
	for existing: String in existing_memories:
		if jaccard(cand_words, content_words(existing)) >= duplicate_jaccard():
			return "duplicate"
	return ""


# ------------------------------------------------------------ store arithmetic


## docs/02 §6 "Store: 24 slots".
static func capacity() -> int:
	return int(_table()["capacity"])


## docs/08 §1 "≤ 8 facts": PromptBuilder's MEMORY_LIMIT, pinned by a test.
static func prompt_limit() -> int:
	return int(_table()["prompt_limit"])


## TurnSchema.MEMORY_MAX_LENGTH; a fact never exceeds the schema's own limit.
static func max_length() -> int:
	return int(_table()["max_length"])


static func duplicate_jaccard() -> float:
	return float(_table()["duplicate_jaccard"])


static func new_importance() -> float:
	return float((_table()["importance"] as Dictionary)["new_fact"])


## docs/02 §6 "Importance +1 each time she quotes it."
static func quote_bonus() -> float:
	return float((_table()["importance"] as Dictionary)["quote_bonus"])


## docs/02 §6 "oldest low-importance evicted": the victim is the lowest
## importance in the store, and among equals the oldest (insertion order).
## `skip` excludes one index — `MemoryStore.consider()` passes the slot it just
## appended, because "oldest low-importance" cannot mean the newest fact
## (review r2 CODE-1/DES-3). Returns -1 for an empty store or when every index
## is skipped.
static func eviction_index(entries: Array, skip: int = -1) -> int:
	var victim := -1
	var lowest := INF
	for i: int in entries.size():
		if i == skip:
			continue
		var entry: Variant = entries[i]
		if not entry is Dictionary:
			return i
		var importance := float((entry as Dictionary).get("importance", 0.0))
		if importance < lowest:
			lowest = importance
			victim = i
	return victim


## "She quotes it": the share of the fact's content words that appear in her
## `say` reaches `quote_overlap` (0.5). The measure is per fact, so its cost
## scales with length: a three-word fact needs two words back and a two-word fact
## ("likes coffee") is quoted by one — the share is the only reading the doc's
## "she quotes it" offers at that length, and importance only orders eviction.
static func quoted_by(say_text: String, fact: String) -> bool:
	var fact_words := content_words(fact)
	if fact_words.is_empty():
		return false
	var said: Dictionary = {}
	for word: String in content_words(say_text):
		said[word] = true
	var hits := 0
	for word: String in fact_words:
		if said.has(word):
			hits += 1
	return float(hits) / float(fact_words.size()) >= float(_table()["quote_overlap"])


# ---------------------------------------------------------------- corruption


## docs/02 §6: "from stage 3, when memories are injected into the prompt,
## 10–25% are subtly altered". Value is the per-fact chance; the documented band
## is a hard clamp so no data edit can push corruption outside 10–25 %.
static func corruption_chance(stage: int) -> float:
	var spec: Dictionary = _table()["corruption"]
	if stage < int(spec["min_stage"]):
		return 0.0
	var chances: Dictionary = spec["chance"]
	var key := str(clampi(stage, 0, MAX_STAGE))
	# A row the data file omits falls back to its documented value before the
	# clamp: clamping a missing row would clamp 0.0 up to the band floor and
	# corrupt at 10 % on a stage that was meant to have no row at all.
	var docs: Dictionary = (DOCS_TABLE["corruption"] as Dictionary)["chance"]
	var raw := float(chances.get(key, docs.get(key, 0.0)))
	var band: Array = spec["band"]
	return clampf(raw, float(band[0]), float(band[1]))


## One seeded mutation of `fact`, or {} when the fact offers no applicable kind
## (e.g. a fact with no name and no number cannot be name/number corrupted).
## Deterministic for a given rng state: the kind order is tried from a seeded
## offset, so every mutation shape is reachable.
static func corrupt(fact: String, rng: RandomNumberGenerator) -> Dictionary:
	var spec: Dictionary = _table()["corruption"]
	var kinds: Array = spec["kinds"]
	if kinds.is_empty() or rng == null:
		return {}
	var start := rng.randi() % kinds.size()
	for offset: int in kinds.size():
		var kind := String(kinds[(start + offset) % kinds.size()])
		var text := _mutate(kind, fact, rng, spec)
		if not text.is_empty() and text != fact:
			return {"kind": kind, "original": fact, "corrupted": text}
	return {}


## The doc's three examples: "a name swapped, a number off by one, 'you told me
## you'd never leave'". Unknown kinds return nothing; a data test asserts every
## listed kind is implemented.
static func _mutate(
	kind: String, fact: String, rng: RandomNumberGenerator, spec: Dictionary
) -> String:
	match kind:
		"name_swap":
			return _swap_name(fact, rng, spec)
		"number_off_by_one":
			return _shift_number(fact, rng, spec)
		"false_promise":
			return _append_promise(fact, spec)
	return ""


## The doc's first example: "a name swapped". A capitalised token is only a
## candidate when it is not a function word and not the first word of its
## sentence: "My brother is called Ren" must corrupt to "… called Mira", never
## to "Rin brother …" — the prompt carries what she *misremembers*, and broken
## English reads as a bug rather than as a false memory (review r2 DES-1).
static func _swap_name(fact: String, rng: RandomNumberGenerator, spec: Dictionary) -> String:
	var regex := RegEx.new()
	regex.compile("\\b[A-Z][a-z]{1,}\\b")
	var exclude: Array = spec["name_swap_exclude"]
	var stop_words: Array = _table()["stop_words"]
	var candidates: Array[String] = []
	for m: RegExMatch in regex.search_all(fact):
		var token := m.get_string()
		if exclude.has(token) or stop_words.has(token.to_lower()):
			continue
		if _starts_a_sentence(fact, m.get_start()):
			continue
		candidates.append(token)
	if candidates.is_empty():
		return ""
	var original := candidates[rng.randi() % candidates.size()]
	var pool: Array = spec["names"]
	if pool.is_empty():
		return ""
	var replacement := ""
	# Seeded offset over the pool: a name already in the fact is not a
	# corruption, so it can never be the answer.
	var start := rng.randi() % pool.size()
	for offset: int in pool.size():
		var name := String(pool[(start + offset) % pool.size()])
		if name != original and fact.find(name) < 0:
			replacement = name
			break
	if replacement.is_empty():
		return ""
	return fact.replace(original, replacement)


## True when nothing but whitespace and sentence/clause punctuation precedes
## `start`, i.e. the token there is a sentence's first word.
static func _starts_a_sentence(fact: String, start: int) -> bool:
	var i := start - 1
	while i >= 0:
		var c := fact[i]
		if c == " " or c == "\t" or c == "\n":
			i -= 1
			continue
		return SENTENCE_START_CHARS.has(c)
	return true


static func _shift_number(fact: String, rng: RandomNumberGenerator, spec: Dictionary) -> String:
	var digits := _shift_digits(fact, rng)
	if not digits.is_empty():
		return digits
	return _shift_number_word(fact, rng, spec)


static func _shift_digits(fact: String, rng: RandomNumberGenerator) -> String:
	var regex := RegEx.new()
	regex.compile("\\b\\d+\\b")
	var found := regex.search(fact)
	if found == null:
		return ""
	var value := int(found.get_string())
	var shifted := _shifted_value(value, rng)
	return fact.substr(0, found.get_start()) + str(shifted) + fact.substr(found.get_end())


static func _shift_number_word(
	fact: String, rng: RandomNumberGenerator, spec: Dictionary
) -> String:
	var words: Dictionary = spec["number_words"]
	if words.is_empty():
		return ""
	var alternation := PackedStringArray()
	for key: Variant in words:
		alternation.append(String(key))
	var regex := RegEx.new()
	regex.compile("\\b(" + "|".join(alternation) + ")\\b")
	var found := regex.search(fact)
	if found == null:
		return ""
	var value := int(words[found.get_string()])
	var replacement := _word_for(_shifted_value(value, rng), words)
	if replacement.is_empty():
		return ""
	return fact.substr(0, found.get_start()) + replacement + fact.substr(found.get_end())


## ±1, never below zero, and never a no-op (0 − 1 would be 0).
static func _shifted_value(value: int, rng: RandomNumberGenerator) -> int:
	var shifted := value + (1 if rng.randi() % 2 == 0 else -1)
	if shifted < 0 or shifted == value:
		shifted = value + 1
	return shifted


static func _word_for(value: int, words: Dictionary) -> String:
	for key: Variant in words:
		if int(words[key]) == value:
			return String(key)
	return ""


## "…you told me you'd never leave" appended to the fact (the doc's third
## example). `max_length` is TurnSchema's cap on the model's *proposal* field,
## not on this bullet: skipping the mutation made every 49–80 character fact
## with no name and no number corruption-proof at every stage (measured 0 % at
## stage 5, review r2 CODE-2/DES-2). The rendered prompt's own soft budget
## report (`PromptBuilder._over_budget`) is the only limit here.
static func _append_promise(fact: String, spec: Dictionary) -> String:
	var promise := String(spec["promise"]).strip_edges()
	if promise.is_empty():
		return ""
	return "%s — %s" % [fact, promise]


# -------------------------------------------------------------------- tokens


static func tokenize(text: String) -> Array[String]:
	var regex := RegEx.new()
	regex.compile("\\w+")
	var matches: Array[RegExMatch] = regex.search_all(text)
	var tokens: Array[String] = []
	for m: RegExMatch in matches:
		tokens.append(m.get_string())
	return tokens


## Unique content words, lower-cased, in first-appearance order.
static func content_words(text: String) -> Array[String]:
	var seen: Dictionary = {}
	var words: Array[String] = []
	for token: String in tokenize(text.to_lower()):
		if _is_content_word(token) and not seen.has(token):
			seen[token] = true
			words.append(token)
	return words


## Rule 3's Jaccard over the sets the caller passes in. docs/02 §6 says "token
## Jaccard < 0.6"; `reject_reason()` feeds *content* words on both sides, which
## is the reading: with raw tokens "likes coffee" and "likes coffee a lot" score
## 0.5 (accepted) although they are the same fact, and shared function words
## make unrelated facts look alike. Pinned by
## `MemoryTest.test_rule3_compares_content_words_not_raw_tokens`.
static func jaccard(a: Array[String], b: Array[String]) -> float:
	var set_a: Dictionary = {}
	var set_b: Dictionary = {}
	for token: String in a:
		set_a[token] = true
	for token: String in b:
		set_b[token] = true

	var intersection_count := 0
	for token: String in set_a:
		if set_b.has(token):
			intersection_count += 1

	var union_count := set_a.size()
	for token: String in set_b:
		if not set_a.has(token):
			union_count += 1

	if union_count == 0:
		return 0.0
	return float(intersection_count) / float(union_count)


## Returns {fact, shared_words} for the first stored fact the message denies, or
## {} when nothing is contradicted. Facts are compared in store order, so the
## same transcript and the same store always pick the same fact. A denial cue
## never counts as a shared word: her own corrupted "you'd never leave" must not
## make every "never" look like a contradiction.
static func contradiction(player_text: String, facts: Array, spec := {}) -> Dictionary:
	var text := player_text.to_lower()
	if text.strip_edges().is_empty() or facts.is_empty():
		return {}
	var given: Dictionary = spec if spec is Dictionary else {}
	var negations: Variant = given.get("negations")
	if not negations is Array or (negations as Array).is_empty():
		negations = DEFAULT_NEGATIONS
	if not _has_negation(text, negations):
		return {}
	var min_shared := int(given.get("min_shared_words", DEFAULT_SHARED_WORDS))
	var denial: Dictionary = _cue_words(negations)
	var said: Array[String] = content_words(text)
	for fact: Variant in facts:
		var stored := str(fact)
		var shared := 0
		for word: String in content_words(stored):
			if said.has(word) and not denial.has(word):
				shared += 1
		if shared >= maxi(1, min_shared):
			return {"fact": stored, "shared_words": shared}
	return {}


## A cue matches as a whole-word phrase ("never" must not match "whenever").
## Compiled once per cue: the guard runs on every begin/close turn.
static func _has_negation(text: String, negations: Array) -> bool:
	for cue: Variant in negations:
		var phrase := str(cue).strip_edges()
		if phrase.is_empty():
			continue
		var regex := _cue_regex(phrase)
		if regex != null and regex.search(text) != null:
			return true
	return false


static func _cue_regex(phrase: String) -> RegEx:
	if _cue_cache.has(phrase):
		return _cue_cache[phrase] as RegEx
	var regex := RegEx.new()
	var compiled := regex.compile("\\b" + phrase + "\\b")
	_cue_cache[phrase] = regex if compiled == OK else null
	return _cue_cache[phrase] as RegEx


## The words a cue is made of, so a denial word cannot ground a contradiction.
static func _cue_words(negations: Array) -> Dictionary:
	var words: Dictionary = {}
	for cue: Variant in negations:
		for word: String in tokenize(str(cue).to_lower()):
			words[word] = true
	return words


## Rule 1's fail-closed edge: no player window grounds nothing (CODE-10b).
static func _shares_content_word(cand_words: Array[String], player_inputs: Array) -> bool:
	var grounds: Dictionary = {}
	for line: Variant in player_inputs:
		for word: String in content_words(String(line)):
			grounds[word] = true
	for word: String in cand_words:
		if grounds.has(word):
			return true
	return false


static func _is_content_word(token: String) -> bool:
	if token.length() < int(_table()["min_content_word_length"]):
		return false
	return not (_table()["stop_words"] as Array).has(token)


static func _has_meta_word(text: String) -> bool:
	var meta: Array = _table()["meta_words"]
	for token: String in tokenize(text.to_lower()):
		if meta.has(token):
			return true
	return false


static func _shape_reject(trimmed: String) -> String:
	if trimmed.is_empty():
		return "empty"
	if trimmed.length() > int(_table()["max_length"]):
		return "too_long"
	if content_words(trimmed).is_empty():
		return "no_content"
	return ""


# --------------------------------------------------------------------- table


## The merged table (docs values overlaid with memory.json). READ-ONLY: it is
## shared, and copying it per rule call would allocate on the turn path.
static func _table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _load_table()
	return _table_cache


static func _load_table() -> Dictionary:
	var merged: Dictionary = DOCS_TABLE.duplicate(true)
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("MemoryRules: %s missing; using the docs/02 §6 values" % TABLE_PATH)
		return merged
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	if not parsed is Dictionary:
		push_warning(
			"MemoryRules: %s is not a JSON object; using the docs/02 §6 values" % TABLE_PATH
		)
		return merged
	_merge_into(merged, parsed as Dictionary)
	return merged


## Recursive overlay so a partial data file keeps the documented value for every
## key it omits instead of dropping the whole table.
static func _merge_into(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		var value: Variant = source[key]
		var existing: Variant = target.get(key)
		if value is Dictionary and existing is Dictionary:
			_merge_into(existing, value)
		else:
			target[key] = value
