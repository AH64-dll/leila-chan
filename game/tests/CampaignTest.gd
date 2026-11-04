extends GdUnitTestSuite
## P2.19 — the campaign half of the day/night loop: the day counter, the scenario
## availability rule (docs/08 §7's `available` block) and the day's pick. The pool
## is injected in the synthetic cases so the rule is exercised at days/stages/paths
## the one shipped scenario cannot reach.

const GameStateScript := preload("res://autoload/GameState.gd")
const CampaignScript := preload("res://llm/Campaign.gd")
const ScenarioLoaderScript := preload("res://scenario/ScenarioLoader.gd")
const D02_PATH := "res://data/scenarios/D02_cafe.json"


func _state() -> Variant:
	return auto_free(GameStateScript.new())


func after_test() -> void:
	ScenarioLoaderScript.clear_pool_cache()


func _scenario(id: String, days: Array, stages: Array, paths: Variant) -> Dictionary:
	return {
		"id": id,
		"kind": "date",
		"title": id,
		"background": "bg/cafe",
		"music": "calm",
		"ambience": "cafe",
		"available": {"days": days, "stages": stages, "paths": paths},
		"goal": "goal",
		"prompt": "prompt",
		"stage_variants": {"0": "variant"},
		"path_twists": {},
		"events": [],
		"end": {"min_turns": 1, "max_turns": 2, "on_goal": "end_date"},
	}


func _row(id: String, days: Array, stages: Array, paths: Variant) -> Dictionary:
	return {
		"path": "res://data/scenarios/%s.json" % id,
		"id": id,
		"scenario": _scenario(id, days, stages, paths),
	}


func test_day_counter_reads_the_game_state() -> void:
	var s: Variant = _state()
	var campaign: Variant = auto_free(CampaignScript.new(s))
	assert_int(campaign.day()).is_equal(1)
	assert_int(CampaignScript.day_max()).is_equal(14)
	assert_int(CampaignScript.day_max()).is_equal(GameStateScript.DAY_MAX)
	assert_bool(campaign.is_last_day()).is_false()
	s.day = CampaignScript.day_max()
	assert_bool(campaign.is_last_day()).is_true()


func test_shipped_pool_lists_the_dates() -> void:
	ScenarioLoaderScript.clear_pool_cache()
	var pool: Array = ScenarioLoaderScript.pool()
	assert_int(pool.size()).is_greater_equal(1)
	var ids := {}
	for row: Dictionary in pool:
		assert_str(String(row["path"])).starts_with(ScenarioLoaderScript.SCENARIO_DIR)
		assert_str(String(row["id"])).is_not_empty()
		assert_dict(row["scenario"]).is_not_empty()
		ids[String(row["id"])] = true
	assert_bool(ids.has("D02_cafe")).is_true()
	assert_int(ids.size()).is_equal(pool.size())


func test_availability_follows_the_available_block() -> void:
	var early := _scenario("A", [1, 3], [0, 5], "any")
	var late := _scenario("B", [2, 5], [3, 5], "any")
	var path_only := _scenario("C", [1, 14], [0, 5], ["YANDERE"])
	assert_bool(ScenarioLoaderScript.is_available(early, 2, 0, "")).is_true()
	assert_bool(ScenarioLoaderScript.is_available(early, 4, 0, "")).is_false()
	assert_bool(ScenarioLoaderScript.is_available(late, 2, 2, "")).is_false()
	assert_bool(ScenarioLoaderScript.is_available(late, 2, 3, "")).is_true()
	assert_bool(ScenarioLoaderScript.is_available(path_only, 2, 0, "")).is_false()
	assert_bool(ScenarioLoaderScript.is_available(path_only, 2, 0, "YANDERE")).is_true()
	assert_bool(ScenarioLoaderScript.is_available(path_only, 2, 0, "AWAKE")).is_false()
	# A malformed block is unavailable, never "always".
	assert_bool(ScenarioLoaderScript.is_available({"available": {"days": [1]}}, 1, 0)).is_false()
	assert_bool(ScenarioLoaderScript.is_available({}, 1, 0)).is_false()


func test_begin_day_picks_a_scenario_that_may_run_today() -> void:
	var s: Variant = _state()
	var campaign: Variant = CampaignScript.new(s)
	var pool := [_row("A", [1, 3], [0, 5], "any"), _row("B", [2, 5], [0, 5], "any")]
	var pick: Dictionary = campaign.begin_day(pool)
	assert_str(String(pick["id"])).is_equal("A")
	assert_array(campaign.played_ids()).has_size(1)
	assert_str(String(campaign.played_ids()[0])).is_equal("A")


