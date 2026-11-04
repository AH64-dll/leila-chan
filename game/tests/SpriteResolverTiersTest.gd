extends GdUnitTestSuite
## P2.14 — SpriteResolver T2-T3 (docs/03 §3.1-§3.2, docs/10 §3-§4).
## The base table's stage 3-5 rows, the YANDERE/AWAKE path overrides, the scene-scoped
## reveal budget, the corrupt-band siblings and the on-enter effects, plus a mock
## casting table loaded from user:// that proves every rule comes from data.
## The T0-T1 suite stays in SpriteResolverTest.gd.

const MOCK_PATH := "user://sprite_resolver_mock_casting.json"

var _resolver: Node


func before_test() -> void:
	_resolver = load("res://autoload/SpriteResolver.gd").new()
	_resolver.reload()


func after_test() -> void:
	_resolver.free()
	if FileAccess.file_exists(MOCK_PATH):
		DirAccess.remove_absolute(MOCK_PATH)


## Acceptance criterion 1: every feeling x intensity x stage 3-5 x {none, YANDERE,
## AWAKE} resolves to the casting.json value. The expected cell is derived from the
## table the way docs/03 §3 step 2/3 reads it — path override (or flagged row, when
## its flag is set) if the sprite's documented tiers reach this tier, else the base
## cell — so the test fails if the resolver invents a rule the data does not have.
func test_table_stages_3_to_5_all_paths() -> void:
	var cells := 0
	var wrong: Array[String] = []
	for feeling: String in _resolver.casting["feelings"]:
		for intensity: int in [1, 2, 3]:
			for stage: int in [3, 4, 5]:
				for path: String in ["", "YANDERE", "AWAKE"]:
					cells += 1
					var want := _expected(feeling, intensity, stage, path, {})
					var got: String = _resolver.resolve(feeling, intensity, stage, path)
					if got != want:
						wrong.append(
							(
								"%s i%d st%d %s -> %s (want %s)"
								% [feeling, intensity, stage, _path_name(path), got, want]
							)
						)
	assert_int(cells).is_equal(594)
	assert_array(wrong).is_empty()


## The same 594 cells with the YANDERE flag set: only warmth changes, and only at T3 —
## 27's documented tiers are T3, so the flag can never force the bloodstained face
## into stage 3 (docs/03 §1).
func test_table_with_rival_gone_flag() -> void:
	var flags := {"rival_gone": true}
	var cells := 0
	var wrong: Array[String] = []
	for feeling: String in _resolver.casting["feelings"]:
		for intensity: int in [1, 2, 3]:
			for stage: int in [3, 4, 5]:
				for path: String in ["", "YANDERE", "AWAKE"]:
					cells += 1
					var want := _expected(feeling, intensity, stage, path, flags)
					var got: String = _resolver.resolve(feeling, intensity, stage, path, flags)
					if got != want:
						wrong.append(
							(
								"%s i%d st%d %s -> %s (want %s)"
								% [feeling, intensity, stage, _path_name(path), got, want]
							)
						)
	assert_int(cells).is_equal(594)
	assert_array(wrong).is_empty()
	assert_str(_resolver.resolve("warmth", 1, 3, "YANDERE", flags)).is_equal("02")
	assert_str(_resolver.resolve("warmth", 1, 4, "YANDERE", flags)).is_equal("27")


## docs/03 §1 says 21 (the knife), 25 (shadowed) and 29 (glitch) are T3-only. A T2
## path override that names one of them falls through to the feeling's own T2 face
## instead of the fallback face — the beat still has to look like her.
func test_t3_only_faces_wait_for_t3() -> void:
	assert_str(_resolver.resolve("angry", 1, 3, "YANDERE")).is_equal("17")
	assert_str(_resolver.resolve("angry", 1, 4, "YANDERE")).is_equal("21")
	assert_str(_resolver.resolve("angry", 3, 5, "YANDERE")).is_equal("21")
	assert_str(_resolver.resolve("cold", 1, 3, "AWAKE")).is_equal("07")
	assert_str(_resolver.resolve("cold", 1, 4, "AWAKE")).is_equal("25")
	assert_str(_resolver.resolve("confused", 1, 3, "AWAKE")).is_equal("08")
	assert_str(_resolver.resolve("confused", 1, 4, "AWAKE")).is_equal("29")
	# T2-T3 faces are allowed at stage 3, so the path still reads at T2
	assert_str(_resolver.resolve("suspicious", 1, 3, "YANDERE")).is_equal("28")
	assert_str(_resolver.resolve("surprised", 1, 3, "AWAKE")).is_equal("26")
	assert_str(_resolver.resolve("love", 1, 3, "YANDERE")).is_equal("24")


