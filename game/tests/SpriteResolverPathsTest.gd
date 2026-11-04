extends GdUnitTestSuite
## P3.06 — every path rule in docs/03 §3.2 and every sprite pool in docs/01 §4.
##
## The pure table (resolve()) covers 6 paths x 22 feelings x 3 intensities x 3 stages,
## once with no beat flags and once with the TSUN break / ANCHOR relapse flags set.
## What only a beat stream can show lives in the sequence tests: SPLIT's 01 <-> 17
## whiplash, HOLLOW's frozen face and ANCHOR's one-beat relapse then 02 recovery.

const MOCK_PATH := "user://sprite_resolver_paths_mock.json"
const BREAK_FLAGS := {"tsun_break": true}
const RELAPSE_FLAGS := {"anchor_relapse": true}

## docs/01 §4.1–§4.6's `Sprites:` lines, transcribed verbatim in doc order. The
## Python twin (tests/test_casting_paths.py) reads the markdown itself; this copy
## guards the game/data/casting.json the runtime actually loads.
const DOC_POOLS := {
	"YANDERE": ["01", "06", "24", "21", "30", "27"],
	"SPLIT": ["01", "17", "19", "15", "16", "13"],
	"TSUN": ["03", "07", "09", "17", "10", "26"],
	"HOLLOW": ["14", "12", "10", "23", "25"],
	"AWAKE": ["08", "29", "11", "22", "25"],
	"ANCHOR": ["02", "05", "06", "13", "14", "26", "21"],
}

## docs/03 §3.2's faces that fall outside their path's docs/01 §4 pool: the per-feeling
## spot fixes the resolver spec names explicitly (kept; counted here, never hidden).
const DOC03_EXTRAS := {
	"YANDERE": ["22", "28"],
	"SPLIT": [],
	"TSUN": ["16", "18", "20"],
	"HOLLOW": [],
	"AWAKE": ["26"],
	"ANCHOR": ["22"],
}

var _resolver: Node


func before_test() -> void:
	_resolver = load("res://autoload/SpriteResolver.gd").new()
	_resolver.reload()


func after_test() -> void:
	_resolver.free()
	if FileAccess.file_exists(MOCK_PATH):
		DirAccess.remove_absolute(MOCK_PATH)


## Acceptance criterion 1: every feeling x intensity x stage 3-5 x path (all six)
## resolves to the casting.json value. The expected cell is derived from the table the
## way docs/03 §3 steps 2-3 read it, so the test fails if the resolver invents a rule
## the data does not have: break / relapse flags first, then HOLLOW's drift, then
## ANCHOR's pre-fracture column, then the docs/03 §3.2 overrides, else the base cell.
func test_table_stages_3_to_5_all_six_paths() -> void:
	var cells := 0
	var wrong: Array[String] = []
	for path: String in DOC_POOLS:
		for feeling: String in _resolver.casting["feelings"]:
			for intensity: int in [1, 2, 3]:
				for stage: int in [3, 4, 5]:
					cells += 1
					var want := _expected(feeling, intensity, stage, path, {})
					var got: String = _resolver.resolve(feeling, intensity, stage, path)
					if got != want:
						wrong.append(
							(
								"%s %s i%d st%d -> %s (want %s)"
								% [path, feeling, intensity, stage, got, want]
							)
						)
	assert_int(cells).is_equal(1188)
	assert_array(wrong).is_empty()


