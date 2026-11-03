extends RefCounted
## Test stand-in for IncrementalJson (lands with P1.03): turns a raw streamed
## turn-JSON string into the beat/say_chunk event sequence the Director feeds
## the UI (docs/02 §4 step 5). Only tracks the "say" strings of beats[] —
## enough to prove the typewriter consumes say_chunk events live, on partial
## chunks and split keys.

signal beat_start(index: int)
signal say_chunk(index: int, text: String)
signal beat_end(index: int)

var _raw := ""
var _cursor := 0
var _in_say := false
var _say_emitted := 0  # decoded characters already forwarded for the open beat
var _beat := -1


func feed(chunk: String) -> void:
	_raw += chunk
	_consume()


func _consume() -> void:
	var guard := 0
	while _cursor < _raw.length() and guard < 100000:
		guard += 1
		if _in_say:
			if _consume_say_body():
				return  # string still open — wait for more tokens
			continue
		var key_pos := _raw.find('"say"', _cursor)
		if key_pos < 0:
			# Keep the tail in case the key itself is split across chunks.
			_cursor = maxi(_cursor, _raw.length() - 4)
			return
		var colon := _raw.find(":", key_pos + 5)
		if colon < 0:
			_cursor = key_pos  # key complete, colon pending
			return
		var quote := _raw.find('"', colon + 1)
		if quote < 0:
			_cursor = key_pos  # wait for the opening quote
			return
		_beat += 1
		_say_emitted = 0
		_in_say = true
		_cursor = quote + 1
		beat_start.emit(_beat)


## Inside a "say" string literal: decode what is complete so far, forward the
## delta, stop at the closing quote. Returns true while the literal is open.
func _consume_say_body() -> bool:
	var i := _cursor
	var escaped := false
	var close := -1
	while i < _raw.length():
		var c := _raw[i]
		if escaped:
			escaped = false
		elif c == "\\":
			escaped = true
		elif c == '"':
			close = i
			break
		i += 1
	var end := close if close >= 0 else _raw.length()
	var decoded := _decode(_raw.substr(_cursor, end - _cursor))
	if decoded.length() > _say_emitted:
		var delta := decoded.substr(_say_emitted)
		_say_emitted = decoded.length()
		say_chunk.emit(_beat, delta)
	if close < 0:
		return true  # _cursor stays at the body start; more tokens are coming
	_cursor = close + 1
	_in_say = false
	beat_end.emit(_beat)
	return false


## Decode a *prefix* of a JSON string body. A trailing lone backslash is
## dropped so a half-written escape never corrupts the delta bookkeeping.
func _decode(body: String) -> String:
	var safe := body
	if safe.ends_with("\\"):
		safe = safe.substr(0, safe.length() - 1)
	var parsed: Variant = JSON.parse_string('"' + safe + '"')
	return parsed if parsed is String else safe
