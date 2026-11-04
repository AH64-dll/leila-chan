class_name Typewriter
extends RefCounted
## Character-at-a-time reveal engine (docs/02 §4: 35–45 chars/s hides the rest
## of the streamed turn). A pure RefCounted — TextBox calls advance(delta)
## from _process; tests call it directly for deterministic timing.
##
## The queue holds beat dictionaries {"i": int, "text": String, "closed":
## bool} shared with the TextBox, so a chunk landing mid-reveal simply
## lengthens the text of the beat it belongs to. A beat counts as "done" only
## when every queued character is on screen AND its stream side is closed: a
## pause between say_chunk events must never read as finished typing.
## get_visible_text() keeps returning the last displayed line once the queue
## is empty — the box never flickers blank between beats.

signal revealed(count: int)  ## count newly visible characters since the last emission.
signal beat_drained(index: int)  ## Beat index fully on screen.
signal drained  ## Every queued beat is closed and fully on screen.

var chars_per_second := 40.0
## Settings.text_speed (P3.13): a multiplier on `chars_per_second`, stored
## separately so `configure()` keeps owning the data-clamped base rate.
var speed_scale := 1.0
var instant := false  ## reduced-motion / photosensitive-safe mode: everything appears at once
var pause_chars: Dictionary = {}  ## {".": 240, ...} extra ms to dwell after the character

var _beats: Array = []  # shared dicts owned by TextBox
var _pos := 0  # visible character count inside _beats[0]
var _credit := 0.0
var _pause_ms := 0.0
var _last_text := ""


func configure(config: Dictionary) -> void:
	var cps := float(config.get("chars_per_second", chars_per_second))
	var cps_min := float(config.get("chars_per_second_min", 35.0))
	var cps_max := float(config.get("chars_per_second_max", 45.0))
	chars_per_second = clampf(cps, cps_min, cps_max)
	if config.get("pause_chars") is Dictionary:
		pause_chars = config["pause_chars"].duplicate()


## Append a beat dictionary {"i", "text", "closed"} to the queue. The dict is
## shared — the caller mutates "text" and "closed" as chunks arrive.
func append_beat(beat: Dictionary) -> void:
	_beats.append(beat)


func reset() -> void:
	_beats = []
	_pos = 0
	_credit = 0.0
	_pause_ms = 0.0
	_last_text = ""


## Advance the reveal by delta seconds. Emits `revealed` once per call when at
## least one character appeared; `beat_drained` fires exactly once per beat;
## `drained` fires when the queue tail is closed and empty.
func advance(delta: float) -> int:
	if instant:
		return _reveal_instant()
	var gained := 0
	if _pause_ms > 0.0:
		_pause_ms -= delta * 1000.0
		if _pause_ms > 0.0:
			return 0
		delta = -_pause_ms / 1000.0  # the leftover frame time still earns characters
		_pause_ms = 0.0
	_credit += delta * chars_per_second * speed_scale
	var guard := 0
	while _credit >= 1.0 and _available() > 0 and guard < 100000:
		guard += 1
		var step := _next_step(int(_credit))
		if step == 0:
			break
		gained += _reveal(step)
		_credit -= step
		if _pause_ms > 0.0:
			_credit = 0.0  # a dwell consumes the rest of the frame's credit
			break
		_maybe_advance_beat()  # carry leftover credit over a beat boundary
	_maybe_advance_beat()
	if _available() == 0:
		# Nothing to chew: the queue is empty, or the front beat is fully
		# revealed but still open — a server pause between say_chunks. Neither
		# may bank credit, or the chunk that finally lands would burst out far
		# faster than the 35–45 chars/s contract (docs/02 §4). Holding it at one
		# character keeps the pause invisible and the burst impossible.
		_credit = minf(_credit, 1.0)
	return gained


## Characters to reveal in one go: the frame's credit, capped at the first
## pause character (revealed inclusive, text must follow it) and at the
## front beat's remaining length.
func _next_step(credit: int) -> int:
	var remaining := _available()
	if remaining <= 0:
		return 0
	var text := _front_text()
	var step := mini(credit, remaining)
	for i: int in range(_pos, _pos + step):
		if pause_chars.has(text[i]) and i < _pos + remaining - 1:
			step = i - _pos + 1
			break
	return step


## Reveal every queued character immediately (skip / fast-forward).
func reveal_now() -> int:
	var count := _queued_count()
	if count <= 0:
		_maybe_advance_beat()
		return 0
	while not _beats.is_empty():
		_pos = _front_text().length()
		_emit_beat_drained()
	revealed.emit(count)
	_maybe_emit_drained()
	return count


func get_visible_text() -> String:
	if _beats.is_empty():
		return _last_text
	return _front_text().substr(0, _pos)


func has_pending() -> bool:
	return _queued_count() > 0


## True while queued text is still hidden or the front beat is still open —
## the visual "typing".
func is_revealing() -> bool:
	if has_pending():
		return true
	return not _beats.is_empty() and not bool(_beats[0].get("closed", false))


## True when nothing is queued (every beat emitted beat_drained).
func is_complete() -> bool:
	return _beats.is_empty()


func _available() -> int:
	if _beats.is_empty():
		return 0
	return _front_text().length() - _pos


func _queued_count() -> int:
	var total := 0
	for i: int in _beats.size():
		var text: String = _beats[i].get("text", "")
		total += text.length() - (_pos if i == 0 else 0)
	return total


func _front_text() -> String:
	return str(_beats[0].get("text", ""))


func _reveal(count: int) -> int:
	var text := _front_text()
	var target := mini(_pos + count, text.length())
	var last := target - 1
	# Dwell after sentence punctuation while more text sits behind it.
	if pause_chars.has(text[last]) and last < text.length() - 1:
		_pause_ms = float(pause_chars[text[last]])
	_pos = target
	revealed.emit(count)
	return count


func _reveal_instant() -> int:
	var count := _queued_count()
	if count <= 0:
		_maybe_advance_beat()
		return 0
	while not _beats.is_empty():
		_pos = _front_text().length()
		_emit_beat_drained()
	revealed.emit(count)
	_maybe_emit_drained()
	return count


## The front beat is fully on screen; only closed beats count as drained — an
## open beat mid-pause keeps waiting for the next chunk to land.
func _maybe_advance_beat() -> void:
	while (
		not _beats.is_empty()
		and bool(_beats[0].get("closed", false))
		and _pos >= _front_text().length()
	):
		_emit_beat_drained()
	_maybe_emit_drained()


func _emit_beat_drained() -> void:
	_last_text = _front_text()
	var index := int(_beats[0].get("i", -1))
	_beats.pop_front()
	_pos = 0
	_pause_ms = 0.0
	beat_drained.emit(index)


func _maybe_emit_drained() -> void:
	if _beats.is_empty():
		drained.emit()
