extends GdUnitTestSuite
## TranscriptLogger (P1.18, docs/07 §5): per-session JSONL transcripts under
## user://debug — canonical turn records (prompt/schema/raw output/applied
## events/metrics), session markers, safety-redaction gating, size rotation
## with a file cap, flush-on-write durability and the replay loader. The clock
## is injected so file names and ts are deterministic.

const TL := preload("res://llm/TranscriptLogger.gd")
const BASE := "user://debug_test_transcript/"

var _dir := ""
var _clock_ms := 1700000000
var _case := 0


func before() -> void:
	_rm_dir(BASE)
	DirAccess.make_dir_recursive_absolute(BASE)


func after() -> void:
	_rm_dir(BASE)


func before_test() -> void:
	_case += 1
	_dir = BASE + "case_%03d/" % _case


func _logger(cfg := {}) -> TranscriptLogger:
	var l := TL.new()
	l.set_clock(func() -> int: return _clock_ms)
	l.configure({"debug_dir": _dir})
	l.configure(cfg)
	return l


func _turn(n: int, tail := "") -> Dictionary:
	return {
		"turn": n,
		"prompt": [{"role": "user", "content": "msg %d" % n}],
		"schema": {"type": "object"},
		"output": '{"beats":[{"say":"reply %d"}]}' % n + tail,
	}


func _rm_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	for f: String in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub: String in d.get_directories():
		_rm_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _load(path: String) -> Dictionary:
	return TL.load_transcript(path)


func test_turn_record_fields_session_markers_and_order() -> void:
	var l := _logger()
	assert_str(l.start_session({"device": "dev"})).is_equal("s1700000000-001")
	var accepted: bool = (
		l
		. log_turn(
			{
				"turn": 1,
				"prompt": [{"role": "system", "content": "sys"}],
				"schema": {"type": "object"},
				"output": '{"say":"hi"}',
				"metrics": {"generate_ms": 12},
				"events": [{"type": "say_chunk"}],
				"error": {"code": "none"},
				"day": 1,
				"stage": 0,
				"path": "romantic",
				"dose": {"malice": 4.5},
				"junk": "dropped",
			}
		)
	)
	assert_bool(accepted).is_true()
	var path := l.current_file()
	l.close()

	var loaded := _load(path)
	var errors: Array = loaded["errors"]
	assert_array(errors).is_empty()
	var records: Array = loaded["records"]
	assert_int(records.size()).is_equal(3)  # session start + turn + session end

	var start: Dictionary = records[0]
	assert_str(String(start["type"])).is_equal("session")
	assert_str(String(start["event"])).is_equal("start")
	assert_str(String(start["meta"]["device"])).is_equal("dev")

	var turn: Dictionary = records[1]
	assert_int(int(turn["v"])).is_equal(TL.RECORD_VERSION)
	assert_str(String(turn["type"])).is_equal("turn")
	assert_str(String(turn["session"])).is_equal("s1700000000-001")
	assert_int(int(turn["seq"])).is_equal(0)
	assert_int(int(turn["ts"])).is_equal(_clock_ms)
	assert_int(int(turn["turn"])).is_equal(1)
	assert_array(turn["prompt"]).has_size(1)
	assert_bool(turn["schema"] is Dictionary).is_true()
	assert_str(String(turn["output"])).is_equal('{"say":"hi"}')
	assert_int(int(turn["metrics"]["generate_ms"])).is_equal(12)
	assert_array(turn["events"]).has_size(1)
	assert_str(String(turn["error"]["code"])).is_equal("none")
	assert_int(int(turn["day"])).is_equal(1)
	assert_int(int(turn["stage"])).is_equal(0)
	assert_str(String(turn["path"])).is_equal("romantic")
	assert_float(float(turn["dose"]["malice"])).is_equal(4.5)
	# unknown keys never reach disk — the format stays canonical
	assert_bool(turn.has("junk")).is_false()
	# canonical key order (JSON.stringify is sorted-deterministic) so
	# transcript diffs stay readable and replay output is stable
	var keys: Array = turn.keys()
	var sorted_keys: Array = keys.duplicate()
	sorted_keys.sort()
	assert_array(keys).is_equal(sorted_keys)

	var end: Dictionary = records[2]
	assert_str(String(end["type"])).is_equal("session")
	assert_str(String(end["event"])).is_equal("end")


