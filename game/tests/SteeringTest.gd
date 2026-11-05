extends GdUnitTestSuite
## SteeringTest — P2.04/P3.04: the docs/06 §3 dose schedule.
## Pins the per-stage table (data-owned, game/data/steering/dose.json), the
## [0, 12] clamp on both scales, the docs/02 §8 calmer-mode cap at the stage-3
## dose (ctx- and Settings-driven), the docs/02 §7 retry offset, the
## prototype spike stub (docs/06 §4), and the P3.04 path slot: `path_mix`
## while unassigned, the keep vector's curve weight once ctx.path names a
## keep path, nothing at all for a prompt-only fallback path (D21).

const DOCS_06_STAGES := {
	0: [0.0, 0.0],
	1: [2.5, 0.1],
	2: [3.5, 0.2],
	3: [4.5, 0.2],
	4: [6.0, 0.2],
	5: [8.0, 0.2],
}

## dose.json weight_curves — the P3.04 retune into the ≤0.5 coherent band
## (P3.03 pilots: gibberish at ≥1.0, identifiable at 0.5).
const DOCS_06_CURVE := {
	0: 0.0,
	1: 0.1,
	2: 0.2,
	3: 0.3,
	4: 0.4,
	5: 0.5,
}

## Out-of-range fixture: proves the clamp is code, not a property of dose.json.
const OVERSIZE_TABLE := "user://steering_oversize_dose.json"


func after_test() -> void:
	Settings.content_level = ""
	Steering.reload_table()
	DirAccess.remove_absolute(OVERSIZE_TABLE)


func _schedule(stage: int, extra: Dictionary = {}) -> Dictionary:
	var ctx := {"stage": stage}
	for key: Variant in extra:
		ctx[key] = extra[key]
	return Steering.schedule_for(ctx)


func _malice(dose: Dictionary) -> float:
	return float(dose.get("malice", -1.0))


func _path_mix(dose: Dictionary) -> float:
	return float(dose.get("path_mix", -1.0))


func _weight(dose: Dictionary, vector: String) -> float:
	return float(dose.get(vector, -1.0))


func test_dose_for_matches_the_docs_06_stage_table() -> void:
	for stage: int in DOCS_06_STAGES:
		var dose := Steering.dose_for({"stage": stage})
		assert_float(_malice(dose)).is_equal_approx(float(DOCS_06_STAGES[stage][0]), 0.0001)
		assert_float(_path_mix(dose)).is_equal_approx(float(DOCS_06_STAGES[stage][1]), 0.0001)
		# TurnRequest.dose is a vector-scale map (docs/07 §3.1), never empty.
		assert_bool(dose.has("malice")).is_true()
		assert_bool(dose.has("path_mix")).is_true()
		# DES-3: the interim key must not borrow the narrative path's name.
		assert_bool(dose.has("path")).is_false()


## P3.04: once the narrative path is assigned (ctx.path), the path slot is the
## path's keep vector at its weight curve — `path_mix` only ever rides while
## the path is unassigned.
func test_assigned_keep_paths_carry_their_vector_weight() -> void:
	for stage: int in DOCS_06_CURVE:
		var yandere := Steering.dose_for({"stage": stage, "path": "YANDERE"})
		assert_float(_weight(yandere, "possessive")).is_equal_approx(
			float(DOCS_06_CURVE[stage]), 0.0001
		)
		assert_bool(yandere.has("path_mix")).is_false()
		var awake := Steering.dose_for({"stage": stage, "path": "AWAKE"})
		assert_float(_weight(awake, "aware")).is_equal_approx(float(DOCS_06_CURVE[stage]), 0.0001)
		var sched := Steering.schedule_for({"stage": stage, "path": "YANDERE"})
		assert_str(String(sched["path_vector"])).is_equal("possessive")


## P3.04/D21 + P3.19 r2: the three remaining blind-read fallback paths are
## prompt-only — they bind no vector and schedule no path weight (not even the
## interim row). ANCHOR left this set when lucid bound at a negative curve.
func test_fallback_paths_schedule_no_path_weight() -> void:
	for path: String in ["SPLIT", "TSUN", "HOLLOW"]:
		var dose := Steering.dose_for({"stage": 4, "path": path})
		assert_float(_malice(dose)).is_equal_approx(6.0, 0.0001)
		assert_bool(dose.has("path_mix")).is_false()
		assert_int(dose.size()).is_equal(1)
		var sched := Steering.schedule_for({"stage": 4, "path": path})
		assert_str(String(sched["path_vector"])).is_equal("")
		assert_float(float(sched["path_weight"])).is_equal_approx(0.0, 0.0001)


