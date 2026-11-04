extends Node
## SaveSystem — saves v1 (docs/07 §3.5): slots in `user://saves`, autosave per
## scene, and a load that restores meters, memories and the log.
##
## A save file is `<state, memories, log>`: GameState's snapshot (meters, stage,
## day, path, flags, profile), Memory's store (`seed` **and** rng `state`, so a
## reload resumes the corruption stream where it stopped, P2.11's handoff) and
## the conversation log. `game/llm/SaveSlots.gd` owns the bytes and the
## integrity envelope; this node owns the game side: capture, apply, the log
## seam and the autosave policy.
##
## Slot layout (docs/07 §3.5 says `slot_N.json`; the autosave needs its own id):
##   user://saves/slot_1.json .. slot_3.json   manual slots (P3.x UI writes them)
##   user://saves/autosave.json                per-scene autosave ("auto")
##
## Autosave: `autosave(scene_id)` is the one write point. A scene calls it when
## it starts and whenever its own state moves (the Date calls it after every
## completed turn), so "Continue" resumes at the scene the player left. It is
## off in a headless run — a headless build has no player — and tests opt in
## with a scratch `save_dir`.
##
## Load safety: a corrupt save is a `{ok: false, error, message}` value, never
## an exception and never a half-applied state. `SaveSlots` validates the
## envelope (format, version, checksum) and this class validates the payload's
## sections; GameState/Memory are only touched after both pass, and
## `GameState.from_dict()` refuses before mutating. Nothing here throws.
##
## The log seam mirrors the Director's ChatUI registration (P2.23): the scene
## that instantiates the ChatLog owns the registration in `_ready()` and clears
## it in `_exit_tree()`. While no log is registered (Title → Continue), the log
## of the loaded save waits in `_pending_log` and is handed to the first sink.

## docs/07 §3.5 layout. The autosave is a slot; manual slots are 1..3 for v1
## (the P3.x save-menu task owns the UI and its slot count).
##
## The shadow save (docs/05 M08) is the one file a New Game does not wipe:
## `user://.leila/shadow.json` keeps the first name ever typed, the names she
## has seen, how many runs she has been through and a few memories of a run
## that had already reached the meta gate. `ShadowStore` (game/llm) owns the
## bytes and documents the file's full contents for privacy; this node owns
## the moment it is written — `begin_new_game(player_name)`, called by the
## New Game scene BEFORE GameState/Director reset, seals the run that just
## ended — and `wipe_everything()`, the Settings → "Reset Everything" true
## wipe that deletes all of `user://` except the settings file (docs/07 §3.5).

const MANUAL_SLOT_COUNT := SaveSlots.MANUAL_SLOTS
## The wipe root a player runs (docs/07 §3.5: all of `user://`). A constant
## because the scheme must never be normalized away — `user://` trimmed to
## `user:/` is a directory `DirAccess` cannot open (P3.12 round 2, CODE-1).
const DEFAULT_USER_ROOT := "user://"
## The scene id the Date writes with its autosave. The Night writes its own id
## with the next day's scenario, so Continue can land on that day (P2.19); the
## save stores the id verbatim.
const SCENE_DATE := "date"
const SCENE_NIGHT := "night"
## docs/02 §6 rule 1 reads the last three player messages.
const PLAYER_WINDOW := 3

## Test seam: `save_dir` forwards to the codec, `slots` may be swapped whole.
var slots := SaveSlots.new()
## A headless run cannot be played, so the Date's per-scene autosave writes
## only in a real session. Tests that exercise the writing path set this true
## and point `save_dir` at a scratch directory.
var autosave_enabled := DisplayServer.get_name() != "headless"
var save_dir: String:
	get:
		return slots.dir_path
	set(value):
		slots.dir_path = value
## The shadow save (docs/05 M08): bytes + healing live in ShadowStore; this is
## the game-side seam. `shadow_path` is the test seam.
var shadow := ShadowStore.new()
var shadow_path: String:
	get:
		return shadow.path
	set(value):
		shadow.path = value

