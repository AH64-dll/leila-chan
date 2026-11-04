extends GdUnitTestSuite
## P2.02 — the docs/01 §3 stage machine: the six Instability bands, the
## diegetic crossing event that fires exactly once per crossing, and the
## docs/08 §6 EVENT line she is told in her next prompt.
##
## The boundary table is the doc's, not the code's: every edge (14/15, 29/30,
## 49/50, 69/70, 89/90) is asserted from below and from the edge itself, and the
## data-driven loader is proved by feeding it a synthetic document whose bands
## differ from the shipped ones.

const GameStateScript := preload("res://autoload/GameState.gd")
const StagesScript := preload("res://llm/Stages.gd")
const DATA_PATH := "res://data/stages.json"
const EPS := 0.0001

## docs/01_GAME_DESIGN.md §3, verbatim.
const DOC_BANDS := [0, 15, 30, 50, 70, 90]
const DOC_NAMES := ["Honeymoon", "Hairline Cracks", "Leaks", "Fracture", "Collapse", "Terminal"]
## docs/01 §4 sensitivity rule: her sickness is never named as a disorder.
const FORBIDDEN := [
	"bipolar",
	"borderline",
	"schiz",
	"psychos",
	"psychot",
	"depress",
	"disorder",
	"insane",
	"crazy",
	"ptsd",
	"ocd",
	"bpd",
	"autis",
	"narciss",
]


func _state() -> Variant:
	return auto_free(GameStateScript.new())


func _ints(values: Array) -> Array:
	var out: Array = []
	for value: Variant in values:
		out.append(int(value))
	return out


## A synthetic data document: six bands, six names, one transition block.
func _document(floors: Array, duration: Variant = 2.5) -> Dictionary:
	return {
		"bands": floors,
		"names": ["A", "B", "C", "D", "E", "F"],
		"transition":
		{
			"duration_s": duration,
			"fx": "glitch",
			"cue": "stinger.stage_change",
			"events": {},
		},
	}


func test_bands_come_from_data() -> void:
	# docs/01 §3 in res://data/stages.json, and the loader reads THAT file: the
	# table it returns carries the same bands and names.
	StagesScript.clear_cache()
	assert_array(Array(StagesScript.bands())).is_equal(DOC_BANDS)
	assert_int(StagesScript.max_stage()).is_equal(5)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	assert_bool(parsed is Dictionary).is_true()
	var data: Dictionary = parsed
	assert_array(_ints(data["bands"])).is_equal(DOC_BANDS)
	assert_array(data["names"]).is_equal(DOC_NAMES)
	assert_array(Array(StagesScript.table()["bands"])).is_equal(DOC_BANDS)
	assert_array(StagesScript.table()["names"]).is_equal(DOC_NAMES)


func test_every_boundary_derives_its_stage() -> void:
	# docs/01 §3: 0–14 → 0, 15–29 → 1, 30–49 → 2, 50–69 → 3, 70–89 → 4, 90–100 → 5.
	var cases := [
		[-5.0, 0],
		[0.0, 0],
		[14.0, 0],
		[14.999, 0],
		[15.0, 1],
		[29.0, 1],
		[29.999, 1],
		[30.0, 2],
		[49.0, 2],
		[49.999, 2],
		[50.0, 3],
		[69.0, 3],
		[69.999, 3],
		[70.0, 4],
		[89.0, 4],
		[89.999, 4],
		[90.0, 5],
		[100.0, 5],
		[1000.0, 5],
	]
	for case: Array in cases:
		assert_int(StagesScript.for_instability(case[0])).is_equal(case[1]).append_failure_message(
			"instability %s should be stage %d" % [case[0], case[1]]
		)
	# A value with no band reads as the healthiest one; GameState drops
	# non-finite writes long before it gets here.
	assert_int(StagesScript.for_instability(NAN)).is_zero()


