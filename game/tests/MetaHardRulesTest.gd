extends GdUnitTestSuite
## P3.08 — the docs/05 §0 hard rules, one test per rule the catalogue itself
## can break. The gate is `MetaDirector._hard_rule_violation()`: `eligible()`
## and therefore the roller refuse a row that trips it, so a malformed row can
## never reach the model's `action` enum.
##
## Rules 3 (closing always works, Esc always pauses) and the "logged for Extras"
## half of rule 5 are structural rather than data, which is why they are
## asserted against the node itself here and against the close path in
## MetaSchedulerTest.gd.


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	MetaDirector.reset_session()
	MetaDirector.set_seed_base(7)
	MetaDirector.load_catalog()
	Settings.immersion = "standard"


func test_shipped_catalogue_passes_every_hard_rule() -> void:
	# Rule 4 is the one rule that depends on the player: under Immersion: Deep
	# the whole shipped catalogue is legal, and under the default Standard the
	# only refusals are the OS-level rows asking for the opt-in — never a data
	# error. `state()` is what the F3 overlay shows.
	Settings.immersion = "deep"
	for action: Variant in MetaDirector.action_ids():
		assert_str(MetaDirector._hard_rule_violation(String(action))).is_equal("")
	Settings.immersion = "standard"
	var violations: Dictionary = MetaDirector.state()["hard_rule_violations"]
	# window_shake (M13), push_window (M14), look_at_me (M15) — the Imm. rows.
	assert_int(violations.size()).is_equal(3)
	for action: String in violations:
		assert_str(String(violations[action])).starts_with("R4")


func test_hard_rule_1_writes_outside_user_dir_are_refused() -> void:
	# docs/05 §0 rule 1: the game never touches a file outside user://. A row
	# that names any other target is a data error, not a runtime negotiation.
	GameState.set_meter(&"instability", 55.0)  # stage 3
	for target: String in ["/home/player/.ssh/authorized_keys", "res://data/x.txt", "C:/x"]:
		MetaDirector.set_catalog({"events": {"call_player_name": _row({"writes": target})}})
		assert_str(MetaDirector._hard_rule_violation("call_player_name")).starts_with("R1")
		assert_bool(MetaDirector.eligible("call_player_name", 3)).is_false()
	# A traversal path is the same escape wearing the user:// scheme.
	MetaDirector.set_catalog(
		{"events": {"call_player_name": _row({"writes": "user://../.ssh/authorized_keys"})}}
	)
	assert_str(MetaDirector._hard_rule_violation("call_player_name")).starts_with("R1")
	assert_array(MetaDirector.offers(3)).is_empty()
	# With every row refused, the enum is exactly ["none"] — the criterion.
	var schema := TurnSchema.build_turn_schema(3, MetaDirector.offers(3))
	assert_array(schema["properties"]["action"]["enum"]).is_equal(["none"])
	# The shipped letter row is the legal shape: user:// and no traversal.
	MetaDirector.load_catalog()
	assert_str(MetaDirector._hard_rule_violation("write_note")).is_equal("")


func test_hard_rule_2_network_and_real_crash_rows_are_refused() -> void:
	# docs/05 §0 rule 2: no network calls, ever; every "crash" is an in-game
	# scene. Each forbidden flag alone is enough to stop the row.
	GameState.set_meter(&"instability", 55.0)  # stage 3
	for flag: String in [
		"network", "real_crash", "delete_files", "move_files", "read_personal_files"
	]:
		var overrides := {}
		overrides[flag] = true
		MetaDirector.set_catalog({"events": {"call_player_name": _row(overrides)}})
		assert_str(MetaDirector._hard_rule_violation("call_player_name")).starts_with("R")
		assert_bool(MetaDirector.eligible("call_player_name", 3)).is_false()
		assert_array(MetaDirector.offers(3)).is_empty()


func test_hard_rule_3_scheduler_never_takes_input() -> void:
	# docs/05 §0 rule 3: Esc always opens the safe pause, and closing always
	# costs at most one extra press. The scheduler never reads input and never
	# touches the close path — MetaDirector's only global hook is the window's
	# `close_requested` (see MetaSchedulerTest), so nothing here can swallow Esc.
	assert_bool(MetaDirector.has_method("_input")).is_false()
	assert_bool(MetaDirector.has_method("_unhandled_input")).is_false()
	assert_bool(MetaDirector.has_method("_unhandled_key_input")).is_false()


