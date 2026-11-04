extends GdUnitTestSuite
## P2.19 — docs/01 §1's night, in the bible's order:
##
##   night: meters update → stage check → path check → overnight event
##
## The suite drives a fresh GameState (the StageSteering/StagesTest pattern: a
## GameState instance, no autoload ring) and asserts each step against the ONE
## definition it delegates to — Meters' daily burn, Stages' bands and transition,
## Paths' assign/lock pair — plus the step-to-step order that makes this a night.

const GameStateScript := preload("res://autoload/GameState.gd")
const NightLoopScript := preload("res://llm/NightLoop.gd")
const CampaignScript := preload("res://llm/Campaign.gd")
const OvernightEventsScript := preload("res://llm/OvernightEvents.gd")
const StagesScript := preload("res://llm/Stages.gd")
const PathsScript := preload("res://llm/Paths.gd")
const MetersScript := preload("res://llm/Meters.gd")
const EPS := 0.0001


func _state() -> Variant:
	return auto_free(GameStateScript.new())


func after_test() -> void:
	# The one static cache this suite can install into (see the ordering test).
	OvernightEventsScript.clear_cache()


func test_night_runs_the_checks_in_the_doc_order() -> void:
	var s: Variant = _state()
	s.set_meter(&"instability", 30.0)
	var loop: Variant = auto_free(NightLoopScript.new(s))
	var report: Dictionary = loop.resolve()
	assert_array(report["checks"]).is_equal(["meters", "stage", "path", "event"])
	# 1) meters: the day advanced and the docs/01 §2 daily burn landed.
	assert_int(report["meters"]["day_before"]).is_equal(1)
	assert_int(report["meters"]["day"]).is_equal(2)
	assert_float(report["meters"]["burn"]).is_equal_approx(MetersScript.daily_burn(), EPS)
	assert_float(report["meters"]["instability_after"]).is_equal_approx(
		float(report["meters"]["instability_before"]) + MetersScript.daily_burn(), EPS
	)
	# 2) stage: derived from the POST-burn instability, never the pre-burn one.
	assert_int(report["stage"]["after"]).is_equal(
		StagesScript.for_instability(float(report["meters"]["instability_after"]))
	)
	assert_bool(report["stage"]["valid"]).is_true()
	# 3) path: the rule holds against the post-burn stage.
	assert_bool(report["path"]["valid"]).is_true()
	# 4) event: the night's own pick (or none), never a crash.
	assert_bool(report["event"] is Dictionary).is_true()


func test_night_advances_the_day_counter() -> void:
	var s: Variant = _state()
	var days: Array = []
	s.day_changed.connect(func(day: int) -> void: days.append(day))
	var report: Dictionary = NightLoopScript.new(s).resolve()
	assert_int(report["day"]).is_equal(2)
	assert_int(int(s.day)).is_equal(2)
	assert_array(days).is_equal([2])


func test_night_locks_the_path_at_stage_three() -> void:
	# The acceptance criterion: a night that crosses into Stage 3 locks the path,
	# and the lock is permanent (docs/01 §4).
	var s: Variant = _state()
	s.bump_profile(&"warmth", 3)
	s.bump_profile(&"jealousy_bait", 1)
	s.set_meter(&"instability", 47.0)
	assert_int(int(s.stage)).is_equal(2)
	assert_bool(bool(s.path_locked)).is_false()
	var frozen := String(s.path)
	assert_str(frozen).is_equal("YANDERE")
	var report: Dictionary = NightLoopScript.new(s).resolve()
	assert_int(int(s.stage)).is_equal(3)
	assert_bool(bool(s.path_locked)).is_true()
	assert_str(String(s.path)).is_equal(frozen)
	assert_bool(report["path"]["locked_now"]).is_true()
	# A later turn that would win a different path cannot move a locked one; the
	# scores stay live so the overlay still tells the truth.
	s.bump_profile(&"meta_curiosity", 9)
	s.apply_turn_profile(&"meta")
	assert_str(String(s.path)).is_equal(frozen)
	assert_float(float(s.path_scores.get("AWAKE", 0.0))).is_greater(0.0)


func test_night_assigns_softly_at_stage_two() -> void:
	var s: Variant = _state()
	s.bump_profile(&"apathy", 3)
	s.set_meter(&"instability", 27.0)
	assert_int(int(s.stage)).is_equal(1)
	assert_str(String(s.path)).is_empty()
	var report: Dictionary = NightLoopScript.new(s).resolve()
	assert_int(int(s.stage)).is_equal(2)
	assert_str(String(s.path)).is_equal("HOLLOW")
	assert_bool(bool(s.path_locked)).is_false()
	assert_bool(report["path"]["assigned"]).is_true()
	assert_bool(report["path"]["valid"]).is_true()