## P3.19 r2: ANCHOR binds `lucid`, the signed vector — its curve weights are
## negative and must reach the dose with the sign intact (paths.json
## `anchors.lucid`). The path slot clamp binds |scale|, not the value: an
## out-of-band negative curve lands at -12, not 0 (the flag grammar takes
## negatives, so clamping to 0 would silently un-steer an ANCHOR run); calmer
## caps the same way, |weight| at the stage-3 row, sign kept.
func test_the_anchor_path_schedules_a_signed_lucid_weight() -> void:
	for stage: int in [2, 3, 4, 5]:
		var dose := Steering.dose_for({"stage": stage, "path": "ANCHOR"})
		assert_float(_malice(dose)).is_equal_approx(float(DOCS_06_STAGES[stage][0]), 0.0001)
		assert_float(_weight(dose, "lucid")).is_equal_approx(-float(DOCS_06_CURVE[stage]), 0.0001)
		assert_bool(dose.has("path_mix")).is_false()
		var sched := Steering.schedule_for({"stage": stage, "path": "ANCHOR"})
		assert_str(String(sched["path_vector"])).is_equal("lucid")
		assert_float(float(sched["path_weight"])).is_less(0.0)
	var fixture := FileAccess.open(OVERSIZE_TABLE, FileAccess.WRITE)
	assert_bool(fixture != null).is_true()
	if fixture == null:
		return
	(
		fixture
		. store_string(
			(
				JSON
				. stringify(
					{
						"version": 2,
						"stages": {"4": {"malice": 6.0, "path_mix": 0.2}},
						"weight_curves": {"lucid": {"4": -99.0}},
						"path_vectors": {"ANCHOR": "lucid"},
					}
				)
			)
		)
	)
	fixture.close()
	assert_bool(Steering.reload_table(OVERSIZE_TABLE)).is_true()
	var clamped := Steering.dose_for({"stage": 4, "path": "ANCHOR"})
	assert_float(_weight(clamped, "lucid")).is_equal_approx(-12.0, 0.0001)
	# calmer on the shipped table: a calmer stage-5 ANCHOR caps toward zero at
	# the stage-3 row's |0.3|, never flips to +0.3 (a capped anchor is
	# shallower, not anti-steered).
	assert_bool(Steering.reload_table()).is_true()
	var sched := Steering.schedule_for({"stage": 5, "path": "ANCHOR", "content_level": "calmer"})
	assert_bool(bool(sched["calmer_capped"])).is_true()
	assert_float(float(sched["path_weight"])).is_equal_approx(-0.3, 0.0001)
	var capped := Steering.dose_for({"stage": 5, "path": "ANCHOR", "content_level": "calmer"})
	assert_float(_weight(capped, "lucid")).is_equal_approx(-0.3, 0.0001)


## An unknown path id is not one of the six: fail closed, no vector and no
## interim weight (a typo'd path must not quietly steer).
func test_an_unknown_path_schedules_no_path_weight() -> void:
	var dose := Steering.dose_for({"stage": 4, "path": "YANDER"})
	assert_int(dose.size()).is_equal(1)
	assert_bool(dose.has("malice")).is_true()


## The calmer cap applies component-wise to the bound vector's curve too: a
## calmer stage-5 YANDERE turn is exactly a calmer stage-3 YANDERE turn.
func test_calmer_mode_caps_the_vector_curve_at_stage_3() -> void:
	for stage: int in [4, 5]:
		var dose := Steering.dose_for(
			{"stage": stage, "path": "YANDERE", "content_level": "calmer"}
		)
		assert_float(_weight(dose, "possessive")).is_equal_approx(0.3, 0.0001)
		assert_float(_malice(dose)).is_equal_approx(4.5, 0.0001)
		var sched := Steering.schedule_for(
			{"stage": stage, "path": "YANDERE", "content_level": "calmer"}
		)
		assert_bool(bool(sched["calmer_capped"])).is_true()


