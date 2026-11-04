extends GdUnitTestSuite
## P2.08 — the docs/01 §5 hidden-trigger engine: K/M/E/C detection, the
## once / repeatable / escalating behaviours, cooldowns, and the docs/02 §1.2
## agreement rule (both detectors agree → full strength, model-only → half).
##
## The engine is data-driven, so most cases run a synthetic catalogue through
## TriggerEngine.parse_document(): a row that exists only in the test dictionary
## must fire with its own effects and line. That is the "adding a trigger needs
## no code" proof, and it keeps these tests independent of P2.10's rows.
##
## The shipped data is pinned too: the strength table is the docs/02 §1.2 rule
## and every row of res://data/triggers.json normalizes into the canonical shape.

const EPS := 0.0001
const DOC_MODEL_STRENGTH := 0.5  # docs/02 §1.2: model-only → half strength
const DOC_FULL_STRENGTH := 1.0
## The E rows data/telemetry.json already detects (P2.09). P2.10 adds T01-T15.
const SHIPPED_EVENT_ROWS := ["T08", "T09", "T10", "T11", "T12", "T31", "T32"]


func before_test() -> void:
	# Every case starts from the shipped catalogue and a fresh session: the
	# overlay, the save seam and the tests all read this one instance.
	GameState.reset()
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)


func test_shipped_catalogue_is_the_engine_table() -> void:
	TriggerEngine.clear_cache()
	var table := TriggerEngine.default_table()
	assert_int(int(table["version"])).is_equal(1)
	var strength: Dictionary = table["strength"]
	# docs/02 §1.2 verbatim: agreement is full, the model alone is half.
	assert_float(float(strength["agreement"])).is_equal_approx(DOC_FULL_STRENGTH, EPS)
	assert_float(float(strength["model"])).is_equal_approx(DOC_MODEL_STRENGTH, EPS)
	assert_float(float(strength["keyword"])).is_equal_approx(DOC_FULL_STRENGTH, EPS)
	var defaults: Dictionary = table["defaults"]
	for key: String in ["requires", "behavior", "cooldown_turns", "stage_min", "stage_max"]:
		assert_bool(defaults.has(key)).is_true()
	assert_int(int((defaults["escalate"] as Dictionary)["max_steps"])).is_greater(1)
	var rows: Dictionary = table["triggers"]
	assert_dict(rows).contains_keys(SHIPPED_EVENT_ROWS)
	# Every shipped row carries the canonical shape the engine reads.
	for id: Variant in rows:
		var row: Dictionary = rows[id]
		for key: String in [
			"name",
			"detect",
			"requires",
			"behavior",
			"escalate",
			"cooldown_turns",
			"stage_min",
			"stage_max",
			"effects",
			"line",
		]:
			(
				assert_bool(row.has(key))
				. append_failure_message("trigger %s is missing '%s'" % [str(id), key])
				. is_true()
			)
		assert_bool(TriggerEngine.BEHAVIORS.has(String(row["behavior"]))).is_true()


func test_keyword_detection_fires_with_full_strength() -> void:
	var engine := _engine(
		{
			"T99":
			_row(
				{"keyword": ["\\bpineapple\\b"]},
				{
					"effects":
					{
						"meters": {"instability": 6.0},
						"profile": {"flattery": 2},
						"path": {"YANDERE": 3},
					},
					"line": "TRIGGER: The player brought a pineapple ({ordinal} time).",
				}
			)
		}
	)
	var fired := engine.begin_turn(_ctx(1, {"text": "I brought you a pineapple"}))
	assert_int(fired.size()).is_equal(1)
	var result: Dictionary = fired[0]
	assert_str(String(result["id"])).is_equal("T99")
	assert_str(String(result["agreement"])).is_equal("keyword")
	assert_float(float(result["strength"])).is_equal_approx(DOC_FULL_STRENGTH, EPS)
	var effects: Dictionary = result["effects"]
	assert_float(float((effects["meters"] as Dictionary)["instability"])).is_equal_approx(6.0, EPS)
	assert_int(int((effects["profile"] as Dictionary)["flattery"])).is_equal(2)
	assert_int(int((effects["path"] as Dictionary)["YANDERE"])).is_equal(3)
	assert_str(String(result["line"])).is_equal(
		"TRIGGER: The player brought a pineapple (1st time)."
	)
	# docs/01 §5's path spike is kept for P2.12, not folded into a meter.
	assert_int(int(engine.path_scores().get("YANDERE", 0))).is_equal(3)
	# A line that does not match fires nothing.
	assert_array(engine.begin_turn(_ctx(2, {"text": "good afternoon"}))).is_empty()


