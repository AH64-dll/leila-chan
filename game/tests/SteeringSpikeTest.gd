extends GdUnitTestSuite
## SteeringSpikeTest — docs/05 M39: the dose spike. Split out of SteeringTest.gd so
## that file stays inside gdlint's public-method cap. Covers the live spike (decay,
## clamps, the calmer ceiling), trigger intake, the after-line, the once-per-input
## player-turn sequence and the InputHook path that feeds it.

const NEUTRAL_PHRASE := "The garden looks lovely this morning."

var _saved_stage := 0


func before_test() -> void:
	# Every case starts with no spike, no waiting trigger ids and no open turn, and with
	# the trigger engine's event state cleared (as TriggersTest does).
	_saved_stage = GameState.stage
	Settings.content_level = ""
	Steering.reset_spike()
	Triggers.clear_engine_events()
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)


func after_test() -> void:
	Settings.content_level = ""
	Steering.reload_table()
	Steering.reset_spike()
	Steering.set_spikes_live(false)
	GameState.stage = _saved_stage
	Triggers.clear_engine_events()
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)


func _schedule(stage: int, extra: Dictionary = {}) -> Dictionary:
	var ctx := {"stage": stage}
	for key: Variant in extra:
		ctx[key] = extra[key]
	return Steering.schedule_for(ctx)


func _malice(dose: Dictionary) -> float:
	return float(dose.get("malice", -1.0))


## docs/05 M39: live on the native backend, a request decays 3.5 -> 1.75 -> 0, and the
## current value adds exactly to the stage-3 malice dose (4.5 + 3.5 = 8.0).
func test_live_spike_decays_and_raises_malice() -> void:
	Steering.set_spikes_live(true)
	Steering.request_spike(3.5, 2)
	var first := Steering.current_spike()
	assert_float(first).is_equal_approx(3.5, 0.0001)
	var sched := _schedule(3, {"spike": first})
	assert_float(float(sched["malice"])).is_equal_approx(8.0, 0.0001)
	Steering.advance_spike()
	assert_float(Steering.current_spike()).is_equal_approx(1.75, 0.0001)
	Steering.advance_spike()
	assert_float(Steering.current_spike()).is_equal_approx(0.0, 0.0001)


## docs/05 M39 clamps (docs/06 §3): amount into 3..4, turns into 1..2.
func test_request_spike_clamps_amount_and_turns() -> void:
	Steering.set_spikes_live(true)
	Steering.request_spike(9.0, 5)
	assert_float(Steering.current_spike()).is_equal_approx(4.0, 0.0001)
	Steering.reset_spike()
	Steering.request_spike(1.0, 1)
	assert_float(Steering.current_spike()).is_equal_approx(3.0, 0.0001)
	Steering.reset_spike()
	Steering.request_spike(3.5, 5)
	Steering.advance_spike()
	assert_float(Steering.current_spike()).is_equal_approx(1.75, 0.0001)
	Steering.advance_spike()
	assert_float(Steering.current_spike()).is_equal_approx(0.0, 0.0001)


## docs/06 §4 gate: off on the server transport. The spike is dropped from the dose,
## but spike_requested still reports the request.
func test_spike_is_dropped_when_not_live() -> void:
	Steering.set_spikes_live(false)
	Steering.request_spike(4.0, 2)
	assert_float(Steering.spike_for({"spike": 4.0})).is_equal_approx(0.0, 0.0001)
	var sched := _schedule(3, {"spike": 4.0})
	assert_float(float(sched["spike"])).is_equal_approx(0.0, 0.0001)
	assert_float(float(sched["spike_requested"])).is_equal_approx(4.0, 0.0001)


## docs/06 §3/§5: the total dose stays on the [0, 12] scale. Stage 5 malice 8 + spike 4
## + scene 3 = 15 is clamped to 12.
func test_spike_total_clamps_at_twelve_at_stage_five() -> void:
	Steering.set_spikes_live(true)
	Steering.request_spike(4.0, 1)
	var sched := _schedule(5, {"spike": Steering.current_spike(), "scene_modifier": 3.0})
	assert_float(float(sched["spike"])).is_equal_approx(4.0, 0.0001)
	assert_float(float(sched["malice"])).is_equal_approx(12.0, 0.0001)


## docs/02 §8 calmer ceiling: a live stage-5 spike is capped at the stage-3 malice
## (4.5), the same as every other stage-5 term.
func test_calmer_mode_keeps_a_stage_five_spike_at_the_stage_three_ceiling() -> void:
	Steering.set_spikes_live(true)
	Steering.request_spike(4.0, 1)
	var sched := _schedule(5, {"spike": Steering.current_spike(), "content_level": "calmer"})
	assert_float(float(sched["malice"])).is_equal_approx(4.5, 0.0001)
	assert_bool(bool(sched["calmer_capped"])).is_true()


