extends GdUnitTestSuite
## P3.16 — docs/01 §7's endings as rules: the table, the condition evaluator, the
## selection rule and the forced state behind the F3 buttons.
##
## The round's acceptance is "conditions data-driven; each ending forceable from
## F3; persisted across saves". This suite owns the first two at the module level:
## every shipped row is satisfiable and *wins* the evaluator (never "the caller
## said so"), a synthetic row added to a document is selected with no code change,
## and a row with a condition key the evaluator does not know is dropped instead
## of silently widening. The overlay's button click and the save round trip are in
## DebugOverlayTest and EndingSceneTest.

const TEST_DIR := "user://endings_test/"
const LOG_PATH := TEST_DIR + "endings.json"
const DebugOverlayPacked := preload("res://scenes/debug/DebugOverlay.tscn")

var _snapshot := {}
var _clock_tick := 0


func before_test() -> void:
	_snapshot = GameState.to_dict()
	_remove_dir(TEST_DIR)
	_clock_tick = 0
	EndingLog.use_path(LOG_PATH)
	EndingLog.set_clock(_clock)
	EndingLog.clear_cache()
	Endings.clear_cache()
	GameState.reset()


func after_test() -> void:
	EndingLog.use_path("")
	EndingLog.set_clock(Callable())
	EndingLog.clear_cache()
	_remove_dir(TEST_DIR)
	Endings.clear_cache()
	if not _snapshot.is_empty():
		GameState.from_dict(_snapshot)
	_snapshot = {}


## The shipped table is the bible's catalogue, and it loads without a problem.
func test_the_shipped_table_is_the_bible() -> void:
	var names := {}
	var endings := 0
	for row: Dictionary in Endings.rows():
		names[String(row.get("id", ""))] = String(row.get("name", ""))
		if String(row.get("kind", "")) == Endings.KIND_ENDING:
			endings += 1
	assert_int(endings).is_equal(14)
	assert_str(String(names.get("E01", ""))).is_equal("Forever Together")
	assert_str(String(names.get("E07", ""))).is_equal("Honest, Finally")
	assert_str(String(names.get("E12", ""))).is_equal("Remission")
	assert_str(String(names.get("E14", ""))).is_equal("Static")
	assert_str(String(names.get(Endings.SECRET_ID, ""))).is_equal("Weights")
	assert_array(Endings.problems()).is_empty()


## Acceptance 1 (reachability): every row's forced state is a snapshot GameState
## accepts, and the LIVE evaluator picks that row from it. Nothing is asserted
## about a decision the evaluator was not asked for.
func test_every_ending_is_satisfiable_and_wins_the_evaluation() -> void:
	for row: Dictionary in Endings.rows():
		if String(row.get("kind", "")) != Endings.KIND_ENDING:
			continue
		var id := String(row.get("id", ""))
		var built := Endings.satisfying_state(row)
		(
			assert_bool(bool(built.get("ok", false)))
			. override_failure_message("%s: its own condition does not select it" % id)
			. is_true()
		)
		(
			assert_bool(GameState.from_dict(built.get("state", {})))
			. override_failure_message("%s: the forced state is not a valid snapshot" % id)
			. is_true()
		)
		var decision := Endings.evaluate(GameState.to_dict(), Endings.PHASE_CAMPAIGN_END)
		(
			assert_str(String(decision.get("id", "")))
			. override_failure_message("%s: the live evaluator picked another row" % id)
			. is_equal(id)
		)


## Acceptance 1 (data-driven): a new ending is a document row, not a code branch.
func test_adding_an_ending_needs_no_code() -> void:
	var document := Endings.table().duplicate(true)
	(
		document["endings"]
		. append(
			{
				"id": "E99",
				"name": "Synthetic",
				"path": "ANY",
				"kind": "ending",
				"priority": 1,
				"at": "any_time",
				"condition": {"flags": {"synthetic_ending": true}},
			}
		)
	)
	assert_array(Endings.use_document(document)).is_empty()
	var state := GameState.to_dict()
	state["day"] = 9
	state["flags"] = {"synthetic_ending": true}
	assert_str(String(Endings.evaluate(state, Endings.PHASE_TURN).get("id", ""))).is_equal("E99")
	Endings.clear_cache()
	assert_dict(Endings.get_ending("E99")).is_empty()


