class_name MetaBirthday
extends RefCounted
## MetaBirthday — docs/05 §1.5 M37: "if the player told her their birthday
## (memory), the game remembers on that real date."
##
## Pure parsing, split out of MetaEventsM31 so the date grammar is testable on
## its own and the module stays inside the file-length budget. A fact only
## counts when it mentions the birthday at all, so an unrelated date the player
## mentions ("I went out on May 3") never becomes a birthday.
##
## The grammar is data (`data/meta_notes.json` `birthday.patterns`): month names,
## day-first and month-first orders, and ISO `YYYY-MM-DD`. Numeric `03/05` is
## deliberately unsupported — day-month vs month-day is unresolvable without a
## locale, and a wrong birthday is worse than none.


static func parse(facts: Array, spec: Dictionary) -> Dictionary:
	var keywords: Array = spec.get("keywords", [])
	var months: Dictionary = spec.get("months", {})
	for fact_variant: Variant in facts:
		var fact := str(fact_variant).to_lower()
		if not _mentions(fact, keywords):
			continue
		var parsed := _parse_one(fact, months, spec)
		if not parsed.is_empty():
			return parsed
	return {}


static func _mentions(fact: String, keywords: Array) -> bool:
	for keyword: Variant in keywords:
		if fact.contains(String(keyword)):
			return true
	return false


static func _parse_one(fact: String, months: Dictionary, spec: Dictionary) -> Dictionary:
	var patterns: Variant = spec.get("patterns", [])
	if not (patterns is Array):
		return {}
	for row_variant: Variant in patterns as Array:
		var row: Dictionary = row_variant
		var re := RegEx.new()
		if re.compile(String(row.get("regex", ""))) != OK:
			continue
		var hit := re.search(fact)
		if hit == null:
			continue
		var pair := _pair_for(hit, String(row.get("order", "")), months)
		if pair[0] >= 1 and pair[0] <= 12 and pair[1] >= 1 and pair[1] <= 31:
			return {"month": pair[0], "day": pair[1]}
	return {}


## [month, day] for one match. An unknown month name stays 0 and fails the
## caller's range check, so a typo in the data cannot invent a date.
static func _pair_for(hit: RegExMatch, order: String, months: Dictionary) -> Array[int]:
	match order:
		"dmy":
			return [_digit(str(months.get(hit.get_string(2), 0))), _digit(hit.get_string(1))]
		"mdy":
			return [_digit(str(months.get(hit.get_string(1), 0))), _digit(hit.get_string(2))]
		"iso":
			return [_digit(hit.get_string(2)), _digit(hit.get_string(3))]
	return [0, 0]


## The first integer in the text (never `int("")` on a hostile match).
static func _digit(text: String) -> int:
	var digits := ""
	for index: int in text.length():
		var code := text.unicode_at(index)
		if code >= 48 and code <= 57:
			digits += text[index]
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 0