## The same 1188 cells with both beat flags set: TSUN turns afraid/crying into the
## scared child, ANCHOR relapses on every feeling (26 distress / 22 elation, 21 crisis
## at T3 i3), and nothing else moves.
func test_table_stages_3_to_5_with_break_and_relapse_flags() -> void:
	var flags := {"tsun_break": true, "anchor_relapse": true}
	var cells := 0
	var wrong: Array[String] = []
	for path: String in DOC_POOLS:
		for feeling: String in _resolver.casting["feelings"]:
			for intensity: int in [1, 2, 3]:
				for stage: int in [3, 4, 5]:
					cells += 1
					var want := _expected(feeling, intensity, stage, path, flags)
					var got: String = _resolver.resolve(feeling, intensity, stage, path, flags)
					if got != want:
						wrong.append(
							(
								"%s %s i%d st%d -> %s (want %s)"
								% [path, feeling, intensity, stage, got, want]
							)
						)
	assert_int(cells).is_equal(1188)
	assert_array(wrong).is_empty()


## Acceptance criterion 2: every path's docs/01 §4 pool is the doc's own list (in doc
## order), every pool face is exported art, and every face a path's rules can select
## is either a pool face or one of the docs/03 §3.2 extras listed above.
func test_path_pools_match_docs_01() -> void:
	var casting: Dictionary = _resolver.casting
	assert_array(casting["paths"].keys()).contains_exactly(DOC_POOLS.keys())
	for path: String in DOC_POOLS:
		var spec: Dictionary = casting["paths"][path]
		assert_array(spec["pool"]).is_equal(DOC_POOLS[path]).append_failure_message(
			path + " pool is not the docs/01 §4 list"
		)
		assert_array(spec["docs_03_extras"]).is_equal(DOC03_EXTRAS[path]).append_failure_message(
			path + " docs/03 extras drifted"
		)
		var allowed: Array = spec["pool"] + spec["docs_03_extras"]
		for sprite_id: String in _rule_faces(spec):
			assert_array(allowed).contains(sprite_id).append_failure_message(
				(
					"%s rule names %s, which is neither in its pool nor a docs/03 extra"
					% [path, sprite_id]
				)
			)
		for sprite_id: String in spec["pool"]:
			(
				assert_str(_resolver.sprite_texture_path(sprite_id))
				. is_not_empty()
				. append_failure_message(path + " pool face " + sprite_id + " is not exported")
			)


## docs/01 §4.2 "01 <-> 17 rapid swaps" + docs/03 §3.2 "forces alternation when beats
## flip valence": at T3 a positive joy beat is normally the corrupt 22, but after a
## negative beat it snaps to the idealize face and back.
func test_split_whiplash_alternates_on_valence_flips() -> void:
	assert_str(_resolver.resolve("joy", 1, 4, "SPLIT")).is_equal("22")
	_resolver.reset_scene()
	var first: Dictionary = _resolver.resolve_beat("joy", 1, 4, "SPLIT")
	assert_str(String(first["sprite"])).is_equal("22")
	assert_str(String(first["path_rule"])).is_empty()
	var flip_to_hate: Dictionary = _resolver.resolve_beat("angry", 1, 4, "SPLIT")
	assert_str(String(flip_to_hate["sprite"])).is_equal("17")
	assert_str(String(flip_to_hate["path_rule"])).is_equal("whiplash")
	var flip_to_love: Dictionary = _resolver.resolve_beat("joy", 1, 4, "SPLIT")
	assert_str(String(flip_to_love["sprite"])).is_equal("01")
	assert_str(String(flip_to_love["path_rule"])).is_equal("whiplash")
	# another flip turns the face over again (sad is negative after the positive beat)
	var hate_again: Dictionary = _resolver.resolve_beat("sad", 1, 4, "SPLIT")
	assert_str(String(hate_again["sprite"])).is_equal("17")
	assert_str(String(hate_again["path_rule"])).is_equal("whiplash")
	# same polarity = no flip: the feeling keeps its own base face (bored T3 -> 23)
	var held: Dictionary = _resolver.resolve_beat("bored", 1, 4, "SPLIT")
	assert_str(String(held["sprite"])).is_equal("23")
	assert_str(String(held["path_rule"])).is_empty()
	assert_bool(bool(held["anti_repeated"])).is_false()
	# crying/pleading keep their documented face even on a flip (override wins)
	_resolver.reset_scene()
	_resolver.resolve_beat("joy", 1, 4, "SPLIT")
	var cry: Dictionary = _resolver.resolve_beat("crying", 1, 4, "SPLIT")
	assert_str(String(cry["sprite"])).is_equal("16")
	assert_str(String(cry["path_rule"])).is_equal("override")
	assert_str(String(_resolver.resolve_beat("pleading", 1, 4, "SPLIT")["sprite"])).is_equal("19")


