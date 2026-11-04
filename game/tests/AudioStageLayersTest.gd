extends GdUnitTestSuite
## P2.16 — AudioDirector stage layers (docs/04 §2 drift, §7 blips, §8.3 track
## map; docs/02 §2.1/§2.2 gates, §5 silence rule; docs/10 §5 voice by stage).
## Split from AudioDirectorTest.gd to keep each suite's public method count
## under gdlint's max-public-methods (20); the clock is injected the same way.

const AudioDirectorScript := preload("res://autoload/AudioDirector.gd")

## docs/04 §8.3 state × stage track map: the stages a state's bands cover.
const MUSIC_LAYER_STAGES := {
	"romantic": [0, 1, 2, 3, 4, 5],
	"playful": [0, 1, 2, 3, 4, 5],
	"calm": [0, 1, 2, 3, 4, 5],
	"melancholy": [0, 1, 2, 3, 4, 5],
	"tense": [2, 3, 4, 5],
	"music_box": [2, 3, 4, 5],
	"dread": [4, 5],
	"distorted": [4, 5],
}

## docs/02 §2.1 cue gates (the stage every cue unlocks at).
const CUE_GATES := {
	"giggle": 0,
	"laugh_soft": 0,
	"gasp": 0,
	"sigh": 0,
	"hum": 0,
	"sniffle": 0,
	"sob": 1,
	"heartbeat": 0,
	"heartbeat_fast": 2,
	"whisper": 2,
	"breath_close": 3,
	"music_box_note": 1,
	"clock_tick": 1,
	"phone_buzz": 1,
	"knock": 2,
	"door_slam": 3,
	"glass_shatter": 3,
	"static": 3,
	"laugh_unhinged": 4,
	"knife_draw": 4,
	"scream": 5,
}

## docs/02 §2.2 music gates. dread/distorted are 4 here, not 3: docs/04 §8.3
## has no track for them before stage 4 (DCR P2.16-1); the audio gate follows
## the track map so a state can never be legal without a layer to play.
const MUSIC_GATES := {
	"romantic": 0,
	"playful": 0,
	"calm": 0,
	"melancholy": 0,
	"tense": 2,
	"music_box": 2,
	"dread": 4,
	"distorted": 4,
	"silence": 2,
}


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


func _effect_index(bus_idx: int, klass: String) -> int:
	for i: int in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i).get_class() == klass:
			return i
	return -1


func _clear_cue_history(director: Node) -> void:
	director._cue_last_turn.clear()
	director._cue_counts.clear()
	director._session_counts.clear()
	director._cue_last_file.clear()


func _arm_cue_turn(director: Node) -> void:
	director.begin_turn()
	director._silence_this_turn = false
	director._cue_tokens = 99.0
	director._last_cue_reject = &""