func test_begin_day_honours_the_nights_queue() -> void:
	var s: Variant = _state()
	var campaign: Variant = CampaignScript.new(s)
	var pool := [_row("A", [1, 3], [0, 5], "any"), _row("B", [2, 5], [0, 5], "any")]
	s.set_flag(&"next_scenario", "res://data/scenarios/B.json")
	var pick: Dictionary = campaign.begin_day(pool)
	assert_str(String(pick["id"])).is_equal("B")
	assert_bool(s.flags.has("next_scenario")).is_false()
	assert_array(campaign.played_ids()).has_size(1)
	assert_str(String(campaign.played_ids()[0])).is_equal("B")


func test_next_scenario_queues_the_new_day() -> void:
	var s: Variant = _state()
	var campaign: Variant = CampaignScript.new(s)
	var pool := [_row("A", [1, 3], [0, 5], "any"), _row("B", [2, 5], [0, 5], "any")]
	assert_str(String(campaign.begin_day(pool)["id"])).is_equal("A")
	s.day = 2
	var next: Dictionary = campaign.next_scenario(pool)
	assert_str(String(next["id"])).is_equal("B")
	assert_str(String(s.get_flag(&"next_scenario", ""))).is_equal("res://data/scenarios/B.json")
	# The queued pick is already in the played set: a save taken at night carries
	# both, so Continue cannot reopen the date the queue owns (CODE-2).
	assert_array(campaign.played_ids()).has_size(2)
	assert_str(String(campaign.played_ids()[0])).is_equal("A")
	assert_str(String(campaign.played_ids()[1])).is_equal("B")


func test_next_scenario_never_repeats_a_played_date() -> void:
	var s: Variant = _state()
	var campaign: Variant = CampaignScript.new(s)
	var pool := [_row("A", [1, 3], [0, 5], "any"), _row("B", [1, 3], [0, 5], "any")]
	s.set_flag(&"next_scenario", "res://data/scenarios/A.json")
	campaign.begin_day(pool)
	var next: Dictionary = campaign.next_scenario(pool)
	assert_str(String(next["id"])).is_equal("B")
	assert_array(campaign.played_ids()).has_size(2)
	assert_str(String(campaign.played_ids()[1])).is_equal("B")


## docs/01 §6.1/§6.2 + the P2.18 handoff: a day is a date scene and an interrupt
## is an in-date event, so the day's pick never hands out an interrupt row — an
## interrupt-only pool leaves the day empty rather than running one as the day.
func test_day_pick_never_returns_an_interrupt() -> void:
	var s: Variant = _state()
	var interrupt := _scenario("I01", [1, 14], [0, 5], "any")
	interrupt["kind"] = "interrupt"
	var row := {"path": "res://data/scenarios/I01.json", "id": "I01", "scenario": interrupt}
	var campaign: Variant = CampaignScript.new(s)
	assert_dict(campaign.begin_day([row])).is_empty()
	assert_dict(campaign.next_scenario([row])).is_empty()
	assert_array(campaign.played_ids()).is_empty()


## The merged pool ships six dates and the I01 interrupt in the same directory:
## no seed may draw the interrupt as the day, and every seed still opens day 1.
func test_shipped_campaign_never_opens_on_an_interrupt() -> void:
	ScenarioLoaderScript.clear_pool_cache()
	var pool: Array = ScenarioLoaderScript.pool()
	var kinds := {}
	for row: Dictionary in pool:
		kinds[String(row["scenario"].get("kind", ""))] = true
	assert_bool(kinds.has("interrupt")).is_true()
	for seed_value: int in 64:
		var s: Variant = _state()
		s.set_flag(&"campaign_seed", seed_value)
		var pick: Dictionary = CampaignScript.new(s).begin_day(pool)
		assert_dict(pick).is_not_empty()
		assert_str(String(pick.get("scenario", {}).get("kind", ""))).is_equal("date")


## A stale queue that names an interrupt is not honoured as a day, and it is
## consumed rather than shadowing the availability pick on every later morning.
func test_begin_day_consumes_an_unusable_queue() -> void:
	var s: Variant = _state()
	var interrupt := _scenario("I01", [1, 14], [0, 5], "any")
	interrupt["kind"] = "interrupt"
	var row := {"path": "res://data/scenarios/I01.json", "id": "I01", "scenario": interrupt}
	s.set_flag(&"next_scenario", "res://data/scenarios/I01.json")
	var campaign: Variant = CampaignScript.new(s)
	var pick: Dictionary = campaign.begin_day([row, _row("A", [1, 14], [0, 5], "any")])
	assert_str(String(pick["id"])).is_equal("A")
	assert_bool(s.flags.has("next_scenario")).is_false()