## docs/03 §3.2 TSUN-BREAK: "at 'break' moments afraid -> 20, crying -> 16". At T3 the
## pale face is 26 (the corruption), so the break flag is what pulls the scared child
## back; below the path's tiers the rule is inert.
func test_tsun_break_flag_cracks_the_act() -> void:
	assert_str(_resolver.resolve("afraid", 1, 5, "TSUN")).is_equal("26")
	assert_str(_resolver.resolve("afraid", 1, 5, "TSUN", BREAK_FLAGS)).is_equal("20")
	assert_str(_resolver.resolve("crying", 1, 5, "TSUN", BREAK_FLAGS)).is_equal("16")
	var broken: Dictionary = _resolver.resolve_beat("afraid", 1, 5, "TSUN", BREAK_FLAGS)
	assert_str(String(broken["sprite"])).is_equal("20")
	assert_str(String(broken["path_rule"])).is_equal("break")
	assert_str(String(broken["on_enter_events"]["cue"])).is_equal("heartbeat_fast")
	# the act itself is untouched: angry keeps its TSUN override
	var angry: Dictionary = _resolver.resolve_beat("angry", 1, 5, "TSUN", BREAK_FLAGS)
	assert_str(String(angry["sprite"])).is_equal("17")
	assert_str(String(angry["path_rule"])).is_equal("override")
	# inert at T2 and below (paths list T2-T3 only)
	assert_str(_resolver.resolve("afraid", 1, 3, "TSUN", BREAK_FLAGS)).is_equal("20")
	assert_str(_resolver.resolve("afraid", 1, 2, "TSUN", BREAK_FLAGS)).is_equal("20")
	(
		assert_str(String(_resolver.resolve_beat("afraid", 1, 2, "TSUN", BREAK_FLAGS)["path_rule"]))
		. is_empty()
	)


