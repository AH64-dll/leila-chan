class_name CorruptionSession
extends RefCounted
## CorruptionSession — the streaming adapter for Corruption (docs/07 §3.4).
##
## The typewriter consumes `say_chunk` events live, so the filter cannot wait
## for the whole beat before emitting text. This adapter therefore works
## **word-serially**: it holds the trailing partial word back until the stream
## supplies its whitespace boundary (or `flush()` closes the beat), and applies
## the seeded effects to complete words in order. Chunk boundaries are
## invisible to the result: pushing one character at a time and pushing the
## whole beat produce the same text, which is what makes the filter testable
## and replayable.
##
## It is deliberately dumb: every text rule lives in `Corruption`. The session
## only decides *when* a rule fires (per-beat rolls at `begin_beat`, per-word
## rolls at each word), and it draws those rolls from one seeded RNG in a fixed
## order so a replay reproduces the same line.
##
## Lifetime: the ChatUI owns one session and drives it —
##   begin_turn(config) → begin_beat(i) → push(i, chunk)* → flush(i) → end_beat
## `replace_beat` rewrites a queued beat, so `transform_beat()` reruns the
## whole beat from a fresh seed instead of appending to a dead stream.

## Configuration (copied from begin_turn; also writable for tests/tools).
var stage := 0
var path := ""
var player_name := "Senpai"
var reduced_motion := false
var content_level := ""
var turn := 0
## Test/replay salt: changes the seed sequence without touching the data.
var seed_base := 0

var _plan: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _buffer := ""
var _beat := -1
var _started := false
var _word_index := 0
var _counts: Dictionary = {}
var _pending_hesitate := false
var _fired_bleed := false
var _fired_reverse := false
var _beat_text := ""
var _tail_mark := "…"


## New turn: copy the pipeline context ChatUI resolved (stage, names,
## accessibility, seeded turn counter) and drop any half-streamed beat.
func begin_turn(config: Dictionary = {}) -> void:
	stage = int(config.get("stage", stage))
	path = String(config.get("path", path))
	player_name = String(config.get("player_name", player_name))
	reduced_motion = bool(config.get("reduced_motion", reduced_motion))
	content_level = String(config.get("content_level", content_level))
	turn = int(config.get("turn", turn))
	seed_base = int(config.get("seed_base", seed_base))
	abort()


## Start a beat. Rolls the per-beat effects (docs/07 §3.4 gates) now, so the
## same beat index always starts from the same RNG state.
func begin_beat(beat_index: int) -> void:
	_reset_beat(beat_index)
	_started = true


## Feed a streamed say chunk for `beat_index`; returns the text that is safe to
## hand to the typewriter now. A trailing partial word is held until its
## boundary lands or the beat flushes.
func push(beat_index: int, chunk: String) -> String:
	if chunk.is_empty():
		return ""
	if not _started or _beat != beat_index:
		begin_beat(beat_index)
	_beat_text += chunk
	_buffer += chunk
	return _drain()


## Close the beat: process the trailing word, append the stage-5 bleed/reverse
## echoes, and reset. Safe to call twice (the second call returns "").
func flush(beat_index: int) -> String:
	if not _started or _beat != beat_index:
		return ""
	var out := _drain()
	if not _buffer.is_empty():
		out += _process_word(_buffer)
		_buffer = ""
	# A hesitation roll that never found its word boundary lands at the end of
	# a one-word beat rather than being dropped.
	if _pending_hesitate and _word_index > 0:
		out += " " + _tail_mark
		_pending_hesitate = false
	if _fired_bleed:
		var words := int(
			Corruption.table().get("params", {}).get("bleed", {}).get("fragment_words", 2)
		)
		var fragment := Corruption.tail_words(_beat_text, words)
		if not fragment.is_empty():
			out += "\n" + Corruption.bleed_fragment(fragment)
	if _fired_reverse:
		var sentence := Corruption.tail_sentence(_beat_text)
		if not sentence.is_empty():
			out += "\n" + Corruption.reverse_text(sentence)
	_started = false
	_beat = -1
	return out


## Whole-beat variant for ChatUI.replace_beat (docs/02 §7 post-stream repairs):
## the queued beat is rewritten, so the streamed prefix is not continued —
## rerun the beat from its seed and return the complete corrupted text.
func transform_beat(beat_index: int, text: String) -> String:
	_reset_beat(beat_index)
	_started = true
	if text.is_empty():
		return flush(beat_index)
	_beat_text += text
	_buffer += text
	var out := _drain()
	out += flush(beat_index)
	return out


## Drop the in-flight beat (aborted/failed turn). The next push restarts one.
func abort() -> void:
	_started = false
	_beat = -1
	_buffer = ""
	_beat_text = ""
	_word_index = 0
	_counts = {}
	_pending_hesitate = false
	_fired_bleed = false
	_fired_reverse = false


## The plan the current beat is running (tests/debug overlay). Empty before
## the first begin_beat.
func current_plan() -> Dictionary:
	return _plan.duplicate(true)


## ── Internals ──────────────────────────────────────────────────────────────


