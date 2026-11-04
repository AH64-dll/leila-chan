extends GdUnitTestSuite
## P3.08 — docs/05 §3 MetaDirector scheduling: 0–2 offered actions per turn,
## every open offer carrying its docs/05 §2 OPPORTUNITY line, the per-scene
## caps, "never two in a row", the per-event session/save/cooldown kinds, and
## the docs/05 §0 gates (Deep-immersion rows need the opt-in; a close press is
## never more than one extra click away).
##
## The lottery is deterministic per (campaign seed, turn) — `set_seed_base`
## pins it — and `set_catalog` swaps data/meta_events.json for a suite-owned
## document, the same seam Triggers.set_catalog uses.


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	MetaDirector.reset_session()
	MetaDirector.set_seed_base(7)
	MetaDirector.load_catalog()
	Settings.immersion = "standard"


func test_enum_is_none_only_until_an_offer_opens() -> void:
	# docs/02 §2.4 + the acceptance criterion: below the catalogue's lowest gate
	# (St 2, M31) no offer exists, and the schema's action enum is exactly
	# ["none"]. The floor is derived from the rows, never a second number.
	GameState.set_meter(&"instability", 20.0)  # stage 1
	assert_int(MetaDirector.scheduler_stage_min()).is_equal(2)
	assert_array(MetaDirector.offers(1)).is_empty()
	var schema := TurnSchema.build_turn_schema(1, MetaDirector.offers(1))
	var action_enum: Array = schema["properties"]["action"]["enum"]
	assert_array(action_enum).is_equal(["none"])


func test_m31_letter_row_is_offerable_at_its_documented_stage_2_gate() -> void:
	# docs/05 §1.4 gives M31 ("A letter") St 2; the scheduler's floor is the
	# lowest row gate, so that documented gate is reachable (r1 CODE-5/DES-4:
	# a hand-kept `scheduler_stage_min: 3` used to hide it forever).
	assert_int(MetaDirector.scheduler_stage_min()).is_equal(2)
	GameState.set_meter(&"instability", 35.0)  # stage 2
	assert_bool(MetaDirector.eligible("write_note", 2)).is_true()
	assert_array(MetaDirector.offers(2)).contains("write_note")


func test_schema_enum_matches_the_open_offers() -> void:
	# The enum is ["none"] plus exactly what was offered — the scheduler's
	# stage-4 catalogue is drawn through the real TurnSchema gate.
	GameState.set_meter(&"instability", 75.0)  # stage 4
	var offers: Array = MetaDirector.offers(4)
	assert_int(offers.size()).is_between(1, 2)
	var schema := TurnSchema.build_turn_schema(4, offers)
	var action_enum: Array = schema["properties"]["action"]["enum"]
	assert_str(str(action_enum[0])).is_equal("none")
	for action: Variant in offers:
		assert_array(action_enum).contains(action)


func test_never_more_than_two_offers() -> void:
	# docs/05 §3 caps the enum at 0–2 actions even when more rows are eligible:
	# a catalogue of three stage-4 actions can only ever open two (stage 4's
	# scene budget is 2, so the scene cap is not what stops the third).
	var row := {"stage": 4, "fallback": "in-window swap", "note_line": "EVENT: x"}
	var doc := {
		"events":
		{
			"rename_window": row.merged({"meta": "M12"}),
			"call_player_name": row.merged({"meta": "M28"}),
			"write_note":
			row.merged({"meta": "M31", "note_line": "EVENT: y", "writes": "user://letters/"}),
		}
	}
	MetaDirector.set_catalog(doc)
	GameState.set_meter(&"instability", 75.0)  # stage 4 → scene cap 2
	var offers: Array = MetaDirector.offers(4)
	assert_int(offers.size()).is_equal(2)
	assert_array(MetaDirector.offers(4)).is_equal(offers)  # one roll per turn


func test_every_open_offer_carries_its_opportunity_line() -> void:
	# docs/05 §2 "only on turns with an offer": each offered action's own
	# sentence is delivered WITH this turn's events (the Director merges
	# `turn_events()` into the step-1 snapshot), never queued for the next
	# submit, and closing the offer drops it with the enum entry.
	GameState.set_meter(&"instability", 75.0)  # stage 4
	var offers: Array = MetaDirector.offers(4)
	var events := MetaDirector.turn_events([], 4)
	for action: Variant in offers:
		var line := TurnSchema.opportunity_line(String(action))
		assert_str(line).starts_with("OPPORTUNITY")
		assert_array(events).contains(line)
		# The pending queue is not the carrier (r1 CODE-1): nothing to drain
		# on a later submit.
		assert_array(GameState.pending_events).not_contains(line)
	MetaDirector.execute_after_text(String(offers[0]))
	var spent_line := TurnSchema.opportunity_line(String(offers[0]))
	assert_array(MetaDirector.turn_events([], 4)).not_contains(spent_line)