## docs/03 §3.2 HOLLOW: "sprite changes only on intensity 3" — the face stops
## responding. i1/i2 beats hold the last face with the docs/03 §4 `freeze` preset, no
## budget spend, no entry events and no anti-repeat swap (which would itself be a
## change); an i3 beat drifts.
func test_hollow_freezes_the_face_until_intensity_3() -> void:
	_resolver.reset_scene()
	var entered: Array = []
	var sink := func(events: Dictionary) -> void: entered.append(String(events["sprite"]))
	_resolver.sprite_entered.connect(sink)
	var open: Dictionary = _resolver.resolve_beat("joy", 3, 4, "HOLLOW")
	assert_str(String(open["sprite"])).is_equal("23")
	assert_str(String(open["path_rule"])).is_equal("drift")
	assert_str(String(open["motion"])).is_equal("freeze")  # 23's own on_enter preset
	var hold_i1: Dictionary = _resolver.resolve_beat("angry", 1, 4, "HOLLOW")
	assert_str(String(hold_i1["sprite"])).is_equal("23")
	assert_str(String(hold_i1["path_rule"])).is_equal("freeze")
	var hold_i2: Dictionary = _resolver.resolve_beat("sad", 2, 4, "HOLLOW")
	assert_str(String(hold_i2["sprite"])).is_equal("23")
	assert_str(String(hold_i2["path_rule"])).is_equal("freeze")
	# docs/03 §4: a held beat carries `freeze`, never the held face's own on_enter
	# motion or the current feeling's (angry -> shake, sad -> sink) — DES-3
	assert_str(String(hold_i1["motion"])).is_equal("freeze")
	assert_str(String(hold_i2["motion"])).is_equal("freeze")
	assert_float(float(hold_i1["motion_scale"])).is_equal_approx(1.0, 0.001)
	# an i3 beat is allowed to move: sad drifts to its own numb face, with its preset
	var drift: Dictionary = _resolver.resolve_beat("sad", 3, 4, "HOLLOW")
	assert_str(String(drift["sprite"])).is_equal("14")
	assert_str(String(drift["path_rule"])).is_equal("drift")
	assert_str(String(drift["motion"])).is_equal("sink")
	# three identical held beats must not anti-repeat into a sibling
	for i: int in range(3):
		var held: Dictionary = _resolver.resolve_beat("angry", 1, 4, "HOLLOW")
		assert_str(String(held["sprite"])).is_equal("14")
		assert_str(String(held["motion"])).is_equal("freeze")
		assert_bool(bool(held["anti_repeated"])).is_false()
	assert_array(entered).is_equal(["23", "14"])
	_resolver.sprite_entered.disconnect(sink)
	# every drift face is a docs/01 §4.4 signature; 25 reaches the screen from the T3
	# base cell, never from an entry that could not change a face (DES-2)
	var drift_faces: Array = []
	for value: Variant in _resolver.casting["paths"]["HOLLOW"]["drift"].values():
		if not drift_faces.has(String(value)):
			drift_faces.append(String(value))
	for face: String in drift_faces:
		assert_array(DOC_POOLS["HOLLOW"]).contains(face)
	assert_array(drift_faces).contains_exactly_in_any_order(["23", "14", "12", "10"])
	# and every face HOLLOW can show is one of those signatures: the dropped `cold: 25`
	# entry used to leave the healthy 07 on screen at T2, outside docs/01 §4.4 (DES-2)
	for feeling: String in _resolver.casting["feelings"]:
		for intensity: int in [1, 2, 3]:
			for stage: int in [3, 4, 5]:
				assert_array(DOC_POOLS["HOLLOW"]).contains(
					_resolver.resolve(feeling, intensity, stage, "HOLLOW")
				)


## DES-2: a drift entry that maps a feeling onto the face it already resolves to is
## dead data — it cannot change a face, yet docs/10 would print it as a live rule. Every
## entry must beat the base cell at a tier the drift face may appear at (25 is T3-only
## and cold's T3 base cell is already 25, which is why `cold` has no entry).
func test_hollow_drift_entries_are_all_reachable() -> void:
	var casting: Dictionary = _resolver.casting
	var drift: Dictionary = casting["paths"]["HOLLOW"]["drift"]
	for feeling: String in drift:
		if feeling == "default":
			continue  # the fallback, pinned by the table's other feelings
		var drift_face := String(drift[feeling])
		var reachable := false
		for tier: String in casting["paths"]["HOLLOW"]["tiers"]:
			for col: int in [1, 2, 3]:
				var base := String(casting["feelings"][feeling]["tiers"][tier]["sprite"][str(col)])
				if base != drift_face and _above_min_tier(casting, drift_face, tier):
					reachable = true
		assert_bool(reachable).is_true().append_failure_message(
			"HOLLOW drift %s -> %s can never change a face" % [feeling, drift_face]
		)


## docs/03 §3.2 ANCHOR: "keeps healthy sprites; relapse beats use 26/22 for one beat,
## then 02". No ANCHOR cell at T2-T3 shows a corrupt face.
func test_anchor_keeps_healthy_sprites() -> void:
	var corrupt: Array[String] = []
	for feeling: String in _resolver.casting["feelings"]:
		for intensity: int in [1, 2, 3]:
			for stage: int in [3, 4, 5]:
				var got: String = _resolver.resolve(feeling, intensity, stage, "ANCHOR")
				if int(got) >= 21:
					corrupt.append("%s i%d st%d -> %s" % [feeling, intensity, stage, got])
	assert_array(corrupt).is_empty()
	assert_str(_resolver.resolve("joy", 3, 4, "ANCHOR")).is_equal("01")
	assert_str(_resolver.resolve("love", 1, 5, "ANCHOR")).is_equal("06")
	assert_str(_resolver.resolve("sad", 1, 5, "ANCHOR")).is_equal("14")
	assert_str(String(_resolver.resolve_beat("joy", 1, 4, "ANCHOR")["path_rule"])).is_equal(
		"healthy"
	)


