extends GdUnitTestSuite
## P3.08 round 2 — docs/05 §3's per-scene budget, which round 1 enforced only
## when the roller collected candidates. Three seams have to hold together:
##
##   * the roll may reserve no more offers than the scene has room for
##     (r1 CODE-4/DES-5: a cap-1 scene opened two),
##   * the close path re-checks it before it holds the close, so a spent scene
##     cannot gain a `refuse_exit` on top of a scheduled event (SAF-3), and
##   * execution re-checks it, so an offer that outlived its scene budget is
##     consumed without firing.
##
## Every case walks the real `MetaDirector` caps with the shipped catalogue
## (or a one-scene fixture), never a private counter.


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	MetaDirector.reset_session()
	MetaDirector.set_seed_base(7)
	MetaDirector.load_catalog()
	Settings.immersion = "standard"


func test_per_scene_cap_bounds_the_events() -> void:
	# docs/05 §3 "max 1 meta event per scene at stage 3": the second execution
	# of the same scene cannot be offered — the budget is charged at
	# execute_after_text, not at the roll.
	GameState.set_meter(&"instability", 55.0)  # stage 3 → cap 1
	MetaDirector.note_scene("D02")
	MetaDirector.debug_offer("rename_window")
	MetaDirector.execute_after_text("rename_window")
	GameState.turn = 1
	# A spent scene rolls nothing: every candidate trips the scene cap.
	assert_array(MetaDirector.offers(3)).is_empty()
	MetaDirector.note_scene("D03")
	GameState.turn = 2
	assert_array(MetaDirector.offers(3)).is_not_empty()


func test_one_roll_reserves_only_the_scene_budget() -> void:
	# docs/05 §3: a stage-3 scene holds ONE meta event, so one roll may open one
	# offer — candidates are vetted before any offer opens, so the draw loop has
	# to re-check the budget per pick (r1 CODE-4/DES-5: this opened two).
	var row := {"stage": 3, "fallback": "in-window swap", "note_line": "EVENT: x"}
	var doc := {
		"events":
		{
			"rename_window": row.merged({"meta": "M12"}),
			"call_player_name": row.merged({"meta": "M28"}),
			"window_shake": row.merged({"meta": "M13", "immersion_deep": true}),
		}
	}
	MetaDirector.set_catalog(doc)
	Settings.immersion = "deep"  # window_shake is a §0 rule-4 trick
	GameState.set_meter(&"instability", 55.0)  # stage 3 → cap 1
	MetaDirector.note_scene("D05")
	assert_array(MetaDirector.offers(3)).has_size(1)


func test_scene_budget_is_rechecked_at_execution() -> void:
	# docs/05 §3 + §0 rule 3, the close path: a spent stage-3 scene (cap 1) buys
	# no intercept, so the press simply closes — the cap can never trap the
	# player (r1 CODE-4 / DES-5 / SAF-3).
	GameState.set_meter(&"instability", 55.0)  # stage 3 → cap 1
	MetaDirector.note_scene("D06")
	var quits := [0]
	MetaDirector.set_quit_callable(func() -> void: quits[0] += 1)
	MetaDirector.debug_offer("rename_window")
	MetaDirector.execute_after_text("rename_window")
	assert_int(int(MetaDirector.state()["scene_events"])).is_equal(1)
	MetaDirector._on_close_requested()
	assert_int(quits[0]).is_equal(1)  # the close was never held
	assert_bool(bool(MetaDirector.state()["close_held"])).is_false()
	assert_array(MetaDirector.offers(3)).is_empty()


func test_execute_drops_an_event_when_the_scene_budget_is_spent() -> void:
	# The backstop behind the reservation rule: an offer that outlived its scene
	# budget is consumed without firing, so a scene can never exceed its
	# docs/05 §3 maximum even when the offer path was bypassed (F3, debug_offer).
	GameState.set_meter(&"instability", 55.0)  # stage 3 → cap 1
	MetaDirector.note_scene("D07")
	MetaDirector.debug_offer("rename_window")
	MetaDirector.debug_offer("call_player_name")
	MetaDirector.execute_after_text("rename_window")
	assert_int(int(MetaDirector.state()["scene_events"])).is_equal(1)
	MetaDirector.execute_after_text("call_player_name")
	assert_int(int(MetaDirector.state()["scene_events"])).is_equal(1)
	assert_array(MetaDirector.events_seen()).not_contains("M28")
	assert_bool(MetaDirector._open_offers.has("call_player_name")).is_false()