func _await_size(items: Array, count: int, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while items.size() < count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_int(items.size()).is_greater_equal(count)


## docs/04 §8.3 + acceptance criterion 1: every music state has a cue_map
## entry and resolves a track at every stage its layer covers — and only there.
func test_every_music_state_maps_to_its_stage_bands() -> void:
	var director := _new_director()
	var music: Dictionary = director._cue_map["music"]
	var gates: Dictionary = director._rules["music_gates"]
	for state: String in MUSIC_LAYER_STAGES:
		assert_bool(music.has(state)).is_true().append_failure_message(
			"docs/04 §8.3 state %s has no cue_map entry" % state
		)
		var covered: Array = MUSIC_LAYER_STAGES[state]
		assert_int(int(gates.get(state, -1))).is_equal(int(covered[0])).append_failure_message(
			"audio gate for %s must match its first track stage" % state
		)
		for stage: int in 6:
			director.set_stage(stage)
			var band: Array = director._band_files(music[state])
			if covered.has(stage):
				assert_array(band).is_not_empty().append_failure_message(
					"%s @ stage %d must resolve a track" % [state, stage]
				)
			else:
				assert_array(band).is_empty().append_failure_message(
					"%s @ stage %d must not resolve a track" % [state, stage]
				)
	# `silence` is the one state with no track (docs/04 §2): its cue_map row
	# exists with an empty pool so the mapping stays complete, and the player
	# cuts instantly instead of crossfading.
	assert_bool(music.has("silence")).is_true()
	director.set_stage(2)
	assert_array(director._band_files(music["silence"])).is_empty()


func test_music_layer_selection_follows_stage_band() -> void:
	var director := _new_director()
	var spy := _spy(director)
	director.set_stage(3)
	director.begin_turn()
	assert_bool(director.request_music(&"romantic")).is_true()
	var track := String(spy["music"][0][1])
	assert_bool(track.contains("apple_cider") or track.contains("ice_cream_date")).is_true()
	assert_bool(track.contains("flowerbed_fields")).is_false().append_failure_message(
		"the 0-1-only romantic track leaked into stage 3"
	)

	# 4-5 melancholy is the music box arrangement, not the lullaby.
	director.advance_time(20.0)
	director.set_stage(4)
	director.begin_turn()
	assert_bool(director.request_music(&"melancholy")).is_true()
	assert_bool(String(spy["music"][1][1]).contains("musicbox3_sad_tune")).is_true()

	# docs/04 §8.3 has no dread before stage 4, so the audio gate holds it back
	# even though docs/02 §2.2 offers it at 3 (DCR P2.16-1).
	director.advance_time(20.0)
	director.set_stage(3)
	director.begin_turn()
	assert_bool(director.request_music(&"dread")).is_false()
	assert_str(String(spy["music_denied"].back()[1])).is_equal("gated")
	director.set_stage(4)
	director.begin_turn()
	assert_bool(director.request_music(&"dread")).is_true()
	assert_str(String(director.current_music())).is_equal("dread")


## docs/04 §2 stage drift, read back from the Music bus itself.
func test_stage_dsp_drift_matches_docs() -> void:
	var director := _new_director()
	var bus := AudioServer.get_bus_index("Music")
	var pitch_idx := _effect_index(bus, "AudioEffectPitchShift")
	var lowpass_idx := _effect_index(bus, "AudioEffectLowPassFilter")
	var distortion_idx := _effect_index(bus, "AudioEffectDistortion")
	var reverb_idx := _effect_index(bus, "AudioEffectReverb")
	assert_int(pitch_idx).is_greater_equal(0)
	assert_int(lowpass_idx).is_greater_equal(0)
	assert_int(distortion_idx).is_greater_equal(0)
	assert_int(reverb_idx).is_greater_equal(0)
	var pitch := AudioServer.get_bus_effect(bus, pitch_idx) as AudioEffectPitchShift
	var lowpass := AudioServer.get_bus_effect(bus, lowpass_idx) as AudioEffectLowPassFilter
	var distortion := AudioServer.get_bus_effect(bus, distortion_idx) as AudioEffectDistortion
	var reverb := AudioServer.get_bus_effect(bus, reverb_idx) as AudioEffectReverb

	director.set_stage(0)
	assert_float(pitch.pitch_scale).is_equal_approx(1.0, 0.0001)
	assert_bool(AudioServer.is_bus_effect_enabled(bus, lowpass_idx)).is_false()
	assert_bool(AudioServer.is_bus_effect_enabled(bus, distortion_idx)).is_false()
	assert_bool(AudioServer.is_bus_effect_enabled(bus, reverb_idx)).is_false()

	director.set_stage(2)
	assert_float(pitch.pitch_scale).is_equal_approx(pow(2.0, -10.0 / 1200.0), 0.0001)
	assert_bool(AudioServer.is_bus_effect_enabled(bus, lowpass_idx)).is_true()
	assert_float(lowpass.cutoff_hz).is_equal_approx(12000.0, 1.0)

	director.set_stage(5)
	assert_float(pitch.pitch_scale).is_equal_approx(pow(2.0, -25.0 / 1200.0), 0.0001)
	assert_float(lowpass.cutoff_hz).is_equal_approx(9000.0, 1.0)
	assert_bool(AudioServer.is_bus_effect_enabled(bus, distortion_idx)).is_true()
	assert_float(distortion.drive).is_equal_approx(0.25, 0.001)
	assert_bool(AudioServer.is_bus_effect_enabled(bus, reverb_idx)).is_true()
	assert_float(reverb.wet).is_equal_approx(0.28, 0.001)

	director.set_stage(3)
	assert_bool(AudioServer.is_bus_effect_enabled(bus, distortion_idx)).is_false()
	assert_float(reverb.wet).is_equal_approx(0.08, 0.001)


## docs/04 §7 + docs/10 §5: the blip pool switches with the stage, AWAKE
## overrides from stage 3, and stage 5 is 30% demon under the stage-4 whispers.
func test_voice_blip_pool_switches_by_stage() -> void:
	var director := _new_director()
	assert_str(String(director._blip_key(0, &""))).is_equal("voice_blip.stage0_2")
	assert_str(String(director._blip_key(1, &""))).is_equal("voice_blip.stage0_2")
	assert_str(String(director._blip_key(2, &""))).is_equal("voice_blip.stage0_2")
	assert_str(String(director._blip_key(3, &""))).is_equal("voice_blip.stage3")
	assert_str(String(director._blip_key(4, &""))).is_equal("voice_blip.stage4")
	assert_str(String(director._blip_key(2, &"AWAKE"))).is_equal("voice_blip.stage0_2")
	assert_str(String(director._blip_key(3, &"AWAKE"))).is_equal("voice_blip.awake")
	assert_str(String(director._blip_key(5, &"AWAKE"))).is_equal("voice_blip.awake")

	director.set_rng_seed(42)
	var demon := 0
	var base := 0
	for i: int in 600:
		var key: StringName = director._blip_key(5, &"")
		if key == &"voice_blip.stage5":
			demon += 1
		elif key == &"voice_blip.stage4":
			base += 1
	assert_int(demon + base).is_equal(600)
	assert_float(float(demon) / 600.0).is_between(0.2, 0.4)


func _find_blip(items: Array, key: String) -> Array:
	for entry: Variant in items:
		if String((entry as Array)[0]) == key:
			return entry as Array
	return []


func test_text_blip_plays_stage_pool_pitched_by_feeling() -> void:
	var director := _new_director()
	var played: Array = []
	director.voice_blip_played.connect(
		func(key: StringName, _file: String, pitch: float, gain: float) -> void:
			played.append([String(key), pitch, gain])
	)
	# Cadence (docs/04 §4): one soft blip every 2-3 revealed characters, so
	# four characters must trigger at least one.
	var triggered := 0
	for i: int in 4:
		if director.text_blip(&"joy", 0, &""):
			triggered += 1
	assert_int(triggered).is_greater_equal(1)
	await _await_size(played, 1)
	var joy := _find_blip(played, "voice_blip.stage0_2")
	assert_array(joy).is_not_empty()
	assert_float(float(joy[1])).is_equal_approx(pow(2.0, 0.25), 0.001)
	assert_float(float(joy[2])).is_equal_approx(0.0, 0.001)

	# docs/04 §4: `empty` has no voice spec — she speaks in silence.
	for i: int in 12:
		assert_bool(director.text_blip(&"empty", 3, &"")).is_false()
	# angry: +1 st and louder (docs/04 §4; casting.json gain_db 3). Streams
	# resolve asynchronously, so wait for the stage-3 blip by key, not index
	# (a cadence can emit two blips for four characters; a late joy blip must
	# never be read as the angry one).
	for i: int in 4:
		director.text_blip(&"angry", 3, &"")
	var angry: Array = []
	var deadline := Time.get_ticks_msec() + 8000
	while angry.is_empty() and Time.get_ticks_msec() < deadline:
		angry = _find_blip(played, "voice_blip.stage3")
		if angry.is_empty():
			await get_tree().process_frame
	assert_array(angry).is_not_empty()
	assert_float(float(angry[1])).is_equal_approx(pow(2.0, 1.0 / 12.0), 0.001)
	assert_float(float(angry[2])).is_equal_approx(3.0, 0.001)


## docs/02 §2.1: every cue is refused one stage below its gate and accepted
## (or dies for its own asset reason) from the gate up.
func test_cue_gates_match_docs_and_hold_boundaries() -> void:
	var director := _new_director()
	var gates: Dictionary = director._rules["cue_gates"]
	for cue: String in CUE_GATES:
		var gate: int = CUE_GATES[cue]
		assert_int(int(gates.get(cue, -1))).is_equal(gate).append_failure_message(
			"cue gate for %s differs from docs/02 §2.1" % cue
		)
		if gate > 0:
			_clear_cue_history(director)
			director.set_stage(gate - 1)
			_arm_cue_turn(director)
			assert_bool(director.play_cue(StringName(cue))).is_false().append_failure_message(
				"%s must be gated at stage %d" % [cue, gate - 1]
			)
			assert_str(String(director.last_cue_reject())).is_equal("gated")
		_clear_cue_history(director)
		director.set_stage(gate)
		_arm_cue_turn(director)
		director.play_cue(StringName(cue))
		assert_str(String(director.last_cue_reject())).is_not_equal("gated").append_failure_message(
			"%s must pass its stage-%d gate" % [cue, gate]
		)


func test_music_gates_match_docs_and_deny_below_gate() -> void:
	var director := _new_director()
	var spy := _spy(director)
	var gates: Dictionary = director._rules["music_gates"]
	for state: String in MUSIC_GATES:
		var gate: int = MUSIC_GATES[state]
		assert_int(int(gates.get(state, -1))).is_equal(gate)
		if gate <= 0:
			continue
		director.set_stage(gate - 1)
		director.begin_turn()
		assert_bool(director.request_music(StringName(state))).is_false()
		assert_str(String(spy["music_denied"].back()[1])).is_equal("gated")


## docs/02 §5: at stage >= 3, 10% of turns drop all cues; below stage 3 the
## rule never fires. Seeded RNG keeps the measurement deterministic.
func test_silence_rule_is_ten_percent_at_stage3_only() -> void:
	var director := _new_director()
	director.set_rng_seed(2026)
	director.set_stage(3)
	var turns := 2000
	var drops := 0
	for i: int in turns:
		director.begin_turn()
		if director._silence_this_turn:
			drops += 1
	var rate := float(drops) / float(turns)
	print("P2.16 silence rule: %d/%d turns dropped (%.4f)" % [drops, turns, rate])
	assert_float(rate).is_between(0.07, 0.13).append_failure_message(
		"docs/02 §5 silence rate at stage 3 was %.3f" % rate
	)

	director.set_stage(2)
	for i: int in 300:
		director.begin_turn()
		assert_bool(director._silence_this_turn).is_false()

	# A silence turn drops every cue, whatever its gate or pool.
	director.set_stage(3)
	director.begin_turn()
	director._silence_this_turn = true
	for cue: String in ["giggle", "heartbeat", "static", "whisper"]:
		director._cue_tokens = 99.0
		director._last_cue_reject = &""
		assert_bool(director.play_cue(StringName(cue))).is_false()
		assert_str(String(director.last_cue_reject())).is_equal("silence")


## docs/02 §5 cue budget bands: 0-1 = 1 per 2 turns, 2-3 = 1 per turn,
## 4-5 = 2 per turn. The first turn of a director starts at the band cap.
func test_cue_budget_band_by_stage() -> void:
	var cues: Array[StringName] = [&"giggle", &"sigh", &"gasp", &"laugh_soft"]
	for case: Dictionary in [
		{"stage": 1, "expected": 1},
		{"stage": 2, "expected": 1},
		{"stage": 3, "expected": 1},
		{"stage": 4, "expected": 2},
		{"stage": 5, "expected": 2},
	]:
		var director := _new_director()
		director.set_stage(int(case["stage"]))
		director.begin_turn()
		director._silence_this_turn = false
		var played := 0
		for cue: StringName in cues:
			if director.play_cue(cue):
				played += 1
		assert_int(played).is_equal(int(case["expected"])).append_failure_message(
			"stage %d budget allowed %d cues" % [int(case["stage"]), played]
		)
