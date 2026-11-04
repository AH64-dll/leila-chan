extends Node
## AudioDirector — music states, cues, budgets, stage layers and buses
## (docs/04 §1-§7, docs/02 §5).
##
## The Director reports each turn with begin_turn(), then routes the model's
## `music` request through request_music() and each `cue` through play_cue().
## Music states are *requests*: minimum hold (20 s, from audio_rules.json),
## at most one change per turn, 1.5 s crossfade, instant cut for `silence`.
## Later requests are queued and applied on the next legal turn. Each state
## resolves to a stage-band track pool in cue_map.json (docs/04 §8.3) and the
## Music bus carries the docs/04 §2 stage drift — pitch drifts -5 cents per
## stage, the low-pass closes 1 kHz per stage after 2, distortion and reverb
## open by stage (table: audio_rules.json "stage_layers"). Cues resolve
## through res://data/cue_map.json, honour the stage gates and the docs/02 §5
## token-bucket budget, the 4-turn same-cue window, the rare-reveal caps and
## the stage >= 3 silence rule. Over-budget values are dropped silently
## (denials are observable via cue_denied for the overlay, never sent back).
## Her text blips (text_blip) pick the casting.json voice_by_stage pool per
## stage (AWAKE override from stage 3, stage 5 mixing the demon pool under
## stage 4's) and pitch it by the beat's feeling (docs/04 §4/§7, docs/10 §5).
## MusicA/MusicB child buses form the docs/04 §1 crossfade pair; every bus a
## Settings slider may touch is in bus_names(). Rule tables live in
## res://data/audio_rules.json — content in data, not code.

signal music_changed(state: StringName, track_path: String)
signal music_deferred(state: StringName)
signal music_request_denied(state: StringName, reason: StringName)
signal cue_played(cue: StringName, file_path: String, bus: StringName)
signal cue_denied(cue: StringName, reason: StringName)
signal stream_load_failed(res_path: String, kind: StringName)
signal voice_blip_played(key: StringName, file_path: String, pitch_scale: float, volume_db: float)

const RULES_PATH := "res://data/audio_rules.json"
const CUE_MAP_PATH := "res://data/cue_map.json"
const CASTING_PATH := "res://data/casting.json"
const AUDIO_RES_ROOT := "res://assets/audio/"
const MUSIC_BUS := &"Music"
const MUSIC_PLAYER_COUNT := 2
const SFX_PLAYER_COUNT := 6

## Set false in tests to drive the clock with advance_time() only.
var auto_clock := true
## Runtime-tunable for tests; defaults come from audio_rules.json.
var crossfade_seconds := 1.5

var _rules: Dictionary = {}
var _cue_map: Dictionary = {}
var _casting: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _now := 0.0
var _stage := 0
var _turn_index := -1

var _stage_fx: Dictionary = {}
var _blip_feeling := &""
var _blip_chars := 0
var _blip_next := 2

var _cue_tokens := 0.0
var _cue_last_turn: Dictionary = {}
var _cue_last_file: Dictionary = {}
var _cue_counts: Dictionary = {}
var _session_counts: Dictionary = {}
var _sprites_seen: Dictionary = {}
var _silence_this_turn := false
var _last_cue_reject := &""

var _current_music := &"none"
var _pending_music := &""
var _keep_turns := 0
var _music_started_at := -1.0
var _music_changed_this_turn := false
var _scene_default := &""
var _last_track_by_state: Dictionary = {}

var _music_players: Array = []
var _sfx_players: Array = []
var _sfx_next := 0
var _active_fade: Dictionary = {}
var _stream_cache: Dictionary = {}
var _stream_requests: Dictionary = {}
var _stream_waiters: Dictionary = {}


func _ready() -> void:
	_rules = _load_json_dict(RULES_PATH)
	_cue_map = _load_json_dict(CUE_MAP_PATH)
	_casting = _load_json_dict(CASTING_PATH)
	crossfade_seconds = float(_rules.get("music", {}).get("crossfade_seconds", 1.5))
	_rng.randomize()
	_ensure_buses()
	_ensure_stage_fx()
	_apply_stage_dsp()
	_ensure_players()


func _process(delta: float) -> void:
	if auto_clock:
		_tick(delta)
	for path: String in _stream_requests.keys():
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var stream: Resource = ResourceLoader.load_threaded_get(path)
			_stream_requests.erase(path)
			if stream != null:
				_stream_cache[path] = stream
				_dispatch_stream_waiters(path, stream)
			else:
				_fail_stream_waiters(path)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_stream_requests.erase(path)
			_fail_stream_waiters(path)