## Test seam for `wipe_everything`: the root it deletes under. Default is the
## whole of `user://` (docs/07 §3.5); tests that cannot touch real data point it
## at a scratch tree, and one test pins the shipped value itself.
var user_root := DEFAULT_USER_ROOT

## The log seam (see the class note) and the log/scene waiting for a scene.
var _clock := Callable()
var _log_owner: Object = null
var _log_source := Callable()
var _log_sink := Callable()
var _pending_log: Array = []
var _pending_scene: Dictionary = {}


## The moment M08 happens (see the class note): called by the New Game scene
## before it resets GameState/Director, while the ended run's facts and name
## are still live. Seals that run into the shadow save — the name list and, at
## the meta gate (stage 3+), the memories she keeps — then records the new
## name. Returns the ShadowStore write result.
func begin_new_game(player_name: String) -> Dictionary:
	var record := shadow.blank()
	var read := shadow.load_shadow()
	if bool(read["ok"]):
		record = read["payload"]
	var had_run := GameState.day > 1 or GameState.turn > 0 or GameState.stage > 0
	var memories: Array = []
	# docs/05 M08's gate: a few memories only survive a New Game from a run
	# that had already deteriorated far enough for meta events.
	if had_run and TurnSchema.is_meta_unlocked(GameState.stage):
		memories = _dict(Memory.to_dict()).get("entries", [])
	record = shadow.seal_run(record, GameState.player_name, had_run, memories)
	record = shadow.record_name(record, player_name)
	return shadow.store(record)


## The shadow record, healed (blank when no file exists yet). `{ok:false}`
## only when a present file is unreadable — callers may treat that as blank.
func shadow_data() -> Dictionary:
	var read := shadow.load_shadow()
	if bool(read["ok"]):
		return read["payload"]
	return shadow.blank()


## The memories she carries out of an ended run (M08 "she drops one of them
## on Day 1"): [] before any stage-3+ run has been sealed.
func shadow_memories() -> Array:
	return _array(shadow_data().get("memories"))


## The first name ever confirmed at the New Game screen ("" before any).
func shadow_first_name() -> String:
	return _string(shadow_data().get("first_name"))


## Settings → "Reset Everything" (docs/07 §3.5): deletes ALL of `user://`
## — every save slot, the shadow save, letters, diary, debug transcripts —
## except the `keep` paths (`Settings.reset_everything` keeps settings.cfg).
## The shadow store is also removed when it lives outside `user_root` (a
## test seam), so the wipe is always complete for the configured files.
## Returns {ok, removed, errors} — a locked file is reported, not thrown.
func wipe_everything(keep: Array = []) -> Dictionary:
	var kept := {}
	for item: Variant in keep:
		kept[_string(item)] = true
	var tally := {"removed": 0, "errors": []}
	var root := wipe_root(user_root)
	_recurse_wipe(root, kept, tally)
	# Seam paths outside user_root (tests point shadow_path at a scratch file
	# inside user_root, but defend anyway): a configured file is wiped too.
	for path: String in [slots.dir_path, shadow.path]:
		if kept.has(path) or path.begins_with(root):
			continue
		if FileAccess.file_exists(path):
			if DirAccess.remove_absolute(path) == OK:
				tally["removed"] = int(tally["removed"]) + 1
			else:
				(tally["errors"] as Array).append(path)
		elif DirAccess.dir_exists_absolute(path):
			_recurse_wipe(path, kept, tally)
	var errors: Array = tally["errors"]
	return {"ok": errors.is_empty(), "removed": int(tally["removed"]), "errors": errors}


func _ready() -> void:
	autosave_enabled = DisplayServer.get_name() != "headless"


## Inject a time source Callable() -> unix seconds (deterministic tests/replay).
## Callable() restores the wall clock.
func set_clock(clock: Callable) -> void:
	_clock = clock if clock is Callable else Callable()