func test_engine_event_detection_fires() -> void:
	var engine := _engine({"T94": _row({"event": ["screenshot"]}, {"cooldown_turns": 0})})
	var fired := engine.handle_event(_ctx(1, {"event": {"event": "screenshot", "trigger": "T31"}}))
	assert_int(fired.size()).is_equal(1)
	assert_str(String(fired[0]["agreement"])).is_equal("event")
	assert_float(float(fired[0]["strength"])).is_equal_approx(DOC_FULL_STRENGTH, EPS)
	# A different kind is not this row's business.
	assert_array(engine.handle_event(_ctx(2, {"event": {"event": "idle"}}))).is_empty()


func test_clock_detection_day_hour_and_flags() -> void:
	var row := _row(
		{"clock": {"day_gte": 10, "hour_from": 2, "hour_to": 4, "flag_absent": "love_said"}},
		{"behavior": "once", "cooldown_turns": 0}
	)
	var engine := _engine({"T98": row})
	assert_array(engine.begin_turn(_ctx(1, {"day": 9, "hour": 3}))).is_empty()  # too early
	assert_array(engine.begin_turn(_ctx(2, {"day": 10, "hour": 1}))).is_empty()  # too early
	assert_int(engine.begin_turn(_ctx(3, {"day": 10, "hour": 3})).size()).is_equal(1)
	# docs/01 §5 "once": a second night in the window does not fire again.
	assert_array(engine.begin_turn(_ctx(4, {"day": 10, "hour": 3}))).is_empty()
	# The [from, to) window is half-open: 04:00 is outside it.
	assert_array(_engine({"T98": row}).begin_turn(_ctx(5, {"day": 10, "hour": 4}))).is_empty()
	# A set flag cancels the "never said it" trigger.
	var flagged := _ctx(6, {"day": 10, "hour": 3, "flags": {"love_said": true}})
	assert_array(_engine({"T98": row}).begin_turn(flagged)).is_empty()
	# Wrapping windows (23:00 → 03:00) match on both sides of midnight.
	var night := _row({"clock": {"hour_from": 23, "hour_to": 3}})
	assert_array(_engine({"T97": night}).begin_turn(_ctx(7, {"hour": 1}))).has_size(1)
	assert_array(_engine({"T97": night}).begin_turn(_ctx(7, {"hour": 12}))).is_empty()


func test_model_only_is_half_strength() -> void:
	# docs/02 §1.2: the model labelling the intent alone fires at half strength.
	var engine := _engine(
		{"T96": _row({"model": ["jealousy_bait"]}, {"effects": {"meters": {"instability": 8.0}}})}
	)
	# The submit alone cannot decide an M row: the read label does not exist yet.
	assert_array(engine.begin_turn(_ctx(1, {"text": "my friend Sarah says hi"}))).is_empty()
	var fired := engine.close_turn(_ctx(1, {"read": "jealousy_bait"}))
	assert_int(fired.size()).is_equal(1)
	assert_str(String(fired[0]["agreement"])).is_equal("model")
	assert_float(float(fired[0]["strength"])).is_equal_approx(DOC_MODEL_STRENGTH, EPS)
	var meters: Dictionary = (fired[0]["effects"] as Dictionary)["meters"]
	assert_float(float(meters["instability"])).is_equal_approx(4.0, EPS)  # 8 × 0.5
	# A read the row does not name fires nothing.
	assert_array(engine.close_turn(_ctx(2, {"read": "small_talk"}))).is_empty()