## Resets the per-turn allowances. The Director calls this once per model turn
## (docs/02 §4): it accrues cue budget, rolls the stage >= 3 silence rule,
## re-opens the one-change-per-turn music slot and applies any queued request.
func begin_turn() -> void:
	_turn_index += 1
	_music_changed_this_turn = false
	var budget: Dictionary = _band_entry(_rules.get("cue_budget", {}).get("bands", []), _stage)
	if _turn_index == 0:
		_cue_tokens = float(budget.get("cap", 1.0))
	else:
		_cue_tokens = minf(
			_cue_tokens + float(budget.get("per_turn", 0.5)), float(budget.get("cap", 1.0))
		)
	var silence: Dictionary = _rules.get("silence_rule", {})
	_silence_this_turn = (
		_stage >= int(silence.get("min_stage", 3))
		and _rng.randf() < float(silence.get("drop_rate", 0.1))
	)
	if _pending_music != &"" and _music_legal_now():
		var pending := _pending_music
		_pending_music = &""
		_try_music_change(pending)


## Model `music` request (docs/02 §2.2). `keep` counts toward restoring the
## scene default; anything else is honoured subject to the stage gate, the
## one-change-per-turn slot and the 20 s hold — honoured-but-early requests
## are queued, not dropped. Returns false only for hard denials.
func request_music(state: StringName) -> bool:
	var result := true
	var want := state
	if want == &"keep" or want == &"":
		_keep_turns += 1
		var keep_restore := int(_rules.get("music", {}).get("keep_restore_turns", 3))
		var overridden := _scene_default != &"" and _current_music != _scene_default
		if overridden and _keep_turns >= keep_restore:
			want = _scene_default
			_keep_turns = 0
		else:
			want = &""
	if want != &"":
		_keep_turns = 0
		var gates: Dictionary = _rules.get("music_gates", {})
		if not gates.has(want):
			music_request_denied.emit(want, &"unknown")
			result = false
		elif int(gates[want]) > _stage:
			music_request_denied.emit(want, &"gated")
			result = false
		elif want == _current_music:
			_pending_music = &""
		elif _music_legal_now():
			result = _try_music_change(want)
		else:
			_pending_music = want
			music_deferred.emit(want)
	return result


## Model `cue` request (docs/02 §2.1, §5). Resolves through cue_map.json;
## denials are silent to the model and observable via cue_denied. "none" is
## an accepted no-op. Returns whether a cue will actually play.
func play_cue(cue: StringName) -> bool:
	if cue == &"none" or cue == &"":
		return true
	var entry: Dictionary = _cue_map.get("cues", {}).get(String(cue), {})
	var files: Array = entry.get("files", [])
	var bus: StringName = _cue_bus(cue)
	var reason := _cue_gate_reason(cue, files)
	if reason != &"":
		_deny_cue(cue, reason)
		return false
	var paths := _existing_paths(files, _cue_category(cue))
	if paths.is_empty():
		_deny_cue(cue, &"no_files")
		return false
	_cue_tokens -= 1.0
	_cue_last_turn[cue] = _turn_index
	_cue_counts[cue] = int(_cue_counts.get(cue, 0)) + 1
	_session_counts[cue] = int(_session_counts.get(cue, 0)) + 1
	_fire_files(cue, files, paths, bus, _cue_category(cue))
	return true


## Engine-owned sound groups (cue_map "system" section): stingers, UI, typing,
## voice blips, ambience beds. Not gated or budgeted — the engine, not the
## model, decides when they play.
func play_system(key: StringName) -> bool:
	var spec: Dictionary = _rules.get("system_keys", {}).get(String(key), {})
	var files: Array = _cue_map.get("system", {}).get(String(key), [])
	if files.is_empty():
		_deny_cue(key, &"unknown")
		return false
	var category := String(spec.get("category", "sfx"))
	var paths := _existing_paths(files, category)
	if paths.is_empty():
		_deny_cue(key, &"no_files")
		return false
	_fire_files(key, files, paths, StringName(spec.get("bus", "SFX")), category)
	return true


