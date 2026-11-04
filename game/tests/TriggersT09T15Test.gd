extends GdUnitTestSuite
## P2.10 — docs/01 §5 triggers T09–T15 through the shipped catalogue, plus the
## docs/05 §1.1 M01 close intercept they feed.
##
## T09–T12 and T14 are model/event rows that land on GameState; T13 and T15 are
## guard rows (the game's own deterministic check: a contradiction with a stored
## fact, and the `ignored_questions` bump P2.12's profile just made), because
## docs/02 §1.2's `read` enum has no label for a lie or for an ignored question
## (P2.10 handoff DCR-1/DCR-2).
##
## The close intercept cases pin docs/05 §0's hard rule: closing costs exactly
## ONE extra press, and the quit goes through an injected Callable so a scripted
## close never ends the test run.

const EPS := 0.0001
const IDS := ["T09", "T10", "T11", "T12", "T13", "T14", "T15"]


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)
	MetaDirector.reset_session()


func test_t09_focus_lost() -> void:
	# docs/01 §5 T09 / docs/05 M20 "Am I boring you?": the alt-tab while she is
	# talking is a SPLIT spike, and the E row leaves the line to telemetry.
	GameState.set_meter(&"instability", 20.0)  # stage 1
	Triggers.handle_engine_event({"event": "focus_lost", "trigger": "T09", "data": {}})
	assert_int(int(Triggers.path_scores().get("SPLIT", 0))).is_equal(2)
	assert_int(_count("T09")).is_equal(1)


func test_t10_close_requested_is_once_at_stage_3() -> void:
	# docs/01 §5 T10: "Close is intercepted at Stage 3+". Below the gate the
	# event is recorded by telemetry but she does not react to it.
	var event := {
		"event": "close_requested",
		"trigger": "T10",
		"stage_min": 3,
		"line": "EVENT: The player tried to close the game.",
		"data": {},
	}
	GameState.set_meter(&"instability", 35.0)  # stage 2
	Triggers.handle_engine_event(event)
	assert_int(_count("T10")).is_equal(0)
	GameState.set_meter(&"instability", 55.0)  # stage 3
	GameState.turn = 1
	Triggers.handle_engine_event(event)
	assert_int(_count("T10")).is_equal(1)
	GameState.turn = 2
	Triggers.handle_engine_event(event)
	assert_int(_count("T10")).is_equal(1)  # `once` is permanent
	# The E row is silent: data/telemetry.json speaks this turn's EVENT line.
	assert_str(String(Triggers.last_event("close_requested").get("line", ""))).contains(
		"tried to close the game"
	)
	assert_str(String(_row("T10")["line"])).is_empty()


func test_close_intercept_costs_exactly_one_press() -> void:
	# docs/05 §0 rule 3 + §1.1 M01: the first close press is held once, she gets
	# the docs/05 §2 offer, and the second press always closes.
	GameState.set_meter(&"instability", 55.0)  # stage 3 == T10's data gate
	var quits := [0]
	MetaDirector.set_quit_callable(func() -> void: quits[0] += 1)
	MetaDirector._on_close_requested()
	assert_int(quits[0]).is_equal(0)
	assert_bool(bool(MetaDirector.state()["close_held"])).is_true()
	assert_array(MetaDirector.offers(3)).is_equal(["refuse_exit"])
	# The sentence is the gates data's (docs/07 §2: prompts live in data), and
	# the in-code fallback is pinned equal to it, like the memory tables.
	var offer_line := TurnSchema.opportunity_line("refuse_exit")
	assert_str(offer_line).starts_with("OPPORTUNITY (optional):")
	assert_str(offer_line).is_equal(MetaDirector.OPPORTUNITY_LINE)
	assert_array(GameState.pending_events).contains(offer_line)
	MetaDirector._on_close_requested()
	assert_int(quits[0]).is_equal(1)
	# The held request queued the offer exactly once (the stage crossing above
	# queues its own line, so count the offer, not the queue).
	assert_int(GameState.pending_events.count(offer_line)).is_equal(1)


func test_close_below_the_gate_closes_on_the_first_press() -> void:
	# docs/05 §0 rule 3: nothing is intercepted below the gate — one press quits.
	GameState.set_meter(&"instability", 35.0)  # stage 2
	var quits := [0]
	MetaDirector.set_quit_callable(func() -> void: quits[0] += 1)
	MetaDirector._on_close_requested()
	assert_int(quits[0]).is_equal(1)
	assert_bool(bool(MetaDirector.state()["close_held"])).is_false()
	assert_array(MetaDirector.offers(2)).is_empty()