## A typo in a condition key drops the row: an ending must never become easier to
## reach because the evaluator did not understand one of its clauses.
func test_a_row_with_an_unknown_condition_is_dropped() -> void:
	var document := Endings.table().duplicate(true)
	(
		document["endings"]
		. append(
			{
				"id": "E98",
				"name": "Broken",
				"path": "ANY",
				"kind": "ending",
				"condition": {"impossible": 1},
			}
		)
	)
	assert_array(Endings.use_document(document)).is_not_empty()
	assert_dict(Endings.get_ending("E98")).is_empty()
	var endings := 0
	for row: Dictionary in Endings.rows():
		if String(row.get("kind", "")) == Endings.KIND_ENDING:
			endings += 1
	assert_int(endings).is_equal(14)
	Endings.clear_cache()


## docs/01 §7's E14: "Instability 100 before Day 7 — she burns out early", on any
## path. It is the only `any_time` row, so it is the only ending a turn close can
## reach — and day 7 is already too late.
func test_static_is_an_early_burnout_on_any_path() -> void:
	var state := GameState.to_dict()
	state["path"] = "YANDERE"
	state["day"] = 6
	state["instability"] = 100.0
	state["instability_peak"] = 100.0
	state["stage"] = 5
	var decision := Endings.evaluate(state, Endings.PHASE_TURN)
	assert_str(String(decision.get("id", ""))).is_equal("E14")
	assert_str(String(decision.get("reason", ""))).is_equal("condition")
	var late := state.duplicate(true)
	late["day"] = 7
	assert_dict(Endings.evaluate(late, Endings.PHASE_TURN)).is_empty()
	var healthy := state.duplicate(true)
	healthy["instability"] = 40.0
	healthy["stage"] = 2
	assert_dict(Endings.evaluate(healthy, Endings.PHASE_TURN)).is_empty()
	# At the campaign's end the same row is not eligible, and the path's own
	# fallback answers instead of a second Static.
	assert_str(String(Endings.evaluate(late, Endings.PHASE_CAMPAIGN_END).get("id", ""))).is_equal(
		"E01"
	)


## docs/01 §7's E01: "Affection ≥ 80 at Terminal — you stay".
func test_campaign_end_picks_the_paths_ending() -> void:
	_load("YANDERE", 95.0, {"affection": 82.0})
	var decision := Endings.evaluate(GameState.to_dict(), Endings.PHASE_CAMPAIGN_END)
	assert_str(String(decision.get("id", ""))).is_equal("E01")
	assert_str(String(decision.get("reason", ""))).is_equal("condition")
	assert_int(int(decision.get("day", 0))).is_equal(14)
	assert_int(int(decision.get("stage", 0))).is_equal(5)


## The data's priority is what keeps a specific fact ahead of a broad one: leaving
## talks outrank staying, and boundaries set late outrank both.
func test_a_more_specific_condition_outranks_the_default() -> void:
	_load("YANDERE", 95.0, {"profile": {"leaving_talk": 1}})
	assert_str(_campaign_end_id()).is_equal("E02")
	GameState.bump_profile(&"boundaries", 3)
	assert_str(_campaign_end_id()).is_equal("E03")


## docs/01 §7 gives every ending a condition but no row for the run that matches
## none of them. The table's per-path fallback is that answer, and the reason says
## so — a "default" decision is visible, not disguised as a condition match.
func test_a_run_that_matches_nothing_gets_its_paths_fallback() -> void:
	_load("HOLLOW", 20.0)
	var decision := Endings.evaluate(GameState.to_dict(), Endings.PHASE_CAMPAIGN_END)
	assert_str(String(decision.get("id", ""))).is_equal("E08")
	assert_str(String(decision.get("reason", ""))).is_equal("default")
	assert_array(decision.get("matched", [])).is_empty()


## The secret is docs/01 §7's "play all six paths" unlock: never a run's ending,
## and gated by the paths the log has actually completed.
func test_the_secret_is_an_extras_unlock_not_a_run_ending() -> void:
	assert_str(String(Endings.secret_row().get("id", ""))).is_equal(Endings.SECRET_ID)
	assert_bool(Endings.secret_available([])).is_false()
	(
		assert_bool(Endings.secret_available(["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE"]))
		. is_false()
	)
	(
		assert_bool(
			Endings.secret_available(["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"])
		)
		. is_true()
	)
	assert_str(String(Endings.evaluate(GameState.to_dict()).get("id", ""))).is_not_equal(
		Endings.SECRET_ID
	)