## The Director's own docs/02 §5 auto-fill pick: plays a cue as the ENGINE, not
## as a model request — so it skips the cue token bucket, the repeat window and
## the stage gate the model's picks are subject to. The Director only reaches
## for this after four quiet turns at intensity >= 2, i.e. exactly when the
## model's restraint has starved the scene; charging it to the model's budget
## would silently void the fill (review CODE-11). Asset existence still decides:
## a cue with no importable file reports false and the fill stays owed.
func play_engine_cue(cue: StringName) -> bool:
	var entry: Dictionary = _cue_map.get("cues", {}).get(String(cue), {})
	var files: Array = entry.get("files", [])
	if files.is_empty():
		_deny_cue(cue, &"unknown")
		return false
	var category := _cue_category(cue)
	var paths := _existing_paths(files, category)
	if paths.is_empty():
		_deny_cue(cue, &"no_files")
		return false
	_fire_files(cue, files, paths, _cue_bus(cue), category)
	return true


## One revealed character of her `say` (docs/04 §4/§7, docs/10 §5). Call this
## once per character from the typewriter: the director plays a soft blip every
## 2-3 characters, drawing the pool from casting.json's voice_by_stage — AWAKE
## overrides from stage 3, and stage 5 already mixes the demon pool under the
## stage-4 whispers. Pitch and gain come from the beat's feeling voice spec
## (`empty` has none, so she speaks in silence). Returns true when this
## character triggered a blip; engine-owned, so it never charges the cue budget.
func text_blip(feeling: StringName, stage: int = -1, path: StringName = &"") -> bool:
	var use_stage := _stage if stage < 0 else clampi(stage, 0, 5)
	if feeling != _blip_feeling:
		_blip_feeling = feeling
		_blip_chars = 0
	_blip_chars += 1
	if _blip_chars < _blip_next:
		return false
	var cadence: Dictionary = _rules.get("voice_blips", {})
	_blip_chars = 0
	_blip_next = _rng.randi_range(
		int(cadence.get("every_chars_min", 2)), int(cadence.get("every_chars_max", 3))
	)
	return _play_blip(feeling, use_stage, path)


## Sprite on-enter hook (docs/04 §3): tracks sprites 21/30 for knife_draw.
func note_sprite(sprite_id: StringName) -> void:
	_sprites_seen[String(sprite_id)] = true


## Scene install: records the scene's own music so `keep` can restore it
## (docs/04 §2) and resets the per-scene rare-reveal caps and sprite memory.
## Playing the default itself waits its turn like any request.
func set_scene_music(default_state: StringName) -> void:
	_scene_default = default_state
	_keep_turns = 0
	_cue_counts.clear()
	_sprites_seen.clear()
	if default_state != &"" and _current_music != default_state:
		if _music_legal_now():
			_try_music_change(default_state)
		else:
			_pending_music = default_state


func set_stage(stage: int) -> void:
	_stage = clampi(stage, 0, 5)
	_apply_stage_dsp()


func current_music() -> StringName:
	return _current_music


func pending_music() -> StringName:
	return _pending_music


## Buses the Settings menu may expose (docs/04 §1); MusicA/MusicB are the
## internal crossfade pair and stay hidden.
func bus_names() -> PackedStringArray:
	var names := PackedStringArray(["Master"])
	for bus: String in _rules.get("buses", {}):
		if _rules["buses"][bus].get("expose", false):
			names.append(bus)
	return names


func cue_budget() -> Dictionary:
	var budget: Dictionary = _band_entry(_rules.get("cue_budget", {}).get("bands", []), _stage)
	return {
		"tokens": _cue_tokens,
		"cap": float(budget.get("cap", 1.0)),
		"per_turn": float(budget.get("per_turn", 0.5)),
	}


func bus_volume_linear(bus: StringName) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


## linear 0.0-1.0+, 0.0 floors at -80 dB. T21: mute stays detectable via
## AudioServer.is_bus_mute() — volume 0 is not a substitute.
func set_bus_volume_linear(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0)))