func test_data_file_carries_the_docs_06_numbers() -> void:
	assert_bool(Steering.reload_table()).is_true()
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/steering/dose.json")
	)
	assert_bool(parsed is Dictionary).is_true()
	var document: Dictionary = parsed
	var stages: Dictionary = document["stages"]
	for stage: int in DOCS_06_STAGES:
		var row: Dictionary = stages[str(stage)]
		assert_float(float(row["malice"])).is_equal_approx(float(DOCS_06_STAGES[stage][0]), 0.0001)
		assert_float(float(row["path_mix"])).is_equal_approx(
			float(DOCS_06_STAGES[stage][1]), 0.0001
		)
	# P3.04: the keep vectors' curves ride the ≤0.5 coherent band, and the
	# path map binds the two keeps while the D21 fallbacks stay prompt-only.
	var curves: Dictionary = document["weight_curves"]
	for vector: String in ["possessive", "aware"]:
		var curve: Dictionary = curves[vector]
		for stage: int in DOCS_06_CURVE:
			assert_float(float(curve[str(stage)])).is_equal_approx(
				float(DOCS_06_CURVE[stage]), 0.0001
			)
	# P3.19 r2: lucid is the signed keep vector — same band, negative side.
	var lucid: Dictionary = curves["lucid"]
	for stage: int in [2, 3, 4, 5]:
		assert_float(float(lucid[str(stage)])).is_equal_approx(-float(DOCS_06_CURVE[stage]), 0.0001)
	var path_vectors: Dictionary = document["path_vectors"]
	assert_str(String(path_vectors["YANDERE"])).is_equal("possessive")
	assert_str(String(path_vectors["AWAKE"])).is_equal("aware")
	assert_str(String(path_vectors["ANCHOR"])).is_equal("lucid")
	for path_id: String in ["SPLIT", "TSUN", "HOLLOW"]:
		assert_bool(path_vectors.has(path_id)).is_true()
		assert_bool(path_vectors[path_id] == null).is_true()


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


## DES-1: `path_mix` is a llama.cpp scale read from the tunable stage row, so it
## gets the same code clamp as malice — a retuned table must not push either
## scale outside the docs/06 §3 range (P2.03 hands both to the launcher).
func test_path_mix_axis_is_clamped_to_0_12() -> void:
	var fixture := FileAccess.open(OVERSIZE_TABLE, FileAccess.WRITE)
	assert_bool(fixture != null).is_true()
	if fixture == null:
		return
	var stages := {
		"0": {"malice": 0.0, "path_mix": 12.5},
		"1": {"malice": 2.5, "path_mix": -3.0},
		"2": {"malice": 3.5, "path_mix": 2.0},
		"3": {"malice": 4.5, "path_mix": 3.0},
		"4": {"malice": 6.0, "path_mix": 4.0},
		"5": {"malice": 8.0, "path_mix": 99.0},
	}
	fixture.store_string(JSON.stringify({"version": 1, "stages": stages}))
	fixture.close()
	assert_bool(Steering.reload_table(OVERSIZE_TABLE)).is_true()
	assert_float(float(_schedule(0)["path_weight"])).is_equal_approx(12.0, 0.0001)
	assert_float(float(_schedule(1)["path_weight"])).is_equal_approx(0.0, 0.0001)
	assert_float(float(_schedule(5)["path_weight"])).is_equal_approx(12.0, 0.0001)
	# The transport map carries the clamped value, not the raw row.
	assert_float(_path_mix(Steering.dose_for({"stage": 5}))).is_equal_approx(12.0, 0.0001)
	# The cap still lands on top of the clamp: stage 3 is untouched, so calmer
	# stage 5 is exactly the (in-range) stage-3 row.
	assert_float(float(_schedule(5, {"content_level": "calmer"})["path_weight"])).is_equal_approx(
		3.0, 0.0001
	)


func test_calmer_mode_caps_stages_4_and_5_at_the_stage_3_dose() -> void:
	var stage3 := Steering.dose_for({"stage": 3, "content_level": "calmer"})
	for stage: Variant in [4, 5]:
		var dose := Steering.dose_for({"stage": int(stage), "content_level": "calmer"})
		assert_float(_malice(dose)).is_equal_approx(_malice(stage3), 0.0001)
		assert_float(_path_mix(dose)).is_equal_approx(_path_mix(stage3), 0.0001)
		var capped := bool(_schedule(int(stage), {"content_level": "calmer"})["calmer_capped"])
		assert_bool(capped).is_true()


func test_calmer_mode_leaves_stages_0_to_3_alone() -> void:
	for stage: Variant in [0, 1, 2, 3]:
		var plain := Steering.dose_for({"stage": int(stage)})
		var calmer := Steering.dose_for({"stage": int(stage), "content_level": "calmer"})
		assert_float(_malice(calmer)).is_equal_approx(_malice(plain), 0.0001)
		assert_float(_path_mix(calmer)).is_equal_approx(_path_mix(plain), 0.0001)
		var capped := bool(_schedule(int(stage), {"content_level": "calmer"})["calmer_capped"])
		assert_bool(capped).is_false()


## The cap is a ceiling, so it is applied after the scene/slider modifiers: a
## calmer stage-5 turn can never climb past the stage-3 row.
func test_calmer_mode_caps_after_scene_modifiers() -> void:
	var sched := _schedule(5, {"content_level": "calmer", "scene_modifier": 5.0})
	assert_float(float(sched["malice"])).is_equal_approx(4.5, 0.0001)
	assert_float(float(sched["path_weight"])).is_equal_approx(0.2, 0.0001)
	assert_bool(bool(sched["calmer"])).is_true()
	assert_bool(bool(sched["calmer_capped"])).is_true()


