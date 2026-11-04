extends GdUnitTestSuite
## P2.19 — docs/01 §6.3's overnight events: the data table, the availability and
## weight selection rule, and the per-stage/per-path line resolution. The suite
## injects synthetic documents (use_document) wherever a shipped row would make the
## rule untestable, then restores the shipped table.

const OvernightEventsScript := preload("res://llm/OvernightEvents.gd")
const EPS := 0.0001


func after_test() -> void:
	OvernightEventsScript.clear_cache()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _message_row(id: String, once := false) -> Dictionary:
	return {
		"id": id,
		"title": "row %s" % id,
		"kind": "messages",
		"available": {"days": [1, 14], "stages": [0, 5], "paths": "any"},
		"once": once,
		"stage_variants": {"0": [{"time": "2:00 AM", "text": "hello"}]},
	}


func _black_row(id: String, once := false) -> Dictionary:
	return {
		"id": id,
		"title": "row %s" % id,
		"kind": "black",
		"available": {"days": [1, 14], "stages": [0, 5], "paths": "any"},
		"once": once,
		"duration_s": 10.0,
	}


func _document(rows: Array) -> Dictionary:
	return {
		"screen":
		{
			"day_label": "Day {day}",
			"night_label": "Night",
			"morning_line": "good morning.",
			"skip_hint": "skip",
			"message_format": "{time} — {text}",
			"skip_after_s": 3.0,
			"hold_s": 2.5,
		},
		"events": rows,
	}


func test_shipped_table_ships_n01_and_n12() -> void:
	OvernightEventsScript.clear_cache()
	var n01: Dictionary = OvernightEventsScript.get_event("N01")
	var n12: Dictionary = OvernightEventsScript.get_event("N12")
	assert_str(String(n01.get("title", ""))).is_equal("Text messages from her at 2 AM")
	assert_str(String(n01.get("kind", ""))).is_equal("messages")
	assert_str(String(n12.get("title", ""))).is_equal("Nothing")
	assert_str(String(n12.get("kind", ""))).is_equal("black")
	assert_float(float(n12.get("duration_s", 0.0))).is_equal_approx(10.0, EPS)
	# docs/01 §6.3's "a black screen for 10 seconds": the wait is the event, so it
	# has no click window.
	assert_bool(n12.get("skip_after_s") == null).is_true()
	assert_bool(OvernightEventsScript.get_event("N12").get("morning_line") is String).is_true()


func test_screen_carries_the_shared_chrome() -> void:
	OvernightEventsScript.clear_cache()
	var screen: Dictionary = OvernightEventsScript.screen()
	assert_str(String(screen["day_label"])).is_equal("Day {day}")
	assert_str(String(screen["night_label"])).is_equal("Night")
	assert_str(String(screen["morning_line"])).is_equal("good morning.")
	assert_float(float(screen["skip_after_s"])).is_equal_approx(3.0, EPS)
	assert_float(float(screen["hold_s"])).is_greater(0.0)
	assert_str(String(screen["message_format"])).contains("{time}")


func test_selection_respects_day_stage_and_path() -> void:
	var early := _message_row("N01")
	early["available"] = {"days": [1, 3], "stages": [0, 5], "paths": "any"}
	var late := _message_row("N02")
	late["available"] = {"days": [4, 14], "stages": [2, 4], "paths": ["YANDERE"]}
	OvernightEventsScript.use_document(_document([early, late]))
	assert_str(String(OvernightEventsScript.select(2, 0, "").get("id", ""))).is_equal("N01")
	assert_str(String(OvernightEventsScript.select(4, 2, "").get("id", ""))).is_empty()
	assert_str(String(OvernightEventsScript.select(4, 2, "YANDERE").get("id", ""))).is_equal("N02")
	assert_str(String(OvernightEventsScript.select(4, 5, "YANDERE").get("id", ""))).is_empty()
	assert_str(String(OvernightEventsScript.select(9, 0, "").get("id", ""))).is_empty()