## docs/03 §1 "Reveal budget: 1 per scene" / docs/10 §3 budget on sprite 21: the
## second YANDERE anger in one scene shows her own angry face, and reset_scene()
## hands the knife back.
func test_reveal_budget_is_one_per_scene() -> void:
	var first: Dictionary = _resolver.resolve_beat("angry", 1, 4, "YANDERE")
	assert_str(String(first["sprite"])).is_equal("21")
	assert_str(String(first["on_enter_events"]["cue"])).is_equal("knife_draw")
	assert_bool(first.has("budget_spent")).is_false()
	var second: Dictionary = _resolver.resolve_beat("angry", 1, 4, "YANDERE")
	assert_str(String(second["sprite"])).is_equal("17")
	assert_str(String(second["budget_spent"])).is_equal("21")
	assert_str(String(second["on_enter_events"]["cue"])).is_empty()
	_resolver.reset_scene()
	var third: Dictionary = _resolver.resolve_beat("angry", 1, 4, "YANDERE")
	assert_str(String(third["sprite"])).is_equal("21")


## docs/03 §3 step 4 + docs/10 §3.2: a corrupt face repeating swaps inside the
## corruption band (24 -> 28), never to a healthy sibling.
func test_corrupt_siblings_swap_within_the_band() -> void:
	var first: Dictionary = _resolver.resolve_beat("love", 1, 4, "YANDERE")
	var second: Dictionary = _resolver.resolve_beat("love", 1, 4, "YANDERE")
	var third: Dictionary = _resolver.resolve_beat("love", 1, 4, "YANDERE")
	assert_str(String(first["sprite"])).is_equal("24")
	assert_str(String(second["sprite"])).is_equal("24")
	assert_str(String(third["sprite"])).is_equal("28")
	assert_bool(bool(third["anti_repeated"])).is_true()
	assert_int(int(String(third["sprite"]))).is_greater_equal(21)
	# the pair is data, not a code list
	assert_str(String(_resolver.casting["siblings_corrupt"]["24"])).is_equal("28")
	# and every corrupt sibling stays in the band with a distinct face
	for sprite_id: String in _resolver.casting["siblings_corrupt"]:
		var sibling := String(_resolver.casting["siblings_corrupt"][sprite_id])
		assert_str(sibling).is_not_equal(sprite_id)
		assert_int(int(sibling)).is_greater_equal(21)


## Acceptance criterion 2 (resolver half): the packet carries the docs/10 §3 entry
## effects, resolved for the stage — below-stage variants and the terminal-climax
## budget included.
func test_on_enter_events_follow_docs_10_3() -> void:
	_assert_enter("surprised", 1, 3, "", {}, "11", {"system": ["stinger.soft"]})
	_assert_enter("crying", 1, 3, "", {}, "16", {"cue": "sob"})
	_assert_enter("afraid", 2, 3, "", {}, "20", {"cue": "heartbeat_fast", "motion": "tremble"})
	# 22 relaxes its laugh below stage 4 (docs/10 §3 cue_below_stage4)
	_assert_enter("joy", 3, 3, "", {}, "22", {"cue": "laugh_soft", "motion": "shake"})
	_assert_enter("joy", 1, 4, "YANDERE", {}, "22", {"cue": "laugh_unhinged"})
	_assert_enter("empty", 1, 3, "", {}, "23", {"system": ["weird"], "music": "silence"})
	_assert_enter("love", 1, 3, "", {}, "24", {"cue": "heartbeat", "fx": "hearts"})
	_assert_enter(
		"warmth",
		1,
		4,
		"YANDERE",
		{"rival_gone": true},
		"27",
		{"cue": "music_box_note", "music": "music_box"}
	)
	_assert_enter("suspicious", 1, 4, "YANDERE", {}, "28", {"cue": "clock_tick"})
	_assert_enter(
		"confused",
		1,
		4,
		"AWAKE",
		{},
		"29",
		{"cue": "static", "system": ["glitch", "distort_layer"], "fx": "glitch"}
	)
	_assert_enter("surprised", 1, 4, "AWAKE", {}, "26", {"system": ["glitch"], "motion": "twitch"})
	_assert_enter("cold", 1, 4, "AWAKE", {}, "25", {"system": ["stinger.soft"], "fx": "darken"})
	# 30's stage_change sting is the terminal climax: below stage 5 the system
	# sting is withheld and the fx degrades to the vignette (docs/10 §3)
	_assert_enter(
		"angry",
		3,
		4,
		"",
		{},
		"30",
		{"cue": "heartbeat_fast", "system": [], "fx": "vignette_red", "music": "dread"},
		["system:terminal_climax"]
	)
	_assert_enter(
		"angry",
		3,
		5,
		"",
		{},
		"30",
		{"system": ["stinger.stage_change"], "fx": "her_eyes", "motion": "lean_in"}
	)


