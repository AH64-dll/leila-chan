class_name NightLoop
extends RefCounted
## NightLoop — docs/01 §1's night, in the bible's order:
##
##   night: meters update → stage check → path check → overnight event
##
## One resolve() per night. The report it returns is the night screen's data and
## the tests' evidence: every step records what it read BEFORE and what it left
## AFTER, so "in order" is observable rather than asserted (the stage step sees the
## post-burn meters, the path step sees the post-burn stage, the event is chosen
## from the state both produced).
##
## The steps are not re-implementations: the daily burn is GameState.advance_day()
## (docs/01 §2), the band crossing happens inside the meter write through Stages /
## GameState._refresh_stage (docs/01 §3), and the Stage-2/Stage-3 path rule is
## GameState's one copy (docs/01 §4). This class sequences them, verifies the
## invariants, and picks the content.

const STEPS: Array[String] = ["meters", "stage", "path", "event"]
const FLAG_PLAYED_OVERNIGHT := &"played_overnight"
const FLAG_SEED := &"campaign_seed"

var _state: Node
var _rng: RandomNumberGenerator
var _report: Dictionary = {}


## `state` is the GameState node (the autoload in game, a fresh instance in tests);
## `rng` is injected when a test needs a fixed draw, else seeded deterministically
## from the campaign seed and the day being closed.
func _init(state: Node, rng: RandomNumberGenerator = null) -> void:
	_state = state
	if rng != null:
		_rng = rng
		return
	_rng = RandomNumberGenerator.new()
	var base := 0
	var day := 1
	if state != null:
		base = int(state.get_flag(FLAG_SEED, 0))
		day = int(state.day)
	_rng.seed = int(hash("%d:%d" % [base, day]))


## The last report ({} before resolve()).
func report() -> Dictionary:
	return _report.duplicate(true)


## Runs the night once. A second call returns the first report: a night is one
## roll-over, and resolving twice would burn a second day. {} only when there is no
## state to resolve.
func resolve() -> Dictionary:
	if not _report.is_empty():
		return _report.duplicate(true)
	if _state == null:
		push_warning("NightLoop: no GameState — the night cannot resolve")
		return {}
	var day_before := int(_state.day)
	var instability_before := float(_state.instability)
	var stage_before := int(_state.stage)
	var path_before := String(_state.path)
	var locked_before := bool(_state.path_locked)
	var queued_before := int(_state.pending_events.size())

	# 1/4 meters (docs/01 §2): the day advances and the +3 daily burn lands here.
	var burn := float(_state.advance_day())
	var meters := {
		"day_before": day_before,
		"day": int(_state.day),
		"burn": burn,
		"instability_before": instability_before,
		"instability_after": float(_state.instability),
		"instability_floor": float(_state.instability_floor),
	}

	# 2/4 stage (docs/01 §3): the burn's own meter write already crossed the band,
	# so this step verifies and reports what the crossing did — one EVENT line
	# queued, one transition spec for the glitch that hides the dose change.
	var stage_after := int(_state.stage)
	var crossed := stage_after > stage_before
	var stage := {
		"before": stage_before,
		"after": stage_after,
		"name": Stages.name_of(stage_after),
		"crossed": crossed,
		"transition": Stages.transition_spec(stage_after) if crossed else {},
		"events_queued": int(_state.pending_events.size()) - queued_before,
		"valid": stage_after == Stages.for_instability(float(_state.instability_peak)),
	}
	if not bool(stage["valid"]):
		push_warning(
			(
				"NightLoop: stage %d does not match the peak's band — the stage machine is out of sync"
				% stage_after
			)
		)

	# 3/4 path (docs/01 §4): a crossing above already applied the Stage-2 assign or
	# the Stage-3 lock. The re-score below runs against the post-burn meters so the
	# scores and the runner-up the next prompt reads are current; a lock stays
	# frozen. No turn data and no player line: the night is not a turn, so her
	# pending question is left pending.
	var decision: Dictionary = _state.apply_turn_profile(&"", "")
	var path := {
		"before": path_before,
		"path": String(_state.path),
		"locked_before": locked_before,
		"locked": bool(_state.path_locked),
		"assigned": String(_state.path) != path_before,
		"locked_now": bool(_state.path_locked) and not locked_before,
		"runner_up": String(_state.path_runner_up),
		"scores": _state.path_scores.duplicate(true),
		"tied": bool(decision.get("tied", false)),
		"valid": _path_rule_holds(stage_after),
	}
	if not bool(path["valid"]):
		push_warning(
			(
				"NightLoop: path '%s' breaks the docs/01 §4 stage rule at stage %d"
				% [path["path"], stage_after]
			)
		)

	# 4/4 overnight event (docs/01 §6.3): chosen from the state the checks above
	# produced — the day that just ended, the new stage, the (possibly new) path.
	var event := OvernightEvents.select(
		day_before, stage_after, String(_state.path), _rng, _played_overnight()
	)
	if bool(event.get("once", false)):
		_note_played_overnight(String(event.get("id", "")))

	_report = {
		"day_before": day_before,
		"day": int(_state.day),
		"campaign_over": day_before >= Campaign.day_max(),
		"checks": STEPS.duplicate(),
		"meters": meters,
		"stage": stage,
		"path": path,
		"event": event,
	}
	return _report.duplicate(true)


## docs/01 §4: stage 2 assigns soft, stage 3 locks. The rule is applied by the
## crossing (GameState._refresh_stage); this is the check that it holds, so a
## malformed snapshot cannot leave the night with an impossible path state.
func _path_rule_holds(stage: int) -> bool:
	var path := String(_state.path)
	if stage >= Paths.lock_stage():
		return bool(_state.path_locked) and not path.is_empty()
	if stage >= Paths.assign_stage():
		return not path.is_empty()
	return true


func _played_overnight() -> Array:
	var stored: Variant = _state.get_flag(FLAG_PLAYED_OVERNIGHT, [])
	return stored if stored is Array else []


func _note_played_overnight(id: String) -> void:
	if id.is_empty():
		return
	var stored: Array = _played_overnight().duplicate()
	if not stored.has(id):
		stored.append(id)
		_state.set_flag(FLAG_PLAYED_OVERNIGHT, stored)