func set_bus_mute(bus: StringName, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


func is_bus_muted(bus: StringName) -> bool:
	var idx := AudioServer.get_bus_index(bus)
	return idx >= 0 and AudioServer.is_bus_mute(idx)


## Test/debug hook for the injected clock: also drives any running crossfade
## so fades stay deterministic when auto_clock is off.
func advance_time(seconds: float) -> void:
	_tick(maxf(seconds, 0.0))


func set_rng_seed(seed: int) -> void:
	_rng.seed = seed


## Reason of the most recent cue_denied emission; empty when nothing denied.
func last_cue_reject() -> StringName:
	return _last_cue_reject


# ---------------------------------------------------------------- internals


func _tick(delta: float) -> void:
	_now += delta
	if _active_fade.is_empty():
		return
	var fade_duration := float(_active_fade.get("duration", 0.0))
	var keep_player: AudioStreamPlayer = _active_fade.get("player")
	var keep_db := (
		-80.0
		if fade_duration <= 0.0
		else linear_to_db(minf(_now - float(_active_fade["start"]), fade_duration) / fade_duration)
	)
	for player: AudioStreamPlayer in _music_players:
		if player == keep_player:
			player.volume_db = keep_db
		elif player.playing:
			player.volume_db = (
				-80.0
				if fade_duration <= 0.0
				else lerpf(
					float(_active_fade["others"].get(player, 0.0)),
					-80.0,
					minf(_now - float(_active_fade["start"]), fade_duration) / fade_duration,
				)
			)
			if player.volume_db <= -79.0:
				player.stop()
	if _now - float(_active_fade["start"]) >= fade_duration:
		_active_fade.clear()


func _music_legal_now() -> bool:
	var max_changes := int(_rules.get("music", {}).get("max_changes_per_turn", 1))
	var hold := float(_rules.get("music", {}).get("min_hold_seconds", 20.0))
	var change_slot_open := not _music_changed_this_turn or max_changes <= 0
	var hold_open := _music_started_at < 0.0 or _now - _music_started_at >= hold
	return change_slot_open and (hold_open or _current_music == &"none")


func _try_music_change(state: StringName) -> bool:
	var entry: Dictionary = _cue_map.get("music", {}).get(String(state), {})
	var track_src := ""
	if state != &"silence":
		var pool := _band_files(entry)
		if pool.is_empty():
			music_request_denied.emit(state, &"no_band")
			return false
		var paths := _existing_paths(pool, "music")
		if paths.is_empty():
			music_request_denied.emit(state, &"no_files")
			return false
		track_src = _pick_avoiding(paths, _last_track_by_state.get(state, ""))
		_last_track_by_state[state] = track_src
	_music_changed_this_turn = true
	_current_music = state
	_music_started_at = _now
	var track_res := ""
	if state == &"silence":
		_cut_music()
	else:
		var res_path := _resolve_src(track_src, "music")
		track_res = res_path
		_with_stream(
			res_path, &"music", func(stream: AudioStream) -> void: _start_music_track(stream)
		)
	music_changed.emit(state, track_res)
	return true


func _cut_music() -> void:
	_active_fade.clear()
	for player: AudioStreamPlayer in _music_players:
		player.stop()
		player.volume_db = 0.0


func _start_music_track(stream: AudioStream) -> void:
	var target: AudioStreamPlayer = null
	for player: AudioStreamPlayer in _music_players:
		if not player.playing:
			target = player
			break
	if target == null:
		target = _music_players[0]
	var others := {}
	for player: AudioStreamPlayer in _music_players:
		if player != target and player.playing:
			others[player] = player.volume_db
	target.stream = stream
	target.volume_db = -80.0 if crossfade_seconds > 0.0 else 0.0
	target.play()
	_active_fade = {
		"player": target,
		"others": others,
		"start": _now,
		"duration": crossfade_seconds,
	}


func _cue_category(cue: StringName) -> String:
	if _rules.get("vocal_cues", []).has(String(cue)):
		return "vocal"
	return "sfx"


func _cue_bus(cue: StringName) -> StringName:
	var map: Dictionary = _rules.get("bus_for_category", {})
	return StringName(map.get(_cue_category(cue), "SFX"))


func _play_blip(feeling: StringName, stage: int, path: StringName) -> bool:
	var voice: Variant = _voice_spec(feeling)
	if not voice is Dictionary:
		return false
	var key := _blip_key(stage, path)
	var files: Array = _cue_map.get("system", {}).get(String(key), [])
	if key == &"" or files.is_empty():
		return false
	var spec: Dictionary = _rules.get("system_keys", {}).get(String(key), {})
	var category := String(spec.get("category", "vocal"))
	var paths := _existing_paths(files, category)
	if paths.is_empty():
		return false
	var rel := _pick_avoiding(paths, _cue_last_file.get(key, ""))
	_cue_last_file[key] = rel
	var res_path := _resolve_src(String(files[paths.find(rel)]), category)
	var pitch := pow(2.0, float(voice.get("pitch_st", 0)) / 12.0)
	var gain := float(voice.get("gain_db", 0.0))
	var bus := StringName(spec.get("bus", "Voice"))
	_with_stream(
		res_path,
		&"blip",
		func(stream: AudioStream) -> void:
			var player := _next_sfx_player()
			player.bus = bus
			player.stream = stream
			player.pitch_scale = pitch
			player.volume_db = gain
			player.play()
			voice_blip_played.emit(key, res_path, pitch, gain)
	)
	return true


## docs/10 §5 voice_by_stage: AWAKE overrides the stage pool from stage 3 and
## stage 5 mixes the demon pool under the stage-4 whispers 30% of the time
## (docs/04 §7).
func _blip_key(stage: int, path: StringName) -> StringName:
	var table: Dictionary = _casting.get("voice_by_stage", {})
	var blips: Dictionary = _rules.get("voice_blips", {})
	if path == &"AWAKE" and stage >= int(blips.get("awake_min_stage", 3)):
		return StringName(String(table.get("AWAKE>=3", "")))
	var key := StringName(String(table.get(str(clampi(stage, 0, 5)), "")))
	if key == &"voice_blip.stage5" and _rng.randf() >= float(blips.get("stage5_demon_mix", 0.3)):
		return StringName(String(blips.get("stage5_base_key", "voice_blip.stage4")))
	return key


## casting.json feelings[f].voice; null means "no blips" (docs/04 §4 — "empty:
## no blips, silence while she 'speaks'").
func _voice_spec(feeling: StringName) -> Variant:
	var feelings: Dictionary = _casting.get("feelings", {})
	var entry: Variant = feelings.get(String(feeling))
	if not entry is Dictionary:
		return null
	return entry.get("voice")


## Gate, silence, window, caps and budget in drop order. Asset existence is
## checked after this so a missing file never burns the turn's budget.
func _cue_gate_reason(cue: StringName, files: Array) -> StringName:
	var reason := &""
	var gates: Dictionary = _rules.get("cue_gates", {})
	var rare: Dictionary = _rules.get("rare_limits", {}).get(String(cue), {})
	var exempt: Dictionary = _rules.get("repeat_exempt", {})
	var window := int(_rules.get("repeat_window_turns", 4))
	if not _cue_map.get("cues", {}).has(String(cue)):
		reason = &"unknown"
	elif _silence_this_turn:
		reason = &"silence"
	elif int(gates.get(String(cue), 99)) > _stage:
		reason = &"gated"
	elif (
		_cue_last_turn.has(cue)
		and _turn_index - int(_cue_last_turn[cue]) < window
		and not (
			String(cue) == String(exempt.get("cue", ""))
			and _stage >= int(exempt.get("min_stage", 4))
		)
	):
		reason = &"repeat_window"
	elif rare.has("requires_sprites") and not _sprites_seen_any(rare["requires_sprites"]):
		reason = &"requires_sprite"
	elif rare.has("session_cap") and _session_counts.get(cue, 0) >= int(rare["session_cap"]):
		reason = &"session_cap"
	elif rare.has("scene_cap") and _cue_counts.get(cue, 0) >= int(rare["scene_cap"]):
		reason = &"scene_cap"
	elif files.is_empty():
		reason = &"gap"
	elif _cue_tokens < 1.0:
		reason = &"budget"
	return reason


func _sprites_seen_any(sprite_ids: Array) -> bool:
	for sprite_id: Variant in sprite_ids:
		if _sprites_seen.has(String(sprite_id)):
			return true
	return false


func _deny_cue(cue: StringName, reason: StringName) -> void:
	_last_cue_reject = reason
	cue_denied.emit(cue, reason)


func _fire_files(
	name_key: StringName, files: Array, paths: Array, bus: StringName, category: String
) -> void:
	var rel := _pick_avoiding(paths, _cue_last_file.get(name_key, ""))
	_cue_last_file[name_key] = rel
	var src: Variant = files[paths.find(rel)]
	var res_path := _resolve_src(String(src), category)
	_with_stream(
		res_path,
		&"cue",
		func(stream: AudioStream) -> void:
			var player := _next_sfx_player()
			player.bus = bus
			player.stream = stream
			var jitter: Dictionary = _rules.get("randomisation", {})
			var cents := float(jitter.get("cue_pitch_cents_range", 0.05))
			var decibels := float(jitter.get("cue_volume_db_range", 2.0))
			player.pitch_scale = 1.0 + _rng.randf_range(-cents, cents)
			player.volume_db = _rng.randf_range(-decibels, decibels)
			player.play()
			cue_played.emit(name_key, res_path, bus)
	)


func _next_sfx_player() -> AudioStreamPlayer:
	var player: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	return player


func _pick_avoiding(paths: Array, avoid: String) -> String:
	var pick := String(paths[_rng.randi_range(0, paths.size() - 1)])
	if pick == avoid and paths.size() > 1:
		var idx := (paths.find(avoid) + _rng.randi_range(1, paths.size() - 1)) % paths.size()
		pick = String(paths[idx])
	return pick


func _existing_paths(files: Array, category: String) -> Array:
	var out: Array = []
	for src: Variant in files:
		if ResourceLoader.exists(_resolve_src(String(src), category)):
			out.append(String(src))
	return out


func _band_files(entry: Dictionary) -> Array:
	for band: String in entry:
		var span := _band_span(band)
		if span.x >= 0 and _stage >= span.x and _stage <= span.y:
			return entry[band]
	return []


func _band_span(band: String) -> Vector2i:
	if band == "any":
		return Vector2i(0, 5)
	var parts := band.split("-")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(-1, -1)


func _band_entry(bands: Array, stage: int) -> Dictionary:
	for band: Variant in bands:
		var span := _band_span(String(band.get("stages", "")))
		if span.x >= 0 and stage >= span.x and stage <= span.y:
			return band
	return {}


## cue_map src rel path -> imported res path. Mirrors the importer's
## sanitisation (tools/audio/import_audio.py, parity test in
## tests/test_audio_import.py): lowercase, non [a-z0-9._-] runs -> "_",
## "_" runs collapsed, edge "_" stripped, and only the filename segment
## gets the .ogg extension forced.
func _resolve_src(src_rel: String, category: String) -> String:
	var clean := PackedStringArray()
	var invalid := RegEx.create_from_string("[^a-z0-9._-]+")
	var dupes := RegEx.create_from_string("_+")
	var parts := src_rel.split("/")
	for i in parts.size():
		var seg := dupes.sub(invalid.sub(String(parts[i]).to_lower(), "_", true), "_", true)
		while seg.begins_with("_"):
			seg = seg.substr(1)
		while seg.ends_with("_"):
			seg = seg.substr(0, seg.length() - 1)
		if i == parts.size() - 1 and not seg.ends_with(".ogg"):
			seg = seg.get_basename() + ".ogg"
		clean.append(seg)
	return AUDIO_RES_ROOT + category + "/" + "/".join(clean)


func _ensure_buses() -> void:
	var buses: Dictionary = _rules.get("buses", {})
	for bus: String in buses:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, String(buses[bus].get("parent", "Master")))


