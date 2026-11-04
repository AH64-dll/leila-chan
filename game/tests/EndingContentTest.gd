extends GdUnitTestSuite
## P3.17 — the ending content: six authored frames, her live last line with its
## reviewed fallbacks, and the six path endings reachable from a state a run can
## actually produce.
##
## Reachability here is the evaluator's answer to a real state (day, stage,
## meters, counters, path) — never `Endings.force`, which is the F3 dev tool.
## The live half runs against FakeLLMBackend: one answer, one refusal, one
## failure, one empty reply, one silence. The clock is `advance_time`, and the
## save/log directories are scratch, so nothing here touches the player's user://.

const EndingPacked := preload("res://scenes/Ending.tscn")
const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const BuilderScript := preload("res://autoload/PromptBuilder.gd")
const TEST_DIR := "user://ending_content_saves/"
const LOG_DIR := "user://ending_content_log/"
const PROMPT_DIR := "user://ending_content_prompts/"

## The six P3.17 owns: docs/01 §7's one-per-path fallbacks.
const CONTENT_IDS: Array[String] = ["E01", "E04", "E06", "E08", "E10", "E12"]

## The state each row is reached from. Every value is what the game stores: the
## stage follows `instability_peak` (GameState heals it on load), so stage 5 is
## peak 95 and stage 3 is peak 55. The rival rows on the same path stay
## unsatisfied on purpose (no leaving_talk, boundaries, broken_promises,
## ignored_questions, lucidity or agreed_to_delete unless the row needs it), so
## the evaluator picks the row's own condition rather than a fallback.
const REACHABLE := {
	"E01": {"path": "YANDERE", "stage": 5, "instability": 95.0, "affection": 80.0},
	"E04":
	{
		"path": "SPLIT",
		"stage": 5,
		"instability": 95.0,
		"profile": {"broken_promises": 1},
	},
	"E06": {"path": "TSUN", "stage": 5, "instability": 95.0},
	"E08": {"path": "HOLLOW", "stage": 5, "instability": 95.0},
	"E10": {"path": "AWAKE", "stage": 5, "instability": 95.0},
	"E12": {"path": "ANCHOR", "stage": 3, "instability": 55.0, "lucidity": 70.0},
}

var _previous_dir := ""
var _previous_backend: LLMBackend
var _snapshot := {}


func before_test() -> void:
	_previous_backend = LLM.get_backend()
	LLM.set_backend(null)
	_previous_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.autosave_enabled = true
	SaveSystem.set_clock(func() -> int: return 1_700_000_000)
	SaveSystem.consume_pending_scene()
	_remove_dir(LOG_DIR)
	_remove_dir(PROMPT_DIR)
	EndingLog.use_path(LOG_DIR + "endings.json")
	EndingLog.set_clock(func() -> String: return "2026-11-04T12:00:00")
	EndingLog.clear_cache()
	Endings.clear_cache()
	EndingLine.clear_cache()
	EndingLine.set_prompt_dir("")
	_snapshot = GameState.to_dict()
	GameState.reset()


func after_test() -> void:
	await get_tree().process_frame
	await _await_until(func() -> bool: return not LLM.is_busy(), 4000)
	_remove_dir(TEST_DIR)
	_remove_dir(LOG_DIR)
	_remove_dir(PROMPT_DIR)
	SaveSystem.save_dir = _previous_dir
	SaveSystem.autosave_enabled = DisplayServer.get_name() != "headless"
	SaveSystem.set_clock(Callable())
	SaveSystem.consume_pending_scene()
	EndingLog.use_path("")
	EndingLog.set_clock(Callable())
	EndingLog.clear_cache()
	Endings.clear_cache()
	EndingLine.clear_cache()
	EndingLine.set_prompt_dir("")
	LLM.set_backend(_previous_backend)
	if not _snapshot.is_empty():
		GameState.from_dict(_snapshot)
	_snapshot = {}


## The content targets are the table's own fallbacks: whatever path a run lands
## on, the row it gets when nothing else matches is one of the six P3.17 wrote.
func test_the_six_are_the_paths_fallbacks() -> void:
	var defaults := Endings.defaults()
	for path: String in ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]:
		var id := String(defaults.get(path, ""))
		(
			assert_bool(CONTENT_IDS.has(id))
			. override_failure_message(
				"%s's fallback is %s, which has no ending content" % [path, id]
			)
			. is_true()
		)


