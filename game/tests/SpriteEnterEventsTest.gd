extends GdUnitTestSuite
## P2.14 acceptance criterion 2 (Director half): the docs/10 §3 sprite on-enter events
## actually fire. The resolver announces every face change with its already-resolved
## effects; the Director hands cue/system/fx/music to the engine systems, and each
## subsystem's own signal is the evidence. A cue may answer "no_files" when its sample
## is not in the imported pool — the dispatch is what this suite proves.
## Cue playback is asynchronous (threaded stream load), so counts settle through
## _await_cue instead of assuming the signal already landed.

const CharScene := preload("res://scenes/character/Character.tscn")

var _char
var _cues: Array = []  # [cue, played-or-reason] in dispatch order
var _fx: Array = []  # [name, played-or-reason] in dispatch order


func before_test() -> void:
	GameState.reset()
	GameState.stage = 4
	SpriteResolver.reset_scene()
	Director.reset()
	Director.last_sprite_enter = {}
	FX.reset()
	AudioDirector.set_stage(4)
	AudioDirector.begin_turn()
	_char = CharScene.instantiate()  # registers itself as the FX host
	get_tree().root.add_child(_char)
	_cues.clear()
	_fx.clear()
	AudioDirector.cue_played.connect(_on_cue_played)
	AudioDirector.cue_denied.connect(_on_cue_denied)
	FX.fx_triggered.connect(_on_fx_triggered)
	FX.fx_dropped.connect(_on_fx_dropped)


func after_test() -> void:
	AudioDirector.cue_played.disconnect(_on_cue_played)
	AudioDirector.cue_denied.disconnect(_on_cue_denied)
	FX.fx_triggered.disconnect(_on_fx_triggered)
	FX.fx_dropped.disconnect(_on_fx_dropped)
	SpriteResolver.reset_scene()
	Director.reset()
	Director.last_sprite_enter = {}
	FX.reset()
	_char.free()


## YANDERE love at T3 is 24: heartbeat cue, hearts fx (the one entry effect FX v1
## implements) and no music — the packet's entry events reach every subsystem.
func test_enter_events_fire_through_the_director() -> void:
	var packet: Dictionary = SpriteResolver.resolve_beat("love", 1, 4, "YANDERE")
	assert_str(String(packet["sprite"])).is_equal("24")
	var events: Dictionary = Director.last_sprite_enter["events"]
	assert_str(String(events["sprite"])).is_equal("24")
	assert_str(String(events["cue"])).is_equal("heartbeat")
	var report: Dictionary = Director.last_sprite_enter["report"]
	assert_str(String(report["cue"])).is_equal("heartbeat")
	await _await_cue("heartbeat", 1)
	assert_int(_count(_cues, "heartbeat")).is_equal(1)
	assert_str(String(report["fx"])).is_equal("hearts")
	assert_bool(bool(report["fx_ok"])).is_true()
	assert_int(_count(_fx, "hearts")).is_equal(1)


## 21's reveal budget is one per scene, and the entry sting must not fire for the
## second anger beat: the knife is a reveal, not a loop.
func test_knife_reveal_fires_once_per_scene() -> void:
	var first: Dictionary = SpriteResolver.resolve_beat("angry", 1, 4, "YANDERE")
	assert_str(String(first["sprite"])).is_equal("21")
	var report: Dictionary = Director.last_sprite_enter["report"]
	assert_str(String(report["cue"])).is_equal("knife_draw")
	assert_array(report["system"]).is_equal(["stinger.mid"])
	assert_str(String(report["fx"])).is_equal("vignette_red")
	assert_str(String(report["music"])).is_equal("dread")
	await _await_cue("knife_draw", 1)
	assert_int(_count(_cues, "knife_draw")).is_equal(1)
	_cues.clear()
	var second: Dictionary = SpriteResolver.resolve_beat("angry", 1, 4, "YANDERE")
	assert_str(String(second["sprite"])).is_equal("17")
	await get_tree().process_frame
	assert_int(_count(_cues, "knife_draw")).is_equal(0)


## docs/10 §3 budget "terminal climax only": 30 can appear at stage 4, but its
## stage_change sting and glowing eyes wait for stage 5; the fx degrades to the
## vignette and the heartbeat still lands.
func test_terminal_climax_sting_waits_for_stage_5() -> void:
	var stage4: Dictionary = SpriteResolver.resolve_beat("angry", 3, 4)
	assert_str(String(stage4["sprite"])).is_equal("30")
	var early: Dictionary = Director.last_sprite_enter["report"]
	assert_array(early["system"]).is_empty()
	assert_str(String(early["fx"])).is_equal("vignette_red")
	await _await_cue("heartbeat_fast", 1)
	assert_int(_count(_cues, "heartbeat_fast")).is_equal(1)
	assert_int(_count(_fx, "vignette_red")).is_equal(1)  # dispatched (FX v1 drops it)
	assert_int(_count(_fx, "her_eyes")).is_equal(0)

	# a new scene state so the same face counts as a fresh entrance
	SpriteResolver.reset_scene()
	_cues.clear()
	var stage5: Dictionary = SpriteResolver.resolve_beat("angry", 3, 5)
	assert_str(String(stage5["sprite"])).is_equal("30")
	var late: Dictionary = Director.last_sprite_enter["report"]
	assert_array(late["system"]).is_equal(["stinger.stage_change"])
	assert_str(String(late["fx"])).is_equal("her_eyes")
	await _await_cue("heartbeat_fast", 1)
	assert_int(_count(_cues, "heartbeat_fast")).is_equal(1)


## A held face is not an entrance: repeating the same sprite must not replay its
## entry sound or effect.
func test_repeated_face_does_not_refire_its_events() -> void:
	SpriteResolver.resolve_beat("love", 1, 4, "YANDERE")
	await _await_cue("heartbeat", 1)
	_cues.clear()
	_fx.clear()
	SpriteResolver.resolve_beat("love", 1, 4, "YANDERE")
	await get_tree().process_frame
	assert_array(_cues).is_empty()
	assert_array(_fx).is_empty()


## Waits for the threaded stream load behind a cue to land (or the denial, which
## signals immediately) so a count never races the audio thread.
func _await_cue(name: String, expected: int, timeout_ms := 1500) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while _count(_cues, name) < expected and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _on_cue_played(cue: StringName, _file_path: String, _bus: StringName) -> void:
	_cues.append([String(cue), "played"])


func _on_cue_denied(cue: StringName, reason: StringName) -> void:
	_cues.append([String(cue), String(reason)])


func _on_fx_triggered(name: String) -> void:
	_fx.append([name, "played"])


func _on_fx_dropped(name: String, reason: String) -> void:
	_fx.append([name, reason])


## How many dispatch records carry `name` (whatever the subsystem answered).
func _count(records: Array, name: String) -> int:
	var hits := 0
	for record: Array in records:
		if String(record[0]) == name:
			hits += 1
	return hits