func test_missing_or_wrong_required_fields_rejected() -> void:
	var l := _logger()
	l.start_session()
	var bad := [
		{"prompt": [], "schema": {}, "output": "x"},
		{"turn": 1, "schema": {}, "output": "x"},
		{"turn": 1, "prompt": [], "output": "x"},
		{"turn": 1, "prompt": [], "schema": {}},
		{"turn": "1", "prompt": [], "schema": {}, "output": "x"},
		{"turn": 1, "prompt": "not-msgs", "schema": {}, "output": "x"},
		{"turn": 1, "prompt": [], "schema": {}, "output": 7},
	]
	for rec: Dictionary in bad:
		assert_bool(l.log_turn(rec)).append_failure_message(str(rec)).is_false()
	assert_str(String(l.last_error()["message"])).is_not_empty()
	l.end_session()
	# only the two session markers reached disk — no half-written turns
	var files := TL.transcript_files(_dir)
	assert_int(files.size()).is_equal(1)
	var records: Array = _load(_dir.path_join(files[0]))["records"]
	assert_int(TL.turn_records(records).size()).is_equal(0)


func test_log_turn_auto_starts_session_and_seq_increments() -> void:
	var l := _logger()
	l.log_turn(_turn(1))
	l.log_turn(_turn(2))
	var sid := l.session_id()
	var path := l.current_file()
	l.end_session()

	assert_str(sid).is_not_empty()
	var records: Array = _load(path)["records"]
	var turns := TL.turn_records(records)
	assert_int(turns.size()).is_equal(2)
	assert_int(int(turns[0]["seq"])).is_equal(0)
	assert_int(int(turns[1]["seq"])).is_equal(1)
	assert_str(String(turns[0]["session"])).is_equal(sid)
	assert_str(String(turns[1]["session"])).is_equal(sid)


func test_each_session_gets_its_own_file() -> void:
	var l := _logger()
	var s1 := l.start_session()
	l.log_turn(_turn(1))
	var s2 := l.start_session()  # implicitly ends s1
	l.log_turn(_turn(2))
	l.end_session()

	assert_str(s2).is_not_equal(s1)
	var files := TL.transcript_files(_dir)
	assert_int(files.size()).is_equal(2)
	assert_str(files[0]).contains(s1)
	assert_str(files[1]).contains(s2)


func test_rotation_splits_files_without_splitting_lines() -> void:
	var l := _logger({"max_file_bytes": 220})
	l.start_session()
	for i: int in 6:
		l.log_turn(_turn(i + 1, "x".repeat(40)))
	l.end_session()

	var files := TL.transcript_files(_dir)
	assert_int(files.size()).is_greater(1)
	assert_str(files[0]).contains("_p001")
	assert_str(files[1]).contains("_p002")
	# every rotated file is intact JSONL; no turn is lost across the boundary
	var turns := 0
	for f: String in files:
		var loaded := _load(_dir.path_join(f))
		assert_array(loaded["errors"]).append_failure_message(f).is_empty()
		turns += TL.turn_records(loaded["records"]).size()
	assert_int(turns).is_equal(6)
	# completed files respect the byte budget (in UTF-8, not chars)
	var first := FileAccess.open(_dir.path_join(files[0]), FileAccess.READ)
	assert_int(int(first.get_length())).is_less_equal(220)
	first.close()


func test_max_files_cap_prunes_oldest_but_never_the_open_file() -> void:
	var l := _logger({"max_file_bytes": 120, "max_files": 2})
	l.start_session()
	var sid := l.session_id()
	for i: int in 8:
		l.log_turn(_turn(i + 1, "y".repeat(30)))
	l.end_session()

	var files := TL.transcript_files(_dir)
	assert_int(files.size()).is_equal(2)
	assert_str(files[files.size() - 1]).contains(sid)
	var turns := 0
	for f: String in files:
		turns += TL.turn_records(_load(_dir.path_join(f))["records"]).size()
	assert_int(turns).is_less(8)  # the oldest parts are gone — bounded storage


func test_disabled_writes_nothing() -> void:
	var l := _logger({"enabled": false})
	assert_bool(l.is_enabled()).is_false()  # also false in release builds
	l.start_session()
	assert_bool(l.log_turn(_turn(1))).is_false()
	l.end_session()
	assert_array(Array(TL.transcript_files(_dir))).is_empty()
	assert_str(l.current_file()).is_empty()