## docs/04 §1: the Music bus carries the stage-driven effect chain. Idempotent —
## the AudioServer bus graph outlives a single AudioDirector instance (tests
## build many), so an existing effect of the same class is reused, never
## stacked, and its index is cached for _apply_stage_dsp().
func _ensure_stage_fx() -> void:
	var bus_idx := AudioServer.get_bus_index(MUSIC_BUS)
	if bus_idx < 0:
		return
	_stage_fx = {
		"pitch": _bus_effect_index(bus_idx, AudioEffectPitchShift.new()),
		"lowpass": _bus_effect_index(bus_idx, AudioEffectLowPassFilter.new()),
		"distortion": _bus_effect_index(bus_idx, AudioEffectDistortion.new()),
		"reverb": _bus_effect_index(bus_idx, AudioEffectReverb.new()),
	}


func _bus_effect_index(bus_idx: int, effect: AudioEffect) -> int:
	for i: int in AudioServer.get_bus_effect_count(bus_idx):
		var existing := AudioServer.get_bus_effect(bus_idx, i)
		if existing != null and existing.get_class() == effect.get_class():
			return i
	AudioServer.add_bus_effect(bus_idx, effect)
	return AudioServer.get_bus_effect_count(bus_idx) - 1


## docs/04 §2 stage drift computed from the "stage_layers" table so the bus
## effects and the tests share one source: pitch -5 cents per stage, the
## low-pass base 12 kHz closing 1 kHz per stage after 2, distortion drive and
## reverb wet by stage (0.0 = effect bypassed).
func _stage_layer(stage: int) -> Dictionary:
	var spec: Dictionary = _rules.get("stage_layers", {})
	var cents := float(spec.get("pitch_cents_per_stage", -5.0)) * stage
	var lowpass_start := int(spec.get("lowpass_start_stage", 2))
	var lowpass := 0.0
	if stage >= lowpass_start:
		lowpass = (
			float(spec.get("lowpass_base_hz", 12000.0))
			+ float(spec.get("lowpass_hz_per_stage", -1000.0)) * (stage - lowpass_start)
		)
	var distortion: Dictionary = spec.get("distortion", {})
	var drive := 0.0
	if stage >= int(distortion.get("min_stage", 4)):
		drive = float(distortion.get("drive", {}).get(str(stage), 0.0))
	var reverb: Dictionary = spec.get("reverb", {})
	var wet := 0.0
	if stage >= int(reverb.get("min_stage", 3)):
		wet = float(reverb.get("wet", {}).get(str(stage), 0.0))
	return {
		"pitch_cents": cents,
		"pitch_scale": pow(2.0, cents / 1200.0),
		"lowpass_hz": lowpass,
		"distortion_drive": drive,
		"reverb_wet": wet,
	}