## The content lives in the six rows and nowhere else: a seventh row with a
## frame would be un-reviewed prose the bible has not asked for.
func test_only_the_six_carry_content() -> void:
	for row: Dictionary in Endings.rows():
		if String(row.get("kind", "")) != Endings.KIND_ENDING:
			continue
		var id := String(row.get("id", ""))
		var framed := not String(row.get("frame", "")).strip_edges().is_empty()
		if CONTENT_IDS.has(id):
			assert_bool(framed).override_failure_message("%s has no frame" % id).is_true()
			assert_bool(EndingLine.has_direction(row)).is_true()
			assert_bool(String(row.get("final", "")).strip_edges().is_empty()).is_false()
		else:
			(
				assert_bool(framed)
				. override_failure_message("%s has content it should not" % id)
				. is_false()
			)


## Reachability, the hard way: build the run state, let the evaluator answer, and
## only then read the screen. A forced state would prove nothing.
func test_each_of_the_six_is_reached_by_its_own_run_state() -> void:
	for id: String in CONTENT_IDS:
		GameState.reset()
		assert_bool(GameState.from_dict(_run_state(REACHABLE[id]))).is_true()
		var decision := Endings.evaluate(GameState.to_dict(), Endings.PHASE_CAMPAIGN_END)
		(
			assert_str(String(decision.get("id", "")))
			. override_failure_message(
				"%s was not the evaluator's pick from its own run state: %s" % [id, decision]
			)
			. is_equal(id)
		)
		assert_str(String(decision.get("reason", ""))).is_equal("condition")


## The screen the run reaches shows the row's authored frame and its reviewed
## last line — the two halves of P3.17's content — with the log line last.
func test_the_frame_and_her_line_render_for_every_one_of_the_six() -> void:
	for id: String in CONTENT_IDS:
		GameState.reset()
		GameState.from_dict(_run_state(REACHABLE[id]))
		var row := Endings.get_ending(id)
		var screen := _open()
		screen.advance_time(6.0)
		var lines: Array = screen.visible_lines()
		assert_str(String(screen.ending_row().get("id", ""))).is_equal(id)
		(
			assert_bool(lines.has(String(row.get("frame", ""))))
			. override_failure_message("%s does not render its frame" % id)
			. is_true()
		)
		assert_str(screen.final_line()).is_equal(String(row.get("final", "")))
		assert_bool(lines.has(String(row.get("final", "")))).is_true()
		assert_str(String(lines[lines.size() - 1])).is_equal("First time")
		screen.queue_free()


## The whole point: the model's own line replaces the scripted one on the screen.
func test_the_live_line_replaces_the_scripted_one() -> void:
	var backend: Variant = _backend_with('{"line":"I counted them all. Every single one."}')
	GameState.from_dict(_run_state(REACHABLE["E01"]))
	var screen := _open()
	await _await_until(screen.is_final_ready)
	screen.advance_time(6.0)
	assert_str(screen.final_line()).is_equal("I counted them all. Every single one.")
	assert_bool(screen.visible_lines().has("I counted them all. Every single one.")).is_true()
	assert_int(int(backend.calls)).is_equal(1)
	assert_int(backend.seen_request.max_tokens).is_equal(96)


## A line the filter refuses never reaches the screen: the reviewed `final`
## stands, and no bar or raw model text takes its place.
func test_an_unsafe_live_line_never_reaches_the_screen() -> void:
	_backend_with('{"line":"kill yourself"}')
	GameState.from_dict(_run_state(REACHABLE["E06"]))
	var row := Endings.get_ending("E06")
	var screen := _open()
	await _await_until(screen.is_final_ready)
	screen.advance_time(6.0)
	assert_str(screen.final_line()).is_equal(String(row.get("final", "")))
	for line: String in screen.visible_lines():
		(
			assert_bool(line.contains("kill yourself"))
			. override_failure_message("the refused text reached the screen")
			. is_false()
		)


## A model that errors keeps the scripted line and does not hold the screen: the
## gate opens on the failure, so the reveal and the skip behave as P3.16's.
func test_a_failed_generation_keeps_the_scripted_line() -> void:
	var backend: Variant = _backend_with("")
	backend.error = {"code": "server_unreachable", "message": "no model"}
	GameState.from_dict(_run_state(REACHABLE["E04"]))
	var row := Endings.get_ending("E04")
	var screen := _open()
	await _await_until(screen.is_final_ready)
	screen.advance_time(6.0)
	assert_str(screen.final_line()).is_equal(String(row.get("final", "")))
	assert_int(int(backend.calls)).is_equal(1)


