extends GdUnitTestSuite
## P2.20 — saves v1 (docs/07 §3.5): slots under user://saves, the per-scene
## autosave, and a load that restores meters, memories and the log.
##
## The round trip goes through the real files: a mid-campaign state is written
## to a scratch slot, the live game is wiped, and the load must bring back
## exactly the saved snapshot — meters/stage/day/path/flags/profile, the memory
## store (facts, importance, the rng seed AND the stream position), the prompt
## history rebuilt from the log, and the log itself.
##
## A corrupted save is a value, never an exception. Each corrupt case asserts
## (a) an error code, (b) the live game untouched, and (c) the suite reaching
## its end — no crash. The cases: non-JSON bytes, a truncation, a bit flip
## inside a string (which still parses; the checksum catches it), a future
## version, a valid envelope with missing sections, and hostile field types.

const TEST_DIR := "user://save_slots_test/"
const FakeChatLogScript := preload("res://tests/helpers/FakeChatLog.gd")
const Fixtures := preload("res://tests/helpers/MemoryFixtures.gd")
const SCENARIO := "res://data/scenarios/D02_cafe.json"

var _previous_dir := ""
var _log: Variant = null


func before_test() -> void:
	_previous_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.autosave_enabled = true
	SaveSystem.set_clock(func() -> int: return 1_700_000_000)
	SaveSystem.consume_pending_scene()
	_log = FakeChatLogScript.new()
	_reset_game()
	_register_log()
	_log.entries = []


func after_test() -> void:
	SaveSystem.clear_log_seam(_log)
	_remove_dir(TEST_DIR)
	SaveSystem.save_dir = _previous_dir
	SaveSystem.autosave_enabled = DisplayServer.get_name() != "headless"
	SaveSystem.set_clock(Callable())
	SaveSystem.consume_pending_scene()
	_reset_game()
	_log = null


## Acceptance 1: a mid-campaign state survives save → wipe → load, including
## the log and the prompt history rebuilt from it.
func test_round_trip_restores_a_mid_campaign_state() -> void:
	_log.entries = [
		{"speaker_key": "her", "speaker": "Leila", "text": "You came back."},
		{"speaker_key": "player", "speaker": "Ren", "text": "I always do."},
		{"speaker_key": "her", "speaker": "Leila", "text": "Say it again."},
		{"speaker_key": "her", "speaker": "Leila", "text": "Say my name."},
	]
	_build_mid_campaign()
	var state_before: Variant = _json(GameState.to_dict())
	# The memory store compares directly: its rng counters are 64-bit ints, and
	# a JSON round trip would hide a one-bit difference (doubles).
	var memory_before: Dictionary = Memory.to_dict()
	var saved := SaveSystem.save_to_slot(2, "date", {"scenario": SCENARIO, "turn": 4})
	assert_bool(bool(saved["ok"])).is_true()
	assert_bool(FileAccess.file_exists(TEST_DIR + "slot_2.json")).is_true()

	# Wipe everything the save is supposed to bring back.
	Director.reset()
	GameState.reset()
	Memory.reset()
	_log.entries = []
	assert_str(GameState.player_name).is_equal("Senpai")
	assert_int(Memory.size()).is_zero()

	var loaded := SaveSystem.load_from_slot(2)
	assert_bool(bool(loaded["ok"])).is_true()
	assert_str(String(loaded["slot"])).is_equal("2")
	assert_dict(_json(GameState.to_dict())).is_equal(state_before)
	assert_dict(Memory.to_dict()).is_equal(memory_before)
	(
		assert_array(_log.entries)
		. is_equal(
			[
				{"speaker_key": "her", "speaker": "Leila", "text": "You came back."},
				{"speaker_key": "player", "speaker": "Ren", "text": "I always do."},
				{"speaker_key": "her", "speaker": "Leila", "text": "Say it again."},
				{"speaker_key": "her", "speaker": "Leila", "text": "Say my name."},
			]
		)
	)
	# docs/08 §1: the prompt history is the displayed text, her reply as one
	# assistant message per turn, and the rule-1 window is the last player lines.
	(
		assert_array(Director.history)
		. is_equal(
			[
				{"role": "assistant", "text": "You came back."},
				{"role": "user", "text": "I always do."},
				{"role": "assistant", "text": "Say it again. Say my name."},
			]
		)
	)
	assert_array(Director.last_player_inputs).contains_exactly(["I always do."])
	assert_dict(SaveSystem.pending_scene()).is_equal(
		{"id": "date", "scenario": SCENARIO, "turn": 4}
	)