func test_game_state_follows_every_boundary() -> void:
	# The same boundaries through the real state write, one fresh instance per
	# case: the crossing signal fires once, with the whole previous→current pair.
	var cases := [
		[0.0, 0],
		[14.9, 0],
		[15.0, 1],
		[29.9, 1],
		[30.0, 2],
		[49.9, 2],
		[50.0, 3],
		[69.9, 3],
		[70.0, 4],
		[89.9, 4],
		[90.0, 5],
		[100.0, 5],
	]
	for case: Array in cases:
		var s: Variant = _state()
		var changes: Array = []
		s.stage_changed.connect(func(p: int, c: int) -> void: changes.append([p, c]))
		s.set_meter(&"instability", case[0])
		assert_int(s.stage).is_equal(case[1]).append_failure_message("instability %s" % case[0])
		if case[1] > 0:
			assert_array(changes).is_equal([[0, case[1]]])
		else:
			assert_array(changes).is_empty()


func test_crossing_emits_one_transition() -> void:
	# docs/01 §3: the transition carries the data-owned spec for the new stage.
	var s: Variant = _state()
	var transitions: Array = []
	s.stage_transition.connect(
		func(previous: int, current: int, spec: Dictionary) -> void:
			transitions.append([previous, current, spec])
	)
	s.set_meter(&"instability", 15.0)
	assert_int(transitions.size()).is_equal(1)
	assert_int(transitions[0][0]).is_equal(0)
	assert_int(transitions[0][1]).is_equal(1)
	var spec: Dictionary = transitions[0][2]
	assert_int(int(spec["stage"])).is_equal(1)
	assert_str(String(spec["name"])).is_equal("Hairline Cracks")
	assert_float(float(spec["duration_s"])).is_between(2.0 - EPS, 3.0 + EPS)
	assert_str(String(spec["fx"])).is_equal("glitch")
	assert_str(String(spec["cue"])).is_equal("stinger.stage_change")


func test_once_per_crossing_guard() -> void:
	# The guard: staying inside a band never re-announces the stage, however
	# many writes land there.
	var s: Variant = _state()
	var transitions: Array = []
	s.stage_transition.connect(
		func(previous: int, current: int, _spec: Dictionary) -> void:
			transitions.append([previous, current])
	)
	for value: float in [15.0, 16.0, 20.5, 29.0, 29.9]:
		s.set_meter(&"instability", value)
	assert_int(transitions.size()).is_equal(1).append_failure_message(
		"the stage was re-announced inside its own band"
	)
	assert_array(transitions).is_equal([[0, 1]])
	# A dip and a re-rise inside the band is still the same crossing.
	s.set_meter(&"instability", 15.0)
	s.set_meter(&"instability", 25.0)
	assert_int(transitions.size()).is_equal(1)
	# The next band fires exactly once too.
	s.set_meter(&"instability", 31.0)
	s.set_meter(&"instability", 40.0)
	assert_int(transitions.size()).is_equal(2)
	assert_array(transitions[1]).is_equal([1, 2])


func test_two_band_jump_fires_once() -> void:
	# A trigger spike can take her from stage 0 to stage 3 in one write: that is
	# ONE crossing, with one transition and one EVENT line — not three.
	var s: Variant = _state()
	var changes: Array = []
	var transitions: Array = []
	s.stage_changed.connect(func(p: int, c: int) -> void: changes.append([p, c]))
	s.stage_transition.connect(
		func(p: int, c: int, _spec: Dictionary) -> void: transitions.append([p, c])
	)
	s.set_meter(&"instability", 55.0)
	assert_int(s.stage).is_equal(3)
	assert_array(changes).is_equal([[0, 3]])
	assert_array(transitions).is_equal([[0, 3]])
	assert_int(s.pending_events.size()).is_equal(1)


func test_stage_never_regresses_on_a_good_day() -> void:
	# docs/01 §2: Instability dips to the ratchet floor, the stage does not.
	var s: Variant = _state()
	var transitions: Array = []
	s.stage_transition.connect(
		func(p: int, c: int, _spec: Dictionary) -> void: transitions.append([p, c])
	)
	s.set_meter(&"instability", 55.0)
	s.set_meter(&"instability", 10.0)
	assert_float(s.instability).is_equal_approx(s.instability_floor, EPS)
	assert_int(s.stage).is_equal(3)
	assert_array(transitions).is_equal([[0, 3]])


