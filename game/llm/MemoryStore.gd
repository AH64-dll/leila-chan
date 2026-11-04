class_name MemoryStore
extends RefCounted
## MemoryStore — the docs/02 §6 memory: 24 slots, importance, eviction, and the
## corruption of what she *reads* from stage 3.
##
## The store keeps the true facts; corruption never rewrites them. It is applied
## when the facts are injected into the prompt ("when memories are injected …
## 10–25% are subtly altered"), so the same fact is read accurately on one turn
## and wrongly on the next — she is not lying, she misremembered. Corruption is
## re-rolled per injection (a retry is a new injection) and every change is
## reported through `last_corruptions` for the transcript record.
##
## Importance drives eviction only (docs/02 §6: "oldest low-importance
## evicted"). +1 per turn in which she quotes the fact; `note_quotes()` runs
## before a new proposal is stored, so a fact cannot be credited for being said
## in the same turn it was learned.
##
## The rng is seeded (default 0) so a transcript replays identically; P2.20's
## save carries `to_dict()`, `seed` and `state` included.

const ENTRY_TEXT := "text"
const ENTRY_IMPORTANCE := "importance"
const ENTRY_QUOTES := "quotes"

## docs/02 §6 "Store: 24 slots". `memory.json` sets it and `_init(size_override)`
## is the test seam; a save's capacity is clamped to the same ceiling, so nothing
## a save, a data edit or a caller carries can widen the store (r2 CODE-4/DES-9).
var capacity: int = 24
var entries: Array[Dictionary] = []
## The changes `prompt_facts()` made this turn: {slot, kind, original, corrupted}.
var last_corruptions: Array[Dictionary] = []
## The facts she quoted this turn (importance already bumped).
var last_quotes: Array[String] = []
## The most recent proposal decision — {accepted, reason, evicted, text}. The
## transcript carries it so a refused fact is auditable ("rule 2: meta_word"),
## not just absent.
var last_proposal: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func _init(size_override := 0) -> void:
	capacity = size_override if size_override > 0 else MemoryRules.capacity()
	_rng.seed = 0


## Forget every fact (New Game / Director.reset). The seed survives: replay
## identity is a property of the session, not of the fact list.
func reset() -> void:
	var seed := _rng.seed
	entries.clear()
	begin_turn()
	_rng.seed = seed


## Open this turn's record (`Director._start_turn`, and the unsafe-input refusal
## that never opens a turn). `prompt_facts()` clears the corruption log and
## `note_quotes()` the quotes, but nothing cleared the proposal, and a turn that
## builds no prompt (a refusal), fails, is cancelled, or whose model sent
## `"memory": ""` would report the previous turn's fields — the transcript's
## `proposal` is "why she just refused to remember", so it must be this turn's
## (review r2 CODE-3/DES-6).
func begin_turn() -> void:
	last_corruptions.clear()
	last_quotes.clear()
	last_proposal = {}


# ------------------------------------------------------------------ proposals


## Try to store a model-proposed fact. Rejects through MemoryRules' three rules
## and names the rule that fired. On accept, over-capacity evicts the oldest
## low-importance slot — never the fact just accepted, which is the newest and
## would otherwise be its own victim in a store of quoted facts (review r2
## CODE-1/DES-3).
func consider(candidate: String, player_inputs: Array) -> Dictionary:
	# The window is typed at the rule layer; a tool or a save may hand us an
	# untyped Array, so it is normalised here instead of erroring inside the
	# rules (review r2 DES-8).
	var window: Array[String] = []
	for line: Variant in player_inputs:
		window.append(str(line))
	var reason := MemoryRules.reject_reason(candidate, window, facts())
	if not reason.is_empty():
		last_proposal = {"accepted": false, "reason": reason, "evicted": "", "text": ""}
		return last_proposal
	var trimmed := candidate.strip_edges()
	(
		entries
		. append(
			{
				ENTRY_TEXT: trimmed,
				ENTRY_IMPORTANCE: MemoryRules.new_importance(),
				ENTRY_QUOTES: 0,
			}
		)
	)
	var evicted := ""
	if entries.size() > capacity:
		var victim := MemoryRules.eviction_index(entries, entries.size() - 1)
		if victim >= 0:
			evicted = String(entries[victim][ENTRY_TEXT])
			entries.remove_at(victim)
	last_proposal = {"accepted": true, "reason": "", "evicted": evicted, "text": trimmed}
	return last_proposal


# ------------------------------------------------------------------ injection


## The facts she sees this turn: the newest `prompt_limit` slots, in insertion
## order, each corrupted with the docs/02 §6 per-stage chance. The store's own
## facts stay true; `last_corruptions` records what changed.
func prompt_facts(ctx: Dictionary = {}) -> Array[String]:
	last_corruptions.clear()
	var limit := maxi(1, MemoryRules.prompt_limit())
	var first := maxi(0, entries.size() - limit)
	var chance := MemoryRules.corruption_chance(_stage_of(ctx))
	var out: Array[String] = []
	for i: int in range(first, entries.size()):
		var text := String(entries[i][ENTRY_TEXT])
		if chance > 0.0 and _rng.randf() < chance:
			var change := MemoryRules.corrupt(text, _rng)
			if not change.is_empty():
				(
					last_corruptions
					. append(
						{
							"slot": i,
							"kind": change["kind"],
							"original": change["original"],
							"corrupted": change["corrupted"],
						}
					)
				)
				text = String(change["corrupted"])
		out.append(text)
	return out


