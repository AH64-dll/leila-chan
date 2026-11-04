extends GdUnitTestSuite
## P2.03 — the facade's stage-change steering glue (docs/06 §4): a crossing maps to
## the stage's dose and the shipped vectors, the transition's own duration is the
## glitch window, and a failed or attached relaunch keeps the old dose. The
## transport's relaunch is LlamaServerSteeringTest.gd; the live timing is
## LlamaServerLiveTest.gd.

const LLMScript := preload("res://autoload/LLM.gd")
const FakeBackend := preload("res://tests/helpers/FakeLLMBackend.gd")
const Steer := preload("res://llm/StageSteering.gd")


func _new_llm(transport: Variant) -> Node:
	var llm: Node = auto_free(LLMScript.new())
	add_child(llm)
	if transport != null:
		llm.set_backend(transport)
	return llm


## P2.03: a crossing binds the stage's dose by relaunching the server with the
## shipped vectors, inside the transition's own glitch window (docs/06 §4). The
## facade does the mapping; the transport does the relaunch.
func test_stage_transition_binds_the_dose_inside_the_glitch_window() -> void:
	var backend := FakeBackend.new()
	backend.steering_ok = true
	var llm := _new_llm(backend)
	var reports := []
	llm.steering_applied.connect(func(info: Dictionary) -> void: reports.append(info))

	llm._on_stage_transition(2, 3, {"duration_s": 2.5})

	assert_array(backend.steering_calls).has_size(1)
	var call: Dictionary = backend.steering_calls[0]
	assert_int(int(call["stage"])).is_equal(3)
	assert_int(int(call["window_ms"])).is_equal(2500)
	var vectors: Array = call["vectors"]
	assert_int(vectors.size()).is_equal(1)
	assert_str(String(vectors[0]["path"])).ends_with("data/steering/malice.gguf")
	assert_float(float(vectors[0]["scale"])).is_equal(4.5)

	await get_tree().process_frame
	assert_int(reports.size()).is_equal(1)
	assert_bool(bool(reports[0]["ok"])).is_true()
	assert_float(float(llm.get_dose()["malice"])).is_equal(4.5)
	assert_float(float(llm.last_steering_info()["dose"]["malice"])).is_equal(4.5)


## CODE-1/DES-1: an unusable vector map must keep the old dose instead of moving
## the stage bookkeeping. Before the fix `launch_for()` returned `ok` with an
## empty `vectors` list, `_same_vectors([], [])` matched a fresh boot, and the
## game recorded a dose the server never bound.
func test_an_unusable_vector_map_keeps_the_old_dose() -> void:
	var backend := FakeBackend.new()
	backend.steering_ok = true
	var llm := _new_llm(backend)
	# An empty mapper stands in for a missing/unreadable vectors.json: the loader
	# leaves both tables empty, so no key is mapped or declared unbound.
	llm._steering = Steer.new()
	var reports := []
	llm.steering_applied.connect(func(info: Dictionary) -> void: reports.append(info))

	assert_bool(llm.apply_stage_steering(3, 2500)).is_false()
	await get_tree().process_frame

	assert_bool(llm.get_dose().is_empty()).is_true()
	assert_array(backend.steering_calls).is_empty()
	assert_int(reports.size()).is_equal(1)
	assert_bool(bool(reports[0]["ok"])).is_false()
	assert_str(String(reports[0]["error"]["code"])).is_equal("control_vector_unmapped")
	assert_array(reports[0]["previous_vectors"]).is_empty()


## AC "failure → keep old dose + log": the dose map must keep describing the
## server that is actually running, not the one the schedule wanted.
func test_a_failed_relaunch_keeps_the_old_dose() -> void:
	var backend := FakeBackend.new()
	var llm := _new_llm(backend)
	var reports := []
	llm.steering_applied.connect(func(info: Dictionary) -> void: reports.append(info))

	llm.apply_stage_steering(3, 2500)
	await get_tree().process_frame
	assert_float(float(llm.get_dose()["malice"])).is_equal(4.5)

	backend.steering_ok = false
	backend.steering_error = {"code": "server_start_timeout", "message": "no health"}
	assert_bool(llm.apply_stage_steering(4, 2500)).is_true()
	await get_tree().process_frame

	assert_float(float(llm.get_dose()["malice"])).is_equal(4.5)
	assert_bool(bool(llm.last_steering_info()["ok"])).is_false()
	assert_str(String(llm.last_steering_info()["error"]["code"])).is_equal("server_start_timeout")
	assert_bool(bool(llm.last_steering_info()["kept_previous"])).is_true()
	assert_int(reports.size()).is_equal(2)
	assert_bool(bool(reports[1]["ok"])).is_false()