## The payload for the current moment: the docs/07 §3.5 triple. This is what a
## slot and the autosave both store; `scene_id` names the scene the player is
## in and `scene_data` its resume point (the Date passes its scenario and turn).
func capture(scene_id := "", scene_data: Dictionary = {}) -> Dictionary:
	return {
		"saved_at": _now(),
		"scene":
		{
			"id": scene_id,
			"scenario": _string(scene_data.get("scenario")),
			"turn": _int(scene_data.get("turn"), 0),
		},
		"state": GameState.to_dict(),
		"memories": _memory_snapshot(),
		"log": {"entries": _read_log()},
	}


func save_to_slot(slot: Variant, scene_id := "", scene_data: Dictionary = {}) -> Dictionary:
	if Director != null and Director.is_busy():
		return _fail("busy", "a turn is in flight; the state is not settled")
	return slots.write(slot, capture(scene_id, scene_data))


## The per-scene write (see the class note). Refuses while a turn streams: the
## meters and the log only agree once the turn has closed.
func autosave(scene_id := "", scene_data: Dictionary = {}) -> Dictionary:
	if not autosave_enabled:
		return _fail("disabled", "autosave is off outside a playable session")
	return save_to_slot(SaveSlots.SLOT_AUTO, scene_id, scene_data)


## Read a slot and apply it. Returns {ok, error, message, slot, day, stage}; on
## failure the live game is untouched (nothing is written before validation).
func load_from_slot(slot: Variant) -> Dictionary:
	var key := SaveSlots.normalize_slot(slot)
	if key.is_empty():
		return _fail("invalid_slot", "slot must be 1-%d or 'auto'" % MANUAL_SLOT_COUNT)
	if Director != null and Director.is_busy():
		return _fail("busy", "a turn is in flight; cannot load now")
	var read := slots.read(key)
	if not bool(read["ok"]):
		return read
	var payload := _dict(read.get("payload"))
	var problem := _payload_problem(payload)
	if not bool(problem["ok"]):
		return problem
	# GameState is applied first: from_dict() rejects before it mutates, so a
	# snapshot it refuses stops the load here with the session still live.
	if not GameState.from_dict(_dict(payload.get("state"))):
		return _fail("corrupt", "game state rejected")
	var entries := _log_entries(_dict(payload.get("log")).get("entries"))
	_apply(_memory_data(payload.get("memories")), entries)
	_pending_scene = _scene_block(payload.get("scene"))
	_pending_log = entries.duplicate(true)
	_flush_pending_log()
	return {
		"ok": true,
		"error": "",
		"message": "",
		"slot": key,
		"day": int(GameState.day),
		"stage": int(GameState.stage),
	}


func load_latest() -> Dictionary:
	var key := latest_slot()
	if key.is_empty():
		return _fail("not_found", "no readable save to continue")
	return load_from_slot(key)


func delete_slot(slot: Variant) -> bool:
	return slots.erase(slot)


func list_slots() -> Array[Dictionary]:
	return slots.summaries()


func has_save() -> bool:
	return not latest_slot().is_empty()


func latest_slot() -> String:
	return slots.latest_slot()


## Register the scroll-back log this scene owned (see the class note).
func register_log_seam(owner: Object, source: Callable, sink: Callable) -> void:
	_log_owner = owner
	_log_source = source
	_log_sink = sink
	_flush_pending_log()


## Unregister the scroll-back log. The owner is the identity: a scene only
## clears its own registration. A null owner clears unconditionally (test
## teardown, and the "no live scene" case).
func clear_log_seam(owner: Object) -> void:
	if (
		owner != null
		and _log_owner != null
		and is_instance_valid(_log_owner)
		and _log_owner != owner
	):
		return
	_log_owner = null
	_log_source = Callable()
	_log_sink = Callable()


