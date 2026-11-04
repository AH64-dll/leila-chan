extends Node
## Memory — player facts, validation, corruption (docs/07 §2, docs/02 §6).
##
## The model only proposes a `memory`; this node owns the truth about what she
## actually knows. `game/llm/MemoryRules.gd` holds the three docs/02 §6 rules and
## the corruption band, `game/llm/MemoryStore.gd` holds the 24 slots, importance,
## eviction and the seeded mutation of what she reads. This autoload is the one
## owner the Director (proposals, prompt injection, quoting) and a save (P2.20)
## talk to, so no second copy of the fact list can drift.
##
## Corruption is reported through `report()`/`last_corruptions`; the Director
## writes it into the turn transcript, which is the audit trail for a replayed
## run. One logging path, asserted end to end by `MemoryTest`.

var store := MemoryStore.new()


## New Game / Director.reset: forget the facts, keep the replay seed.
func reset() -> void:
	store.reset()


## docs/02 §6 rules 1–3 + the slot/eviction rules. Returns
## `{accepted, reason, evicted, text}`; `reason` names the rule that rejected.
func consider(candidate: String, player_inputs: Array) -> Dictionary:
	return store.consider(candidate, player_inputs)


## The docs/08 §1 `[memories]` layer for this turn: newest 8 facts, corrupted
## per `corruption_chance(stage)` from stage 3. `report()` carries what changed.
func prompt_facts(ctx: Dictionary = {}) -> Array[String]:
	return store.prompt_facts(ctx)


## docs/02 §6 importance: +1 for every fact she quoted in `say_text` this turn.
func note_quotes(say_text: String) -> Array[String]:
	return store.note_quotes(say_text)


func facts() -> Array[String]:
	return store.facts()


func size() -> int:
	return store.size()


## True stored facts, this turn's corruptions and this turn's quotes, for the
## transcript record (`Director._log_turn_record`).
func report() -> Dictionary:
	return store.report()


func set_rng_seed(value: int) -> void:
	store.set_rng_seed(value)


func to_dict() -> Dictionary:
	return store.to_dict()


func from_dict(data: Dictionary) -> void:
	store.from_dict(data)
