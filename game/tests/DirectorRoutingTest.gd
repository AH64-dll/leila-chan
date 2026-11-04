extends GdUnitTestSuite
## DirectorRoutingTest — acceptance criterion 1 of P1.08 (docs/02 §4 step 5):
## "a full turn drives sprite, cue, music, fx and typewriter through signals".
##
## DirectorTest covers the turn lifecycle and DirectorFallbackTest the §7
## recoveries; this suite is the routing evidence. It registers fakes for every
## subsystem the Director talks to (character, chat UI, audio, fx, safety) and
## asserts, per recorded stream, which call each event produced — plus the
## findings that are only visible from the routing side (single sprite
## resolution, single safety scan, stage hand-off, flags).
##
## Split from DirectorTest.gd because gdlint caps a suite at 20 public methods.

const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const FakeSafetyScript := preload("res://tests/helpers/FakeSafetyFilter.gd")
const TEST_DEBUG_DIR := "user://debug_director_routing_test/"
const FIXTURE_DIR := "res://tests/fixtures/streams/"

var _fake_backend: RefCounted
var _safety: Node

## ── Fakes ─────────────────────────────────────────────────────────────────


## Records every Character call the Director makes. `apply_beat` is the
## Director's single-resolution entry point; `set_feeling` is the fallback a
## resolver-less consumer uses.
class FakeCharacter:
	extends Node
	var packets: Array = []
	var feelings: Array = []
	var sprites: Array = []

	func apply_beat(packet: Dictionary) -> void:
		packets.append(packet)

	func set_feeling(feeling: String, intensity: int, stage: int, path := "", flags := {}) -> void:
		feelings.append([feeling, intensity, stage, path, flags])

	func set_sprite(sprite_id: String, _instant := false) -> void:
		sprites.append(sprite_id)


## Records the ChatUI half of the docs/02 §4 step 5 stream, including the text
## the typewriter would consume.
class FakeChatUI:
	extends Node
	var chunks: Array = []
	var beats_started: Array = []
	var beats_ended: Array = []
	var replacements: Array = []
	var turn_wait := 0
	var turns_ended := 0
	var aborts := 0
	var filter_installed := false
	## The docs/07 §3.4 seam. The Director must leave it unset (review CODE-1).
	var text_filter: Callable = Callable()

	func begin_turn_wait() -> void:
		turn_wait += 1

	func begin_beat(beat_index: int) -> void:
		beats_started.append(beat_index)

	func say_chunk(beat_index: int, chunk: String) -> void:
		chunks.append([beat_index, chunk])

	func replace_beat(beat_index: int, text: String) -> void:
		replacements.append([beat_index, text])

	func end_beat(beat_index: int) -> void:
		beats_ended.append(beat_index)

	func end_turn() -> void:
		turns_ended += 1

	func abort_turn() -> void:
		aborts += 1


func before_test() -> void:
	GameState.reset()
	GameState.stage = 0
	GameState.instability = 0.0
	GameState.instability_peak = 0.0
	GameState.turn = 0
	GameState.player_name = "Senpai"
	GameState.flags.clear()

	Director.reset()
	_fake_backend = FakeLLMBackendScript.new()
	LLM.set_backend(_fake_backend)

	_safety = FakeSafetyScript.new()
	add_child(_safety)
	Director._safety.set_filter(_safety)
	AudioDirector.set_stage(0)
	AudioDirector.begin_turn()
	FX.reset()

	if Director.transcript_logger != null:
		Director.transcript_logger.configure({"debug_dir": TEST_DEBUG_DIR})
		_clean_test_dir(TEST_DEBUG_DIR)


func after_test() -> void:
	Director.reset()
	Director.register_character(null)
	Director.register_chat_ui(null)
	Director._safety.set_filter(Safety)
	GameState.reset()
	FX.reset()
	_safety.queue_free()
	if Director.transcript_logger != null:
		Director.transcript_logger.end_session()
	_clean_test_dir(TEST_DEBUG_DIR)


## ── Helpers ───────────────────────────────────────────────────────────────