## docs/02 §6 "Importance +1 each time she quotes it": every stored fact whose
## content words fill `quote_overlap` of her spoken text gains one point, once
## per turn. Returns the quoted facts (already bumped).
func note_quotes(say_text: String) -> Array[String]:
	last_quotes.clear()
	if say_text.strip_edges().is_empty():
		return last_quotes
	for entry: Dictionary in entries:
		if MemoryRules.quoted_by(say_text, String(entry[ENTRY_TEXT])):
			entry[ENTRY_IMPORTANCE] = float(entry[ENTRY_IMPORTANCE]) + MemoryRules.quote_bonus()
			entry[ENTRY_QUOTES] = int(entry[ENTRY_QUOTES]) + 1
			last_quotes.append(String(entry[ENTRY_TEXT]))
	return last_quotes


# --------------------------------------------------------------------- reads


func size() -> int:
	return entries.size()


func facts() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in entries:
		out.append(String(entry[ENTRY_TEXT]))
	return out


func importances() -> Array[float]:
	var out: Array[float] = []
	for entry: Dictionary in entries:
		out.append(float(entry[ENTRY_IMPORTANCE]))
	return out


## What the transcript records for this turn: the true facts, what she actually
## read, and what she quoted. `facts` and `corruptions.original` are the audit
## trail, so a replayed run can be checked against the shipped prompt.
func report() -> Dictionary:
	return {
		"count": entries.size(),
		"capacity": capacity,
		"facts": facts(),
		"corruptions": last_corruptions.duplicate(true),
		"quotes": last_quotes.duplicate(),
		"proposal": last_proposal.duplicate(true),
	}


# --------------------------------------------------------------------- saves


func set_rng_seed(value: int) -> void:
	_rng.seed = value


func rng_seed() -> int:
	return _rng.seed


func to_dict() -> Dictionary:
	var rows: Array = []
	for entry: Dictionary in entries:
		rows.append(entry.duplicate(true))
	return {
		"capacity": capacity,
		"seed": _rng.seed,
		"state": _rng.state,
		"entries": rows,
	}


## Restore a save. Anything malformed is dropped rather than trusted: a slot
## without a non-empty string is not a fact, a negative importance or quote
## count is healed to zero, and a save carrying more slots than the store allows
## is trimmed by the same eviction rule a live store uses (docs/02 §6 "24 slots";
## corrupt-save handling is P2.20's, this function is only its input guard).
func from_dict(data: Dictionary) -> void:
	reset()
	# Every field below is untrusted, and `int()`/`float()`/`String()` on a
	# Dictionary abort the script: each conversion goes through a total helper,
	# so the guard's own promise ("malformed is dropped rather than trusted")
	# cannot crash a load (P2.20). Capacity stays docs/02 §6's 24 at most, so a
	# hand-edited save is data, never a wider store (review r2 CODE-4/DES-9).
	capacity = clampi(
		_save_int(data.get("capacity"), MemoryRules.capacity()), 1, MemoryRules.capacity()
	)
	_rng.seed = _save_int(data.get("seed"), 0)
	if data.has("state"):
		_rng.state = _save_int(data["state"], 0)
	var rows: Variant = data.get("entries", [])
	if not rows is Array:
		return
	for row: Variant in rows:
		if not row is Dictionary:
			continue
		# Only a string is a fact; a number or an array where the text goes is
		# not one (a corrupt slot used to reach `String(7)` and abort here).
		var raw_text: Variant = (row as Dictionary).get(ENTRY_TEXT, "")
		if not raw_text is String and not raw_text is StringName:
			continue
		var text := String(raw_text).strip_edges()
		if text.is_empty():
			continue
		var importance: Variant = (row as Dictionary).get(
			ENTRY_IMPORTANCE, MemoryRules.new_importance()
		)
		var quotes: Variant = (row as Dictionary).get(ENTRY_QUOTES, 0)
		(
			entries
			. append(
				{
					ENTRY_TEXT: text,
					ENTRY_IMPORTANCE: maxf(0.0, _save_number(importance)),
					ENTRY_QUOTES: maxi(0, _save_int(quotes, 0)),
				}
			)
		)
	while entries.size() > capacity:
		entries.remove_at(MemoryRules.eviction_index(entries))


## A finite number from untrusted save data; anything else is the fallback.
static func _save_number(value: Variant) -> float:
	if value is int:
		return float(value)
	if value is float:
		return value if is_finite(value) else 0.0
	return 0.0


## The integer form of `_save_number`, floored/ceiled by the caller.
static func _save_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value) if is_finite(value) else fallback
	return fallback


func _stage_of(ctx: Dictionary) -> int:
	var raw: Variant = ctx.get("stage", 0)
	if raw is int:
		return raw
	if raw is float:
		return int(raw)
	if raw is String and String(raw).is_valid_int():
		return int(String(raw))
	return 0