## The resolver announces a face change exactly once: the Director must never fire
## the same entry cue twice for one sprite.
func test_sprite_entered_fires_only_on_change() -> void:
	var fired: Array = []
	var sink := func(events: Dictionary) -> void: fired.append(events)
	_resolver.sprite_entered.connect(sink)
	_resolver.resolve_beat("love", 1, 4, "YANDERE")
	_resolver.resolve_beat("love", 1, 4, "YANDERE")
	assert_int(fired.size()).is_equal(1)
	assert_str(String(fired[0]["sprite"])).is_equal("24")
	assert_str(String(fired[0]["cue"])).is_equal("heartbeat")
	_resolver.resolve_beat("warmth", 1, 4, "YANDERE", {"rival_gone": true})
	assert_int(fired.size()).is_equal(2)
	assert_str(String(fired[1]["sprite"])).is_equal("27")
	assert_str(String(fired[1]["cue"])).is_equal("music_box_note")
	_resolver.sprite_entered.disconnect(sink)


## docs/03 §4 motion amplitude: the packet carries casting.motion_intensity for the
## beat's own intensity, and the preset still comes from the tables.
func test_motion_scale_tracks_intensity() -> void:
	var scales: Array = []
	for intensity: int in [1, 2, 3]:
		_resolver.reset_scene()
		var packet: Dictionary = _resolver.resolve_beat("joy", intensity, 0)
		scales.append(float(packet["motion_scale"]))
		assert_str(String(packet["sprite"])).is_equal("01")
	assert_float(float(scales[0])).is_equal_approx(0.6, 0.001)
	assert_float(float(scales[1])).is_equal_approx(1.0, 0.001)
	assert_float(float(scales[2])).is_equal_approx(1.4, 0.001)
	assert_str(String(_resolver.resolve_beat("joy", 1, 0)["motion"])).is_equal("breathe")


## docs/10 §4 AWAKE rule: "glitch shader on every sprite change". The resolver reports
## the intent in the packet (P2.15 owns the shader); a repeat is not a change, and the
## rule is inert below the path's T2 tiers like every other path row.
func test_awake_glitch_rule_rides_the_packet() -> void:
	var change: Dictionary = _resolver.resolve_beat("love", 1, 4, "AWAKE")
	assert_str(String(change["path"])).is_equal("AWAKE")
	assert_str(String(change["shader"])).is_equal("glitch")
	var repeat: Dictionary = _resolver.resolve_beat("love", 1, 4, "AWAKE")
	assert_str(String(repeat["sprite"])).is_equal(String(change["sprite"]))
	assert_str(String(repeat["shader"])).is_empty()
	assert_str(String(_resolver.resolve_beat("love", 1, 2, "AWAKE")["shader"])).is_empty()
	assert_str(String(_resolver.resolve_beat("love", 1, 4, "YANDERE")["shader"])).is_empty()


## A hand-written table proves the rules are read from data: path tiers, sprite
## tiers, the reveal budget, the motion ladder, the below-stage variants and the
## per-tier fallback all come out of the mock, not out of the shipped cast.
func test_mock_casting_table_drives_every_rule() -> void:
	_write_mock_casting()
	_resolver.reload(MOCK_PATH)
	assert_str(_resolver.resolve("joy", 1, 3, "MOCK")).is_equal("10")
	assert_str(_resolver.resolve("joy", 1, 4, "MOCK")).is_equal("30")
	assert_str(_resolver.resolve("joy", 1, 4, "TERMINAL")).is_equal("32")
	_resolver.reset_scene()
	var first: Dictionary = _resolver.resolve_beat("joy", 3, 4, "MOCK")
	assert_str(String(first["sprite"])).is_equal("30")
	assert_float(float(first["motion_scale"])).is_equal_approx(2.0, 0.001)
	var second: Dictionary = _resolver.resolve_beat("joy", 3, 4, "MOCK")
	assert_str(String(second["sprite"])).is_equal("12")
	assert_str(String(second["budget_spent"])).is_equal("30")
	# below-stage variants and the climax budget, straight from the mock
	_resolver.reset_scene()
	var early: Dictionary = _resolver.resolve_beat("joy", 1, 3, "TERMINAL")
	assert_str(String(early["sprite"])).is_equal("32")
	assert_str(String(early["on_enter_events"]["cue"])).is_equal("laugh_soft")
	assert_str(String(early["on_enter_events"]["fx"])).is_equal("vignette_red")
	assert_array(early["on_enter_events"]["system"]).is_empty()
	assert_array(early["on_enter_events"]["withheld"]).is_equal(["system:terminal_climax"])
	var late: Dictionary = _resolver.resolve_beat("joy", 1, 5, "TERMINAL")
	assert_str(String(late["on_enter_events"]["cue"])).is_equal("laugh_unhinged")
	assert_str(String(late["on_enter_events"]["fx"])).is_equal("her_eyes")
	assert_array(late["on_enter_events"]["system"]).is_equal(["stinger.stage_change"])
	# the mock's own fallback, and a sprite with no declared tiers deriving its own
	assert_str(_resolver.resolve("unknown", 1, 4)).is_equal("99")
	assert_str(_resolver.resolve("joy", 1, 0)).is_equal("10")