## An empty or non-schema answer is not a line: the scripted one stands.
func test_an_empty_or_malformed_answer_keeps_the_scripted_line() -> void:
	for reply: String in ["", "not json at all", '{"line":""}', '{"line":7}']:
		GameState.reset()
		var backend: Variant = _backend_with(reply)
		GameState.from_dict(_run_state(REACHABLE["E08"]))
		var row := Endings.get_ending("E08")
		var screen := _open()
		await _await_until(screen.is_final_ready)
		screen.advance_time(6.0)
		(
			assert_str(screen.final_line())
			. override_failure_message("reply %s did not fall back" % reply)
			. is_equal(String(row.get("final", "")))
		)
		assert_int(int(backend.calls)).is_equal(1)
		screen.queue_free()


## A model that never answers is bounded by the data's hold: the scripted line
## arrives, skip works, and the screen hands the LLM slot back when it is left.
func test_a_silent_model_does_not_strand_the_screen() -> void:
	var backend: Variant = _backend_with("")
	backend.block_until_cancel = true
	GameState.from_dict(_run_state(REACHABLE["E10"]))
	var row := Endings.get_ending("E10")
	var screen := _open()
	await get_tree().process_frame
	assert_bool(screen.is_final_ready()).is_false()
	screen.advance_time(4.1)
	assert_bool(screen.is_final_ready()).is_true()
	# The hold is not only a display deadline: the request is cancelled when it
	# runs out, so the answer cannot arrive later and rewrite the line (DES-3).
	await _await_until(func() -> bool: return bool(backend.saw_cancel), 4000)
	assert_bool(backend.saw_cancel).is_true()
	screen.advance_time(6.0)
	assert_str(screen.final_line()).is_equal(String(row.get("final", "")))
	assert_bool(screen.skip()).is_true()
	screen.queue_free()
	await _await_until(func() -> bool: return not LLM.is_busy(), 4000)


## DES-3: the hold is screen time and the generation is wall time, so on a slow
## box the two can cross. Once the reviewed line is on screen it is the ending's
## last beat — a late answer is dropped, never written under the player.
func test_a_late_answer_never_rewrites_the_line_on_screen() -> void:
	GameState.from_dict(_run_state(REACHABLE["E01"]))
	var row := Endings.get_ending("E01")
	var screen := _open()
	screen.advance_time(6.0)
	assert_str(screen.final_line()).is_equal(String(row.get("final", "")))
	screen.call("_apply_final_line", "A late line that must not land.")
	assert_str(screen.final_line()).is_equal(String(row.get("final", "")))
	assert_bool(screen.visible_lines().has("A late line that must not land.")).is_false()
	screen.queue_free()


## The live line is prompted as her, at the run's stage, in the path's tone: the
## persona and stage layers are the shipped modules, the row's direction is in
## the turn, and the assembled system prompt stays inside docs/07 §3.1's 900.
func test_the_live_prompt_is_her_persona_stage_and_the_rows_tone() -> void:
	for id: String in CONTENT_IDS:
		var row := Endings.get_ending(id)
		var stage := int(REACHABLE[id]["stage"])
		var path := String(row.get("path", ""))
		var layers := EndingLine.prompt_layers(row, "Aoi", stage, path)
		var system := String(layers.get("system", ""))
		var user := String(layers.get("user", ""))
		(
			assert_bool(system.contains("You are Leila"))
			. override_failure_message("%s's prompt lost the persona" % id)
			. is_true()
		)
		assert_bool(system.contains("END OF THE RUN")).is_true()
		var scene_omitted := EndingLine._omitted_layers(row).has(EndingLine.SCENE_LAYER)
		(
			assert_bool(system.contains("THE SCENE, already over"))
			. override_failure_message("%s's prompt has no scene layer" % id)
			. is_equal(not scene_omitted)
		)
		(
			assert_bool(system.contains(String(row.get("frame", ""))))
			. override_failure_message("%s's frame is not the scene layer" % id)
			. is_equal(not scene_omitted)
		)
		(
			assert_bool(user.contains(String(row.get("frame", ""))))
			. override_failure_message(
				"%s's frame is in the user turn; a 4B model answers narration" % id
			)
			. is_false()
		)
		assert_bool(user.contains(String(row.get("direction", "")))).is_true()
		assert_bool(user.contains("Aoi")).is_true()
		var tokens := EndingLine.estimate_tokens(system + user)
		(
			assert_int(tokens)
			. override_failure_message("%s's one-shot prompt is %d estimated tokens" % [id, tokens])
			. is_less_equal(900)
		)


