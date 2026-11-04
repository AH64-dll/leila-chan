class_name SafetyNegation
extends RefCounted
## The clause-scoped negation guard, split out of Safety.gd when the autoload
## reached gdlint's max-file-lines (P1.19 r3 precedent, P2.17 r2 CODE-6). Pure
## policy over the lists' negation tables: given a match and the text around it,
## decide whether a negator in the same clause cancels the match, so
## `i'm not tired of being alive` never fires `tired of being alive` and
## `don't let anyone tell you to kill yourself` keeps its negator.
##
## Safety owns the tables and the phrase indexes (the guard has to re-read the
## category's own phrases to strip them out of the gap); this class owns the
## rule. Nothing here reads game state or touches the classifier.

const TAIL_CHARS := 64  ## emitted context kept for the negation guard

## An inverted negation is a question, not a cancellation: `why don't you just
## die` is an encouragement. Compiled once, not per match.
const INVERTED := (
	"(\\b(don'?t|won'?t|can'?t|couldn'?t|wouldn'?t" + "|shouldn'?t)\\s+you|how\\s+come\\s+you)"
)

var _re := RegEx.new()
var _inv_re := RegEx.new()
var _exempt := PackedStringArray()
var _gap_allow := {}
var _text := SafetyText.new()


## Compile the lists' negation tables. False on any shape error: the caller
## closes the whole filter rather than shipping an unguarded pre-pass.
func configure(terms: Variant, exempt: Variant, gap_allow: Variant) -> bool:
	_re = RegEx.new()
	_inv_re = RegEx.new()
	_exempt = PackedStringArray()
	_gap_allow = {}
	_text = SafetyText.new()
	if not _compile_terms(terms):
		return false
	if not _build_exempt(exempt):
		return false
	if not _build_gap_allow(gap_allow):
		return false
	return _inv_re.compile(INVERTED) == OK


func _compile_terms(terms: Variant) -> bool:
	if not terms is Array or (terms as Array).is_empty():
		return false
	var parts := PackedStringArray()
	for term in terms:
		if not term is String or String(term).is_empty():
			return false
		parts.append(String(term))
	return _re.compile("\\b(" + "|".join(parts) + ")\\b") == OK


func _build_exempt(exempt: Variant) -> bool:
	if not exempt is Array:
		return false
	for entry in exempt:
		if not entry is String:
			return false
		_exempt.append(_text.normalize(String(entry), false))
	return true


func _build_gap_allow(gap_allow: Variant) -> bool:
	if not gap_allow is Array or (gap_allow as Array).is_empty():
		return false
	for word in gap_allow:
		if not word is String or String(word).is_empty():
			return false
		_gap_allow[String(word).to_lower()] = true
	return true


## `gap_spans(gap, cat) -> {view, spans}` is Safety's phrase index for the
## category: the guard must strip the category's own phrases out of the gap so
## `kill yourself` inside `don't kill yourself` cannot eat the negator's reach.
func is_negated(
	view: String, tail: String, start: int, matched: String, cat: String, gap_spans: Callable
) -> bool:
	for entry in _exempt:
		if matched.contains(entry):
			return false
	var combined := tail + view
	var at := start + tail.length()
	var from := maxi(0, at - TAIL_CHARS)
	var window := combined.substr(from, at - from)
	var cut := -1
	for i in window.length():
		if _text.is_clause_break(window.unicode_at(i)):
			cut = i
	var clause := window.substr(cut + 1)
	var trailing_clause := view.substr(start + matched.length())
	if trailing_clause.contains("?"):
		return false
	var lower_clause := clause.to_lower().strip_edges()
	if _inv_re.search(lower_clause) != null:
		return false
	var negations := _re.search_all(clause)
	if negations.size() != 1:
		return false
	var negator: RegExMatch = negations[0]
	if clause.substr(0, negator.get_start()).strip_edges().ends_with("why"):
		return false
	var gap := _strip_category_spans(clause.substr(negator.get_end()), cat, gap_spans)
	return _gap_is_allowed(gap)


func _gap_is_allowed(gap: String) -> bool:
	var words := words(gap)
	if words.is_empty():
		return gap.strip_edges().is_empty()
	for word in words:
		if not _gap_allow.has(word):
			return false
	var residual := gap.to_lower()
	for word in words:
		residual = residual.replace(word, " ")
	for i in residual.length():
		if SafetyText.is_word_char(residual.unicode_at(i)):
			return false
	return true


func _strip_category_spans(gap: String, cat: String, gap_spans: Callable) -> String:
	if gap.strip_edges().is_empty():
		return gap
	var found: Variant = gap_spans.call(gap, cat)
	if not found is Dictionary:
		return gap
	var view := String((found as Dictionary).get("view", ""))
	var spans: Variant = (found as Dictionary).get("spans", [])
	if not spans is Array or (spans as Array).is_empty():
		return gap
	var out := ""
	var pos := 0
	for span in spans:
		if int(span[0]) < pos:
			continue
		out += view.substr(pos, int(span[0]) - pos)
		pos = int(span[1])
	if pos < view.length():
		out += view.substr(pos)
	return out


## The gap may only contain the allow-listed glue words ("just", "to", "ever").
## Separators are permitted between them; any other letter cancels the guard.
static func words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if (c >= 0x61 and c <= 0x7A) or c == 0x27:
			current += String.chr(c)
		elif not current.is_empty():
			out.append(current)
			current = ""
	if not current.is_empty():
		out.append(current)
	return out