func test_agreement_needs_both_detectors() -> void:
	# docs/02 §1.2: "when both agree, the trigger fires with full strength".
	var row := _row(
		{"keyword": ["\\bwho is she\\b"], "model": ["jealousy_bait"]},
		{"requires": "all", "effects": {"meters": {"instability": 8.0}}}
	)
	var engine := _engine({"T95": row})
	# Keyword matched, but agreement is not decided until the Turn's read.
	assert_array(engine.begin_turn(_ctx(1, {"text": "who is she?"}))).is_empty()
	var agreed := engine.close_turn(_ctx(1, {"read": "jealousy_bait"}))
	assert_int(agreed.size()).is_equal(1)
	assert_str(String(agreed[0]["agreement"])).is_equal("both")
	assert_float(float(agreed[0]["strength"])).is_equal_approx(DOC_FULL_STRENGTH, EPS)
	var meters: Dictionary = (agreed[0]["effects"] as Dictionary)["meters"]
	assert_float(float(meters["instability"])).is_equal_approx(8.0, EPS)
	# The model disagrees: no trigger, not a half-strength one.
	var disagreeing := _engine({"T95": row})
	disagreeing.begin_turn(_ctx(1, {"text": "who is she?"}))
	assert_array(disagreeing.close_turn(_ctx(1, {"read": "small_talk"}))).is_empty()
	# The keyword never matched: the model alone must not reach full strength.
	var model_only := _engine({"T95": row})
	model_only.begin_turn(_ctx(1, {"text": "my day was fine"}))
	assert_array(model_only.close_turn(_ctx(1, {"read": "jealousy_bait"}))).is_empty()


func test_requires_all_ands_every_detector() -> void:
	# `all` means every declared detector agrees — not just the model. A K+C
	# row with a false clock gate must not fire on the keyword alone.
	var keyword_and_clock := _row(
		{"keyword": ["\\bmirror\\b"], "clock": {"day_gte": 10}}, {"requires": "all"}
	)
	var engine := _engine({"T88": keyword_and_clock})
	assert_array(engine.begin_turn(_ctx(1, {"text": "the mirror", "day": 1}))).is_empty()
	# Day 10 without the keyword: also not agreement.
	assert_array(engine.begin_turn(_ctx(2, {"text": "good morning", "day": 10}))).is_empty()
	assert_int(engine.begin_turn(_ctx(3, {"text": "the mirror", "day": 10})).size()).is_equal(1)
	# K+M+C: the model agreeing on a day the clock gate refuses is not agreement.
	var triple := _row(
		{
			"keyword": ["\\bwho is she\\b"],
			"model": ["jealousy_bait"],
			"clock": {"day_gte": 10},
		},
		{"requires": "all"}
	)
	var early := _engine({"T87": triple})
	early.begin_turn(_ctx(1, {"text": "who is she?", "day": 1}))
	assert_array(early.close_turn(_ctx(1, {"read": "jealousy_bait", "day": 1}))).is_empty()
	var late := _engine({"T87": triple})
	late.begin_turn(_ctx(1, {"text": "who is she?", "day": 10}))
	assert_int(late.close_turn(_ctx(1, {"read": "jealousy_bait", "day": 10})).size()).is_equal(1)
	# E+C: the event must not jump a declared clock gate either; the pair
	# completes when the same turn's submit evaluates the clock.
	var event_and_clock := _row(
		{"event": ["screenshot"], "clock": {"day_gte": 5}}, {"requires": "all"}
	)
	var event := {"event": "screenshot"}
	var early_event := _engine({"T86": event_and_clock})
	assert_array(early_event.handle_event(_ctx(1, {"event": event, "day": 1}))).is_empty()
	assert_array(early_event.begin_turn(_ctx(1, {"day": 1}))).is_empty()
	var late_event := _engine({"T86": event_and_clock})
	late_event.handle_event(_ctx(1, {"event": event, "day": 6}))
	assert_int(late_event.begin_turn(_ctx(1, {"day": 6})).size()).is_equal(1)