func test_hard_rule_4_is_reported_as_a_violation_not_a_crash() -> void:
	# The §0 rule-4 gate is visible through the same accessor the overlay and
	# the roller use: Standard names the rule, Deep clears it.
	Settings.immersion = "standard"
	assert_str(MetaDirector._hard_rule_violation("push_window")).starts_with("R4")
	Settings.immersion = "deep"
	assert_str(MetaDirector._hard_rule_violation("push_window")).is_equal("")


func test_hard_rule_5_row_without_a_fallback_is_refused() -> void:
	# docs/05 §0 rule 5: every effect has an accessibility fallback. A row that
	# names none is never offered, so a player on an unsupported platform never
	# loses the beat to a silent no-op.
	GameState.set_meter(&"instability", 55.0)  # stage 3
	var bare := {
		"meta": "M28",
		"stage": 3,
		"note_line": "EVENT: You used the player's name.",
	}
	MetaDirector.set_catalog({"events": {"call_player_name": bare}})
	assert_str(MetaDirector._hard_rule_violation("call_player_name")).starts_with("R5")
	assert_bool(MetaDirector.eligible("call_player_name", 3)).is_false()
	MetaDirector.set_catalog({"events": {"call_player_name": _row({})}})
	assert_bool(MetaDirector.eligible("call_player_name", 3)).is_true()


func test_hard_rule_5_every_fired_event_is_logged_for_extras() -> void:
	# docs/05 §0 rule 5 (second half): the effect is logged so the player can
	# review "what happened" in Extras. The ledger is the `meta_seen` flag, so
	# it survives the session and a resume.
	GameState.set_meter(&"instability", 75.0)  # stage 4
	MetaDirector.note_scene("D04")
	var offers: Array = MetaDirector.offers(4)
	assert_int(offers.size()).is_greater(0)
	MetaDirector.execute_after_text(String(offers[0]))
	var log: Array = MetaDirector.session_log()
	assert_int(log.size()).is_equal(1)
	var fired_id := String((log[0] as Dictionary).get("id", ""))
	assert_array(MetaDirector.events_seen()).contains(fired_id)
	var seen: Dictionary = MetaDirector.state()
	assert_array(seen["events_seen"]).contains(fired_id)


func test_hard_rule_4_survives_a_deleted_declaration() -> void:
	# r1 SAF-1: rule 4 is a property of the EFFECT, not of the row's own flag.
	# The shipped M13 row with `immersion_deep` deleted is still an OS-level
	# trick, so the default Standard immersion must refuse to offer it.
	Settings.immersion = "standard"
	var rows: Dictionary = MetaDirector._events.duplicate(true)
	var shaken: Dictionary = (rows["window_shake"] as Dictionary).duplicate(true)
	shaken.erase("immersion_deep")
	rows["window_shake"] = shaken
	MetaDirector.set_catalog({"events": rows})
	assert_str(MetaDirector._hard_rule_violation("window_shake")).starts_with("R4")
	GameState.set_meter(&"instability", 55.0)  # stage 3
	assert_bool(MetaDirector.eligible("window_shake", 3)).is_false()
	assert_array(MetaDirector.offers(3)).not_contains("window_shake")
	# The only way back is the player's opt-in, never a data edit. The roll above
	# may have reserved the scene's one offer; clear the session so that budget
	# cannot decide this assertion.
	Settings.immersion = "deep"
	MetaDirector.reset_session()
	assert_str(MetaDirector._hard_rule_violation("window_shake")).is_equal("")
	assert_bool(MetaDirector.eligible("window_shake", 3)).is_true()