func _reset_beat(beat_index: int) -> void:
	_beat = beat_index
	_buffer = ""
	_beat_text = ""
	_word_index = 0
	_counts = {}
	_pending_hesitate = false
	_fired_bleed = false
	_fired_reverse = false
	_plan = Corruption.plan(
		stage, {"reduced_motion": reduced_motion, "content_level": content_level}
	)
	_tail_mark = String(Corruption.table().get("params", {}).get("hesitate", {}).get("mark", "…"))
	_rng = RandomNumberGenerator.new()
	_rng.seed = Corruption.seed_for(
		turn, beat_index, int(_plan.get("effective_stage", 0)), seed_base
	)
	_roll_beat_effects()


## Per-beat rolls in pipeline order (the same order every replay). A fired
## per-beat effect arms its marker; its text lands at the documented position
## (hesitation before word 2, bleed/reverse at flush).
func _roll_beat_effects() -> void:
	var effects: Dictionary = _plan.get("effects", {})
	for name: String in Corruption.EFFECT_ORDER:
		var spec: Dictionary = effects.get(name, {})
		if String(spec.get("kind", "word")) != "beat":
			continue
		# Rolled when the stage row gives it a chance, even if reduced motion
		# switched it off: the draw stays in the sequence, so the *other*
		# effects keep their outcomes when the accessibility flag flips.
		if float(spec.get("base_chance", 0.0)) <= 0.0:
			continue
		if _rng.randf() >= float(spec["base_chance"]):
			continue
		if float(spec.get("chance", 0.0)) <= 0.0:
			continue
		_counts[name] = 1
		match name:
			"hesitate":
				_pending_hesitate = true
			"bleed":
				_fired_bleed = true
			"reverse":
				_fired_reverse = true


## Emit every complete word in the buffer (a word is complete once whitespace
## follows it), leaving the trailing partial word held.
func _drain() -> String:
	var out := ""
	while true:
		var at := _first_space(_buffer)
		if at < 0:
			break
		var word := _buffer.substr(0, at)
		var end := at
		while end < _buffer.length() and _is_space(_buffer[end]):
			end += 1
		var sep := _buffer.substr(at, end - at)
		_buffer = _buffer.substr(end)
		if word.is_empty():
			out += sep
			continue
		out += _process_word(word) + sep
	return out


## Apply the effects to one complete word, in docs/07 §3.4 order. The RNG draw
## count per word is fixed by the plan (one roll per word-kind effect whose
## chance is non-zero and whose cap is not reached), not by which effect
## actually produced text — that keeps chunk boundaries out of the result.
func _process_word(word: String) -> String:
	if word.is_empty():
		return ""
	_word_index += 1
	var content := _is_content(word)
	var out := word
	var touched := false

	# 1. hesitation: the pause lands before the second word, so the beat still
	# opens on her first word.
	if _pending_hesitate and _word_index > 1:
		out = _tail_mark + " " + out
		_pending_hesitate = false

	# 2. strike-through self-correction.
	if content and not touched and _can_fire("strike"):
		var struck := Corruption.strike_word(out)
		if not struck.is_empty():
			out = struck
			_bump("strike")
			touched = true

	# 3. word repetition.
	if content and not touched and _can_fire("repeat"):
		var repeated := Corruption.repeat_word(out)
		if not repeated.is_empty():
			out = repeated
			_bump("repeat")
			touched = true

	# 4. wrong name.
	if content and not touched and _can_fire("wrong_name"):
		var renamed := Corruption.wrong_name(out, player_name, _rng)
		if not renamed.is_empty():
			out = renamed
			_bump("wrong_name")
			touched = true

	# 5. zalgo burst. Reduced motion zeroes the plan's chance but not the
	# stage row's `base_chance`; the rolls and the glyph draws are still
	# consumed, and the decorated word is thrown away. That keeps every later
	# effect's RNG outcome identical when the accessibility flag flips — only
	# the jitter glyphs disappear.
	if content and not touched:
		var zspec: Dictionary = (_plan["effects"] as Dictionary)["zalgo"]
		var zbase := float(zspec.get("base_chance", 0.0))
		if zbase > 0.0 and int(_counts.get("zalgo", 0)) < int(zspec.get("max_per_beat", 1)):
			if _rng.randf() < zbase:
				var marked := Corruption.zalgo(
					out, _rng, int(zspec.get("glyphs", 1)), int(zspec.get("marks_per_glyph", 1))
				)
				_bump("zalgo")
				if float(zspec.get("chance", 0.0)) > 0.0:
					out = marked
					touched = true

	# 6. redaction wins the word: it replaces whatever was left.
	if content and _can_fire("redact"):
		var redacted := Corruption.redact_word(out)
		if not redacted.is_empty():
			out = redacted
			_bump("redact")

	return out


func _can_fire(name: String) -> bool:
	var spec: Dictionary = (_plan.get("effects", {}) as Dictionary).get(name, {})
	if spec.is_empty():
		return false
	var chance := float(spec.get("chance", 0.0))
	if chance <= 0.0:
		return false
	if int(_counts.get(name, 0)) >= int(spec.get("max_per_beat", 1)):
		return false
	return _rng.randf() < chance


func _bump(name: String) -> void:
	_counts[name] = int(_counts.get(name, 0)) + 1


func _is_content(word: String) -> bool:
	for i: int in word.length():
		if _is_letter(word[i]):
			return true
	return false


func _first_space(text: String) -> int:
	for i: int in text.length():
		if _is_space(text[i]):
			return i
	return -1


static func _is_space(c: String) -> bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"


static func _is_letter(c: String) -> bool:
	return c.to_lower() != c.to_upper()