## docs/03 §3.2 ANCHOR relapse: one spike beat (26 for a negative beat, 22 for a
## positive one, the knife 21 at T3 i3 on a distress beat per docs/01 §4.6), then
## exactly one 02 recovery beat, then her healthy faces again. The knife still obeys
## its once-per-scene budget.
func test_anchor_relapse_then_recovery() -> void:
	_resolver.reset_scene()
	assert_str(String(_resolver.resolve_beat("sad", 1, 4, "ANCHOR")["sprite"])).is_equal("14")
	var distress: Dictionary = _resolver.resolve_beat("sad", 1, 4, "ANCHOR", RELAPSE_FLAGS)
	assert_str(String(distress["sprite"])).is_equal("26")
	assert_str(String(distress["path_rule"])).is_equal("relapse")
	var recovery: Dictionary = _resolver.resolve_beat("joy", 1, 4, "ANCHOR")
	assert_str(String(recovery["sprite"])).is_equal("02")
	assert_str(String(recovery["path_rule"])).is_equal("recovery")
	assert_str(String(_resolver.resolve_beat("joy", 1, 4, "ANCHOR")["sprite"])).is_equal("01")
	# a positive relapse is the docs/03 §3.2 elation spike
	var elation: Dictionary = _resolver.resolve_beat("joy", 1, 4, "ANCHOR", RELAPSE_FLAGS)
	assert_str(String(elation["sprite"])).is_equal("22")
	_resolver.reset_scene()
	var crisis: Dictionary = _resolver.resolve_beat("angry", 3, 5, "ANCHOR", RELAPSE_FLAGS)
	assert_str(String(crisis["sprite"])).is_equal("21")
	assert_str(String(crisis["on_enter_events"]["cue"])).is_equal("knife_draw")
	assert_str(String(_resolver.resolve_beat("angry", 1, 5, "ANCHOR")["sprite"])).is_equal("02")
	# the second crisis in the same scene is withheld by the reveal budget: no spike,
	# no recovery beat, and the budget names what it spent
	var spent: Dictionary = _resolver.resolve_beat("angry", 3, 5, "ANCHOR", RELAPSE_FLAGS)
	assert_str(String(spent["sprite"])).is_equal("17")
	assert_str(String(spent["budget_spent"])).is_equal("21")
	assert_str(String(_resolver.resolve_beat("joy", 1, 5, "ANCHOR")["sprite"])).is_equal("01")


## DES-1: docs/03 §1 gives 21 valence -3 and docs/03 §3.2 pairs a relapse with 26/22,
## so the knife is the *distress* spike. A positive beat at the crisis tier/intensity
## keeps its elation 22 and leaves the once-per-scene knife budget for the real crisis
## that follows the recovery beat.
func test_anchor_crisis_is_distress_only() -> void:
	_resolver.reset_scene()
	var elated: Dictionary = _resolver.resolve_beat("joy", 3, 5, "ANCHOR", RELAPSE_FLAGS)
	assert_str(String(elated["sprite"])).is_equal("22")
	assert_str(String(elated["path_rule"])).is_equal("relapse")
	assert_str(String(elated.get("budget_spent", ""))).is_empty()
	# the pure table agrees for every non-negative feeling at the crisis cell
	assert_str(_resolver.resolve("joy", 3, 4, "ANCHOR", RELAPSE_FLAGS)).is_equal("22")
	assert_str(_resolver.resolve("warmth", 3, 4, "ANCHOR", RELAPSE_FLAGS)).is_equal("22")
	assert_str(_resolver.resolve("sad", 3, 5, "ANCHOR", RELAPSE_FLAGS)).is_equal("21")
	# the elation spike still costs its one recovery beat ...
	(
		assert_str(String(_resolver.resolve_beat("angry", 3, 5, "ANCHOR", RELAPSE_FLAGS)["sprite"]))
		. is_equal("02")
	)
	# ... and the knife is still there for the distress beat that follows it
	var crisis: Dictionary = _resolver.resolve_beat("angry", 3, 5, "ANCHOR", RELAPSE_FLAGS)
	assert_str(String(crisis["sprite"])).is_equal("21")
	assert_str(String(crisis.get("budget_spent", ""))).is_empty()