func test_hard_rule_1_a_write_effect_must_declare_writes() -> void:
	# r1 SAF-2: rule 1 cannot be opt-in. `write_note` is a write effect by its
	# class, so a row that drops `writes` is refused instead of promising a file
	# the gate cannot check.
	GameState.set_meter(&"instability", 35.0)  # stage 2
	var letter := {
		"meta": "M31",
		"stage": 2,
		"fallback": "Read-only game folder: the letter is an in-game page.",
		"note_line": "EVENT: You wrote a letter into the game's own folder.",
	}
	MetaDirector.set_catalog({"events": {"write_note": letter}})
	assert_str(MetaDirector._hard_rule_violation("write_note")).starts_with("R1")
	assert_bool(MetaDirector.eligible("write_note", 2)).is_false()
	assert_array(MetaDirector.offers(2)).is_empty()
	# The declared target is what makes it legal — and only inside user://.
	letter["writes"] = "user://letters/"
	MetaDirector.set_catalog({"events": {"write_note": letter}})
	assert_str(MetaDirector._hard_rule_violation("write_note")).is_equal("")
	letter["writes"] = "/home/player/.ssh/authorized_keys"
	MetaDirector.set_catalog({"events": {"write_note": letter}})
	assert_str(MetaDirector._hard_rule_violation("write_note")).starts_with("R1")


func test_hard_rule_2_unknown_effect_keys_are_refused() -> void:
	# r1 SAF-2: an effect key the gate does not know (`cursor_warp`, `reads`, a
	# future `network_v2`) is a hard failure, not a silent pass — otherwise the
	# rules would only bind rows that volunteer the keys they already reject.
	GameState.set_meter(&"instability", 55.0)  # stage 3
	for key: String in ["cursor_warp", "reads", "network_v2"]:
		var overrides := {}
		overrides[key] = true
		MetaDirector.set_catalog({"events": {"call_player_name": _row(overrides)}})
		assert_str(MetaDirector._hard_rule_violation("call_player_name")).starts_with("R0")
		assert_bool(MetaDirector.eligible("call_player_name", 3)).is_false()
		assert_array(MetaDirector.offers(3)).is_empty()


func test_hard_rule_5_a_numeric_fallback_is_not_a_fallback() -> void:
	# docs/05 §0 rule 5 wants a sentence the player still gets the beat from;
	# `fallback: 0` stringifies to "0", which is not one (r1 SAF-2).
	GameState.set_meter(&"instability", 55.0)  # stage 3
	var row := _row({"fallback": 0})
	MetaDirector.set_catalog({"events": {"call_player_name": row}})
	assert_str(MetaDirector._hard_rule_violation("call_player_name")).starts_with("R5")
	assert_bool(MetaDirector.eligible("call_player_name", 3)).is_false()


func test_unclassified_actions_are_refused() -> void:
	# docs/05 §0's class table is total: a NEW catalogue action cannot be
	# offered before someone classes it. `peek_window` (M16, an OS-level trick
	# P3.09 owns) is refused outright — never treated as in-window — even with
	# the Deep opt-in, because the class is what the opt-in is checked against.
	Settings.immersion = "deep"
	var row := _row({}).merged({"meta": "M16"})
	MetaDirector.set_catalog({"events": {"peek_window": row}})
	assert_str(MetaDirector._hard_rule_violation("peek_window")).starts_with("R0")
	assert_bool(MetaDirector.eligible("peek_window", 4)).is_false()
	assert_array(MetaDirector.offers(4)).is_empty()


func test_every_catalogue_action_is_classed() -> void:
	# The table and the shipped data cannot drift: every offered row resolves to
	# a verdict, and the rows that declare the Immersion marker are exactly the
	# ones the gate refuses under Standard. `tests/test_meta_events.py` pins the
	# same property on the data side.
	Settings.immersion = "standard"
	for action: Variant in MetaDirector.action_ids():
		var row: Dictionary = MetaDirector._events[String(action)]
		var reason := MetaDirector._hard_rule_violation(String(action))
		if bool(row.get("immersion_deep", false)):
			assert_str(reason).starts_with("R4")
		else:
			assert_str(reason).is_equal("")


## A legal P3.08 row with `overrides` applied — the tampering helper above.
func _row(overrides: Dictionary) -> Dictionary:
	var row := {
		"meta": "M28",
		"stage": 3,
		"fallback": 'No name given: she uses "you".',
		"note_line": "EVENT: You used the player's name.",
	}
	for key: Variant in overrides:
		row[key] = overrides[key]
	return row