func test_close_offer_is_consumed_by_the_model() -> void:
	# docs/02 §4 step 7 / docs/05 §2: one close request buys one refusal.
	GameState.set_meter(&"instability", 55.0)
	MetaDirector.set_quit_callable(func() -> void: pass)
	MetaDirector._on_close_requested()
	assert_array(MetaDirector.offers(3)).is_equal(["refuse_exit"])
	MetaDirector.execute_after_text("refuse_exit")
	assert_array(MetaDirector.offers(3)).is_empty()
	assert_bool(bool(MetaDirector.state()["exit_refused"])).is_true()
	# The offer is never re-armed by the same request.
	MetaDirector.execute_after_text("refuse_exit")
	assert_array(MetaDirector.offers(3)).is_empty()


func test_close_intercept_resets_per_session() -> void:
	# docs/05 §1.1 M01 "once per session": a new session may hold again, which
	# GameState.reset() (the Director's session boundary) drives.
	GameState.set_meter(&"instability", 55.0)
	var quits := [0]
	MetaDirector.set_quit_callable(func() -> void: quits[0] += 1)
	MetaDirector._on_close_requested()
	assert_bool(bool(MetaDirector.state()["close_held"])).is_true()
	GameState.reset()
	assert_bool(bool(MetaDirector.state()["close_held"])).is_false()
	GameState.set_meter(&"instability", 55.0)
	MetaDirector._on_close_requested()
	assert_int(quits[0]).is_equal(0)  # held again, still one press each


func test_t11_idle_starts_talking_to_herself() -> void:
	# docs/01 §5 T11: "HOLLOW +, she starts talking to herself".
	GameState.set_meter(&"instability", 35.0)  # stage 2
	Triggers.handle_engine_event({"event": "idle", "trigger": "T11", "data": {"seconds": 61}})
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_equal(2)


func test_t12_message_repeated_bumps_apathy() -> void:
	# docs/01 §5 T12: "You already said that. Are you testing me?" — a repeated
	# message is apathy evidence, and the escalating step grows it.
	Triggers.handle_engine_event(
		{"event": "message_repeated", "trigger": "T12", "data": {"count": 2}}
	)
	assert_int(int(GameState.profile.get("apathy", 0))).is_equal(1)
	GameState.turn = 1  # cooldown 1
	Triggers.handle_engine_event(
		{"event": "message_repeated", "trigger": "T12", "data": {"count": 3}}
	)
	assert_int(int(GameState.profile.get("apathy", 0))).is_equal(3)


func test_t13_lie_costs_trust_and_quotes_the_fact() -> void:
	# docs/01 §5 T13: "Trust −10, she quotes your earlier message exactly".
	Memory.consider("gave me a music box", ["I got you a music box yesterday"])
	assert_array(Memory.facts()).contains("gave me a music box")
	var lines := Triggers.begin_turn("I never gave you a music box.")
	assert_float(GameState.get_meter(&"trust")).is_equal_approx(-10.0, EPS)
	assert_int(int(GameState.profile.get("broken_promises", 0))).is_equal(1)
	# docs/01 §5 T13 quotes "your earlier message exactly": the stored fact is
	# her paraphrase, so the line carries the player's own sentence (r2 DES-2).
	assert_str(String(lines[0])).contains('"I got you a music box yesterday"')
	assert_str(String(lines[0])).not_contains("gave me a music box")
	assert_int(_count("T13")).is_equal(1)


func test_t13_needs_a_denial_and_a_shared_fact() -> void:
	# The guard is two-sided: a denial with no shared fact, and a restated fact
	# with no denial, are not contradictions. Without this, every "never" stings.
	Memory.consider("gave me a music box", ["I got you a music box yesterday"])
	assert_array(Triggers.begin_turn("I never told you that.")).is_empty()
	assert_array(Triggers.begin_turn("I gave you a music box.")).is_empty()
	# A plain opinion is not a lie (r2 CODE-3): one cue plus one shared word used
	# to cost trust −10 against a fact the player never denied.
	Memory.consider("I like music", ["I like music a lot"])
	assert_array(Triggers.begin_turn("I don't like that music.")).is_empty()
	assert_array(Triggers.begin_turn("I never said that about the music.")).is_empty()
	assert_float(GameState.get_meter(&"trust")).is_equal_approx(0.0, EPS)
	assert_int(int(GameState.profile.get("broken_promises", 0))).is_equal(0)
	# Nothing to contradict: an empty store can never fire it.
	GameState.reset()
	Memory.reset()
	Triggers.clear_engine_events()
	assert_array(Triggers.begin_turn("I never gave you a music box.")).is_empty()


func test_t14_insult_spikes_tsun() -> void:
	# docs/01 §5 T14: "TSUN/SPLIT spike, sprite 17". Model-only → half strength
	# (docs/02 §1.2), so the row's even numbers land on whole points.
	GameState.turn = 0
	Triggers.begin_turn("hello")
	GameState.turn = 1
	var lines := Triggers.close_turn("insult")
	assert_int(int(Triggers.path_scores().get("TSUN", 0))).is_equal(2)
	assert_int(int(Triggers.path_scores().get("SPLIT", 0))).is_equal(1)
	assert_int(int(GameState.flags.get("flash_sprite", 0))).is_equal(17)
	assert_str(String(lines[0])).starts_with("TRIGGER: The player insulted you")