## Latest wins: a second crossing while the first relaunch runs must not be
## dropped — it is queued and bound the moment the running one reports.
func test_a_dose_arriving_during_a_relaunch_is_applied_after_it() -> void:
	var backend := FakeBackend.new()
	backend.steering_hold = true
	var llm := _new_llm(backend)

	assert_bool(llm.apply_stage_steering(3, 2500)).is_true()
	assert_bool(llm.apply_stage_steering(4, 2500)).is_true()
	assert_array(backend.steering_calls).has_size(1)

	backend.finish_steering(true)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_array(backend.steering_calls).has_size(2)
	assert_int(int(backend.steering_calls[1]["stage"])).is_equal(4)
	backend.finish_steering(true)
	await get_tree().process_frame
	assert_float(float(llm.get_dose()["malice"])).is_equal(6.0)


func test_rebinding_the_same_dose_does_not_relaunch() -> void:
	var backend := FakeBackend.new()
	var llm := _new_llm(backend)

	llm.apply_stage_steering(3, 2500)
	await get_tree().process_frame
	assert_array(backend.steering_calls).has_size(1)

	# Same stage, same vectors: the glitch has nothing to hide, so no relaunch.
	assert_bool(llm.apply_stage_steering(3, 2500)).is_true()
	await get_tree().process_frame
	assert_array(backend.steering_calls).has_size(1)
	assert_float(float(llm.get_dose()["malice"])).is_equal(4.5)


## A New Game / restore is the non-glitch path: stage 0 binds no vector, so the
## server goes back to a clean persona instead of carrying the last run's dose.
func test_state_reset_rebinds_the_restored_stage_without_a_glitch() -> void:
	var backend := FakeBackend.new()
	var llm := _new_llm(backend)
	llm.apply_stage_steering(4, 2500)
	await get_tree().process_frame
	assert_float(float(llm.get_dose()["malice"])).is_equal(6.0)

	GameState.reset()
	llm._on_state_reset()
	await get_tree().process_frame

	assert_array(backend.steering_calls).has_size(2)
	assert_int(int(backend.steering_calls[1]["stage"])).is_equal(0)
	assert_int(int(backend.steering_calls[1]["window_ms"])).is_equal(0)
	assert_array(backend.steering_calls[1]["vectors"]).is_empty()
	assert_float(float(llm.get_dose()["malice"])).is_equal(0.0)


## The stage machine is wired to the facade autoload, not to every facade a test
## or tool instantiates (a second listener would relaunch the server twice).
func test_the_autoload_listens_to_the_stage_machine() -> void:
	var autoload := get_node_or_null("/root/LLM")
	assert_bool(autoload != null).is_true()
	(
		assert_bool(
			GameState.is_connected(&"stage_transition", Callable(autoload, "_on_stage_transition"))
		)
		. is_true()
	)
	(
		assert_bool(GameState.is_connected(&"state_reset", Callable(autoload, "_on_state_reset")))
		. is_true()
	)
	var fresh := _new_llm(null)
	(
		assert_bool(
			GameState.is_connected(&"stage_transition", Callable(fresh, "_on_stage_transition"))
		)
		. is_false()
	)


## Boot installs attach mode by default (P1.02), and the dose is a launch flag:
## the refusal keeps the dose and never touches somebody else's server.
func test_an_attached_transport_refuses_and_keeps_the_dose() -> void:
	var backend := LlamaServerBackend.new({"base_url": "http://127.0.0.1:9099"})
	var llm := _new_llm(backend)
	var reports := []
	llm.steering_applied.connect(func(info: Dictionary) -> void: reports.append(info))

	assert_bool(llm.apply_stage_steering(3, 2500)).is_false()
	await get_tree().process_frame

	assert_int(reports.size()).is_equal(1)
	assert_bool(bool(reports[0]["ok"])).is_false()
	assert_str(String(reports[0]["error"]["code"])).is_equal("server_not_owned")
	assert_bool(bool(reports[0]["kept_previous"])).is_true()
	assert_bool(llm.get_dose().is_empty()).is_true()
