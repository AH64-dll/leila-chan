extends GdUnitTestSuite
## P2.03 — the docs/06 §4 dose→vector map (`game/llm/StageSteering.gd`). Pure
## data and file-resolution tests: nothing here launches a server. The relaunch
## itself is covered by LlamaServerLiveTest.gd and tools/SteeringRestartBench.

const Steer := preload("res://llm/StageSteering.gd")
const VECTOR_FILE := "res://data/steering/malice.gguf"
const FIXTURE_DIR := "user://stage_steering_test"

var _steering: StageSteering


func before_test() -> void:
	_steering = Steer.new()


func after_test() -> void:
	var global := ProjectSettings.globalize_path(FIXTURE_DIR)
	if not DirAccess.dir_exists_absolute(global):
		return
	for name: String in DirAccess.get_files_at(global):
		DirAccess.remove_absolute(global.path_join(name))
	DirAccess.remove_absolute(global)


func _write_fixture(name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))
	var path := FIXTURE_DIR.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func test_shipped_map_maps_the_malice_axis() -> void:
	assert_bool(_steering.load_map()).is_true()
	assert_str(_steering.file_for("malice")).is_equal(VECTOR_FILE)
	# P3.04: the keep path vectors bind their shipped .gguf files.
	assert_str(_steering.file_for("possessive")).is_equal("res://data/steering/possessive.gguf")
	assert_str(_steering.file_for("aware")).is_equal("res://data/steering/aware.gguf")
	# P3.19 r2: lucid joins the keeps — ANCHOR's signed vector.
	assert_str(_steering.file_for("lucid")).is_equal("res://data/steering/lucid.gguf")
	assert_array(_steering.known_keys()).contains_exactly(
		["malice", "possessive", "aware", "lucid"]
	)
	# The interim `path_mix` weight binds no file, and the map says why instead
	# of quietly dropping it.
	assert_bool(_steering.unbound_reason("path_mix").is_empty()).is_false()


func test_launch_payload_carries_the_resolved_file_and_scale() -> void:
	assert_bool(_steering.load_map()).is_true()
	# The dose comes from the schedule owner, so this pins map and schedule together.
	# No path yet (stage 4 pre-assignment): malice binds, path_mix stays declared.
	var dose := Steering.dose_for({"stage": 4})
	assert_float(float(dose["malice"])).is_equal(6.0)
	var launch := _steering.launch_for(dose)
	assert_bool(bool(launch["ok"])).is_true()
	var vectors: Array = launch["vectors"]
	assert_int(vectors.size()).is_equal(1)
	var entry: Dictionary = vectors[0]
	assert_str(String(entry["path"])).ends_with("data/steering/malice.gguf")
	assert_bool(FileAccess.file_exists(String(entry["path"]))).is_true()
	assert_float(float(entry["scale"])).is_equal(6.0)
	assert_array(launch["scheduled"]).contains_exactly_in_any_order(["malice", "path_mix"])
	assert_array(launch["unbound"]).contains_exactly(["path_mix"])


func test_launch_payload_binds_the_locked_path_vector() -> void:
	assert_bool(_steering.load_map()).is_true()
	# A locked YANDERE run at stage 3 schedules malice + possessive (P3.04).
	var dose := Steering.dose_for({"stage": 3, "path": "YANDERE"})
	var launch := _steering.launch_for(dose)
	assert_bool(bool(launch["ok"])).is_true()
	var files := {}
	for entry: Variant in launch["vectors"]:
		files[String((entry as Dictionary)["path"]).get_file()] = float(
			(entry as Dictionary)["scale"]
		)
	assert_dict(files).contains_key_value("malice.gguf", 4.5)
	assert_dict(files).contains_key_value("possessive.gguf", 0.3)
	assert_array(launch["unbound"]).is_empty()