func test_night_without_a_crossing_keeps_the_soft_path() -> void:
	var s: Variant = _state()
	s.bump_profile(&"warmth", 2)
	s.set_meter(&"instability", 31.0)
	assert_str(String(s.path)).is_equal("YANDERE")
	var report: Dictionary = NightLoopScript.new(s).resolve()
	assert_bool(report["stage"]["crossed"]).is_false()
	assert_int(int(s.stage)).is_equal(2)
	assert_str(String(s.path)).is_equal("YANDERE")
	assert_bool(bool(s.path_locked)).is_false()


func test_night_picks_the_event_from_the_post_burn_stage() -> void:
	# A synthetic table whose only event is Stage 3+ proves the ordering: at
	# instability 47 the night's own burn crosses into Stage 3 and the row fires;
	# at 27 the same table has nothing to offer in Stage 2.
	(
		OvernightEventsScript
		. use_document(
			{
				"screen":
				{
					"day_label": "Day {day}",
					"night_label": "Night",
					"morning_line": "good morning.",
					"skip_hint": "",
					"message_format": "{time} — {text}",
					"skip_after_s": 3.0,
					"hold_s": 1.0,
				},
				"events":
				[
					{
						"id": "N01",
						"title": "late",
						"kind": "messages",
						"available": {"days": [1, 14], "stages": [3, 5], "paths": "any"},
						"stage_variants": {"3": [{"time": "2:00 AM", "text": "hi"}]},
					},
				],
			}
		)
	)
	var crossing: Variant = _state()
	crossing.set_meter(&"instability", 47.0)
	var report: Dictionary = NightLoopScript.new(crossing).resolve()
	assert_int(int(report["stage"]["after"])).is_equal(3)
	assert_str(String(report["event"].get("id", ""))).is_equal("N01")
	var quiet: Variant = _state()
	quiet.set_meter(&"instability", 27.0)
	var none: Dictionary = NightLoopScript.new(quiet).resolve()
	assert_int(int(none["stage"]["after"])).is_equal(2)
	assert_dict(none["event"]).is_empty()


func test_night_crossing_queues_one_transition_line() -> void:
	var s: Variant = _state()
	s.set_meter(&"instability", 27.0)
	s.take_pending_events()
	var report: Dictionary = NightLoopScript.new(s).resolve()
	assert_int(report["stage"]["after"]).is_equal(2)
	assert_bool(report["stage"]["crossed"]).is_true()
	assert_int(report["stage"]["events_queued"]).is_equal(1)
	assert_array(s.pending_events).has_size(1)
	assert_str(String(s.pending_events[0])).starts_with("EVENT: ")
	var spec: Dictionary = report["stage"]["transition"]
	assert_int(int(spec["stage"])).is_equal(2)
	assert_float(float(spec["duration_s"])).is_between(
		StagesScript.MIN_DURATION_S, StagesScript.MAX_DURATION_S
	)


func test_night_keeps_her_pending_question() -> void:
	# A night is not a turn (P2.19 + P2.12's seam note): the path check re-scores,
	# it must not count as an empty reply and clear docs/01 §5 T15's question.
	var s: Variant = _state()
	s.last_question = "Do you like me?"
	s.bump_profile(&"warmth", 1)
	NightLoopScript.new(s).resolve()
	assert_str(String(s.last_question)).is_equal("Do you like me?")


func test_night_resolves_once() -> void:
	var s: Variant = _state()
	var loop: Variant = auto_free(NightLoopScript.new(s))
	var first: Dictionary = loop.resolve()
	var second: Dictionary = loop.resolve()
	assert_int(int(s.day)).is_equal(2)
	assert_dict(second).is_equal(first)
	assert_dict(loop.report()).is_equal(first)


func test_last_night_does_not_roll_the_campaign_over() -> void:
	var s: Variant = _state()
	s.day = CampaignScript.day_max()
	var report: Dictionary = NightLoopScript.new(s).resolve()
	assert_bool(report["campaign_over"]).is_true()
	assert_int(report["day"]).is_equal(CampaignScript.day_max())
	assert_float(report["meters"]["burn"]).is_zero()


func test_night_invariants_over_a_full_campaign() -> void:
	# 14 nights of ordinary life: the ratchet floor, the stage/peak coupling and the
	# path rule hold after every one of them (docs/01 §2–§4).
	var s: Variant = _state()
	for _day: int in CampaignScript.day_max():
		s.apply_turn_profile(&"flirt")
		s.apply_turn_meters({})
		var report: Dictionary = NightLoopScript.new(s).resolve()
		assert_bool(report["stage"]["valid"]).is_true()
		assert_bool(report["path"]["valid"]).is_true()
		assert_float(s.instability).is_greater_equal(s.instability_floor - EPS)
		assert_int(int(report["day"])).is_less_equal(CampaignScript.day_max())
		if int(s.stage) >= PathsScript.lock_stage():
			assert_bool(bool(s.path_locked)).is_true()
	assert_int(int(s.day)).is_equal(CampaignScript.day_max())
