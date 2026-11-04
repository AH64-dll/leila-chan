extends GdUnitTestSuite
## AudioDirector contract — P1.12 v1 (docs/04 §1-§3, docs/02 §2.1/§2.2/§5).
## P2.16's stage layers/blips/gate tables live in AudioStageLayersTest.gd so each
## suite stays inside gdlint's max-public-methods. The clock is injected
## (auto_clock=false + advance_time) so the 20 s music hold and the 1.5 s
## crossfade are tested deterministically; streams load threaded and tests await
## cue_played instead of timing out on the loader.

const AudioDirectorScript := preload("res://autoload/AudioDirector.gd")

const STAGE0_CUES: Array[StringName] = [
	&"none", &"giggle", &"laugh_soft", &"gasp", &"sigh", &"hum", &"sniffle", &"heartbeat"
]


func _new_director() -> Node:
	var director: Node = auto_free(AudioDirectorScript.new())
	director.auto_clock = false
	add_child(director)
	return director


func _spy(director: Node) -> Dictionary:
	var spy := {"played": [], "denied": [], "music": [], "deferred": [], "music_denied": []}
	director.cue_played.connect(
		func(c: StringName, f: String, b: StringName) -> void: spy["played"].append([c, f, b])
	)
	director.cue_denied.connect(
		func(c: StringName, r: StringName) -> void: spy["denied"].append([c, r])
	)
	director.music_changed.connect(
		func(s: StringName, t: String) -> void: spy["music"].append([s, t])
	)
	director.music_deferred.connect(func(s: StringName) -> void: spy["deferred"].append(s))
	director.music_request_denied.connect(
		func(s: StringName, r: StringName) -> void: spy["music_denied"].append([s, r])
	)
	return spy


