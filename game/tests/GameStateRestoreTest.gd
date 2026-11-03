extends GdUnitTestSuite
## P1.04 round 2 — snapshot restore regressions (review CODE-1, DES-1, DES-2):
## from_dict() rebuilds on a canonical baseline — the result depends only on
## the snapshot, never on the instance it is loaded into. Peak and stage are
## bounded, partial profiles start zeroed, broken path locks heal, unrelated
## Dictionaries are rejected.

const GameStateScript := preload("res://autoload/GameState.gd")
const EPS := 0.0001


func _state() -> Variant:
	return auto_free(GameStateScript.new())


func test_from_dict_restores_onto_dirty_state() -> void:
	# A snapshot loaded into a live state replaces it wholesale — the live
	# stage/profile/flags leave no residue (review probes B and D, DES-2).
	var s: Variant = _state()
	s.set_meter(&"instability", 95.0)
	s.bump_profile(&"warmth", 5)
	s.set_flag(&"leftover", true)
	assert_int(s.stage).is_equal(5)
	var ok: bool = (
		s
		. from_dict(
			{
				"instability": 55.0,
				"instability_peak": 55.0,
				"stage": 3,
				"day": 6,
				"profile": {"coldness": 2},
				"flags": {"kept": true},
			}
		)
	)
	assert_bool(ok).is_true()
	assert_float(s.instability).is_equal_approx(55.0, EPS)
	assert_int(s.stage).is_equal(3)
	assert_int(s.day).is_equal(6)
	assert_int(int(s.profile["warmth"])).is_zero()
	assert_int(int(s.profile["coldness"])).is_equal(2)
	assert_bool(s.get_flag(&"kept")).is_true()
	assert_bool(s.get_flag(&"leftover")).is_false()


func test_from_dict_bounds_peak_and_stage() -> void:
	# A corrupt peak cannot lift the ratchet floor past 100 (review probe A,
	# CODE-1/DES-1); a stored stage above the peak's band heals down, and a
	# stored stage below it heals up to the monotonic high-water mark (probe E).
	var s: Variant = _state()
	assert_bool(s.from_dict({"instability_peak": 999.0, "instability": 5.0})).is_true()
	assert_float(s.instability_peak).is_equal_approx(100.0, EPS)
	assert_float(s.instability).is_equal_approx(85.0, EPS)
	assert_int(s.stage).is_equal(5)
	for meter: StringName in GameStateScript.METER_NAMES:
		var bounds: Vector2 = GameStateScript.METER_RANGES[meter]
		assert_float(s.get_meter(meter)).is_between(bounds.x - EPS, bounds.y + EPS)
	var t: Variant = _state()
	assert_bool(t.from_dict({"instability": 5.0, "stage": 5})).is_true()
	assert_int(t.stage).is_equal(0)


func test_from_dict_partial_profile_resets() -> void:
	# A partial snapshot rebuilds the profile from a zeroed baseline — stale
	# counters from the live instance do not survive (review probe B, CODE-1).
	var s: Variant = _state()
	s.bump_profile(&"warmth", 5)
	assert_bool(s.from_dict({"affection": 10.0})).is_true()
	assert_float(s.affection).is_equal_approx(10.0, EPS)
	for counter: StringName in GameStateScript.PROFILE_COUNTERS:
		assert_int(int(s.profile[String(counter)])).is_zero()


func test_from_dict_unknown_path_clears_lock() -> void:
	# An unknown path heals to "" and its lock is dropped — otherwise
	# assign_path() would be stranded forever (review probe I, CODE-1).
	var s: Variant = _state()
	assert_bool(s.from_dict({"path": "nonsense", "path_locked": true})).is_true()
	assert_str(String(s.path)).is_equal("")
	assert_bool(s.path_locked).is_false()
	assert_bool(s.assign_path(&"YANDERE")).is_true()
	# A stored lock without a valid path clears too.
	var t: Variant = _state()
	assert_bool(t.from_dict({"path_locked": true})).is_true()
	assert_bool(t.path_locked).is_false()


func test_from_dict_rejects_unrelated_dict() -> void:
	# A Dictionary with no snapshot keys is rejected — silently loading
	# defaults would look like a successful restore (CODE-1).
	var s: Variant = _state()
	s.set_meter(&"affection", 42.0)
	assert_bool(s.from_dict({"unrelated": 1, "data": [1, 2]})).is_false()
	assert_float(s.affection).is_equal_approx(42.0, EPS)


func test_from_dict_drops_unsafe_flags() -> void:
	# Flags are validated recursively on load, same rule as set_flag()
	# (CODE-4/DES-5): a corrupt save cannot park a Vector2 in the snapshot.
	var s: Variant = _state()
	var ok: bool = s.from_dict(
		{"flags": {"good": {"a": [1, 2]}, "bad": {"v": Vector2(1, 2)}, "worse": {1: "x"}}}
	)
	assert_bool(ok).is_true()
	assert_dict(s.get_flag(&"good")).is_equal({"a": [1, 2]})
	assert_bool(s.flags.has("bad")).is_false()
	assert_bool(s.flags.has("worse")).is_false()