func test_transition_spec_matches_docs() -> void:
	# docs/01 §3 (2–3 s), docs/02 §2.3 (glitch), docs/04 §2 (stinger.stage_change).
	for stage: int in range(1, 6):
		var spec := StagesScript.transition_spec(stage)
		assert_int(int(spec["stage"])).is_equal(stage)
		assert_str(String(spec["name"])).is_equal(DOC_NAMES[stage])
		assert_float(float(spec["duration_s"])).is_between(2.0 - EPS, 3.0 + EPS)
		assert_str(String(spec["fx"])).is_equal("glitch")
		assert_str(String(spec["cue"])).is_equal("stinger.stage_change")
	# The shipped value sits inside the window rather than being clamped into it.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var shipped: Dictionary = parsed
	assert_float(float(shipped["transition"]["duration_s"])).is_between(2.0 - EPS, 3.0 + EPS)


func test_transition_duration_stays_in_doc_window() -> void:
	# A data edit retunes the glitch INSIDE docs/01 §3's window; widening the
	# window itself is a DCR, so the loader clamps and keeps the docs value for
	# a non-finite one.
	var long := _document(DOC_BANDS, 9.0)
	(
		assert_float(float(StagesScript.parse_document(long)["transition"]["duration_s"]))
		. is_equal_approx(3.0, EPS)
	)
	var short := _document(DOC_BANDS, 0.2)
	(
		assert_float(float(StagesScript.parse_document(short)["transition"]["duration_s"]))
		. is_equal_approx(2.0, EPS)
	)
	var broken := _document(DOC_BANDS, NAN)
	(
		assert_float(float(StagesScript.parse_document(broken)["transition"]["duration_s"]))
		. is_equal_approx(2.5, EPS)
	)


func test_loader_is_the_source_of_the_bands() -> void:
	# Data-driven proof: a synthetic document with different floors moves the
	# machine, so the numbers come from the table and never from a code copy.
	var table := StagesScript.parse_document(_document([0, 10, 20, 30, 40, 50], 2.0))
	assert_array(Array(table["bands"])).is_equal([0, 10, 20, 30, 40, 50])
	assert_float(float(table["transition"]["duration_s"])).is_equal_approx(2.0, EPS)
	# A document the loader cannot trust keeps the documented bands.
	var broken_documents := [
		{"bands": [0, 10]},
		{"bands": [5, 10, 20, 30, 40, 50]},
		{"bands": [0, 20, 10, 30, 40, 50]},
		{"bands": [0, 10, 20, 30, 40, 150]},
		{"bands": [0, 10, 20, 30, 40, 40]},
		{"bands": [0, 10.5, 20, 30, 40, 50]},
		{"bands": "0,15,30,50,70,90"},
	]
	for broken: Variant in broken_documents:
		assert_array(Array(StagesScript.parse_document(broken)["bands"])).is_equal(DOC_BANDS)


func test_broken_document_keeps_docs_defaults() -> void:
	# Wrong types never half-apply: names fall back together, fx/cue must be
	# strings, and an empty event line keeps the stage line-less instead of
	# filling the prompt with an empty "EVENT: ".
	var table := (
		StagesScript
		. parse_document(
			{
				"bands": DOC_BANDS,
				"names": ["only one"],
				"transition": {"duration_s": "slow", "fx": "", "cue": 42, "events": {"1": ""}},
			}
		)
	)
	assert_array(Array(table["names"])).is_equal(DOC_NAMES)
	assert_float(float(table["transition"]["duration_s"])).is_equal_approx(2.5, EPS)
	assert_str(String(table["transition"]["fx"])).is_equal("glitch")
	assert_str(String(table["transition"]["cue"])).is_equal("stinger.stage_change")
	assert_bool((table["transition"]["events"] as Dictionary).is_empty()).is_true()
	# A non-object document keeps every documented default.
	var no_object := StagesScript.parse_document("stages")
	assert_array(Array(no_object["bands"])).is_equal(DOC_BANDS)
	assert_array(Array(no_object["names"])).is_equal(DOC_NAMES)