## P2.11 asked for seed AND stream: the corruption rolls after a load must be
## the rolls the live store would have made. The seed is past 2^53 so a number
## in the file would round and this test would fail.
func test_memory_corruption_stream_resumes_where_it_stopped() -> void:
	Memory.set_rng_seed(9_007_199_254_740_993)
	var facts: Array[String] = Fixtures.filler()
	for i: int in 8:
		Memory.consider(facts[i], [facts[i]])
	# Advance the stream, so the save carries a mid-stream position, not a seed.
	for i: int in 5:
		Memory.prompt_facts({"stage": 5})
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()

	var control: Array = []
	for i: int in 8:
		control.append(Memory.prompt_facts({"stage": 5}))
	assert_bool(bool(SaveSystem.load_from_slot(1)["ok"])).is_true()
	var replay: Array = []
	for i: int in 8:
		replay.append(Memory.prompt_facts({"stage": 5}))
	assert_array(replay).is_equal(control)
	assert_int(int(Memory.to_dict()["seed"])).is_equal(9_007_199_254_740_993)


## docs/07 §3.5: `user://saves/slot_N.json` holding state, memories and log —
## plus the integrity envelope this build reads.
func test_save_file_is_a_checksummed_envelope_in_the_slots_directory() -> void:
	_build_mid_campaign()
	var saved := SaveSystem.save_to_slot(2, "date", {"scenario": SCENARIO, "turn": 4})
	assert_bool(bool(saved["ok"])).is_true()
	assert_str(String(saved["path"])).is_equal(TEST_DIR + "slot_2.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_DIR + "slot_2.json"))
	assert_bool(parsed is Dictionary).is_true()
	var envelope := parsed as Dictionary
	assert_str(String(envelope["format"])).is_equal("leila.save")
	assert_int(int(envelope["version"])).is_equal(1)
	assert_str(String(envelope["checksum"])).has_length(64)
	var payload := _dict(envelope["payload"])
	assert_dict(payload).contains_keys(["saved_at", "scene", "state", "memories", "log"])
	var scene := _dict(payload["scene"])
	assert_str(String(scene["id"])).is_equal("date")
	assert_str(String(scene["scenario"])).is_equal(SCENARIO)
	assert_int(int(scene["turn"])).is_equal(4)
	# the checksum is the sha256 of the canonical payload text
	assert_str(JSON.stringify(payload, "", true).sha256_text()).is_equal(
		String(envelope["checksum"])
	)
	# only the slot that was written exists
	assert_bool(FileAccess.file_exists(TEST_DIR + "slot_1.json")).is_false()
	assert_bool(FileAccess.file_exists(TEST_DIR + "slot_3.json")).is_false()


## Acceptance 2: corrupt bytes are a safe error and the live game is untouched.
func test_corrupt_json_is_a_safe_error_and_keeps_the_live_state() -> void:
	_build_mid_campaign()
	var state_before: Variant = _json(GameState.to_dict())
	var memory_before := Memory.size()
	_write_raw("slot_1.json", '{"format": "leila.save", "version": 1, "payl')
	var loaded := SaveSystem.load_from_slot(1)
	assert_bool(bool(loaded["ok"])).is_false()
	assert_str(String(loaded["error"])).is_equal("corrupt")
	assert_str(String(loaded["message"])).is_not_empty()
	assert_dict(_json(GameState.to_dict())).is_equal(state_before)
	assert_int(Memory.size()).is_equal(memory_before)
	assert_str(GameState.player_name).is_equal("Ren")


func test_truncated_save_is_a_safe_error() -> void:
	_build_mid_campaign()
	assert_bool(bool(SaveSystem.save_to_slot(3)["ok"])).is_true()
	var text := FileAccess.get_file_as_string(TEST_DIR + "slot_3.json")
	_write_raw("slot_3.json", text.substr(0, text.length() / 2))
	var loaded := SaveSystem.load_from_slot(3)
	assert_bool(bool(loaded["ok"])).is_false()
	assert_str(String(loaded["error"])).is_equal("corrupt")


## A bit flip inside a string still parses as JSON, so only the checksum can
## catch it — and the game must stay on the live state.
func test_bit_flip_inside_a_string_is_caught_by_the_checksum() -> void:
	_build_mid_campaign()
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	var text := FileAccess.get_file_as_string(TEST_DIR + "slot_1.json")
	var tampered := text.replace('"Ren"', '"Ken"')
	assert_str(tampered).is_not_equal(text)
	_write_raw("slot_1.json", tampered)
	var state_before: Variant = _json(GameState.to_dict())
	var loaded := SaveSystem.load_from_slot(1)
	assert_bool(bool(loaded["ok"])).is_false()
	assert_str(String(loaded["error"])).is_equal("corrupt")
	assert_dict(_json(GameState.to_dict())).is_equal(state_before)
	# the slot listing reports the file as corrupt instead of hiding it
	var rows := SaveSystem.list_slots()
	assert_int(rows.size()).is_equal(1)
	assert_bool(bool(rows[0]["ok"])).is_false()
	assert_str(String(rows[0]["error"])).is_equal("corrupt")


func test_future_version_is_refused_not_guessed() -> void:
	_write_raw(
		"slot_1.json",
		JSON.stringify({"format": "leila.save", "version": 99, "checksum": "", "payload": {}})
	)
	var loaded := SaveSystem.load_from_slot(1)
	assert_bool(bool(loaded["ok"])).is_false()
	assert_str(String(loaded["error"])).is_equal("unsupported_version")


func test_valid_envelope_without_sections_is_refused() -> void:
	var bare: Dictionary = SaveSystem.slots.encode({"saved_at": 12})
	assert_bool(bool(bare["ok"])).is_true()
	_write_raw("slot_2.json", String(bare["text"]))
	var loaded := SaveSystem.load_from_slot(2)
	assert_bool(bool(loaded["ok"])).is_false()
	assert_str(String(loaded["error"])).is_equal("corrupt")
	# state without memories is not the docs/07 §3.5 triple either
	var half := SaveSystem.slots.encode({"saved_at": 12, "state": GameState.to_dict()})
	_write_raw("slot_2.json", String(half["text"]))
	assert_str(String(SaveSystem.load_from_slot(2)["error"])).is_equal("corrupt")


## A save is untrusted input: wrong types are healed to defaults or dropped,
## never passed into `int()`/`float()` unguarded (which would abort the load).
func test_hostile_field_types_are_healed_without_a_crash() -> void:
	_build_mid_campaign()
	var weird := {
		"saved_at": "soon",
		"scene": "not a dict",
		"state": GameState.to_dict(),
		"memories":
		{
			"capacity": "wide",
			"seed": {},
			"state": [1, 2],
			"entries":
			[
				1,
				"text",
				{"text": 7},
				{"text": "gave me a music box", "importance": "high", "quotes": -3},
			],
		},
		"log":
		{
			"entries":
			[
				42,
				{"speaker_key": 5, "text": null},
				{"speaker_key": "her", "speaker": "Leila", "text": "hi"},
			]
		},
	}
	var encoded: Dictionary = SaveSystem.slots.encode(weird)
	assert_bool(bool(encoded["ok"])).is_true()
	_write_raw("slot_3.json", String(encoded["text"]))
	var loaded := SaveSystem.load_from_slot(3)
	assert_bool(bool(loaded["ok"])).is_true()
	assert_array(Memory.facts()).contains_exactly(["gave me a music box"])
	assert_int(_log.entries.size()).is_equal(1)
	assert_str(String(_log.entries[0]["text"])).is_equal("hi")
	assert_dict(SaveSystem.pending_scene()).is_empty()


func test_missing_and_invalid_slots_are_safe_errors() -> void:
	var missing := SaveSystem.load_from_slot(1)
	assert_bool(bool(missing["ok"])).is_false()
	assert_str(String(missing["error"])).is_equal("not_found")
	var latest := SaveSystem.load_latest()
	assert_bool(bool(latest["ok"])).is_false()
	assert_str(String(latest["error"])).is_equal("not_found")
	assert_bool(SaveSystem.has_save()).is_false()
	assert_str(SaveSystem.latest_slot()).is_empty()
	var invalid := SaveSystem.load_from_slot("seven")
	assert_str(String(invalid["error"])).is_equal("invalid_slot")
	var invalid_save := SaveSystem.save_to_slot(9)
	assert_str(String(invalid_save["error"])).is_equal("invalid_slot")
	assert_bool(SaveSystem.delete_slot(1)).is_false()


func test_saving_twice_replaces_one_valid_file() -> void:
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	GameState.player_name = "Ken"
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	var directory := DirAccess.open(TEST_DIR)
	assert_object(directory).is_not_null()
	# the temporary file never survives a successful write
	assert_array(Array(directory.get_files())).contains_exactly(["slot_1.json"])
	var decoded: Dictionary = SaveSystem.slots.read(1)
	assert_bool(bool(decoded["ok"])).is_true()
	assert_str(String(_dict(decoded["payload"])["state"]["player_name"])).is_equal("Ken")


func test_list_slots_marks_corrupt_files_and_latest_skips_them() -> void:
	var now := [1000]
	SaveSystem.set_clock(func() -> int: return now[0])
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	now[0] = 2000
	assert_bool(bool(SaveSystem.save_to_slot(2)["ok"])).is_true()
	assert_str(SaveSystem.latest_slot()).is_equal("2")
	var rows := SaveSystem.list_slots()
	assert_int(rows.size()).is_equal(2)
	assert_str(String(rows[0]["slot"])).is_equal("1")
	assert_int(int(rows[0]["saved_at"])).is_equal(1000)
	assert_int(int(rows[1]["saved_at"])).is_equal(2000)
	_write_raw("slot_2.json", "corrupt{")
	assert_str(SaveSystem.latest_slot()).is_equal("1")
	var after := SaveSystem.list_slots()
	assert_bool(bool(after[1]["ok"])).is_false()
	assert_str(String(after[1]["error"])).is_equal("corrupt")
	assert_bool(SaveSystem.has_save()).is_true()


func test_autosave_writes_the_auto_slot_and_respects_the_disable() -> void:
	var saved := SaveSystem.autosave("date", {"scenario": SCENARIO, "turn": 2})
	assert_bool(bool(saved["ok"])).is_true()
	var path := TEST_DIR + "autosave.json"
	assert_bool(FileAccess.file_exists(path)).is_true()
	var decoded: Dictionary = SaveSystem.slots.read("auto")
	assert_bool(bool(decoded["ok"])).is_true()
	assert_str(String(_dict(_dict(decoded["payload"])["scene"])["id"])).is_equal("date")
	assert_str(SaveSystem.latest_slot()).is_equal("auto")

	SaveSystem.autosave_enabled = false
	assert_bool(SaveSystem.delete_slot("auto")).is_true()
	var refused := SaveSystem.autosave("date")
	assert_bool(bool(refused["ok"])).is_false()
	assert_str(String(refused["error"])).is_equal("disabled")
	assert_bool(FileAccess.file_exists(path)).is_false()


func test_wipe_removes_every_slot() -> void:
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	assert_bool(bool(SaveSystem.save_to_slot(3)["ok"])).is_true()
	assert_bool(bool(SaveSystem.autosave("date")["ok"])).is_true()
	_write_raw("slot_2.json", "junk")
	assert_int(SaveSystem.wipe()).is_equal(4)
	assert_array(SaveSystem.list_slots()).is_empty()
	assert_bool(DirAccess.dir_exists_absolute(TEST_DIR)).is_true()


func test_busy_director_refuses_save_and_load() -> void:
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	Director._turn_in_flight = true
	var save_res := SaveSystem.save_to_slot(2)
	assert_bool(bool(save_res["ok"])).is_false()
	assert_str(String(save_res["error"])).is_equal("busy")
	var load_res := SaveSystem.load_from_slot(1)
	assert_bool(bool(load_res["ok"])).is_false()
	assert_str(String(load_res["error"])).is_equal("busy")
	Director._turn_in_flight = false
	assert_bool(bool(SaveSystem.load_from_slot(1)["ok"])).is_true()


# ------------------------------------------------------------------ fixtures


## A day-5, stage-3, locked-path run with facts and a mid-stream memory rng.
func _build_mid_campaign() -> void:
	GameState.set_meter(&"affection", 61.5)
	GameState.set_meter(&"trust", -12.25)
	GameState.set_meter(&"instability", 55.0)
	GameState.set_meter(&"fixation", 22.0)
	GameState.set_meter(&"lucidity", 8.0)
	GameState.turn = 9
	GameState.day = 5
	GameState.assign_path(&"YANDERE", true)
	GameState.player_name = "Ren"
	GameState.set_flag(&"said_i_love_you")
	GameState.set_flag(&"meta", {"nested": [1, 2]})
	GameState.bump_profile(&"warmth", 3)
	Memory.set_rng_seed(7)
	Memory.consider("likes film alpha", ["I like film alpha"])
	Memory.prompt_facts({"stage": 3})  # advance the stream mid-way
	Memory.consider("gave me a music box", ["I got you a music box"])


func _reset_game() -> void:
	Director.reset()
	GameState.reset()
	GameState.player_name = "Ren"
	Memory.reset()


func _register_log() -> void:
	SaveSystem.register_log_seam(
		_log, Callable(_log, "get_entries"), Callable(_log, "restore_entries")
	)


func _write_raw(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open(TEST_DIR + file_name, FileAccess.WRITE)
	if file == null:
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


## The JSON domain: numbers are doubles there, which is also the save's domain.
func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}
