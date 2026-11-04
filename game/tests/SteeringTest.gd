extends GdUnitTestSuite
## SteeringTest — P2.04: the docs/06 §3 dose schedule.
## Pins the per-stage table (data-owned, game/data/steering/dose.json), the
## [0, 12] clamp, the docs/02 §8 calmer-mode cap at the stage-3 dose, the
## docs/02 §7 retry offset, and the prototype spike stub (docs/06 §4).

const DOCS_06_STAGES := {
	0: [0.0, 0.0],
	1: [2.5, 1.0],
	2: [3.5, 2.0],
	3: [4.5, 3.0],
	4: [6.0, 4.0],
	5: [8.0, 5.0],
}


func after_test() -> void:
	Steering.reload_table()


func _schedule(stage: int, extra: Dictionary = {}) -> Dictionary:
	var ctx := {"stage": stage}
	for key: Variant in extra:
		ctx[key] = extra[key]
	return Steering.schedule_for(ctx)


func _malice(dose: Dictionary) -> float:
	return float(dose.get("malice", -1.0))


func _path(dose: Dictionary) -> float:
	return float(dose.get("path", -1.0))


func test_dose_for_matches_the_docs_06_stage_table() -> void:
	for stage: int in DOCS_06_STAGES:
		var dose := Steering.dose_for({"stage": stage})
		assert_float(_malice(dose)).is_equal_approx(float(DOCS_06_STAGES[stage][0]), 0.0001)
		assert_float(_path(dose)).is_equal_approx(float(DOCS_06_STAGES[stage][1]), 0.0001)
		# TurnRequest.dose is a vector-scale map (docs/07 §3.1), never empty.
		assert_bool(dose.has("malice")).is_true()
		assert_bool(dose.has("path")).is_true()


func test_data_file_carries_the_docs_06_numbers() -> void:
	assert_bool(Steering.reload_table()).is_true()
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/steering/dose.json")
	)
	assert_bool(parsed is Dictionary).is_true()
	var stages: Dictionary = (parsed as Dictionary)["stages"]
	for stage: int in DOCS_06_STAGES:
		var row: Dictionary = stages[str(stage)]
		assert_float(float(row["malice"])).is_equal_approx(float(DOCS_06_STAGES[stage][0]), 0.0001)
		assert_float(float(row["path"])).is_equal_approx(float(DOCS_06_STAGES[stage][1]), 0.0001)


## The malice column is docs/02 §9's "steering dose (base)" column; sampling.json
## owns that table, dose.json owns the schedule. They must not drift apart.
func test_malice_column_agrees_with_the_docs_02_sampling_table() -> void:
	for stage: int in DOCS_06_STAGES:
		var spec := TurnContext.sampling_spec(stage)
		assert_float(float(spec.get("dose", -1.0))).is_equal_approx(
			_malice(Steering.dose_for({"stage": stage})), 0.0001
		)


func test_dose_clamps_to_0_12() -> void:
	var high := _schedule(5, {"scene_modifier": 9.0})
	assert_float(float(high["malice"])).is_equal_approx(12.0, 0.0001)
	assert_float(float(high["clamp_max"])).is_equal_approx(12.0, 0.0001)
	assert_float(float(high["clamp_min"])).is_equal_approx(0.0, 0.0001)
	var low := _schedule(3, {"player_slider": 30.0})
	assert_float(float(low["malice"])).is_equal_approx(0.0, 0.0001)


func test_calmer_mode_caps_stages_4_and_5_at_the_stage_3_dose() -> void:
	var stage3 := Steering.dose_for({"stage": 3, "content_level": "calmer"})
	for stage: Variant in [4, 5]:
		var dose := Steering.dose_for({"stage": int(stage), "content_level": "calmer"})
		assert_float(_malice(dose)).is_equal_approx(_malice(stage3), 0.0001)
		assert_float(_path(dose)).is_equal_approx(_path(stage3), 0.0001)
		var capped := bool(_schedule(int(stage), {"content_level": "calmer"})["calmer_capped"])
		assert_bool(capped).is_true()