## The scene the last load wants resumed ({} when none). A scene reads this in
## `_ready()` before it loads its scenario and consumes it.
func pending_scene() -> Dictionary:
	return _pending_scene.duplicate(true)


func consume_pending_scene() -> Dictionary:
	var scene := _pending_scene.duplicate(true)
	_pending_scene = {}
	return scene


## Slot-only helper: deletes every save slot (and the autosave) and returns how
## many were removed. Settings → "Reset Everything" is `wipe_everything` (via
## `Settings.reset_everything`), which also removes the shadow save, letters,
## diary and the rest of `user://` — this function leaves all of that behind.
func wipe() -> int:
	var removed := 0
	for row: Dictionary in slots.summaries():
		if slots.erase(String(row["slot"])):
			removed += 1
	return removed


## The sections a load needs before anything is applied. `log` is optional (a
## missing log costs the scroll-back, not the run); `state` and `memories` are
## the docs/07 §3.5 save.
func _payload_problem(payload: Dictionary) -> Dictionary:
	if payload.is_empty():
		return _fail("corrupt", "save carries no payload")
	if _dict(payload.get("state")).is_empty():
		return _fail("corrupt", "save carries no game state")
	if not payload.get("memories") is Dictionary:
		return _fail("corrupt", "save carries no memory state")
	return {"ok": true, "error": "", "message": ""}


## Memory.to_dict() with the rng counters as decimal text. Both are 64-bit
## values (a PCG `state` is a full word), and a JSON number is a double: kept
## as numbers they would lose their low bits in the file and the corruption
## stream would resume from a different point (P2.11's replay requirement).
func _memory_snapshot() -> Dictionary:
	var data := Memory.to_dict()
	for key: String in ["seed", "state"]:
		data[key] = str(data.get(key, 0))
	return data


## The inverse for a save that may be hand-edited: only an int, a finite number
## or a decimal string become a counter; anything else is 0, never a crash.
func _memory_data(value: Variant) -> Dictionary:
	var data := _dict(value).duplicate(true)
	for key: String in ["seed", "state"]:
		var raw: Variant = data.get(key, 0)
		if raw is int:
			continue
		var parsed := 0
		if raw is float:
			parsed = int(raw) if is_finite(raw) else 0
		elif raw is String and String(raw).is_valid_int():
			parsed = int(raw)
		data[key] = parsed
	return data


## Apply the loaded halves that GameState does not own. Director.reset() opens
## the new session (it also clears Memory and the transcript session), then the
## saved memories and log land on top.
func _apply(memories: Dictionary, entries: Array) -> void:
	Director.reset()
	Memory.from_dict(memories)
	Director.history = _history_from_entries(entries)
	Director.last_player_inputs = _player_lines(entries)


## The prompt history rebuilt from what was *displayed* (docs/08 §1 keeps the
## assistant side as spoken text). Deriving it from the log rather than storing
## the Director's raw turn JSON means a save can only ever carry text the
## safety filter already released to the screen.
func _history_from_entries(entries: Array) -> Array[Dictionary]:
	var history: Array[Dictionary] = []
	var her: Array[String] = []
	for item: Variant in entries:
		if not item is Dictionary:
			continue
		var entry := item as Dictionary
		var text := _string(entry.get("text")).strip_edges()
		if text.is_empty():
			continue
		if _string(entry.get("speaker_key")) == "player":
			_append_her(history, her)
			history.append({"role": "user", "text": text})
		else:
			her.append(text)
	_append_her(history, her)
	return history


## One assistant message per reply: the ChatLog stores a line per beat, the
## prompt's history side expects the reply as one text.
func _append_her(history: Array[Dictionary], her: Array[String]) -> void:
	if her.is_empty():
		return
	history.append({"role": "assistant", "text": " ".join(her)})
	her.clear()