func test_execute_counts_the_event_and_tells_her() -> void:
	# docs/05 §2 + §3: a taken offer is the meta event — the Extras ledger
	# (`meta_seen`), the session log, and the next turn's EVENT note all record
	# it once.
	GameState.set_meter(&"instability", 75.0)  # stage 4
	var offers: Array = MetaDirector.offers(4)
	var action := String(offers[0])
	MetaDirector.execute_after_text(action)
	var id := str((MetaDirector._events.get(action, {}) as Dictionary).get("meta", action))
	assert_array(MetaDirector.events_seen()).contains(id)
	var log: Array = MetaDirector.session_log()
	assert_int(log.size()).is_equal(1)
	assert_str(String((log[0] as Dictionary).get("id", ""))).is_equal(id)
	var note := str((MetaDirector._events.get(action, {}) as Dictionary).get("note_line", ""))
	assert_str(note).starts_with("EVENT:")
	assert_array(GameState.pending_events).contains(note)


func test_never_two_meta_events_in_a_row() -> void:
	# docs/05 §3: exactly ONE turn is quiet after an event. This walks the
	# Director's own order (`apply_turn_meters()` advances `turn` before
	# `execute_after_text()`), so the stamp is the turn the player ANSWERED —
	# r1 CODE-2/DES-2: the unit test never advanced `turn`, which hid the
	# second, extra quiet turn the shipped pipeline produced.
	GameState.set_meter(&"instability", 75.0)  # stage 4
	var answered := int(GameState.turn)
	var offers: Array = MetaDirector.offers(4)
	assert_int(offers.size()).is_greater(0)
	GameState.advance_turn()  # what apply_turn_meters() does before step 7
	MetaDirector.execute_after_text(String(offers[0]), answered)
	assert_int(int(MetaDirector.state()["last_event_turn"])).is_equal(answered)
	# The immediately following turn is the quiet one: nothing new opens.
	assert_array(MetaDirector.offers(4)).is_empty()
	GameState.advance_turn()
	assert_array(MetaDirector.offers(4)).is_not_empty()


func test_once_per_session_cap() -> void:
	GameState.set_meter(&"instability", 75.0)  # stage 4
	Settings.immersion = "deep"  # look_at_me is an Immersion: Deep row
	MetaDirector.debug_offer("look_at_me")
	MetaDirector.execute_after_text("look_at_me")
	assert_bool(MetaDirector.eligible("look_at_me", 4)).is_false()
	MetaDirector.reset_session()
	assert_bool(MetaDirector.eligible("look_at_me", 4)).is_true()


func test_once_per_save_survives_a_session_reset() -> void:
	GameState.set_meter(&"instability", 75.0)  # stage 4
	Settings.immersion = "deep"
	MetaDirector.debug_offer("fake_crash")
	MetaDirector.execute_after_text("fake_crash")
	assert_bool(MetaDirector.eligible("fake_crash", 4)).is_false()
	# A new session does not replay a once_per_save event — the seen flag is
	# part of the save.
	MetaDirector.reset_session()
	assert_bool(MetaDirector.eligible("fake_crash", 4)).is_false()
	# A New Game (GameState.reset) wipes the save: the event may be seen again.
	GameState.reset()
	GameState.set_meter(&"instability", 75.0)
	assert_bool(MetaDirector.eligible("fake_crash", 4)).is_true()


func test_repeatable_respects_its_cooldown() -> void:
	# Stage 4's scene cap is 2, so the spent first event leaves room — the
	# cooldown (data: 6 turns) is what `eligible` is really answering here.
	GameState.set_meter(&"instability", 75.0)  # stage 4
	MetaDirector.debug_offer("rename_window")  # repeatable, cooldown 6
	MetaDirector.execute_after_text("rename_window")
	GameState.turn = 3
	assert_bool(MetaDirector.eligible("rename_window", 4)).is_false()
	GameState.turn = 6
	assert_bool(MetaDirector.eligible("rename_window", 4)).is_true()


