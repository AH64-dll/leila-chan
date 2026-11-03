class_name MemoryRules
extends RefCounted
## MemoryRules — the docs/02 §6 memory validation the Director applies to every
## proposed `memory` (P1.08). Split out of Director.gd so the rules stay a unit
## the suite can exercise on their own.
##
## The three rules:
##   1. the candidate shares >= 1 content word with the last 3 player messages
##      (blocks invented facts),
##   2. it contains no schema/meta words (docs/02 §6 rule 2),
##   3. it is not a near-duplicate (token Jaccard < 0.6 vs the stored facts).
##
## Rule 1 is fail-closed: with no player window there is nothing to ground the
## fact in, so the candidate is rejected instead of accepted (P1.08 review
## CODE-10b).
##
## The content-word test keeps a > 2 character floor (CODE-10c): the tokenizer
## emits stop words too ("the", "a", "of"), and one shared stop word would
## satisfy rule 1 for a wholly invented fact. Short *content* words ("cat",
## "job") are given up in exchange for that; the doc's rule is about grounding,
## and grounding on a stop word is worse than missing a two-letter noun.

## docs/02 §6 rule 2, kept in step with the prompt-lab list that measured P1.05
## CON-2 (tools/promptlab/lab.py): only unambiguous meta jargon and the
## snake_case intent labels — a literal schema-key list would reject benign
## facts the few-shots themselves produce (`gave me a music box`, `bad mood`).
const META_WORDS := [
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
	"jealousy_bait",
	"small_talk",
]

const MIN_CONTENT_WORD_LENGTH := 3
const DUPLICATE_JACCARD := 0.6
const MAX_MEMORY_LENGTH := 80


static func validate(
	candidate: String, player_inputs: Array[String], existing_memories: Array[String]
) -> bool:
	var trimmed := candidate.strip_edges()
	if trimmed.is_empty() or trimmed.length() > MAX_MEMORY_LENGTH:
		return false

	var cand_tokens := tokenize(trimmed.to_lower())
	if cand_tokens.is_empty():
		return false

	# Rule 2: no schema / meta words.
	for meta_word: String in META_WORDS:
		if cand_tokens.has(meta_word):
			return false

	# Rule 1: at least one content word shared with the last 3 player messages.
	var player_tokens: Dictionary = {}
	for input_line: String in player_inputs:
		for token: String in tokenize(input_line.to_lower()):
			if _is_content_word(token):
				player_tokens[token] = true

	var shares_word := false
	for token: String in cand_tokens:
		if _is_content_word(token) and player_tokens.has(token):
			shares_word = true
			break
	if not shares_word:
		return false

	# Rule 3: not a near-duplicate of a stored fact.
	for existing: String in existing_memories:
		if jaccard(cand_tokens, tokenize(existing.to_lower())) >= DUPLICATE_JACCARD:
			return false

	return true


static func _is_content_word(token: String) -> bool:
	return token.length() >= MIN_CONTENT_WORD_LENGTH


static func tokenize(text: String) -> Array[String]:
	var regex := RegEx.new()
	regex.compile("\\w+")
	var matches: Array[RegExMatch] = regex.search_all(text)
	var tokens: Array[String] = []
	for m: RegExMatch in matches:
		tokens.append(m.get_string())
	return tokens


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