func _await_activity(spy: Dictionary, key: String, count := 1, timeout_ms := 6000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while spy[key].size() < count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_bool(spy[key].size() >= count).is_true().append_failure_message(
		"timed out waiting for %d %s event(s)" % [count, key]
	)


func _reset_bus_state() -> void:
	for bus: String in [&"Music", &"Ambience", &"SFX", &"Voice", &"UI"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_mute(idx, false)
			AudioServer.set_bus_volume_db(idx, 0.0)


func test_buses_created_and_exposed_for_settings() -> void:
	_reset_bus_state()
	var director := _new_director()
	assert_array(Array(director.bus_names())).contains_exactly(
		["Master", "Music", "Ambience", "SFX", "Voice", "UI"]
	)
	# docs/04 §1 topology: MusicA/MusicB are the internal crossfade pair under
	# Music and must not leak into the exposed list.
	for bus: String in ["Music", "MusicA", "MusicB", "Ambience", "SFX", "Voice", "UI"]:
		assert_int(AudioServer.get_bus_index(bus)).is_greater_equal(0).append_failure_message(
			"missing bus " + bus
		)
	assert_str(String(AudioServer.get_bus_send(AudioServer.get_bus_index("MusicA")))).is_equal(
		"Music"
	)
	assert_str(String(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")))).is_equal(
		"Master"
	)

	director.set_bus_volume_linear(&"Music", 0.5)
	assert_float(director.bus_volume_linear(&"Music")).is_equal_approx(0.5, 0.01)
	director.set_bus_volume_linear(&"Music", 0.0)
	assert_float(director.bus_volume_linear(&"Music")).is_equal_approx(0.0, 0.001)
	assert_bool(director.is_bus_muted(&"Music")).is_false().append_failure_message(
		"volume 0 must not fake a mute (T21)"
	)
	director.set_bus_mute(&"Voice", true)
	assert_bool(director.is_bus_muted(&"Voice")).is_true()
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice"))).is_true()
	director.set_bus_mute(&"Voice", false)
	_reset_bus_state()


func test_stage0_cues_resolve_through_cue_map() -> void:
	var director := _new_director()
	var spy := _spy(director)
	director.set_stage(0)
	var with_files: Array[StringName] = []
	for cue: StringName in STAGE0_CUES:
		if cue == &"none":
			continue
		var files: Array = director._cue_map["cues"][cue]["files"]
		if files.is_empty():
			# hum/sniffle are documented gaps (cue_map quality "gap"): the
			# request is legal, the pool is empty, the cue drops silently.
			director.begin_turn()
			assert_bool(director.play_cue(cue)).is_false()
			assert_str(String(director.last_cue_reject())).is_equal("gap")
			continue
		with_files.append(cue)
		var paths: Array = director._existing_paths(files, director._cue_category(cue))
		assert_array(paths).has_size(files.size()).append_failure_message(
			"cue %s has unimported files" % cue
		)
	assert_array(with_files).contains_exactly(
		[&"giggle", &"laugh_soft", &"gasp", &"sigh", &"heartbeat"]
	)

	# The budget (1 cue / 2 turns) is recharged between real plays.
	director.begin_turn()
	assert_bool(director.play_cue(&"heartbeat")).is_true()
	await _await_activity(spy, "played")
	assert_str(String(spy["played"][0][0])).is_equal("heartbeat")
	assert_str(String(spy["played"][0][2])).is_equal("SFX")


func test_cue_vocal_routing_and_system_key() -> void:
	var director := _new_director()
	var spy := _spy(director)
	director.set_stage(0)
	director.begin_turn()
	assert_bool(director.play_cue(&"giggle")).is_true()
	await _await_activity(spy, "played")
	assert_str(String(spy["played"][0][0])).is_equal("giggle")
	assert_str(String(spy["played"][0][2])).is_equal("Voice")

	director.begin_turn()
	assert_bool(director.play_system(&"voice_blip.stage0_2")).is_true()
	await _await_activity(spy, "played", 2)
	var blip: Array = spy["played"].back()
	assert_str(String(blip[2])).is_equal("Voice")
	assert_bool(director.play_system(&"bogus.key")).is_false()


func test_unknown_gated_and_gap_cues_denied() -> void:
	var director := _new_director()
	director.set_stage(0)
	director.begin_turn()
	assert_bool(director.play_cue(&"bogus_cue")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("unknown")
	assert_bool(director.play_cue(&"sob")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("gated")
	assert_bool(director.play_cue(&"scream")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("gated")
	assert_bool(director.play_cue(&"none")).is_true().append_failure_message(
		"'none' must be an accepted no-op"
	)


func test_cue_budget_stage0_one_per_two_turns() -> void:
	var director := _new_director()
	director.set_stage(0)
	director.begin_turn()
	assert_bool(director.play_cue(&"giggle")).is_true()
	assert_bool(director.play_cue(&"sigh")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("budget")
	director.begin_turn()
	assert_bool(director.play_cue(&"sigh")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("budget")
	director.begin_turn()
	assert_bool(director.play_cue(&"sigh")).is_true()


func test_cue_repeat_window_four_turns() -> void:
	var director := _new_director()
	director.set_stage(0)
	director.begin_turn()
	assert_bool(director.play_cue(&"heartbeat")).is_true()
	for i in 3:
		director.begin_turn()
		assert_bool(director.play_cue(&"heartbeat")).is_false()
		assert_str(String(director.last_cue_reject())).is_equal("repeat_window")
	# Turn +4: the window lifts and the budget has recharged.
	director.begin_turn()
	assert_bool(director.play_cue(&"heartbeat")).is_true()


func test_silence_rule_drops_cues_at_stage3() -> void:
	var director := _new_director()
	director.set_stage(3)
	director.begin_turn()
	director._silence_this_turn = true
	assert_bool(director.play_cue(&"giggle")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("silence")


func test_knife_draw_requires_sprite_and_scream_session_cap() -> void:
	var director := _new_director()
	director.set_stage(4)
	director.begin_turn()
	director._silence_this_turn = false
	assert_bool(director.play_cue(&"knife_draw")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("requires_sprite")
	director.note_sprite(&"99")
	assert_bool(director.play_cue(&"knife_draw")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("requires_sprite")
	director.note_sprite(&"21")
	assert_bool(director.play_cue(&"knife_draw")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("no_files").append_failure_message(
		"sprite gate passed; only the unimported v1 asset is missing"
	)

	director.set_stage(5)
	director._session_counts[&"scream"] = 1
	assert_bool(director.play_cue(&"scream")).is_false()
	assert_str(String(director.last_cue_reject())).is_equal("session_cap")


func test_music_min_hold_and_one_change_per_turn() -> void:
	var director := _new_director()
	var spy := _spy(director)
	director.set_stage(0)
	director.begin_turn()
	assert_bool(director.request_music(&"romantic")).is_true()
	assert_str(String(director.current_music())).is_equal("romantic")

	# Second request same turn: slot closed -> deferred, not applied.
	assert_bool(director.request_music(&"calm")).is_true()
	assert_str(String(director.current_music())).is_equal("romantic")
	assert_str(String(director.pending_music())).is_equal("calm")
	director.begin_turn()
	assert_str(String(director.current_music())).is_equal("romantic").append_failure_message(
		"20 s hold must block the queued change"
	)
	assert_str(String(director.pending_music())).is_equal("calm")

	director.advance_time(20.0)
	director.begin_turn()
	assert_str(String(director.current_music())).is_equal("calm")
	assert_str(String(director.pending_music())).is_equal("")

	# A legal-turn request inside the hold window defers until the hold ends.
	assert_bool(director.request_music(&"playful")).is_true()
	assert_str(String(director.pending_music())).is_equal("playful")
	director.advance_time(20.0)
	director.begin_turn()
	assert_str(String(director.current_music())).is_equal("playful")


func test_music_silence_cuts_instantly() -> void:
	var director := _new_director()
	director.set_stage(0)
	director.begin_turn()
	director.request_music(&"romantic")
	director.advance_time(20.0)
	director.set_stage(2)
	director.begin_turn()
	assert_bool(director.request_music(&"silence")).is_true()
	assert_str(String(director.current_music())).is_equal("silence")
	for player: AudioStreamPlayer in director._music_players:
		assert_bool(player.playing).is_false()
	assert_dict(director._active_fade).is_empty()


func test_music_gate_boundaries_and_stage_layer_playback() -> void:
	var director := _new_director()
	var spy := _spy(director)
	director.set_stage(0)
	director.begin_turn()
	assert_bool(director.request_music(&"dread")).is_false()
	assert_bool(director.request_music(&"bogus")).is_false()
	assert_array(spy["music_denied"]).contains_exactly(
		[[&"dread", &"gated"], [&"bogus", &"unknown"]]
	)
	# docs/04 §8.3: the stage 2-5 tense band is imported, so the docs/02 §2.2
	# stage-2 gate opening now resolves to a real track (was a v1 no_files).
	director.set_stage(2)
	director.begin_turn()
	assert_bool(director.request_music(&"tense")).is_true()
	assert_str(String(director.current_music())).is_equal("tense")
	var track := String(spy["music"][0][1])
	(
		assert_bool(track.contains("music_insistent") or track.contains("glitchstairs"))
		. is_true()
		. append_failure_message("unexpected tense layer track: " + track)
	)


func test_music_keep_restores_scene_default_after_three_turns() -> void:
	var director := _new_director()
	director.set_stage(0)
	director.set_scene_music(&"romantic")
	assert_str(String(director.current_music())).is_equal("romantic")
	director.advance_time(20.0)
	director.begin_turn()
	assert_bool(director.request_music(&"playful")).is_true()
	assert_str(String(director.current_music())).is_equal("playful")

	director.advance_time(20.0)
	for i in 2:
		director.begin_turn()
		director.request_music(&"keep")
		assert_str(String(director.current_music())).is_equal("playful")
	director.begin_turn()
	director.request_music(&"keep")
	assert_str(String(director.current_music())).is_equal("romantic").append_failure_message(
		"3 keeps must restore the scene default (docs/04 §2)"
	)


func test_music_crossfade_swaps_players() -> void:
	var director := _new_director()
	director.crossfade_seconds = 2.0
	director.set_stage(0)
	director.begin_turn()
	director.request_music(&"romantic")
	var first: AudioStreamPlayer = null
	var deadline := Time.get_ticks_msec() + 8000
	while first == null and Time.get_ticks_msec() < deadline:
		for player: AudioStreamPlayer in director._music_players:
			if player.stream != null:
				first = player
		await get_tree().process_frame
	assert_object(first).is_not_null().append_failure_message("romantic track never loaded")
	assert_bool(first.playing).is_true()

	director.advance_time(20.0)
	director.begin_turn()
	director.request_music(&"calm")
	var second: AudioStreamPlayer = null
	deadline = Time.get_ticks_msec() + 8000
	while second == null and Time.get_ticks_msec() < deadline:
		for player: AudioStreamPlayer in director._music_players:
			if player != first and player.stream != null:
				second = player
		await get_tree().process_frame
	assert_object(second).is_not_null().append_failure_message("calm track never loaded")

	# Mid-fade: both audible; end of the injected 2 s fade: first stopped.
	director.advance_time(2.0)
	assert_bool(first.playing).is_false()
	assert_bool(second.playing).is_true()
	assert_float(second.volume_db).is_greater(-1.0)