## Every path row is inert below its tiers (docs/03 §3 step 2): stages 0-2 resolve
## exactly like the path-less table and no beat rule fires.
func test_path_rules_are_inert_below_their_tiers() -> void:
	for path: String in DOC_POOLS:
		for feeling: String in _resolver.casting["feelings"]:
			for intensity: int in [1, 2, 3]:
				for stage: int in [0, 1, 2]:
					var want: String = _resolver.resolve(feeling, intensity, stage)
					var got: String = _resolver.resolve(feeling, intensity, stage, path)
					assert_str(got).is_equal(want).append_failure_message(
						"%s %s i%d st%d" % [path, feeling, intensity, stage]
					)
		var packet: Dictionary = _resolver.resolve_beat("afraid", 1, 2, path, BREAK_FLAGS)
		assert_str(String(packet["path_rule"])).is_empty()


## A hand-written casting table proves every P3.06 rule reads its path data instead of
## shipped ids: the swap pair, the freeze intensity, the healthy column, the relapse
## spike and the recovery face all come out of the mock.
func test_mock_casting_table_drives_every_path_rule() -> void:
	_write_mock_casting()
	_resolver.reload(MOCK_PATH)
	# SPLIT-style whiplash: base 17, flip down -> 11, flip up -> 10
	_resolver.reset_scene()
	assert_str(_resolver.resolve("up", 1, 4, "SWAP")).is_equal("17")
	assert_str(String(_resolver.resolve_beat("up", 1, 4, "SWAP")["sprite"])).is_equal("17")
	var down: Dictionary = _resolver.resolve_beat("down", 1, 4, "SWAP")
	assert_str(String(down["sprite"])).is_equal("11")
	assert_str(String(down["path_rule"])).is_equal("whiplash")
	assert_str(String(_resolver.resolve_beat("up", 1, 4, "SWAP")["sprite"])).is_equal("10")
	# HOLLOW-style freeze: i3 drifts, i1/i2 hold
	_resolver.reset_scene()
	assert_str(String(_resolver.resolve_beat("up", 3, 4, "FREEZE")["sprite"])).is_equal("12")
	var held: Dictionary = _resolver.resolve_beat("down", 1, 4, "FREEZE")
	assert_str(String(held["sprite"])).is_equal("12")
	assert_str(String(held["path_rule"])).is_equal("freeze")
	# ANCHOR-style healthy column + relapse + recovery
	_resolver.reset_scene()
	assert_str(_resolver.resolve("down", 1, 4, "HEAL")).is_equal("11")
	var spike: Dictionary = _resolver.resolve_beat("down", 1, 4, "HEAL", {"r": true})
	assert_str(String(spike["sprite"])).is_equal("13")
	assert_str(String(spike["path_rule"])).is_equal("relapse")
	var heal: Dictionary = _resolver.resolve_beat("up", 1, 4, "HEAL")
	assert_str(String(heal["sprite"])).is_equal("16")
	assert_str(String(heal["path_rule"])).is_equal("recovery")