func _apply_stage_dsp() -> void:
	var bus_idx := AudioServer.get_bus_index(MUSIC_BUS)
	if bus_idx < 0 or _stage_fx.is_empty():
		return
	var layer := _stage_layer(_stage)
	var pitch := (
		AudioServer.get_bus_effect(bus_idx, int(_stage_fx["pitch"])) as AudioEffectPitchShift
	)
	pitch.pitch_scale = float(layer["pitch_scale"])
	var lowpass := (
		AudioServer.get_bus_effect(bus_idx, int(_stage_fx["lowpass"])) as AudioEffectLowPassFilter
	)
	lowpass.cutoff_hz = maxf(float(layer["lowpass_hz"]), 100.0)
	AudioServer.set_bus_effect_enabled(
		bus_idx, int(_stage_fx["lowpass"]), lowpass.cutoff_hz > 100.0
	)
	var distortion := (
		AudioServer.get_bus_effect(bus_idx, int(_stage_fx["distortion"])) as AudioEffectDistortion
	)
	distortion.drive = float(layer["distortion_drive"])
	AudioServer.set_bus_effect_enabled(
		bus_idx, int(_stage_fx["distortion"]), distortion.drive > 0.0
	)
	var reverb := AudioServer.get_bus_effect(bus_idx, int(_stage_fx["reverb"])) as AudioEffectReverb
	reverb.wet = float(layer["reverb_wet"])
	AudioServer.set_bus_effect_enabled(bus_idx, int(_stage_fx["reverb"]), reverb.wet > 0.0)