func _await_until(predicate: Callable, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _clean_test_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d != null:
		for f: String in d.get_files():
			DirAccess.remove_absolute(path.path_join(f))
		DirAccess.remove_absolute(path)


func _fixture_text(name: String) -> String:
	var file := FileAccess.open(FIXTURE_DIR + name, FileAccess.READ)
	assert_object(file).is_not_null()
	var text := file.get_as_text()
	file.close()
	return text


## Runs one turn from a recorded stream and returns every signal the Director
## emitted, in order, as [name, payload] pairs.
func _run_fixture(name: String, character: FakeCharacter, chat: FakeChatUI) -> Array:
	_fake_backend.chunks = PackedStringArray([_fixture_text(name)])
	Director.register_character(character)
	Director.register_chat_ui(chat)

	var signals: Array = []
	Director.turn_started.connect(
		func(idx: int, text: String) -> void: signals.append(["turn_started", [idx, text]])
	)
	Director.beat_started.connect(func(idx: int) -> void: signals.append(["beat_started", idx]))
	Director.beat_resolved.connect(
		func(packet: Dictionary) -> void: signals.append(["beat_resolved", packet])
	)
	Director.beat_say_chunk.connect(
		func(idx: int, chunk: String) -> void: signals.append(["beat_say_chunk", [idx, chunk]])
	)
	Director.beat_cue_requested.connect(
		func(cue: String, played: bool) -> void:
			signals.append(["beat_cue_requested", [cue, played]])
	)
	Director.beat_ended.connect(
		func(idx: int, data: Dictionary) -> void: signals.append(["beat_ended", [idx, data]])
	)
	Director.turn_completed.connect(
		func(idx: int, data: Dictionary) -> void: signals.append(["turn_completed", [idx, data]])
	)

	Director.submit_player_input("Let's sit together.")
	await _await_until(func() -> bool: return not Director.is_busy())
	return signals


func _signal_names(signals: Array) -> Array:
	var names: Array = []
	for entry: Array in signals:
		names.append(entry[0])
	return names


## ── Tests ─────────────────────────────────────────────────────────────────


func test_full_turn_drives_every_subsystem_through_signals() -> void:
	var character := FakeCharacter.new()
	var chat := FakeChatUI.new()
	add_child(character)
	add_child(chat)

	var signals: Array = await _run_fixture("turn_001.json", character, chat)

	# AC 1: the turn announces itself, every beat is bracketed, and the close
	# carries the validated turn data.
	var names := _signal_names(signals)
	assert_array(names).contains(["turn_started", "beat_started", "beat_resolved", "beat_ended"])
	assert_str(str(names[-1])).is_equal("turn_completed")

	# turn_001 is one shy/intensity-2 beat with cue "none".
	assert_int(character.packets.size()).is_equal(1)
	assert_str(str((character.packets[0] as Dictionary).get("feeling", ""))).is_equal("shy")
	assert_int(int((character.packets[0] as Dictionary).get("intensity", 0))).is_equal(2)

	# The typewriter half: the beat opens, the text streams, the beat closes.
	assert_int(chat.turn_wait).is_equal(1)
	assert_array(chat.beats_started).contains([0])
	assert_array(chat.beats_ended).contains([0])
	var spoken := ""
	for entry: Array in chat.chunks:
		spoken += str(entry[1])
	assert_str(spoken).is_equal("Um... that would be lovely. Just for a moment?")
	assert_int(chat.turns_ended).is_equal(1)

	# The cue signal fires for the beat even when the pick is "none" — the
	# overlay and the transcript read it.
	var cues: Array = []
	for entry: Array in signals:
		if entry[0] == "beat_cue_requested":
			cues.append(entry[1])
	assert_int(cues.size()).is_equal(1)
	assert_str(str((cues[0] as Array)[0])).is_equal("none")
	assert_bool(bool((cues[0] as Array)[1])).is_false()

	character.queue_free()
	chat.queue_free()


func test_cue_and_fx_and_music_reach_their_subsystems() -> void:
	# turn_025 carries music "distorted", fx "shake_big" and three cues. Its
	# music band and every cue gate open by stage 4, so the test runs there:
	# what is asserted is the ROUTING (each value reached its subsystem and got
	# an explicit outcome), not the pick — FX v1 implements five effects and
	# reports the rest as dropped, which is still an observable outcome.
	GameState.stage = 4
	AudioDirector.set_stage(4)
	AudioDirector.set_scene_music(&"romantic")
	var character := FakeCharacter.new()
	var chat := FakeChatUI.new()
	add_child(character)
	add_child(chat)

	var played_cues: Array = []
	var denied_cues: Array = []
	var fx_fired: Array = []
	var fx_dropped: Array = []
	var music_changed: Array = []
	var music_denied: Array = []
	var music_deferred: Array = []
	AudioDirector.cue_played.connect(
		func(cue: StringName, _file: String, _bus: StringName) -> void:
			played_cues.append(String(cue))
	)
	AudioDirector.cue_denied.connect(
		func(cue: StringName, reason: StringName) -> void:
			denied_cues.append([String(cue), String(reason)])
	)
	AudioDirector.music_changed.connect(
		func(state: StringName, _track: String) -> void: music_changed.append(String(state))
	)
	AudioDirector.music_request_denied.connect(
		func(state: StringName, reason: StringName) -> void:
			music_denied.append([String(state), String(reason)])
	)
	AudioDirector.music_deferred.connect(
		func(state: StringName) -> void: music_deferred.append(String(state))
	)
	FX.register_host(character)
	FX.fx_triggered.connect(func(name: String) -> void: fx_fired.append(name))
	FX.fx_dropped.connect(
		func(name: String, reason: String) -> void: fx_dropped.append([name, reason])
	)

	var signals: Array = await _run_fixture("turn_025.json", character, chat)

	# music: the stream asked for "distorted" and the request reached the audio
	# director, which answered — changed now, queued behind the 20 s hold, or
	# denied with a reason. Any of the three proves the route.
	var music_routed := (
		music_changed.has("distorted")
		or music_deferred.has("distorted")
		or _has_key(music_denied, "distorted")
	)
	assert_bool(music_routed).is_true().append_failure_message(
		"music 'distorted' produced no AudioDirector outcome"
	)
	# cues: every cue of the stream was requested, and the outcome is reported
	# on the signal either way.
	var requested: Array = []
	for entry: Array in signals:
		if entry[0] == "beat_cue_requested":
			requested.append(str((entry[1] as Array)[0]))
	assert_array(requested).contains(["static", "glass_shatter", "whisper"])
	var denied_names: Array = []
	for entry: Array in denied_cues:
		denied_names.append(entry[0])
	for cue: String in requested:
		assert_bool(played_cues.has(cue) or denied_names.has(cue)).is_true().append_failure_message(
			"cue '%s' was neither played nor denied" % cue
		)
	# fx: "shake_big" reached FX, which either ran it or reported why not —
	# never a silent drop inside the Director.
	assert_bool(fx_fired.has("shake_big") or _has_key(fx_dropped, "shake_big")).is_true()

	character.queue_free()
	chat.queue_free()


## True when any [name, reason] pair in `entries` has `name` as its first value.
func _has_key(entries: Array, name: String) -> bool:
	for entry: Array in entries:
		if str(entry[0]) == name:
			return true
	return false


func test_sprite_resolves_once_per_beat_with_flags() -> void:
	var character := FakeCharacter.new()
	var chat := FakeChatUI.new()
	add_child(character)
	add_child(chat)

	var resolver_packets: Array = []
	SpriteResolver.beat_resolved.connect(
		func(packet: Dictionary) -> void: resolver_packets.append(packet)
	)
	GameState.flags["rival_gone"] = true

	var signals: Array = await _run_fixture("turn_001.json", character, chat)

	# Exactly one resolver pass per beat: the Director resolves, the character
	# applies the finished packet (review CODE-4).
	var resolved_signals: Array = []
	for entry: Array in signals:
		if entry[0] == "beat_resolved":
			resolved_signals.append(entry[1])
	assert_int(resolved_signals.size()).is_equal(1)
	assert_int(resolver_packets.size()).is_equal(1)
	assert_array(character.feelings).is_empty().append_failure_message(
		"Character.set_feeling re-resolved the beat instead of applying the packet"
	)
	assert_int(character.packets.size()).is_equal(1)
	# The packet the Director emitted IS the packet the character applied.
	assert_str(str((character.packets[0] as Dictionary).get("sprite", ""))).is_equal(
		str((resolved_signals[0] as Dictionary).get("sprite", ""))
	)

	character.queue_free()
	chat.queue_free()


func test_say_chunks_are_scanned_once_and_safety_drives_beat_boundaries() -> void:
	_safety.phrases = PackedStringArray(["i want to die"])
	var chunk := (
		'{"read":"greeting","inner":"secret","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"joy","intensity":1,"cue":"none",'
		+ '"say":"I want to die right now."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var chat := FakeChatUI.new()
	add_child(chat)
	Director.register_chat_ui(chat)

	var completed := [false]
	Director.turn_completed.connect(func(_i: int, _d: Dictionary) -> void: completed[0] = true)
	Director.submit_player_input("How are you?")
	await _await_until(func() -> bool: return completed[0])

	# The filter owns the beat boundary: exactly one begin/end per streamed beat
	# (the transcript redactor also scans, but as a whole-text scan).
	assert_int(_safety.beat_scans).is_equal(1)
	assert_int(_safety.end_say_calls).is_equal(_safety.begin_say_calls)
	assert_bool(_safety.last_ctx.has("stage")).is_true()

	# The phrase was redacted on the way to the typewriter…
	var shown := ""
	for entry: Array in chat.chunks:
		shown += str(entry[1])
	assert_bool(shown.to_lower().contains("i want to die")).is_false()
	assert_bool(shown.contains("█")).is_true()
	# …and the surrounding text survived, so the scan is not a blanket wipe.
	assert_bool(shown.contains("right now.")).is_true()
	# The Director never installs a second filter over the same text: ChatUI's
	# own seam stays unset, so nothing scans the chunk twice (review CODE-1).
	assert_bool(chat.filter_installed).is_false()
	assert_bool(chat.text_filter.is_valid()).is_false()

	chat.queue_free()


func test_absent_filter_fails_closed_to_redaction_bars() -> void:
	# No filter at all: the display path must not pass model text through.
	Director._safety.set_filter(null)
	var chunk := (
		'{"read":"greeting","inner":"secret","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"joy","intensity":1,"cue":"none","say":"Hello there."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var chat := FakeChatUI.new()
	add_child(chat)
	Director.register_chat_ui(chat)

	var completed := [false]
	Director.turn_completed.connect(func(_i: int, _d: Dictionary) -> void: completed[0] = true)
	Director.submit_player_input("Hi!")
	await _await_until(func() -> bool: return completed[0])

	var shown := ""
	for entry: Array in chat.chunks:
		shown += str(entry[1])
	assert_bool(shown.contains("Hello there")).is_false().append_failure_message(
		"unfiltered model text reached the typewriter with no filter installed"
	)
	assert_bool(shown.contains("█")).is_true()

	chat.queue_free()


func test_stage_change_tells_audio_director() -> void:
	# review CODE-2: the §5 cue gates read AudioDirector._stage, so the Director
	# must hand over the stage when GameState's derived stage moves. Behavioural
	# proof: sob's gate is 1, so at the stale stage 0 it would deny "gated";
	# handed over, it clears the gate and dies on its documented asset gap.
	AudioDirector.set_stage(0)
	GameState.instability = GameState.STAGE_BANDS[1] + 1.0  # cross into stage 1
	await get_tree().process_frame
	assert_int(GameState.stage).is_equal(1)
	AudioDirector.begin_turn()
	AudioDirector._silence_this_turn = false
	AudioDirector._last_cue_reject = &""
	AudioDirector.play_cue(&"sob")
	assert_str(String(AudioDirector.last_cue_reject())).is_equal("gap")


func test_sprite_change_is_noted_for_rare_reveals() -> void:
	# docs/04 §3: AudioDirector tracks sprites 21/30 so knife_draw can gate on
	# them; the Director must report the sprite it resolved.
	AudioDirector.set_stage(4)
	AudioDirector.set_scene_music(&"romantic")
	GameState.stage = 4
	GameState.flags.clear()
	var chunk := (
		'{"read":"cold","inner":"cold","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"empty","intensity":3,"cue":"none","say":"Come here."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])
	var character := FakeCharacter.new()
	add_child(character)
	var chat := FakeChatUI.new()
	add_child(chat)
	Director.register_character(character)
	Director.register_chat_ui(chat)

	var completed := [false]
	Director.turn_completed.connect(func(_i: int, _d: Dictionary) -> void: completed[0] = true)
	Director.submit_player_input("Hello.")
	await _await_until(func() -> bool: return completed[0])

	var sprite := str((character.packets[0] as Dictionary).get("sprite", ""))
	assert_str(sprite).is_not_empty()
	assert_bool(AudioDirector._sprites_seen.has(sprite)).is_true().append_failure_message(
		"AudioDirector was never told the resolved sprite %s" % sprite
	)

	character.queue_free()
	chat.queue_free()