func test_post_transition_event_line_is_queued_once() -> void:
	# docs/01 §3 + docs/08 §6: one crossing queues her one "EVENT: …" line, and
	# the next turn drains it exactly once.
	var s: Variant = _state()
	s.set_meter(&"instability", 30.0)
	assert_int(s.pending_events.size()).is_equal(1)
	var line := String(s.pending_events[0])
	assert_bool(line.begins_with("EVENT: ")).is_true()
	assert_str(line).is_equal(StagesScript.event_line(2))
	var drained: Array = s.take_pending_events()
	assert_array(Array(drained)).is_equal([line])
	assert_array(Array(s.take_pending_events())).is_empty()
	# Staying inside the band queues nothing; a two-band jump still queues one.
	s.set_meter(&"instability", 40.0)
	assert_array(Array(s.pending_events)).is_empty()
	var t: Variant = _state()
	t.set_meter(&"instability", 75.0)
	assert_int(t.pending_events.size()).is_equal(1)
	assert_str(String(t.pending_events[0])).is_equal(StagesScript.event_line(4))
	# The queue drops blank lines and duplicates.
	t.queue_event("  ")
	t.queue_event(String(t.pending_events[0]))
	assert_int(t.pending_events.size()).is_equal(1)


func test_event_lines_exist_for_every_stage() -> void:
	# docs/01 §3: she comments on the transition afterwards, so every crossing
	# destination has a line; docs/01 §4: the line never names a disorder.
	for stage: int in range(1, 6):
		var line := StagesScript.event_line(stage)
		assert_bool(line.is_empty()).is_false().append_failure_message(
			"stage %d has no transition EVENT line" % stage
		)
		assert_bool(line.begins_with("EVENT: ")).is_true()
		var lower := line.to_lower()
		for word: String in FORBIDDEN:
			assert_bool(lower.contains(word)).is_false().append_failure_message(
				"stage %d line names '%s'" % [stage, word]
			)
	assert_str(StagesScript.event_line(0)).is_equal("")
	assert_str(StagesScript.event_line(6)).is_equal("")


func test_restore_queues_no_transition() -> void:
	# A load re-emits stage_changed so listeners resync (existing contract), but
	# it is not a crossing: no glitch and no EVENT line from a restore.
	var source: Variant = _state()
	source.set_meter(&"instability", 55.0)
	var snapshot: Dictionary = source.to_dict()
	var restored: Variant = _state()
	var changes: Array = []
	var transitions: Array = []
	restored.stage_changed.connect(func(p: int, c: int) -> void: changes.append([p, c]))
	restored.stage_transition.connect(
		func(p: int, c: int, _spec: Dictionary) -> void: transitions.append([p, c])
	)
	assert_bool(restored.from_dict(snapshot)).is_true()
	assert_int(restored.stage).is_equal(3)
	assert_array(changes).is_equal([[0, 3]])
	assert_array(transitions).is_empty()
	assert_array(Array(restored.pending_events)).is_empty()


func test_reset_clears_pending_events() -> void:
	var s: Variant = _state()
	s.set_meter(&"instability", 15.0)
	assert_int(s.pending_events.size()).is_equal(1)
	s.reset()
	assert_array(Array(s.pending_events)).is_empty()
	assert_int(s.stage).is_zero()


func test_stage_invariant_over_a_hundred_turns() -> void:
	# SYS invariant for anything that accumulates: stage is monotonic, always the
	# peak's band, and every rise is one transition with one queued line.
	for seed_value: int in [7, 77]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var s: Variant = _state()
		var transitions: Array = []
		var told: Array = []
		s.stage_transition.connect(
			func(p: int, c: int, _spec: Dictionary) -> void: transitions.append([p, c])
		)
		var last_stage := 0
		for turn: int in 100:
			s.apply_turn_meters(
				{"mood": {"stress": rng.randi_range(-3, 3), "affection": rng.randi_range(-3, 3)}}
			)
			if turn % 7 == 6:
				s.advance_day()
			assert_int(s.stage).is_greater_equal(last_stage)
			assert_int(s.stage).is_equal(StagesScript.for_instability(s.instability_peak))
			last_stage = s.stage
			for line: String in s.take_pending_events():
				told.append(line)
		assert_int(told.size()).is_equal(transitions.size())
		assert_bool(transitions.size() > 0).is_true()
		assert_int(transitions.size()).is_less_equal(s.stage)
		for pair: Array in transitions:
			assert_int(pair[0]).is_less(pair[1])