func _ensure_players() -> void:
	var music_buses := [&"MusicA", &"MusicB"]
	for i in MUSIC_PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = music_buses[i % music_buses.size()]
		add_child(player)
		_music_players.append(player)
	for i in SFX_PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)


func _with_stream(res_path: String, kind: StringName, on_ready: Callable) -> void:
	if _stream_cache.has(res_path):
		on_ready.call(_stream_cache[res_path])
	else:
		if not _stream_waiters.has(res_path):
			_stream_waiters[res_path] = []
			var err := ResourceLoader.load_threaded_request(res_path)
			if err != OK:
				_stream_waiters.erase(res_path)
				stream_load_failed.emit(res_path, kind)
				return
			_stream_requests[res_path] = kind
		_stream_waiters[res_path].append({"kind": kind, "cb": on_ready})


func _dispatch_stream_waiters(path: String, stream: Resource) -> void:
	var waiters: Array = _stream_waiters.get(path, [])
	_stream_waiters.erase(path)
	for waiter: Variant in waiters:
		waiter["cb"].call(stream)


func _fail_stream_waiters(path: String) -> void:
	var waiters: Array = _stream_waiters.get(path, [])
	_stream_waiters.erase(path)
	for waiter: Variant in waiters:
		stream_load_failed.emit(path, StringName(waiter["kind"]))
	if waiters.is_empty():
		stream_load_failed.emit(path, &"unknown")


static func _load_json_dict(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("AudioDirector: cannot read " + path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("AudioDirector: invalid JSON in " + path)
		return {}
	return parsed