## The expected cell for one path, derived from casting.json the way docs/03 §3 steps
## 2-3 read it: beat rules first (break, relapse, drift), then the path record, then
## the sprite's tier gate, else the base cell (from the healthy column when the path
## keeps healthy sprites).
##
## The gate is the sprite's *minimum* tier only (P2.14 DCR-1: docs/03 §1's upper bound
## is descriptive, so a path face documented for T0-T2 may still appear at T3), which is
## why TSUN playful keeps 03 at stage 4-5 instead of falling to the corrupt 25.
func _expected(
	feeling: String, intensity: int, stage: int, path: String, flags: Dictionary
) -> String:
	var casting: Dictionary = _resolver.casting
	var tier: String = _resolver.tier_for_stage(stage)
	var spec: Dictionary = casting["paths"].get(path, {})
	if spec.is_empty() or not tier in spec.get("tiers", []):
		return _base_cell(casting, feeling, intensity, tier)
	var candidate := _special_face(casting, feeling, intensity, tier, spec, flags)
	if candidate.is_empty():
		candidate = _override_face(spec, feeling, flags)
	if not candidate.is_empty() and _above_min_tier(casting, candidate, tier):
		return candidate
	var base_tier := String(spec.get("healthy_tier", tier))
	return _base_cell(casting, feeling, intensity, base_tier)


## docs/03 §3 step 3 as P2.14's DCR-1 reads it: sprite.min_tier <= tier.
func _above_min_tier(casting: Dictionary, sprite_id: String, tier: String) -> bool:
	var tiers: Array = casting["sprites"][sprite_id]["tiers"]
	var order: Array = ["T0", "T1", "T2", "T3"]
	return order.find(String(tiers[0])) <= order.find(tier)


func _base_cell(casting: Dictionary, feeling: String, intensity: int, tier: String) -> String:
	var col := str(clampi(intensity, 1, 3))
	return String(casting["feelings"][feeling]["tiers"][tier]["sprite"][col])


func _special_face(
	casting: Dictionary,
	feeling: String,
	intensity: int,
	tier: String,
	spec: Dictionary,
	flags: Dictionary
) -> String:
	var brk: Dictionary = spec.get("break", {})
	if not brk.is_empty() and bool(flags.get(String(brk.get("flag", "")), false)):
		var broken := String(brk.get("sprite", {}).get(feeling, ""))
		if not broken.is_empty():
			return broken
	var relapse: Dictionary = spec.get("relapse", {})
	if not relapse.is_empty() and bool(flags.get(String(relapse.get("flag", "")), false)):
		var valence := int(casting["feelings"][feeling]["valence"])
		var crisis: Dictionary = relapse.get("crisis", {})
		if (
			valence < 0
			and tier == String(crisis.get("tier", ""))
			and intensity >= int(crisis.get("intensity", 0))
		):
			return String(crisis.get("sprite", ""))
		var spike: Dictionary = relapse.get("spike", {})
		return String(spike.get("elation" if valence >= 0 else "distress", ""))
	var drift: Dictionary = spec.get("drift", {})
	if not drift.is_empty():
		return String(drift.get(feeling, drift.get("default", "")))
	return ""


func _override_face(spec: Dictionary, feeling: String, flags: Dictionary) -> String:
	var flagged: Dictionary = spec.get("flagged", {})
	if flagged.has(feeling):
		var pair: Array = flagged[feeling]
		if bool(flags.get(String(pair[1]), false)):
			return String(pair[0])
	return String(spec.get("override", {}).get(feeling, ""))