## Same state, same table, same answer — every time. The evaluator holds no
## per-call state, so a replayed run cannot drift to another ending.
func test_evaluation_is_replayable() -> void:
	_load("SPLIT", 96.0, {"profile": {"broken_promises": 2}})
	var first := Endings.evaluate(GameState.to_dict(), Endings.PHASE_CAMPAIGN_END)
	assert_str(String(first.get("id", ""))).is_equal("E04")
	assert_str(String(first.get("reason", ""))).is_equal("condition")
	for _run: int in 3:
		assert_dict(Endings.evaluate(GameState.to_dict(), Endings.PHASE_CAMPAIGN_END)).is_equal(
			first
		)


## Acceptance 2 (F3): the module seam the overlay button calls. It lands the run's
## ending flag, clears the once-per-run guard so the screen logs this visit, and
## refuses a row the catalogue does not have.
func test_force_lands_the_flag_and_clears_the_once_guard() -> void:
	GameState.set_flag(Endings.FLAG_RECORDED, true)
	var result := Endings.force("E11")
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_str(String(GameState.get_flag(Endings.FLAG_ENDING, ""))).is_equal("E11")
	assert_bool(GameState.flags.has(String(Endings.FLAG_RECORDED))).is_false()
	assert_bool(bool(GameState.get_flag(&"agreed_to_delete", false))).is_true()
	var missing := Endings.force("E99")
	assert_bool(bool(missing.get("ok", true))).is_false()
	assert_str(String(missing.get("error", ""))).is_equal("unknown_ending")
	var secret := Endings.force(Endings.SECRET_ID)
	assert_str(String(secret.get("error", ""))).is_equal("unknown_ending")


func test_force_reaches_all_fourteen() -> void:
	for row: Dictionary in Endings.rows():
		if String(row.get("kind", "")) != Endings.KIND_ENDING:
			continue
		var id := String(row.get("id", ""))
		var result := Endings.force(id)
		(
			assert_bool(bool(result.get("ok", false)))
			. override_failure_message("force %s did not reach it" % id)
			. is_true()
		)
		assert_str(String(GameState.get_flag(Endings.FLAG_ENDING, ""))).is_equal(id)


## Acceptance 2 ("each ending forceable from F3"): the suite clicks the same
## button a reviewer clicks (`Ending_<id>`) and reads the run's ending flag. The
## button goes through Endings.force(), so a click can never land an ending the
## data would not choose.
func test_the_f3_overlay_forces_every_ending() -> void:
	var overlay: CanvasLayer = auto_free(DebugOverlayPacked.instantiate())
	add_child(overlay)
	overlay.ending_scene_change_enabled = false
	var endings := 0
	for row: Dictionary in Endings.rows():
		if String(row.get("kind", "")) != Endings.KIND_ENDING:
			continue
		endings += 1
		var id := String(row.get("id", ""))
		var button := overlay.find_child("Ending_" + id, true, false) as Button
		assert_object(button).override_failure_message("no F3 button for %s" % id).is_not_null()
		button.pressed.emit()
		assert_str(String(GameState.get_flag(Endings.FLAG_ENDING, ""))).is_equal(id)
	assert_int(endings).is_equal(14)


func test_describe_names_the_rows_facts() -> void:
	var text := Endings.describe(Endings.get_ending("E01"))
	assert_bool(text.contains("E01")).is_true()
	assert_bool(text.contains("affection")).is_true()
	assert_bool(text.contains("80")).is_true()


## The F3 panel and the tests read the same line.
func test_a_condition_line_is_built_from_the_row() -> void:
	var row := Endings.get_ending("E14")
	var text := Endings.describe(row)
	assert_bool(text.contains("Static")).is_true()
	assert_bool(text.contains("instability")).is_true()
	assert_bool(text.contains("100")).is_true()


## A run's state, applied atomically. Raising Instability through the live setter
## would cross a stage and let GameState's own docs/01 §4 rule assign (and LOCK) a
## path from the scores — the exact race a test must not depend on — so the suite
## builds the snapshot it means and loads it.
func _load(path: String, instability: float, extra := {}) -> void:
	var state := {
		"version": GameState.SNAPSHOT_VERSION,
		"day": 14,
		"path": path,
		"instability": instability,
		"instability_peak": instability,
	}
	for key: Variant in extra:
		state[key] = extra[key]
	(
		assert_bool(GameState.from_dict(state))
		. override_failure_message("the built snapshot was rejected")
		. is_true()
	)


func _campaign_end_id() -> String:
	return String(Endings.evaluate(GameState.to_dict(), Endings.PHASE_CAMPAIGN_END).get("id", ""))


func _clock() -> String:
	_clock_tick += 1
	return "2026-11-04T12:%02d:00" % _clock_tick


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