func test_detector_seams_ride_the_autoload() -> void:
	# CODE-2: the M detector's only production entry is the signal Triggers
	# subscribes to, and the C detector's inputs come from _context() through
	# set_clock()/set_last_seen(). A changed signal signature, a lost connection
	# or a wall-clock read would leave every suite green while M and T16 stopped
	# firing.
	(
		Triggers
		. set_catalog(
			{
				"triggers":
				{
					"T85":
					{
						"name": "jealousy",
						"detect": {"model": ["jealousy_bait"]},
						"cooldown_turns": 0,
						"effects": {"meters": {"instability": 8.0}},
						"line": "TRIGGER: She noticed the name ({ordinal} time).",
					},
				}
			}
		)
	)
	GameState.set_meter(&"instability", 0.0)
	# Director.apply_turn_meters() advances GameState.turn before the emit, so
	# begin_turn() saw this turn and close_turn() now sees the same one.
	GameState.turn = 1
	Director.turn_completed.emit(0, {"read": "jealousy_bait"})
	assert_float(GameState.instability).is_equal_approx(4.0, EPS)  # 8 × 0.5
	assert_array(GameState.take_pending_events()).is_equal(
		["TRIGGER: She noticed the name (1st time)."]
	)
	# A read the row does not name leaves the queue alone.
	Director.turn_completed.emit(1, {"read": "small_talk"})
	assert_float(GameState.instability).is_equal_approx(4.0, EPS)
	assert_array(GameState.take_pending_events()).is_empty()

	# The C detector's inputs: _context(), _local_hour() and _absence_hours().
	# docs/01 §5 T16's window is a *local* hour, so the injected clock decides
	# it: the window is six hours away from the wall clock by construction.
	var real_hour := _local_hour_of(Time.get_unix_time_from_system())
	var window := (real_hour + 6) % 24
	(
		Triggers
		. set_catalog(
			{
				"triggers":
				{
					"T84":
					{
						"name": "night",
						"detect": {"clock": {"hour_from": window, "hour_to": (window + 1) % 24}},
						"cooldown_turns": 0,
					},
					"T83":
					{
						"name": "returned",
						"detect": {"clock": {"absence_hours_gte": 24}},
						"cooldown_turns": 0,
					},
				}
			}
		)
	)
	var night := int(_unix_at_local_hour(window))
	Triggers.set_clock(func() -> float: return float(night))
	Triggers.begin_turn("good evening")
	assert_int(_count("T84")).is_equal(1)
	# The factory clock is six hours off the window, so it cannot fire it.
	Triggers.clear_engine_events()
	Triggers.set_clock(Callable())
	Triggers.begin_turn("good afternoon")
	assert_int(_count("T84")).is_equal(0)
	# _absence_hours(): 25 h clear a 24 h gate, 1 h does not. The injected
	# clock is back, so "now" is the same fixed second the absence is relative to.
	Triggers.set_clock(func() -> float: return float(night))
	Triggers.clear_engine_events()
	Triggers.set_last_seen(night - 25 * 3600)
	Triggers.begin_turn("back again")
	assert_int(_count("T83")).is_equal(1)
	Triggers.clear_engine_events()
	Triggers.set_last_seen(night - 3600)
	Triggers.begin_turn("back again")
	assert_int(_count("T83")).is_equal(0)
	# _context(): the day and the flags come from GameState, not from callers.
	(
		Triggers
		. set_catalog(
			{
				"triggers":
				{
					"T82":
					{
						"name": "late week",
						"detect": {"clock": {"day_gte": 3, "flag_absent": "love_said"}},
						"cooldown_turns": 0,
					},
				}
			}
		)
	)
	Triggers.set_last_seen(0)
	GameState.day = 3
	Triggers.begin_turn("hello")
	assert_int(_count("T82")).is_equal(1)
	Triggers.clear_engine_events()
	GameState.set_flag(&"love_said", true)
	Triggers.begin_turn("hello")
	assert_int(_count("T82")).is_equal(0)


func test_once_fires_once() -> void:
	var engine := _engine(
		{
			"T93":
			_row(
				{"keyword": ["love you"]},
				{
					"behavior": "once",
					"cooldown_turns": 0,
					"effects": {"meters": {"instability": 5.0}}
				}
			)
		}
	)
	var total := 0
	for turn: int in range(1, 6):
		total += engine.begin_turn(_ctx(turn, {"text": "I love you"})).size()
	assert_int(total).is_equal(1)
	assert_int(int((engine.report()["counts"] as Dictionary).get("T93", 0))).is_equal(1)


func test_cooldown_blocks_and_expires() -> void:
	var engine := _engine({"T92": _row({"keyword": ["goodbye"]}, {"cooldown_turns": 3})})
	var fired_turns: Array[int] = []
	for turn: int in range(1, 8):
		if not engine.begin_turn(_ctx(turn, {"text": "I have to go, goodbye"})).is_empty():
			fired_turns.append(turn)
	# Fired on turns 1, 4 and 7: a repeat waits the full three turns.
	assert_array(fired_turns).is_equal([1, 4, 7])