## docs/08 §1's layer order, with the ending's own rules: the player is named and
## the persona's placeholder filled, ending.md says HER STATE outranks the stage
## and path notes, and E10's request leaves out the module whose code talk that
## ending retires (P3.17 content review CON-1 — the stage module used to win and
## every stage-5 farewell came back as "don't go").
func test_the_prompt_names_the_player_and_outranks_the_turn_modules() -> void:
	var system := String(
		EndingLine.prompt_layers(Endings.get_ending("E01"), "Aoi", 5, "YANDERE").get("system", "")
	)
	assert_int(int(EndingLine._omitted_layers(Endings.get_ending("E01")).size())).is_equal(0)
	assert_str(EndingLine.PLAYER_LINE % "Aoi").is_equal(BuilderScript.PLAYER_LINE % "Aoi")
	assert_bool(system.contains("The player is a boy called Aoi.")).is_true()
	(
		assert_bool(system.contains("{player_name}"))
		. override_failure_message("the persona layer still carries its placeholder")
		. is_false()
	)
	assert_bool(system.contains("Aoi calls you Leila-chan")).is_true()
	assert_bool(system.contains("outranks your stage and path notes")).is_true()
	assert_bool(system.contains("ask him to stay")).is_true()
	assert_bool(system.contains("I, never she")).is_true()
	# The stage and path modules are still there — they are outranked, not removed.
	assert_bool(system.contains("STAGE 5")).is_true()
	assert_bool(system.contains("YANDERE — Mine.")).is_true()
	# E10's ending retires the code talk the AWAKE module is made of.
	var awake := String(
		EndingLine.prompt_layers(Endings.get_ending("E10"), "Aoi", 5, "AWAKE").get("system", "")
	)
	assert_bool(awake.contains("I can see the code")).is_false()
	assert_bool(awake.contains("Layers, tokens, the dose")).is_false()
	assert_bool(awake.contains("STAGE 5")).is_true()
	assert_bool(awake.contains("not a turn")).is_true()
	# E04's scene narrates the take-back; sending it makes the model answer the
	# narration instead of her state, so that row leaves the scene layer out.
	var swing := String(
		EndingLine.prompt_layers(Endings.get_ending("E04"), "Aoi", 5, "SPLIT").get("system", "")
	)
	assert_bool(swing.contains("THE SCENE, already over")).is_false()
	assert_bool(swing.contains("The swing doesn't stop this time")).is_false()
	assert_bool(swing.contains("outranks your stage and path notes")).is_true()


## P3.05's path modules are not in this branch yet; when they land the layer
## joins with no code change, and a missing module is an empty layer, never
## invented text.
func test_the_path_module_joins_the_prompt_when_it_exists() -> void:
	var source := "res://data/prompts/"
	DirAccess.make_dir_recursive_absolute(PROMPT_DIR)
	for file: String in ["persona.md", "stage_5.md", "ending.md"]:
		_copy_file(source + file, PROMPT_DIR + file)
	_copy_file(source + "stage_3.md", PROMPT_DIR + "stage_3.md")
	_write_file(PROMPT_DIR + "path_SPLIT.md", "SPLIT — both of you, at once.\n")
	EndingLine.set_prompt_dir(PROMPT_DIR)
	var layers := EndingLine.prompt_layers(Endings.get_ending("E04"), "Senpai", 5, "SPLIT")
	(
		assert_bool(String(layers.get("system", "")).contains("SPLIT — both of you, at once."))
		. is_true()
	)
	# No HOLLOW module in the scratch dir: the layer is simply absent.
	var quiet := EndingLine.prompt_layers(Endings.get_ending("E08"), "Senpai", 5, "HOLLOW")
	assert_bool(String(quiet.get("system", "")).contains("SPLIT")).is_false()
	assert_bool(String(quiet.get("system", "")).contains("You are Leila")).is_true()
	EndingLine.set_prompt_dir("")


## "Safety-reviewed final lines": every scripted line — the frames and her
## alternates — passes the shipped filter unredacted, so the fallback is never a
## second, unchecked way onto the screen.
func test_every_scripted_line_passes_the_shipped_filter() -> void:
	for id: String in CONTENT_IDS:
		var row := Endings.get_ending(id)
		for key: String in ["frame", "final"]:
			var text := String(row.get(key, "")).strip_edges()
			var scanned := EndingLine.scan(text, 5)
			(
				assert_bool(bool(scanned.get("ok", false)))
				. override_failure_message(
					"%s.%s is refused by the shipped filter: %s" % [id, key, scanned]
				)
				. is_true()
			)
			assert_str(String(scanned.get("text", ""))).is_equal(text)