func test_calmer_mode_leaves_stages_0_to_3_alone() -> void:
	for stage: Variant in [0, 1, 2, 3]:
		var plain := Steering.dose_for({"stage": int(stage)})
		var calmer := Steering.dose_for({"stage": int(stage), "content_level": "calmer"})
		assert_float(_malice(calmer)).is_equal_approx(_malice(plain), 0.0001)
		assert_float(_path(calmer)).is_equal_approx(_path(plain), 0.0001)
		var capped := bool(_schedule(int(stage), {"content_level": "calmer"})["calmer_capped"])
		assert_bool(capped).is_false()


## The cap is a ceiling, so it is applied after the scene/slider modifiers: a
## calmer stage-5 turn can never climb past the stage-3 row.
func test_calmer_mode_caps_after_scene_modifiers() -> void:
	var sched := _schedule(5, {"content_level": "calmer", "scene_modifier": 5.0})
	assert_float(float(sched["malice"])).is_equal_approx(4.5, 0.0001)
	assert_float(float(sched["path"])).is_equal_approx(3.0, 0.0001)
	assert_bool(bool(sched["calmer"])).is_true()
	assert_bool(bool(sched["calmer_capped"])).is_true()


## docs/06 §4: the prototype's dose is a server launch flag, so a per-turn spike
## cannot be applied. The request must be dropped, not silently half-applied.
func test_spikes_are_stubbed_in_the_prototype() -> void:
	assert_float(Steering.spike_for({"spike": 4.0})).is_equal_approx(0.0, 0.0001)
	var sched := _schedule(5, {"spike": 4.0})
	assert_float(float(sched["spike"])).is_equal_approx(0.0, 0.0001)
	assert_float(float(sched["malice"])).is_equal_approx(8.0, 0.0001)


## docs/02 §7 retry: "dose −2" lands once, on the dose scale, not on each vector.
func test_offset_dose_applies_once_to_the_dose_scale() -> void:
	var retried := Steering.offset_dose({"malice": 2.5, "path": 1.0}, -2.0)
	assert_float(_malice(retried)).is_equal_approx(0.5, 0.0001)
	assert_float(_path(retried)).is_equal_approx(1.0, 0.0001)
	var floored := Steering.offset_dose({"malice": 0.0, "path": 0.0}, -2.0)
	assert_float(_malice(floored)).is_equal_approx(0.0, 0.0001)
	var legacy := Steering.offset_dose({"base": 3.0}, -2.0)
	assert_float(float(legacy["base"])).is_equal_approx(1.0, 0.0001)


func test_describe_renders_the_overlay_line() -> void:
	assert_str(Steering.describe({"malice": 4.5, "path": 3.0})).is_equal("malice 4.5/12 · path 3.0")
	assert_str(Steering.describe({})).is_equal("none")


func test_missing_table_falls_back_to_the_docs_06_rows() -> void:
	assert_bool(Steering.reload_table("res://data/steering/does_not_exist.json")).is_false()
	var dose := Steering.dose_for({"stage": 5})
	assert_float(_malice(dose)).is_equal_approx(8.0, 0.0001)
	assert_float(_path(dose)).is_equal_approx(5.0, 0.0001)


func test_stage_from_context_is_coerced_and_clamped() -> void:
	assert_float(_malice(Steering.dose_for({"stage": "4"}))).is_equal_approx(6.0, 0.0001)
	assert_float(_malice(Steering.dose_for({"stage": 9}))).is_equal_approx(8.0, 0.0001)
	assert_float(_malice(Steering.dose_for({"stage": -3}))).is_equal_approx(0.0, 0.0001)
	assert_float(_malice(Steering.dose_for({}))).is_equal_approx(0.0, 0.0001)