## docs/05 M39 trigger intake: T14 at stage 3 arms; stage 2 and T01 do not; nothing
## re-arms while a spike or its cooldown runs; the cooldown clears after 8 advances.
func test_trigger_intake_is_stage_gated_and_cooled_down() -> void:
	Steering.set_spikes_live(true)
	assert_bool(Steering.on_triggers_fired(["T14"], 2)).is_false()
	assert_bool(Steering.on_triggers_fired(["T01"], 3)).is_false()
	assert_float(Steering.current_spike()).is_equal_approx(0.0, 0.0001)
	assert_bool(Steering.on_triggers_fired(["T14"], 3)).is_true()
	assert_float(Steering.current_spike()).is_equal_approx(3.5, 0.0001)
	assert_bool(Steering.on_triggers_fired(["T14"], 3)).is_false()
	for _i in 7:
		Steering.advance_spike()
	assert_bool(Steering.on_triggers_fired(["T14"], 3)).is_false()
	Steering.advance_spike()
	assert_bool(Steering.on_triggers_fired(["T14"], 3)).is_true()


## Calmer mode: no glitch or after-line for a spike its ceiling would erase.
func test_calmer_mode_arms_no_spike() -> void:
	Steering.set_spikes_live(true)
	Settings.content_level = "calmer"
	assert_bool(Steering.on_triggers_fired(["T14"], 3)).is_false()
	assert_float(Steering.current_spike()).is_equal_approx(0.0, 0.0001)


## docs/05 M39: the after-line comes once, on the turn after the last spike turn.
func test_after_line_is_owed_once_after_the_spike() -> void:
	Steering.set_spikes_live(true)
	Steering.request_spike(3.5, 2)
	assert_str(Steering.take_after_line()).is_empty()
	Steering.advance_spike()
	assert_str(Steering.take_after_line()).is_empty()
	Steering.advance_spike()
	assert_str(Steering.take_after_line()).starts_with("TRIGGER: ")
	assert_str(Steering.take_after_line()).is_empty()


## docs/05 M39 player-turn sequence: T14 arms on the first input, the spike steps once
## per later input, and the after-line comes once, on the turn after the last spike turn.
func test_on_player_turn_steps_the_spike_once_per_input() -> void:
	Steering.set_spikes_live(true)
	Steering.note_trigger_fired({"id": "T14"})
	var first := Steering.on_player_turn(3)
	assert_bool(bool(first["armed"])).is_true()
	assert_str(String(first["after_line"])).is_empty()
	assert_float(_malice(Steering.dose_for({"stage": 3}))).is_equal_approx(8.0, 0.0001)
	var second := Steering.on_player_turn(3)
	assert_bool(bool(second["armed"])).is_false()
	assert_float(_malice(Steering.dose_for({"stage": 3}))).is_equal_approx(6.25, 0.0001)
	var third := Steering.on_player_turn(3)
	assert_float(_malice(Steering.dose_for({"stage": 3}))).is_equal_approx(4.5, 0.0001)
	assert_str(String(third["after_line"])).starts_with("TRIGGER: ")
	var fourth := Steering.on_player_turn(3)
	assert_str(String(fourth["after_line"])).is_empty()
	assert_float(_malice(Steering.dose_for({"stage": 3}))).is_equal_approx(4.5, 0.0001)


## docs/05 M39: a retry rebuilds the dose without a player turn, so it never steps the
## spike. Only on_player_turn() steps it.
func test_a_retry_dose_does_not_step_the_spike() -> void:
	Steering.set_spikes_live(true)
	Steering.note_trigger_fired({"id": "T14"})
	Steering.on_player_turn(3)
	assert_float(_malice(Steering.dose_for({"stage": 3}))).is_equal_approx(8.0, 0.0001)
	assert_float(_malice(Steering.dose_for({"stage": 3}))).is_equal_approx(8.0, 0.0001)
	assert_float(Steering.current_spike()).is_equal_approx(3.5, 0.0001)


## docs/02 §4 step 0 end to end: a live T14 seen by the hook at stage 3 arms the spike.
## T14 is M-detected (detect.model "insult", fired from close_turn), so no input phrase
## fires it; the fire is fed through note_trigger_fired and a neutral phrase is submitted.
func test_input_hook_arms_the_spike_for_t14_at_stage_three() -> void:
	Steering.set_spikes_live(true)
	GameState.stage = 3
	Steering.note_trigger_fired({"id": "T14"})
	InputHook.apply(null, NEUTRAL_PHRASE, 3, {})
	assert_float(Steering.current_spike()).is_equal_approx(3.5, 0.0001)


## Not live (server transport): the same flow through the hook arms nothing.
func test_input_hook_arms_nothing_when_not_live() -> void:
	Steering.set_spikes_live(false)
	GameState.stage = 3
	Steering.note_trigger_fired({"id": "T14"})
	InputHook.apply(null, NEUTRAL_PHRASE, 3, {})
	assert_float(Steering.current_spike()).is_equal_approx(0.0, 0.0001)
	assert_float(_malice(Steering.dose_for({"stage": 3}))).is_equal_approx(4.5, 0.0001)


## Wiring: Steering takes Triggers.triggered, connected deferred from its _ready.
func test_steering_is_connected_to_the_triggers_signal() -> void:
	assert_bool(Triggers.triggered.is_connected(Steering.note_trigger_fired)).is_true()