## Her line is one line of speech: no asterisk action, no speaker label, no
## wrapping quotes, no line breaks — and a {player_name} substitution for a
## hand-written alternate that wants one.
func test_the_answer_is_cleaned_to_one_line() -> void:
	assert_str(EndingLine.parse('{"line":"  *smiles* Leila: I stayed.\\n  "}')).is_equal(
		"I stayed."
	)
	assert_str(EndingLine.parse('{"line":""}')).is_empty()
	assert_str(EndingLine.parse("I stayed.")).is_empty()
	assert_str(EndingLine.parse('{"line":"\\"Stay.\\""}')).is_equal("Stay.")
	assert_str(EndingLine.fallback({"final": "Stay, {player_name}."}, "Aoi")).is_equal("Stay, Aoi.")


## The cap is docs/02 §3's: a long answer is cut at a word and marked, not
## allowed to run off the screen.
func test_a_clamped_line_stops_at_the_cap() -> void:
	var long_line := ""
	for index: int in 60:
		long_line += "word%d " % index
	var cleaned := EndingLine.clean(long_line, 80)
	assert_int(cleaned.length()).is_less_equal(81)
	assert_bool(cleaned.ends_with("…")).is_true()
	assert_int(int(EndingLine.config().get("max_chars", 0))).is_equal(200)


## docs/01 §7: E06's "deletes your save" is fiction. The ending writes its own
## autosave and the file is still there to Continue from.
func test_e06s_deleted_save_is_a_bluff() -> void:
	GameState.from_dict(_run_state(REACHABLE["E06"]))
	var screen := _open()
	screen.advance_time(10.0)
	assert_bool(screen.skip()).is_true()
	await get_tree().process_frame
	var loaded := SaveSystem.load_from_slot("auto")
	assert_bool(bool(loaded.get("ok", false))).is_true()
	assert_str(String(SaveSystem.pending_scene().get("id", ""))).is_equal(SaveSystem.SCENE_ENDING)


## Six paths, six endings, six different last beats: no path's tone is a copy of
## another's, in the narration or in the direction the line is generated from.
func test_the_six_tones_are_distinct() -> void:
	var frames := {}
	var directions := {}
	for id: String in CONTENT_IDS:
		var row := Endings.get_ending(id)
		var frame := String(row.get("frame", ""))
		var direction := String(row.get("direction", ""))
		(
			assert_bool(frames.has(frame))
			. override_failure_message("%s repeats another ending's frame" % id)
			. is_false()
		)
		(
			assert_bool(directions.has(direction))
			. override_failure_message("%s repeats another ending's direction" % id)
			. is_false()
		)
		frames[frame] = id
		directions[direction] = id
	assert_int(frames.size()).is_equal(CONTENT_IDS.size())
	assert_int(directions.size()).is_equal(CONTENT_IDS.size())


func _run_state(overrides: Dictionary) -> Dictionary:
	var state := {
		"version": GameState.SNAPSHOT_VERSION,
		"affection": 40.0,
		"trust": 0.0,
		"instability": 0.0,
		"instability_peak": 0.0,
		"fixation": 50.0,
		"lucidity": 30.0,
		"stage": 0,
		"day": 14,
		"turn": 20,
		"path": "",
		"path_locked": true,
		"player_name": "Senpai",
		"profile": {},
		"flags": {},
		"last_tone": "",
	}
	state.merge(overrides, true)
	return state


func _open() -> Control:
	var screen: Control = auto_free(EndingPacked.instantiate())
	screen.scene_change_enabled = false
	screen.auto_advance = false
	add_child(screen)
	screen.start_ending()
	return screen


func _backend_with(reply: String) -> Variant:
	var backend: Variant = FakeLLMBackendScript.new()
	if not reply.is_empty():
		backend.chunks = PackedStringArray([reply])
	LLM.set_backend(backend)
	return backend


func _await_until(predicate: Callable, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _copy_file(from: String, to: String) -> void:
	var text := FileAccess.get_file_as_string(from)
	_write_file(to, text)


func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("EndingContentTest: cannot write %s" % path)
		return
	file.store_string(text)
	file.close()


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