func test_a_prompt_only_path_binds_only_malice() -> void:
	assert_bool(_steering.load_map()).is_true()
	# SPLIT is the P3.03 fallback (prompt-only): no path weight is scheduled at
	# all, so nothing is declared unbound either.
	var launch := _steering.launch_for(Steering.dose_for({"stage": 4, "path": "SPLIT"}))
	assert_bool(bool(launch["ok"])).is_true()
	assert_int((launch["vectors"] as Array).size()).is_equal(1)
	assert_array(launch["unbound"]).is_empty()


func test_the_anchor_path_binds_lucid_at_a_negative_scale() -> void:
	assert_bool(_steering.load_map()).is_true()
	# P3.19 r2: ANCHOR keeps a vector, the signed one — lucid's positive side IS
	# the anchor voice, so the schedule applies it negative (paths.json
	# `anchors.lucid`); the flag must carry the sign, not drop it.
	var launch := _steering.launch_for(Steering.dose_for({"stage": 4, "path": "ANCHOR"}))
	assert_bool(bool(launch["ok"])).is_true()
	var files := {}
	for entry: Variant in launch["vectors"]:
		files[String((entry as Dictionary)["path"]).get_file()] = float(
			(entry as Dictionary)["scale"]
		)
	assert_dict(files).contains_key_value("malice.gguf", 6.0)
	assert_dict(files).contains_key_value("lucid.gguf", -0.4)
	assert_array(launch["unbound"]).is_empty()


func test_zero_scales_bind_no_vector() -> void:
	assert_bool(_steering.load_map()).is_true()
	# Stage 0 / a New Game: a clean server, not a `:0` no-op flag.
	var launch := _steering.launch_for(Steering.dose_for({"stage": 0}))
	assert_bool(bool(launch["ok"])).is_true()
	assert_array(launch["vectors"]).is_empty()


func test_a_missing_vector_file_fails_the_whole_payload() -> void:
	# docs/06 §4: llama.cpp only warns for a bad FNAME and then serves healthy, so
	# a partial payload must be refused rather than launched unsteered.
	_steering.parse_document(
		{"vectors": {"malice": {"file": "res://data/steering/does_not_exist.gguf"}}}
	)
	var launch := _steering.launch_for({"malice": 4.5})
	assert_bool(bool(launch["ok"])).is_false()
	assert_array(launch["vectors"]).is_empty()
	assert_str(String((launch["error"] as Dictionary)["code"])).is_equal("control_vector_missing")


func test_a_non_gguf_file_fails_the_payload() -> void:
	var path := _write_fixture("not_a_vector.gguf", "this is not a control vector")
	_steering.parse_document({"vectors": {"malice": {"file": path}}})
	var launch := _steering.launch_for({"malice": 4.5})
	assert_bool(bool(launch["ok"])).is_false()
	assert_str(String((launch["error"] as Dictionary)["code"])).is_equal("control_vector_invalid")


func test_non_finite_scales_are_rejected() -> void:
	assert_bool(_steering.load_map()).is_true()
	for bad: float in [INF, -INF, NAN]:
		var launch := _steering.launch_for({"malice": bad})
		assert_bool(bool(launch["ok"])).is_false()
		assert_str(String((launch["error"] as Dictionary)["code"])).is_equal(
			"control_vector_invalid"
		)


func test_unbound_dose_keys_are_reported_not_dropped() -> void:
	assert_bool(_steering.load_map()).is_true()
	# The interim `path_mix` weight has no file: the weight is scheduled and said
	# so, but nothing is invented for it.
	var launch := _steering.launch_for({"malice": 4.5, "path_mix": 0.2})
	assert_bool(bool(launch["ok"])).is_true()
	assert_int((launch["vectors"] as Array).size()).is_equal(1)
	assert_array(launch["unbound"]).contains_exactly(["path_mix"])