## P2.20/P2.19: Continue lands on the Date with the save's own scenario. That
## date is today's, so the campaign agrees: the night's queue is consumed and the
## date is marked played (CODE-2's save-resume half).
func test_resume_day_consumes_the_queue_and_marks_the_date_played() -> void:
	var s: Variant = _state()
	s.set_flag(&"next_scenario", D02_PATH)
	CampaignScript.new(s).resume_day(D02_PATH)
	assert_bool(s.flags.has("next_scenario")).is_false()
	assert_array(CampaignScript.new(s).played_ids()).has_size(1)
	assert_str(String(CampaignScript.new(s).played_ids()[0])).is_equal("D02_cafe")
	# An interrupt save consumes the queue but never enters the played set.
	s.set_flag(&"next_scenario", D02_PATH)
	CampaignScript.new(s).resume_day("res://data/scenarios/I01_phone_call.json")
	assert_bool(s.flags.has("next_scenario")).is_false()
	assert_array(CampaignScript.new(s).played_ids()).has_size(1)
	assert_str(String(CampaignScript.new(s).played_ids()[0])).is_equal("D02_cafe")


func test_pick_is_deterministic_and_seed_driven() -> void:
	var pool := [_row("A", [1, 14], [0, 5], "any"), _row("B", [1, 14], [0, 5], "any")]
	var first: Variant = _state()
	var second: Variant = _state()
	var a: Dictionary = CampaignScript.new(first).begin_day(pool)
	var b: Dictionary = CampaignScript.new(second).begin_day(pool)
	assert_str(String(a["id"])).is_equal(String(b["id"]))
	# The campaign seed is the only knob: every seed is still a legal pick, and the
	# pool must be reachable in more than one order.
	var seen := {}
	for seed_value: int in 16:
		var s: Variant = _state()
		s.set_flag(&"campaign_seed", seed_value)
		seen[String(CampaignScript.new(s).begin_day(pool)["id"])] = true
	assert_int(seen.size()).is_equal(2)


func test_no_available_scenario_keeps_the_day_empty() -> void:
	var s: Variant = _state()
	var campaign: Variant = CampaignScript.new(s)
	var pool := [_row("B", [5, 5], [0, 5], "any")]
	assert_dict(campaign.begin_day(pool)).is_empty()
	assert_array(campaign.played_ids()).is_empty()
	assert_dict(campaign.next_scenario(pool)).is_empty()
	assert_str(String(s.get_flag(&"next_scenario", ""))).is_empty()


func test_available_scenarios_ignores_foreign_rows() -> void:
	var rows: Array = [null, 3, {"path": "x"}, _row("A", [1, 14], [0, 5], "any")]
	var available: Array = ScenarioLoaderScript.available_scenarios(rows, 1, 0, "")
	assert_int(available.size()).is_equal(1)
	assert_str(String(available[0]["id"])).is_equal("A")


func test_shipped_date_is_available_on_day_one() -> void:
	var d02: Dictionary = ScenarioLoaderScript.load_scenario(D02_PATH)
	assert_bool(ScenarioLoaderScript.is_available(d02, 1, 0, "")).is_true()
	assert_bool(ScenarioLoaderScript.is_available(d02, 15, 0, "")).is_false()


## The campaign's own state lives in GameState.flags (docs/07 §3.5), so a save
## taken at night must resume the same day, the same played list and the same
## queued date — the checklist's "save/load round-trip covers any new state".
func test_campaign_state_survives_the_snapshot() -> void:
	var s: Variant = _state()
	var pool := [_row("A", [1, 14], [0, 5], "any"), _row("B", [1, 14], [0, 5], "any")]
	s.set_flag(&"next_scenario", "res://data/scenarios/B.json")
	assert_str(String(CampaignScript.new(s).begin_day(pool)["id"])).is_equal("B")
	var restored: Variant = _state()
	assert_bool(restored.from_dict(s.to_dict())).is_true()
	var replay: Variant = CampaignScript.new(restored)
	assert_array(replay.played_ids()).has_size(1)
	assert_str(String(replay.played_ids()[0])).is_equal("B")
	# The played list survives, so the reloaded campaign does not replay B; the
	# queue the night wrote is consumed as the pick is made, and both picks are
	# in the played set before any save can name them (CODE-2).
	var next: Dictionary = replay.next_scenario(pool)
	assert_str(String(next["id"])).is_equal("A")
	assert_array(replay.played_ids()).has_size(2)
	assert_str(String(replay.played_ids()[1])).is_equal("A")
	assert_bool(restored.flags.has("next_scenario")).is_true()