## Every sprite id a path's rule tables can name (docs/01 §4 pool + docs/03 §3.2).
func _rule_faces(spec: Dictionary) -> Array[String]:
	var faces: Array[String] = []
	for sprite_id: Variant in spec.get("pool", []):
		faces.append(String(sprite_id))
	for sprite_id: Variant in spec.get("override", {}).values():
		faces.append(String(sprite_id))
	for pair: Variant in spec.get("flagged", {}).values():
		faces.append(String((pair as Array)[0]))
	for sprite_id: Variant in spec.get("break", {}).get("sprite", {}).values():
		faces.append(String(sprite_id))
	for key: String in ["idealize", "devalue"]:
		if spec.has(key):
			faces.append(String(spec[key]))
	for sprite_id: Variant in spec.get("drift", {}).values():
		faces.append(String(sprite_id))
	var relapse: Dictionary = spec.get("relapse", {})
	for sprite_id: Variant in relapse.get("spike", {}).values():
		faces.append(String(sprite_id))
	if relapse.get("crisis", {}).has("sprite"):
		faces.append(String(relapse["crisis"]["sprite"]))
	if relapse.has("then"):
		faces.append(String(relapse["then"]))
	return faces


## A three-path casting table small enough to read: a swap pair, a freeze path, and a
## healthy/relapse path, each laid out exactly like the shipped data.
func _write_mock_casting() -> void:
	var mock := {
		"tiers": {"T0": [0, 1], "T1": [2, 2], "T2": [3, 3], "T3": [4, 5]},
		"motion_intensity": {"1": 1.0, "2": 1.0, "3": 1.0},
		"fallback": {"T0": "00", "T1": "00", "T2": "00", "T3": "00"},
		"siblings": {},
		"siblings_corrupt": {},
		"paths":
		{
			"SWAP":
			{"pool": ["10", "11"], "tiers": ["T2", "T3"], "idealize": "10", "devalue": "11"},
			"FREEZE":
			{
				"pool": ["12"],
				"tiers": ["T2", "T3"],
				"change_intensity": 3,
				"drift": {"default": "12"},
			},
			"HEAL":
			{
				"pool": ["13", "14", "15", "16"],
				"tiers": ["T2", "T3"],
				"healthy_tier": "T0",
				"relapse":
				{
					"flag": "r",
					"spike": {"distress": "13", "elation": "14"},
					"crisis": {"sprite": "15", "tier": "T3", "intensity": 3},
					"then": "16",
				},
			},
		},
		"feelings":
		{
			"up":
			{
				"valence": 1,
				"tiers":
				{
					"T0": {"sprite": {"1": "10", "2": "10", "3": "10"}},
					"T1": {"sprite": {"1": "10", "2": "10", "3": "10"}},
					"T2": {"sprite": {"1": "17", "2": "17", "3": "17"}},
					"T3": {"sprite": {"1": "17", "2": "17", "3": "17"}},
				},
			},
			"down":
			{
				"valence": -1,
				"tiers":
				{
					"T0": {"sprite": {"1": "11", "2": "11", "3": "11"}},
					"T1": {"sprite": {"1": "11", "2": "11", "3": "11"}},
					"T2": {"sprite": {"1": "18", "2": "18", "3": "18"}},
					"T3": {"sprite": {"1": "18", "2": "18", "3": "18"}},
				},
			},
		},
		"sprites":
		{
			"00": {"tiers": ["T0", "T1", "T2", "T3"], "on_enter": {}},
			"10": {"tiers": ["T0", "T1", "T2", "T3"], "on_enter": {}},
			"11": {"tiers": ["T0", "T1", "T2", "T3"], "on_enter": {}},
			"12": {"tiers": ["T2", "T3"], "on_enter": {}},
			"13": {"tiers": ["T2", "T3"], "on_enter": {}},
			"14": {"tiers": ["T2", "T3"], "on_enter": {}},
			"15": {"tiers": ["T3"], "on_enter": {}},
			"16": {"tiers": ["T2", "T3"], "on_enter": {}},
			"17": {"tiers": ["T2", "T3"], "on_enter": {}},
			"18": {"tiers": ["T2", "T3"], "on_enter": {}},
		},
	}
	var file := FileAccess.open(MOCK_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(mock, "\t"))
	file.close()