func test_t15_ignored_question_reasks() -> void:
	# docs/01 §5 T15: "HOLLOW/SPLIT +, she re-asks, word for word" — the guard
	# reads the counter P2.12's profile bumps for the same closed turn.
	GameState.turn = 0
	Triggers.begin_turn("nothing much")
	GameState.bump_profile(&"ignored_questions", 1)
	GameState.turn = 1
	var lines := Triggers.close_turn("cold")
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_equal(2)
	assert_int(int(Triggers.path_scores().get("SPLIT", 0))).is_equal(2)
	assert_str(String(lines[0])).contains("Ask it again, word for word")
	# No ignored question this turn: the same cold reply is just cold.
	GameState.reset()
	GameState.turn = 0
	Triggers.clear_engine_events()
	Triggers.begin_turn("hello")
	GameState.turn = 1
	assert_array(Triggers.close_turn("cold")).is_empty()
	assert_int(_count("T15")).is_equal(0)


func test_turn_lines_land_where_they_are_read() -> void:
	# docs/08 §6 "this turn only": a step-0 line rides the turn that is starting
	# (the caller's ctx["events"]), while a close line is queued for the next
	# prompt — the P2.08 placement rule, pinned for P2.10's own rows.
	var lines := Triggers.begin_turn("I have to go")
	assert_array(lines).has_size(1)
	assert_array(GameState.pending_events).is_empty()
	GameState.turn = 1
	var closed := Triggers.close_turn("insult")
	assert_array(closed).has_size(1)
	assert_array(GameState.pending_events).has_size(1)
	assert_str(String(GameState.pending_events[0])).starts_with("TRIGGER: The player insulted you")


func test_close_gate_is_read_from_the_t10_row() -> void:
	# docs/07 §2: the gate is data. A catalogue whose T10 stage_min moved must
	# move the intercept with it, or MetaDirector keeps a second copy of "3".
	var doc := {
		"triggers":
		{
			"T10":
			{
				"name": "close_requested",
				"detect": {"event": ["close_requested"]},
				"stage_min": 4,
			}
		}
	}
	assert_bool(Triggers.set_catalog(doc)).is_true()
	assert_int(Triggers.stage_min_of("T10")).is_equal(4)
	assert_int(MetaDirector.close_gate()).is_equal(4)
	# An unknown id has no gate, and a catalogue that lost T10 falls back to
	# docs/05 §1.1's St 3 instead of intercepting at the wrong stage.
	assert_int(Triggers.stage_min_of("T99")).is_equal(-1)
	Triggers.set_catalog({"triggers": {}})
	assert_int(MetaDirector.close_gate()).is_equal(3)
	Triggers.load_catalog()


func test_close_offer_line_rides_every_turn_of_the_offer() -> void:
	# docs/05 §2: the OPPORTUNITY sentence appears "only on turns with an offer",
	# and docs/02 §2.4's why has to be there on every one of them. The event queue
	# drains once per submit, so the offer re-queues its sentence while it is open
	# (r2 DES-4: turn 2 kept the enum without the reason).
	GameState.set_meter(&"instability", 55.0)  # stage 3
	MetaDirector.set_quit_callable(func() -> void: pass)
	var offer_line := TurnSchema.opportunity_line("refuse_exit")
	MetaDirector._on_close_requested()
	assert_array(GameState.take_pending_events()).contains(offer_line)
	# The sentence rides every turn the offer stays open…
	assert_array(MetaDirector.offers(3)).is_equal(["refuse_exit"])
	assert_array(GameState.pending_events).contains(offer_line)
	# …and taking the offer drops it with no drain in between: the submit that
	# answers the refusal must not drain "you may set refuse_exit" into a prompt
	# whose enum is ["none"] (r3 CODE-9 — this case drained the queue first).
	MetaDirector.execute_after_text("refuse_exit")
	assert_array(MetaDirector.offers(3)).is_empty()
	assert_array(GameState.take_pending_events()).not_contains(offer_line)
	# `reset_session()` closes through the same door, so a held offer's queued
	# line cannot reach the new session either.
	MetaDirector.reset_session()
	MetaDirector._on_close_requested()
	assert_array(GameState.pending_events).contains(offer_line)
	MetaDirector.reset_session()
	assert_array(GameState.pending_events).not_contains(offer_line)


## ── Harness ───────────────────────────────────────────────────────────────


## One shipped row, canonicalized by the engine's own loader.
func _row(id: String) -> Dictionary:
	TriggerEngine.clear_cache()
	return TriggerEngine.default_table()["triggers"].get(id, {}) as Dictionary


func _count(id: String) -> int:
	return int((Triggers.report()["counts"] as Dictionary).get(id, 0))