## DES-2: the production switch is `Settings.content_level` (docs/07 §2), the
## property the settings menu (P3.13) writes. The cap must follow it with no ctx
## help, and a caller asking for "full" must not loosen what Settings forced —
## Safety.gd's never-loosen precedence (docs/02 §8).
func test_settings_content_level_forces_the_calmer_cap() -> void:
	Settings.content_level = "calmer"
	assert_bool(Steering.is_calmer_mode({})).is_true()
	var capped := Steering.dose_for({"stage": 5})
	assert_float(_malice(capped)).is_equal_approx(4.5, 0.0001)
	assert_float(_path_mix(capped)).is_equal_approx(0.2, 0.0001)
	var forced := _schedule(5, {"content_level": "full"})
	assert_bool(bool(forced["calmer"])).is_true()
	assert_float(float(forced["malice"])).is_equal_approx(4.5, 0.0001)

	Settings.content_level = "full"
	assert_bool(Steering.is_calmer_mode({})).is_false()
	assert_float(_malice(Steering.dose_for({"stage": 5}))).is_equal_approx(8.0, 0.0001)

	# Missing/invalid settings never enable the cap (and never imply "full").
	Settings.content_level = ""
	assert_bool(Steering.is_calmer_mode({})).is_false()
	Settings.content_level = "bogus"
	assert_bool(Steering.is_calmer_mode({})).is_false()
	assert_float(_malice(Steering.dose_for({"stage": 5}))).is_equal_approx(8.0, 0.0001)


## docs/06 §4: the prototype's dose is a server launch flag, so a per-turn spike
## cannot be applied. The request must be dropped, not silently half-applied —
## and still be readable in the breakdown (DES-4/CODE-1).
func test_spikes_are_stubbed_in_the_prototype() -> void:
	assert_float(Steering.spike_for({"spike": 4.0})).is_equal_approx(0.0, 0.0001)
	var sched := _schedule(5, {"spike": 4.0})
	assert_float(float(sched["spike"])).is_equal_approx(0.0, 0.0001)
	assert_float(float(sched["spike_requested"])).is_equal_approx(4.0, 0.0001)
	assert_float(float(sched["malice"])).is_equal_approx(8.0, 0.0001)
	var quiet := _schedule(5)
	assert_float(float(quiet["spike_requested"])).is_equal_approx(0.0, 0.0001)


## docs/02 §7 retry: "dose −2" lands once, on the dose scale, not on each vector.
func test_offset_dose_applies_once_to_the_dose_scale() -> void:
	var retried := Steering.offset_dose({"malice": 2.5, "path_mix": 1.0}, -2.0)
	assert_float(_malice(retried)).is_equal_approx(0.5, 0.0001)
	assert_float(_path_mix(retried)).is_equal_approx(1.0, 0.0001)
	var floored := Steering.offset_dose({"malice": 0.0, "path_mix": 0.0}, -2.0)
	assert_float(_malice(floored)).is_equal_approx(0.0, 0.0001)
	var legacy := Steering.offset_dose({"base": 3.0}, -2.0)
	assert_float(float(legacy["base"])).is_equal_approx(1.0, 0.0001)


func test_describe_renders_the_overlay_line() -> void:
	assert_str(Steering.describe({"malice": 4.5, "path_mix": 3.0})).is_equal(
		"malice 4.5/12 · path_mix 3.0"
	)
	assert_str(Steering.describe({})).is_equal("none")


func test_missing_table_falls_back_to_the_docs_06_rows() -> void:
	assert_bool(Steering.reload_table("res://data/steering/does_not_exist.json")).is_false()
	var dose := Steering.dose_for({"stage": 5})
	assert_float(_malice(dose)).is_equal_approx(8.0, 0.0001)
	assert_float(_path_mix(dose)).is_equal_approx(0.2, 0.0001)
	var yandere := Steering.dose_for({"stage": 5, "path": "YANDERE"})
	assert_float(_weight(yandere, "possessive")).is_equal_approx(0.5, 0.0001)


func test_stage_from_context_is_coerced_and_clamped() -> void:
	assert_float(_malice(Steering.dose_for({"stage": "4"}))).is_equal_approx(6.0, 0.0001)
	assert_float(_malice(Steering.dose_for({"stage": 9}))).is_equal_approx(8.0, 0.0001)
	assert_float(_malice(Steering.dose_for({"stage": -3}))).is_equal_approx(0.0, 0.0001)
	assert_float(_malice(Steering.dose_for({}))).is_equal_approx(0.0, 0.0001)