func test_deep_immersion_rows_need_the_opt_in() -> void:
	# docs/05 §0 rule 4: OS-level tricks are never even offered under the
	# default Standard immersion — the player never meets a window trick they
	# did not opt into.
	GameState.set_meter(&"instability", 75.0)  # stage 4
	Settings.immersion = "standard"
	assert_bool(MetaDirector.eligible("window_shake", 4)).is_false()
	assert_bool(MetaDirector.eligible("push_window", 4)).is_false()
	Settings.immersion = "deep"
	assert_bool(MetaDirector.eligible("window_shake", 4)).is_true()
	# And a missing/misspelt level fails closed to Standard — the offer is
	# gated on the exact opt-in, not on a substring.
	Settings.immersion = "Deep!!"
	assert_bool(MetaDirector.eligible("window_shake", 4)).is_false()


func test_m01_still_offers_once_and_closes_on_the_second_press() -> void:
	# docs/05 §0 rule 3 with the scheduler live: the held close still offers
	# `refuse_exit` with its own OPPORTUNITY, and the next press quits through
	# the injected callable — the scheduler never extends the intercept.
	GameState.set_meter(&"instability", 55.0)  # stage 3
	var quits := [0]
	MetaDirector.set_quit_callable(func() -> void: quits[0] += 1)
	MetaDirector._on_close_requested()
	var offers: Array = MetaDirector.offers(3)
	assert_array(offers).contains("refuse_exit")
	assert_int(offers.size()).is_less_equal(2)
	MetaDirector._on_close_requested()
	assert_int(quits[0]).is_equal(1)


func test_m01_offer_evicts_a_scheduled_offer_but_never_exceeds_two() -> void:
	# docs/05 §3's 0–2 cap against M01's guarantee: two scheduled offers open in
	# a stage-4 scene (cap 2), the held close still gets its slot — the oldest
	# scheduled offer yields.
	var row := {"stage": 4, "fallback": "in-window swap", "note_line": "EVENT: x"}
	var doc := {
		"events":
		{
			"rename_window": row.merged({"meta": "M12"}),
			"call_player_name": row.merged({"meta": "M28"}),
		}
	}
	MetaDirector.set_catalog(doc)
	GameState.set_meter(&"instability", 75.0)  # stage 4 → scene cap 2
	assert_array(MetaDirector.offers(4)).has_size(2)
	MetaDirector.set_quit_callable(func() -> void: pass)
	MetaDirector._on_close_requested()
	var offers: Array = MetaDirector.offers(4)
	assert_int(offers.size()).is_equal(2)
	assert_array(offers).contains("refuse_exit")


func test_unused_scheduled_offers_expire_next_turn() -> void:
	# docs/08 §6 "this turn only": an offer the model ignored does not ride the
	# next prompt — its OPPORTUNITY line and enum entry close together, and the
	# scalpel rule keeps it off the immediately following turn too.
	GameState.set_meter(&"instability", 75.0)  # stage 4
	var offers: Array = MetaDirector.offers(4)
	var first := String(offers[0])
	var line := TurnSchema.opportunity_line(first)
	GameState.turn = 1
	var next: Array = MetaDirector.offers(4)
	assert_array(next).not_contains(first)
	assert_array(GameState.pending_events).not_contains(line)


func test_f3_debug_offer_reaches_the_enum() -> void:
	# Role checklist: every offerable action is one overlay click away, through
	# the same `_open_offer` path the scheduler uses — the Safety/execute seam
	# is never bypassed, only the lottery.
	GameState.set_meter(&"instability", 55.0)  # stage 3
	assert_bool(MetaDirector.debug_offer("call_player_name")).is_true()
	assert_array(MetaDirector.offers(3)).contains("call_player_name")
	assert_bool(MetaDirector.debug_offer("not_an_action")).is_false()


func test_f3_overlay_button_reaches_the_enum() -> void:
	# The role checklist's real seam: the F3 panel's META button, not just the
	# MetaDirector method behind it. `fire_meta` is what a click runs.
	var overlay := (
		(load("res://scenes/debug/DebugOverlay.tscn") as PackedScene).instantiate() as DebugOverlay
	)
	add_child(auto_free(overlay))
	GameState.set_meter(&"instability", 55.0)  # stage 3
	assert_bool(overlay.fire_meta("rename_window")).is_true()
	assert_array(MetaDirector.offers(3)).contains("rename_window")
	var text := overlay.get_meta_text()
	assert_str(text).starts_with("Open:")
	assert_str(text).contains("rename_window")
	# Under the default Standard immersion the overlay also names the docs/05 §0
	# rule-4 rows it is refusing, WITH the rule id and reason — a reviewer reads
	# "window_shake → R4: …", not just a list of names (r1 CODE-6/SAF-4).
	assert_str(text).contains("Blocked:")
	assert_str(text).contains("window_shake → R4: an OS-level trick needs Immersion: Deep")
	assert_bool(overlay.fire_meta("not_an_action")).is_false()