func test_an_undeclared_dose_key_fails_the_payload() -> void:
	# A renamed/typo'd key must be a failure, not a silent skip: otherwise the
	# caller "binds" nothing, moves the stage bookkeeping and the server runs
	# unsteered (docs/06 §4.1 "Failure keeps the old dose", CODE-1). `unstable`
	# is a shipped-but-fallback vector: it exists on disk and is deliberately
	# unmapped, so it must still fail like any unknown key.
	assert_bool(_steering.load_map()).is_true()
	var launch := _steering.launch_for({"malice": 4.5, "unstable": 2.0})
	assert_bool(bool(launch["ok"])).is_false()
	assert_array(launch["vectors"]).is_empty()
	assert_str(String((launch["error"] as Dictionary)["code"])).is_equal("control_vector_unmapped")
	(
		_steering
		. parse_document(
			{
				"vectors": {"malice": {"file": VECTOR_FILE}},
				"unbound": {"possessive": "P3.04 ships this vector"},
			}
		)
	)
	var declared := _steering.launch_for({"malice": 4.5, "possessive": 2.0})
	assert_bool(bool(declared["ok"])).is_true()
	assert_array(declared["unbound"]).contains_exactly(["possessive"])


func test_empty_dose_binds_nothing() -> void:
	assert_bool(_steering.load_map()).is_true()
	var launch := _steering.launch_for({})
	assert_bool(bool(launch["ok"])).is_true()
	assert_array(launch["vectors"]).is_empty()


func test_broken_documents_leave_the_map_empty() -> void:
	# Unusable documents are refused, not half-loaded: the caller keeps the old dose.
	for document: Variant in [null, {}, {"vectors": {}}, {"vectors": []}]:
		assert_bool(_steering.parse_document(document)).is_false()
		assert_array(_steering.known_keys()).is_empty()
	# One broken row must not take the usable rows with it.
	(
		assert_bool(
			_steering.parse_document(
				{"vectors": {"malice": {"file": VECTOR_FILE}, "broken": {"file": ""}}}
			)
		)
		. is_true()
	)
	assert_array(_steering.known_keys()).contains_exactly(["malice"])


func test_missing_map_file_reports_the_reason() -> void:
	assert_bool(_steering.load_map("res://data/steering/does_not_exist.json")).is_false()
	assert_bool(_steering.last_error().is_empty()).is_false()
	# With no map there are no declarations either, so a scheduled dose must fail
	# closed instead of reporting an empty (unsteered) bind (CODE-1/DES-1).
	var launch := _steering.launch_for({"malice": 4.5})
	assert_bool(bool(launch["ok"])).is_false()
	assert_str(String((launch["error"] as Dictionary)["code"])).is_equal("control_vector_unmapped")


func test_shipped_vector_is_a_gguf_container() -> void:
	assert_bool(FileAccess.file_exists(VECTOR_FILE)).is_true()
	assert_bool(_steering.has_gguf_magic(ProjectSettings.globalize_path(VECTOR_FILE))).is_true()
	var text := _write_fixture("fake.gguf", "GGU")
	assert_bool(_steering.has_gguf_magic(ProjectSettings.globalize_path(text))).is_false()


func test_extraction_copies_the_bytes_for_a_packed_build() -> void:
	# An exported build keeps res:// inside the .pck, which llama-server cannot
	# open; the launch path must be a real file (docs/06 §2 "ship in the pack").
	var extracted := _steering.extract_to(VECTOR_FILE, FIXTURE_DIR)
	assert_bool(extracted.is_empty()).is_false()
	assert_bool(FileAccess.file_exists(extracted)).is_true()
	assert_bool(_steering.has_gguf_magic(extracted)).is_true()
	var original := FileAccess.get_file_as_bytes(VECTOR_FILE)
	var copy := FileAccess.get_file_as_bytes(extracted)
	assert_int(copy.size()).is_equal(original.size())


func test_describe_renders_file_and_scale() -> void:
	assert_str(Steer.describe([{"path": "/tmp/x/malice.gguf", "scale": 4.5}])).is_equal(
		"malice.gguf 4.5"
	)
	assert_str(Steer.describe([])).is_equal("")