## docs/10 §3/§4, read as the resolver reads it: path override (or flagged row when
## the flag is live) only inside the path's tiers and only when the sprite's own
## documented tiers reach them; otherwise the feeling's base cell.
func _expected(
	feeling: String, intensity: int, stage: int, path: String, flags: Dictionary
) -> String:
	var casting: Dictionary = _resolver.casting
	var tier: String = String(_resolver.tier_for_stage(stage))
	var candidate := ""
	var spec: Dictionary = casting["paths"].get(path, {})
	if not spec.is_empty() and tier in spec.get("tiers", []):
		var flagged: Dictionary = spec.get("flagged", {})
		if flagged.has(feeling):
			var pair: Array = flagged[feeling]
			if bool(flags.get(String(pair[1]), false)):
				candidate = String(pair[0])
		else:
			candidate = String(spec.get("override", {}).get(feeling, ""))
	if not candidate.is_empty() and tier in casting["sprites"][candidate]["tiers"]:
		return candidate
	var col := str(clampi(intensity, 1, 3))
	return String(casting["feelings"][feeling]["tiers"][tier]["sprite"][col])


func _path_name(path: String) -> String:
	return path if not path.is_empty() else "none"


func _assert_enter(
	feeling: String,
	intensity: int,
	stage: int,
	path: String,
	flags: Dictionary,
	sprite: String,
	want: Dictionary,
	withheld: Array = []
) -> void:
	_resolver.reset_scene()
	var packet: Dictionary = _resolver.resolve_beat(feeling, intensity, stage, path, flags)
	var where := "%s i%d st%d %s" % [feeling, intensity, stage, _path_name(path)]
	assert_str(String(packet["sprite"])).is_equal(sprite).append_failure_message(where)
	var events: Dictionary = packet["on_enter_events"]
	for key: String in want:
		var got: Variant = events.get(key, "<missing>")
		assert_bool(got == want[key]).is_true().append_failure_message(
			"%s %s = %s (want %s)" % [where, key, str(got), str(want[key])]
		)
	assert_array(events.get("withheld", [])).is_equal(withheld).append_failure_message(where)


## A two-feeling, five-sprite casting table: small enough to read, and it exercises
## every branch the real table exercises (gated override, reveal budget, below-stage
## variants, climax budget, per-tier fallback, undeclared sprite tiers).
func _write_mock_casting() -> void:
	var mock := {
		"tiers": {"T0": [0, 1], "T1": [2, 2], "T2": [3, 3], "T3": [4, 5]},
		"motion_intensity": {"1": 0.5, "2": 1.0, "3": 2.0},
		"fallback": {"T0": "00", "T1": "00", "T2": "00", "T3": "99"},
		"siblings": {"joy": "11"},
		"paths":
		{
			"MOCK": {"tiers": ["T2", "T3"], "override": {"joy": "30"}},
			"TERMINAL": {"tiers": ["T2", "T3"], "override": {"joy": "32"}, "shader": "glitch"},
		},
		"feelings":
		{
			"joy":
			{
				"valence": 3,
				"tint": "#ffffff",
				"motion": {"1": "breathe", "2": "bounce", "3": "bounce"},
				"tiers":
				{
					"T0": {"sprite": {"1": "10", "2": "10", "3": "11"}},
					"T1": {"sprite": {"1": "10", "2": "10", "3": "11"}},
					"T2": {"sprite": {"1": "10", "2": "10", "3": "12"}},
					"T3": {"sprite": {"1": "10", "2": "10", "3": "12"}},
				},
			},
		},
		"sprites":
		{
			"10": {"tiers": ["T0", "T1", "T2", "T3"], "on_enter": {}},
			"11": {"tiers": ["T0", "T1", "T2", "T3"], "on_enter": {}},
			"12": {},
			"30":
			{
				"tiers": ["T3"],
				"on_enter": {"cue": "knife_draw", "budget": "1 reveal per scene"},
			},
			"32":
			{
				"tiers": ["T2", "T3"],
				"on_enter":
				{
					"cue": "laugh_unhinged",
					"cue_below_stage4": "laugh_soft",
					"fx": "her_eyes",
					"fx_below_stage5": "vignette_red",
					"system": ["stinger.stage_change"],
					"budget": "terminal climax only",
				},
			},
			"99": {"tiers": ["T3"], "on_enter": {}},
		},
	}
	var file := FileAccess.open(MOCK_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(mock, "\t"))
	file.close()