func test_redactor_rewrites_records_and_gets_a_deep_copy() -> void:
	var l := _logger()
	var hooked: Array = []
	l.set_redactor(
		func(r: Dictionary) -> Dictionary:
			r["hooked"] = true
			hooked.append(r.get("type", ""))
			if r.has("output"):
				r["output"] = "[REDACTED]"
			return r
	)
	l.start_session()
	var rec := _turn(1)
	l.log_turn(rec)
	var path := l.current_file()
	l.end_session()

	var records: Array = _load(path)["records"]
	# every written line — session markers included — passed the safety hook
	for r: Variant in records:
		assert_bool((r as Dictionary).has("hooked")).is_true()
	var turns := TL.turn_records(records)
	assert_str(String(turns[0]["output"])).is_equal("[REDACTED]")
	# the caller's dictionary is untouched: the hook worked on a deep copy
	assert_str(String(rec["output"])).is_equal('{"beats":[{"say":"reply 1"}]}')
	assert_bool(rec.has("hooked")).is_false()


func test_redact_ready_blocks_until_the_hook_is_alive() -> void:
	var l := _logger()
	assert_bool(l.redact_ready()).is_true()  # unset hook = nothing to wait for
	var hook := Node.new()
	var dangling := Callable(hook, "queue_free")
	hook.free()  # the safety object died — its callable is now invalid
	l.set_redactor(dangling)

	assert_bool(l.redact_ready()).is_false()
	assert_bool(l.log_turn(_turn(1))).is_false()  # held, not dropped
	assert_array(Array(TL.transcript_files(_dir))).is_empty()

	l.set_redactor(func(r: Dictionary) -> Dictionary: return r)
	assert_bool(l.redact_ready()).is_true()
	assert_bool(l.log_turn(_turn(1))).is_true()
	l.end_session()


func test_redactor_returning_non_dictionary_drops_the_record() -> void:
	var l := _logger()
	l.set_redactor(
		func(r: Dictionary) -> Variant: return 42 if String(r.get("type", "")) == "turn" else r
	)
	l.start_session()
	assert_bool(l.log_turn(_turn(1))).is_false()
	assert_int(int(l.last_error()["code"])).is_equal(ERR_INVALID_DATA)
	var path := l.current_file()
	l.end_session()

	var records: Array = _load(path)["records"]
	# the session markers passed through fine; only the broken turn was dropped
	assert_int(records.size()).is_equal(2)
	assert_int(TL.turn_records(records).size()).is_equal(0)


func test_loader_tolerates_corrupt_lines_and_missing_files() -> void:
	var l := _logger()
	l.log_turn(_turn(1))
	l.log_turn(_turn(2))
	var path := l.current_file()
	l.end_session()

	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string("\n{broken json\nnot json either\n")
	f.close()

	var loaded := _load(path)
	var errors: Array = loaded["errors"]
	assert_int(errors.size()).is_equal(2)
	assert_int(int(errors[0]["line"])).is_equal(6)
	assert_int(int(errors[1]["line"])).is_equal(7)
	# good records survive around the corruption — replay keeps working
	assert_int(TL.turn_records(loaded["records"]).size()).is_equal(2)

	var missing := _load(_dir + "does_not_exist.jsonl")
	assert_array(missing["records"]).is_empty()
	assert_int((missing["errors"] as Array).size()).is_equal(1)


func test_close_is_final_flush_safe_and_reopenable() -> void:
	var l := _logger()
	l.start_session()
	l.log_turn(_turn(1))
	assert_bool(l.flush()).is_true()
	var path := l.current_file()
	l.close()

	assert_bool(l.log_turn(_turn(2))).is_false()  # closed logger refuses turns
	assert_str(l.current_file()).is_empty()
	var records: Array = _load(path)["records"]
	assert_int(TL.turn_records(records).size()).is_equal(1)
	assert_str(String(records[records.size() - 1]["event"])).is_equal("end")

	# an explicit new session reopens the logger
	var sid := l.start_session()
	assert_bool(l.log_turn(_turn(3))).is_true()
	l.end_session()
	assert_str(sid).is_equal("s1700000000-002")


func test_transcript_files_filters_foreign_files_and_sorts() -> void:
	var l := _logger()
	l.start_session()
	l.log_turn(_turn(1))
	l.end_session()
	var foreign := FileAccess.open(_dir.path_join("notes.txt"), FileAccess.WRITE)
	foreign.store_string("x")
	foreign.close()
	var foreign2 := FileAccess.open(_dir.path_join("transcript_sx.jsonl"), FileAccess.WRITE)
	foreign2.store_string("{}\n")
	foreign2.close()

	var files := TL.transcript_files(_dir)
	assert_int(files.size()).is_equal(1)
	assert_str(files[0]).starts_with("turns_ss1700000000-001_p")
	assert_str(files[0]).ends_with(".jsonl")
	# missing/empty dir answers empty, never an error
	assert_array(Array(TL.transcript_files(BASE + "ghost/"))).is_empty()