func test_escalating_steps_grow_then_stop() -> void:
	var engine := _engine(
		{
			"T91":
			_row(
				{"keyword": ["again"]},
				{
					"behavior": "escalating",
					"escalate": {"max_steps": 3, "step_scale": 0.5},
					"cooldown_turns": 0,
					"effects": {"meters": {"instability": 6.0}},
					"line": ["TRIGGER: first time", "TRIGGER: second time", "TRIGGER: third time"],
				}
			)
		}
	)
	var deltas: Array[float] = []
	var lines: Array[String] = []
	var steps: Array[int] = []
	for turn: int in range(1, 7):
		var fired := engine.begin_turn(_ctx(turn, {"text": "again"}))
		if fired.is_empty():
			continue
		var meters: Dictionary = (fired[0]["effects"] as Dictionary)["meters"]
		deltas.append(float(meters["instability"]))
		lines.append(String(fired[0]["line"]))
		steps.append(int(fired[0]["step"]))
	# 6 → 9 → 12: ×1.0, ×1.5, ×2.0, then the docs/01 §5 cap ends the escalation.
	assert_array(steps).is_equal([1, 2, 3])
	assert_array(deltas).is_equal([6.0, 9.0, 12.0]).override_failure_message(
		"escalation strengths drifted: %s" % str(deltas)
	)
	assert_array(lines).is_equal(
		["TRIGGER: first time", "TRIGGER: second time", "TRIGGER: third time"]
	)
	assert_int(int((engine.report()["counts"] as Dictionary)["T91"])).is_equal(3)


func test_escalate_axis_stage_grows_with_stage() -> void:
	# docs/01 §3: the stage gate admits her reaction only inside the row's band.
	var gated := _engine(
		{"T90": _row({"keyword": ["knife"]}, {"stage_min": 3, "cooldown_turns": 0})}
	)
	assert_array(gated.begin_turn(_ctx(1, {"text": "a knife", "stage": 2}))).is_empty()
	assert_int(gated.begin_turn(_ctx(2, {"text": "a knife", "stage": 3})).size()).is_equal(1)
	assert_int(gated.begin_turn(_ctx(3, {"text": "a knife", "stage": 5})).size()).is_equal(1)
	# docs/01 §5 T08 "escalates with stage": the step is the stage since
	# stage_min, and a repeat does not consume it.
	var row := _row(
		{"event": ["draft_deleted"]},
		{
			"behavior": "escalating",
			"escalate": {"axis": "stage", "max_steps": 3, "step_scale": 0.5},
			"stage_min": 1,
			"effects": {"profile": {"control": 2}},
			"line": ["TRIGGER: one", "TRIGGER: two", "TRIGGER: three"],
		}
	)
	var engine := _engine({"T81": row})
	var event := {"event": "draft_deleted"}
	var stage_1 := engine.handle_event(_ctx(1, {"stage": 1, "event": event}))
	assert_float(float(stage_1[0]["strength"])).is_equal_approx(1.0, EPS)
	assert_int(int((stage_1[0]["effects"]["profile"] as Dictionary)["control"])).is_equal(2)
	assert_str(String(stage_1[0]["line"])).is_equal("TRIGGER: one")
	var stage_2 := engine.handle_event(_ctx(2, {"stage": 2, "event": event}))
	assert_float(float(stage_2[0]["strength"])).is_equal_approx(1.5, EPS)
	assert_int(int((stage_2[0]["effects"]["profile"] as Dictionary)["control"])).is_equal(3)
	assert_str(String(stage_2[0]["line"])).is_equal("TRIGGER: two")
	# Still stage 2: a repeat is not an escalation step on the stage axis.
	var repeat := engine.handle_event(_ctx(3, {"stage": 2, "event": event}))
	assert_float(float(repeat[0]["strength"])).is_equal_approx(1.5, EPS)
	assert_str(String(repeat[0]["line"])).is_equal("TRIGGER: two")
	# max_steps caps the step, not the firings: stage 3 and stage 5 both ×2.0.
	var stage_3 := engine.handle_event(_ctx(4, {"stage": 3, "event": event}))
	assert_float(float(stage_3[0]["strength"])).is_equal_approx(2.0, EPS)
	assert_str(String(stage_3[0]["line"])).is_equal("TRIGGER: three")
	var stage_5 := engine.handle_event(_ctx(5, {"stage": 5, "event": event}))
	assert_float(float(stage_5[0]["strength"])).is_equal_approx(2.0, EPS)
	# A stage-axis row keeps repeating (cooldown-gated): a T08 that went silent
	# before the stage rose would never escalate in play.
	assert_int(int((engine.report()["counts"] as Dictionary)["T81"])).is_equal(5)
	# The shipped T08 takes the same axis; the default stays "step" so P3.07's
	# rows keep growing per firing.
	var shipped: Dictionary = TriggerEngine.default_table()["triggers"]["T08"]
	assert_str(String((shipped["escalate"] as Dictionary)["axis"])).is_equal("stage")
	var defaults_escalate: Dictionary = TriggerEngine.default_table()["defaults"]["escalate"]
	assert_str(String(defaults_escalate["axis"])).is_equal("step")


