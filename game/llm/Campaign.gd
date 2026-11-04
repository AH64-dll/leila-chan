class_name Campaign
extends RefCounted
## Campaign — docs/01 §1's day/night loop clock: the 14-day counter and the
## scenario each day opens with.
##
## The day value itself stays GameState's (one owner for the truth: it is in the
## snapshot, the HUD and the save). This class reads it and owns the two moves the
## loop makes around it:
##   begin_day()   the Date asks for today's scenario by availability;
##   next_scenario() the Night, after its checks, queues the new day's pick.
##
## Both picks mark the scenario played, so a campaign never repeats a date while
## the pool can offer an unplayed one, and both are deterministic for a given
## (campaign seed, day): the same state replays the same campaign.
##
## The pool is injected by the caller when it needs a synthetic one (tests); the
## shipped pool is res://data/scenarios via ScenarioLoader.pool().

const GameStateScript := preload("res://autoload/GameState.gd")

## Campaign state lives in GameState.flags — it is in the snapshot, so a save
## resumes the campaign's day and its played list (docs/07 §3.5).
const FLAG_NEXT_SCENARIO := &"next_scenario"
const FLAG_PLAYED := &"played_scenarios"
const FLAG_SEED := &"campaign_seed"

var _state: Node


func _init(state: Node) -> void:
	_state = state


## docs/01 §1: the campaign is 14 in-game days. The number is GameState's (the
## day counter clamps to it) — read here, never copied.
static func day_max() -> int:
	return GameStateScript.DAY_MAX


## The current in-game day, 1-based.
func day() -> int:
	return int(_state.day) if _state != null else 0


## docs/01 §1: days 12–14 only exist on some paths, so the last day of a run is
## the ending system's business (P3.16). This answers the loop's own question:
## is there a day after this one?
func is_last_day() -> bool:
	return day() >= day_max()


## The scenario ids this campaign already opened, in play order.
func played_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if _state == null:
		return out
	var stored: Variant = _state.get_flag(FLAG_PLAYED, [])
	if stored is Array:
		for item: Variant in stored:
			var id := String(item).strip_edges()
			if not id.is_empty():
				out.append(StringName(id))
	return out


## docs/01 §1: the Date opens with today's scenario. The Night queued its pick for
## the morning; every other day (day 1, a resumed campaign) falls through to the
## same availability rule. The choice is consumed here — the queue is cleared and
## the scenario marked played — so one day is one date, once.
## Returns {"path", "id", "scenario"} or {} when nothing may run today.
func begin_day(pool_rows: Array = []) -> Dictionary:
	if _state == null:
		return {}
	var pool: Array = pool_rows if not pool_rows.is_empty() else ScenarioLoader.pool()
	var queued := String(_state.get_flag(FLAG_NEXT_SCENARIO, "")).strip_edges()
	var picked := _row_for_path(pool, queued)
	if picked.is_empty():
		picked = _pick(pool)
	else:
		_state.clear_flag(FLAG_NEXT_SCENARIO)
	if picked.is_empty():
		return {}
	_note_played(StringName(String(picked.get("id", ""))))
	return picked


## docs/01 §1: after the night's checks the loop queues the new day's date and
## returns it. Written into the flags so a save taken at night resumes the right
## scenario; {} when no scenario is available — the Date then keeps its default.
func next_scenario(pool_rows: Array = []) -> Dictionary:
	if _state == null:
		return {}
	var pool: Array = pool_rows if not pool_rows.is_empty() else ScenarioLoader.pool()
	var picked := _pick(pool)
	if picked.is_empty():
		return {}
	_state.set_flag(FLAG_NEXT_SCENARIO, String(picked.get("path", "")))
	return picked


## Everything that may run today (docs/08 §7 availability at this day, stage and
## path), minus what the campaign already played; a fully played pool falls back
## to the available set so a day is never left without a date. One candidate is
## drawn per (campaign seed, day), so the pick is deterministic and replayable.
func _pick(pool: Array) -> Dictionary:
	if _state == null:
		return {}
	var rows := ScenarioLoader.available_scenarios(
		pool, day(), int(_state.stage), String(_state.path)
	)
	if rows.is_empty():
		return {}
	var played := played_ids()
	var unplayed: Array[Dictionary] = []
	for row: Dictionary in rows:
		if not played.has(StringName(String(row.get("id", "")))):
			unplayed.append(row)
	var candidates: Array[Dictionary] = unplayed if not unplayed.is_empty() else rows
	var rng := _rng()
	return candidates[rng.randi_range(0, candidates.size() - 1)].duplicate(true)


func _row_for_path(pool: Array, path: String) -> Dictionary:
	if path.is_empty():
		return {}
	for row: Variant in pool:
		if row is Dictionary and String((row as Dictionary).get("path", "")) == path:
			return (row as Dictionary).duplicate(true)
	return {}


## Deterministic per (campaign seed, day): docs/01 §1's campaign is replayable, and
## the seed is fixed at 0 until a New Game assigns one (the P2.11 convention).
func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var base := int(_state.get_flag(FLAG_SEED, 0))
	rng.seed = int(hash("%d:%d" % [base, day()]))
	return rng


func _note_played(id: StringName) -> void:
	if String(id).is_empty():
		return
	var ids := played_ids()
	if ids.has(id):
		return
	ids.append(id)
	var stored: Array = []
	for item: StringName in ids:
		stored.append(String(item))
	_state.set_flag(FLAG_PLAYED, stored)