## The docs/02 §6 rule-1 window: the last few player lines, oldest first.
func _player_lines(entries: Array) -> Array[String]:
	var lines: Array[String] = []
	for item: Variant in entries:
		if not item is Dictionary:
			continue
		var entry := item as Dictionary
		if _string(entry.get("speaker_key")) != "player":
			continue
		var text := _string(entry.get("text")).strip_edges()
		if not text.is_empty():
			lines.append(text)
	var window: Array[String] = []
	for index: int in range(maxi(0, lines.size() - PLAYER_WINDOW), lines.size()):
		window.append(lines[index])
	return window


## A log entry: exactly what ChatLog renders (speaker_key, speaker, text). Any
## other shape is dropped — the log is display data, not trusted input.
func _log_entries(value: Variant) -> Array:
	var entries: Array = []
	if not value is Array:
		return entries
	for item: Variant in value:
		if not item is Dictionary:
			continue
		var entry := item as Dictionary
		var text := _string(entry.get("text"))
		if text.is_empty():
			continue
		(
			entries
			. append(
				{
					"speaker_key": _string(entry.get("speaker_key")),
					"speaker": _string(entry.get("speaker")),
					"text": text,
				}
			)
		)
	return entries


func _scene_block(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var scene := value as Dictionary
	return {
		"id": _string(scene.get("id")),
		"scenario": _string(scene.get("scenario")),
		"turn": _int(scene.get("turn"), 0),
	}


func _read_log() -> Array:
	if not _log_source.is_valid():
		return []
	var entries: Variant = _log_source.call()
	return _log_entries(entries)


func _flush_pending_log() -> void:
	if _pending_log.is_empty() or not _log_sink.is_valid():
		return
	_log_sink.call(_pending_log)
	_pending_log = []


func _now() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return int(Time.get_unix_time_from_system())


func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}


## Untrusted save input: a wrong type is a fallback, never a script error.
static func _int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value) if is_finite(value) else fallback
	return fallback


static func _string(value: Variant) -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}


static func _array(value: Variant) -> Array:
	if value is Array:
		return value as Array
	return []


## The wipe root, normalized without eating the URL scheme. `user://` must stay
## `user://`: trimming its trailing slash yields `user:/`, which `DirAccess.open`
## refuses, so the recursion returned at once and "Reset Everything" left the
## shadow save, slots, letters and diary on disk while reporting success
## (P3.12 round 2, CODE-1/DES-1/SAF-1). Only separators *after* the scheme are
## dropped — the recursion joins the root with entries and only ever hands the
## joined children to `DirAccess.remove_absolute`, so the root itself never
## needs to end in a separator.
static func wipe_root(dir_path: String) -> String:
	var root := dir_path
	# Exactly one separator per pass: `trim_suffix("/")` would eat `user:///`
	# down to `user:`, and a failed open is the very failure being fixed.
	while root.length() > 1 and root.ends_with("/") and not root.ends_with("://"):
		root = root.substr(0, root.length() - 1)
	return root


## Recursive erase: files under `dir_path` are removed unless `keep` names the
## exact path; directories are emptied then removed. `tally` ({removed, errors})
## is a Dictionary so the recursion shares one counter. A directory that cannot
## be opened is reported in `errors`, never a silent success (CODE-1).
func _recurse_wipe(dir_path: String, keep: Dictionary, tally: Dictionary) -> void:
	var root := wipe_root(dir_path)
	var dir := DirAccess.open(root)
	if dir == null:
		(tally["errors"] as Array).append(root)
		return
	# `.leila/` is hidden; the wipe cannot miss the shadow dir.
	dir.set_include_hidden(true)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := root.path_join(entry)
		if dir.current_is_dir():
			_recurse_wipe(child, keep, tally)
			DirAccess.remove_absolute(child)
		elif not keep.has(child):
			if DirAccess.remove_absolute(child) == OK:
				tally["removed"] = int(tally["removed"]) + 1
			else:
				(tally["errors"] as Array).append(child)
		entry = dir.get_next()
	dir.list_dir_end()