func test_selection_skips_played_once_rows_only() -> void:
	OvernightEventsScript.use_document(
		_document([_message_row("N01", true), _black_row("N12", false)])
	)
	# One `once` row and one repeatable row: after the once row played, the
	# repeatable one is the only candidate left — and it stays after playing too.
	(
		assert_str(String(OvernightEventsScript.select(1, 0, "", _rng(1), ["N01"]).get("id", "")))
		. is_equal("N12")
	)
	(
		assert_str(
			String(OvernightEventsScript.select(1, 0, "", _rng(1), ["N01", "N12"]).get("id", ""))
		)
		. is_equal("N12")
	)
	# A table whose only row already played has nothing to show.
	OvernightEventsScript.use_document(_document([_message_row("N01", true)]))
	assert_dict(OvernightEventsScript.select(1, 0, "", null, ["N01"])).is_empty()


func test_selection_is_seeded_and_weighted() -> void:
	OvernightEventsScript.use_document(_document([_message_row("N01"), _black_row("N12")]))
	var first: Dictionary = OvernightEventsScript.select(2, 0, "", _rng(7))
	var again: Dictionary = OvernightEventsScript.select(2, 0, "", _rng(7))
	assert_dict(first).is_equal(again)
	# Both rows are reachable across seeds: a weight-0 or never-drawn row would show
	# up as a single-entry set.
	var seen := {}
	for seed_value: int in 24:
		var picked: Dictionary = OvernightEventsScript.select(2, 0, "", _rng(seed_value))
		seen[String(picked.get("id", ""))] = true
	assert_int(seen.size()).is_equal(2)


func test_messages_follow_the_stage_variant_and_path_line() -> void:
	var event := _message_row("N01")
	event["stage_variants"] = {
		"0": [{"time": "2:00 AM", "text": "early"}],
		"3": [{"time": "2:01 AM", "text": "late {player_name}"}],
	}
	event["path_variants"] = {"YANDERE": {"time": "2:02 AM", "text": "mine"}}
	# Highest defined variant not above the stage (the scenario fallback rule).
	var low: Array = OvernightEventsScript.messages(event, 2, "", "Ren")
	assert_int(low.size()).is_equal(1)
	assert_str(String(low[0]["text"])).is_equal("early")
	var high: Array = OvernightEventsScript.messages(event, 5, "YANDERE", "Ren")
	assert_int(high.size()).is_equal(2)
	assert_str(String(high[0]["text"])).is_equal("late Ren")
	assert_str(String(high[1]["text"])).is_equal("mine")
	# A path with no line adds nothing.
	assert_int(OvernightEventsScript.messages(event, 5, "AWAKE", "Ren").size()).is_equal(1)


func test_unknown_rows_and_kinds_are_dropped() -> void:
	var unknown_id := _message_row("N99")
	var unknown_kind := _message_row("N02")
	unknown_kind["kind"] = "video"
	var no_variants := _message_row("N03")
	no_variants.erase("stage_variants")
	OvernightEventsScript.use_document(
		_document([unknown_id, unknown_kind, no_variants, _black_row("N12")])
	)
	assert_int(OvernightEventsScript.events().size()).is_equal(1)
	assert_str(String(OvernightEventsScript.events()[0].get("id", ""))).is_equal("N12")


func test_broken_document_degrades_to_no_events() -> void:
	OvernightEventsScript.use_document("not a document")
	assert_array(OvernightEventsScript.events()).is_empty()
	assert_dict(OvernightEventsScript.select(1, 0, "")).is_empty()
	# The numbers a night still needs survive; the prose has no fallback.
	assert_float(float(OvernightEventsScript.screen()["skip_after_s"])).is_equal_approx(
		OvernightEventsScript.DEFAULT_SKIP_AFTER_S, EPS
	)
	assert_str(String(OvernightEventsScript.screen()["morning_line"])).is_empty()


func test_get_event_unknown_is_empty() -> void:
	OvernightEventsScript.clear_cache()
	assert_dict(OvernightEventsScript.get_event("N07")).is_empty()
	assert_dict(OvernightEventsScript.get_event("")).is_empty()
	# Id lookup is case- and whitespace-tolerant: the data owns canonical ids.
	assert_str(String(OvernightEventsScript.get_event(" n01 ").get("id", ""))).is_equal("N01")