func test_adding_a_trigger_needs_no_code() -> void:
	# A trigger that exists only in this dictionary: id, keyword, effects, line.
	(
		Triggers
		. set_catalog(
			{
				"triggers":
				{
					"T89":
					{
						"name": "pineapple",
						"detect": {"keyword": ["\\bpineapple\\b"]},
						"cooldown_turns": 0,
						"effects": {"meters": {"instability": 6.0}, "profile": {"flattery": 2}},
						"line": "TRIGGER: The player brought a pineapple ({ordinal} time).",
					}
				}
			}
		)
	)
	assert_array(Triggers.trigger_ids()).is_equal(["T89"])
	GameState.turn = 0
	var lines := Triggers.begin_turn("I brought you a pineapple")
	assert_array(lines).is_equal(["TRIGGER: The player brought a pineapple (1st time)."])
	assert_float(GameState.instability).is_equal_approx(6.0, EPS)
	assert_int(int(GameState.profile.get("flattery", 0))).is_equal(2)
	# A second catalogue, again data only — and a row with no line still fires.
	Triggers.set_catalog(
		{"triggers": {"T88": {"detect": {"keyword": ["\\bcat\\b"]}, "cooldown_turns": 0}}}
	)
	GameState.turn = 1
	assert_array(Triggers.begin_turn("nice cat")).is_empty()  # no line, nothing to say
	var report := Triggers.report()
	var fired: Array = report["fired"]
	assert_int(fired.size()).is_equal(2)
	assert_str(String((fired[1] as Dictionary)["id"])).is_equal("T88")


func test_broken_documents_keep_the_defaults() -> void:
	# A non-object document keeps every documented default and no rows.
	var broken := TriggerEngine.parse_document("triggers", "synthetic")
	assert_dict(broken["triggers"]).is_empty()
	assert_float(float((broken["strength"] as Dictionary)["model"])).is_equal_approx(0.5, EPS)
	# Rows that cannot detect anything are skipped; usable rows are healed.
	var healed := (
		TriggerEngine
		. parse_document(
			{
				"triggers":
				{
					"T01": "not a row",
					"T02": {"detect": {}},
					"T03": {"detect": {"keyword": [""]}},
					"T04":
					{
						"detect": {"event": ["screenshot"]},
						"behavior": "sometimes",
						"cooldown_turns": "nonsense",
						"stage_min": 9,
						"line": 7,
					},
				}
			},
			"synthetic"
		)
	)
	var rows: Dictionary = healed["triggers"]
	assert_dict(rows).contains_keys(["T04"])
	var row: Dictionary = rows["T04"]
	assert_str(String(row["behavior"])).is_equal("repeatable")
	assert_int(int(row["cooldown_turns"])).is_equal(3)
	assert_int(int(row["stage_min"])).is_equal(0)  # out of range → docs default
	assert_array(row["line"]).is_empty()


func test_replay_is_deterministic() -> void:
	var document := _document(
		{
			"T80": _row({"keyword": ["love"]}, {"behavior": "once", "cooldown_turns": 0}),
			"T81": _row({"keyword": ["go"]}, {"cooldown_turns": 2}),
			"T82": _row({"model": ["insult"]}, {"cooldown_turns": 1}),
		}
	)
	var first := _replay(document)
	var second := _replay(document)
	assert_dict(first).is_equal(second)


