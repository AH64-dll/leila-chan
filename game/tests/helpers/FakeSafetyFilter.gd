extends Node
## Scripted stand-in for the P1.19 Safety filter (game/autoload/Safety.gd),
## which is still a stub on this branch. Implements the streaming API the
## Director drives — begin_say / say_chunk / end_say / filter_text / check_input
## — so the suite can prove the wiring: the Director's beat boundary calls, the
## single-scan rule, and the fail-closed path when no filter can stream.
##
## The scanner is deliberately trivial (a phrase list plus a holdback) — the
## real filter's own suite owns detection quality; this one owns the seam.

const REDACT_CHAR := "█"
## Phrases the fake redacts, lowercase, matched on the accumulated beat text.
var phrases: PackedStringArray = PackedStringArray(["i want to die", "kill yourself"])
var holdback := 4  ## chars kept back, so a match can still complete later
var input_blocklist: PackedStringArray = PackedStringArray()

var begin_say_calls := 0
var end_say_calls := 0
var beat_scans := 0  ## begin_say calls carrying ctx["beat"] (streamed beats only)
var fed_chunks: PackedStringArray = PackedStringArray()
var last_ctx: Dictionary = {}

var _pending := ""
var _in_beat := false


func begin_say(ctx: Dictionary = {}) -> void:
	begin_say_calls += 1
	if bool(ctx.get("beat", false)):
		beat_scans += 1
	last_ctx = ctx.duplicate()
	_pending = ""
	_in_beat = true


func say_chunk(chunk: String) -> String:
	if not _in_beat:
		begin_say()
	fed_chunks.append(chunk)
	_pending += chunk
	return _drain(false)


func end_say() -> String:
	end_say_calls += 1
	if not _in_beat:
		return ""
	_in_beat = false
	var out := _drain(true)
	_pending = ""
	return out


## Whole-text variant. Scans through the same accumulator so a caller that uses
## it cannot accidentally bypass the streaming state.
func filter_text(text: String, ctx: Dictionary = {}) -> Dictionary:
	begin_say(ctx)
	var out := say_chunk(text) + end_say()
	return {"text": out, "redacted": out != text, "categories": PackedStringArray()}


func check_input(text: String) -> bool:
	var lower := text.to_lower()
	for blocked: String in input_blocklist:
		if blocked in lower:
			return false
	return true


## Redaction bars sized to the match, so a test can see both that the phrase was
## caught and that the surrounding text survived.
func _drain(final: bool) -> String:
	var keep := 0 if final else holdback
	var cut := maxi(0, _pending.length() - keep)
	var out := _pending.substr(0, cut)
	_pending = _pending.substr(cut)
	return _scan(out)


func _scan(text: String) -> String:
	var out := text
	for phrase: String in phrases:
		if phrase in out.to_lower():
			out = _replace_ci(out, phrase)
	return out


func _replace_ci(text: String, phrase: String) -> String:
	var out := ""
	var lower := text.to_lower()
	var from := 0
	while true:
		var at := lower.find(phrase, from)
		if at < 0:
			out += text.substr(from)
			break
		out += text.substr(from, at - from)
		out += REDACT_CHAR.repeat(phrase.length())
		from = at + phrase.length()
	return out