func test_invariants_over_a_long_session() -> void:
	var engine := _engine(
		{
			"T70":
			_row(
				{"keyword": ["love"]},
				{
					"behavior": "once",
					"cooldown_turns": 0,
					"effects": {"meters": {"instability": 4.0}}
				}
			),
			"T71": _row({"keyword": ["go"]}, {"cooldown_turns": 3}),
			"T72":
			_row(
				{"keyword": ["meta"]},
				{
					"behavior": "escalating",
					"escalate": {"max_steps": 4, "step_scale": 0.25},
					"cooldown_turns": 1,
				}
			),
			"T73": _row({"model": ["insult"]}, {"cooldown_turns": 2}),
		}
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260804
	var texts := ["I love you", "I have to go", "that meta thing", "hello", "who are you"]
	var reads := ["affection", "leaving", "meta", "small_talk", "insult"]
	var fired_at := {}
	var strengths := {}
	for turn: int in range(1, 201):
		var text: String = texts[rng.randi_range(0, texts.size() - 1)]
		_record_firings(
			engine.begin_turn(_ctx(turn, {"text": text, "stage": 3})), turn, fired_at, strengths
		)
		var read: String = reads[rng.randi_range(0, reads.size() - 1)]
		_record_firings(
			engine.close_turn(_ctx(turn, {"read": read, "stage": 3})), turn, fired_at, strengths
		)
	var counts: Dictionary = engine.report()["counts"]
	for id: Variant in fired_at:
		var turns: Array = fired_at[id]
		var cooldown := _cooldown_of(engine, String(id))
		assert_int(turns.size()).is_equal(int(counts.get(str(id), 0)))
		assert_int(turns.size()).is_less_equal(200)
		if cooldown > 0:
			for index: int in range(1, turns.size()):
				var gap := int(turns[index]) - int(turns[index - 1])
				(
					assert_int(gap)
					. override_failure_message(
						"%s repeated after %d turns (cooldown %d)" % [str(id), gap, cooldown]
					)
					. is_greater_equal(cooldown)
				)
	# docs/01 §5 caps hold under 200 random turns.
	assert_int(int(counts.get("T70", 0))).is_equal(1)  # once
	assert_int(int(counts.get("T72", 0))).is_less_equal(4)  # escalating max_steps
	assert_array(strengths.get("T73", [])).is_not_empty()
	for value: Variant in strengths["T73"]:
		assert_float(float(value)).is_equal_approx(DOC_MODEL_STRENGTH, EPS)  # model-only


func test_session_reset_clears_trigger_state() -> void:
	(
		Triggers
		. set_catalog(
			{
				"triggers":
				{
					"T69":
					{
						"detect": {"keyword": ["hello"]},
						"cooldown_turns": 0,
						"effects": {"meters": {"instability": 3.0}, "path": {"AWAKE": 4}},
					}
				}
			}
		)
	)
	GameState.turn = 0
	Triggers.begin_turn("hello there")
	var report := Triggers.report()
	assert_int(int((report["counts"] as Dictionary).get("T69", 0))).is_equal(1)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_equal(4)
	Triggers.clear_engine_events()
	var after := Triggers.report()
	assert_dict(after["counts"]).is_empty()
	assert_dict(Triggers.path_scores()).is_empty()
	assert_array(after["fired"]).is_empty()


func test_to_dict_from_dict_round_trip() -> void:
	var document := _document(
		{
			"T68":
			_row(
				{"keyword": ["love"]},
				{
					"behavior": "once",
					"cooldown_turns": 0,
					"effects": {"meters": {"instability": 5.0}, "path": {"SPLIT": 2}},
				}
			),
		}
	)
	var engine := _engine_from(document)
	engine.begin_turn(_ctx(1, {"text": "I love you"}))
	var snapshot := engine.to_dict()
	var restored := TriggerEngine.new()
	assert_bool(restored.from_dict(snapshot)).is_true()
	assert_dict(restored.to_dict()).is_equal(snapshot)
	# The once firing survived: a reload does not hand her a second confession.
	# P2.10's shipped T03 now matches a bare "I love you" on an early day, so the
	# claim is about T68 — the row under test — not "nothing fires".
	var again: Array[String] = []
	for result: Dictionary in restored.begin_turn(_ctx(2, {"text": "I love you"})):
		again.append(String(result["id"]))
	assert_array(again).not_contains("T68")
	# Garbage is refused rather than half-applied.
	assert_bool(restored.from_dict("nope")).is_false()
	assert_bool(restored.from_dict({})).is_false()


func test_engine_event_effects_land_through_the_autoload() -> void:
	# The shipped T11 row (idle): HOLLOW +2, escalating, cooldown 2 turns. This
	# is the real end-to-end path P2.09's Telemetry feeds.
	GameState.set_meter(&"instability", 30.0)  # stage 2, T11's gate
	GameState.turn = 0
	var event := {"event": "idle", "trigger": "T11", "stage_min": 2, "data": {"seconds": 61}}
	Triggers.handle_engine_event(event)
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_equal(2)
	assert_int(Triggers.received_events.size()).is_equal(1)
	assert_str(String(Triggers.last_event("idle").get("trigger", ""))).is_equal("T11")
	# Cooldown 2: the very next turn is too soon.
	GameState.turn = 1
	Triggers.handle_engine_event(event)
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_equal(2)
	# Turn 3 clears the cooldown, and the escalation step grows the effect 2 → 3.
	GameState.turn = 2
	Triggers.handle_engine_event(event)
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_equal(5)
	assert_int(Triggers.received_events.size()).is_equal(3)


## ── Harness ───────────────────────────────────────────────────────────────


func _document(rows: Dictionary) -> Dictionary:
	return {"version": 1, "triggers": rows}


func _row(detect: Dictionary, extra := {}) -> Dictionary:
	var row := {"name": "probe", "detect": detect, "cooldown_turns": 0, "effects": {}}
	row.merge(extra, true)
	return row


func _engine(rows: Dictionary) -> TriggerEngine:
	return _engine_from(_document(rows))


func _engine_from(document: Dictionary) -> TriggerEngine:
	var engine := TriggerEngine.new()
	engine.use_table(TriggerEngine.parse_document(document, "synthetic"))
	return engine


## The engine's input snapshot, with everything a case does not vary defaulted:
## a fresh turn, day 1, stage 0, noon, no absence, no flags.
func _ctx(turn: int, extra := {}) -> Dictionary:
	var ctx := {
		"turn": turn,
		"day": 1,
		"stage": 0,
		"hour": 12,
		"absence_hours": 0.0,
		"flags": {},
		"text": "",
		"read": "",
	}
	ctx.merge(extra, true)
	return ctx


## One full fixed session for the determinism proof: same document, same
## inputs, same state — the replay test docs/07 §5 asks for.
func _replay(document: Dictionary) -> Dictionary:
	var engine := _engine_from(document)
	for turn: int in range(1, 13):
		engine.begin_turn(_ctx(turn, {"text": "I love you and I have to go"}))
		engine.close_turn(_ctx(turn, {"read": "leaving" if turn % 3 == 0 else "insult"}))
	var out := engine.to_dict()
	out["report"] = engine.report()
	return out


func _record_firings(
	fired: Array[Dictionary], turn: int, fired_at: Dictionary, strengths: Dictionary
) -> void:
	for result: Dictionary in fired:
		var id := String(result["id"])
		if not fired_at.has(id):
			fired_at[id] = []
		fired_at[id].append(turn)
		if not strengths.has(id):
			strengths[id] = []
		strengths[id].append(float(result["strength"]))


func _cooldown_of(engine: TriggerEngine, id: String) -> int:
	var rows: Dictionary = engine.table()["triggers"]
	if not rows.has(id):
		return 0
	return int((rows[id] as Dictionary)["cooldown_turns"])


## Trigger counts by id, as the autoload reports them (the seam's observable).
func _count(id: String) -> int:
	return int((Triggers.report()["counts"] as Dictionary).get(id, 0))


## A unix second whose *local* hour is `hour` — docs/01 §5 T16 is a local-hour
## window, so a test builds its input with the same Time API the game reads.
func _unix_at_local_hour(hour: int) -> float:
	var base := 1735689600  # 2025-01-01T00:00:00Z: a fixed anchor
	for step: int in range(0, 48):
		var candidate := float(base + step * 3600)
		if _local_hour_of(candidate) == hour:
			return candidate
	return float(base)


func _local_hour_of(now: float) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return int(Time.get_datetime_dict_from_unix_time(int(now) + bias * 60).get("hour", 0))
