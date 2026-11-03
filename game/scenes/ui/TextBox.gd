extends PanelContainer
## TextBox — the dialogue box (docs/07 §2). Owns the typewriter queue, the
## NameTag and the diegetic typing indicator (docs/02 §4).
##
## Beats queue up exactly as IncrementalJson emits them: begin_beat(i) →
## say_chunk(i, chunk)* → end_beat(i). Beat dictionaries are shared with the
## Typewriter, so a chunk landing mid-reveal just lengthens its beat's text;
## each beat replaces the previous one on screen only after it finished
## revealing — the 35–45 chars/s read-out lags the stream like a visual
## novel, and say_chunk events are consumed live as they land.

## Beat index fully on screen (its spoken text now belongs in the log too).
signal beat_displayed(index: int)
signal all_displayed  ## Every streamed beat so far is on screen.

const IndicScr := preload("res://scenes/ui/TypingIndicator.gd")
const WriterScr := preload("res://scenes/ui/Typewriter.gd")

var _writer: Typewriter
var _indicator: TypingIndicator
## {"i": int, "text": String, "closed": bool} — stream record, shared with the writer.
var _beats: Array = []
var _showing_indicator := false
var _speaker_name := "Leila"

@onready var _body: Label = $VBox/Body
@onready var _name_tag: Label = $VBox/NameTag


func _ready() -> void:
	_ensure_parts()
	_name_tag.text = _speaker_name


func _ensure_parts() -> void:
	if _writer == null:
		_writer = WriterScr.new()
		_writer.revealed.connect(_on_writer_revealed)
		_writer.drained.connect(_on_writer_drained)
		_writer.beat_drained.connect(_on_writer_beat_drained)
	if _indicator == null:
		_indicator = IndicScr.new()


func configure(config: Dictionary) -> void:
	_ensure_parts()
	_writer.configure(config.get("typewriter", {}))
	_indicator.configure(config.get("typing_indicator", {}))
	set_speaker(str(config.get("names", {}).get("leila", "Leila")))


func _process(delta: float) -> void:
	if _showing_indicator:
		_indicator.advance(delta)
		_body.text = _indicator.display_text()
	elif _writer != null:
		_writer.advance(delta)


## ── Beat queue (the Director-facing half of the turn pipeline) ─────────────


## A new beat started streaming. Implicitly closes the previous beat — by
## docs/02 §1 a beat's "say" always finishes before the next beat's fields.
func begin_beat(beat_index: int) -> void:
	_ensure_parts()
	if not _beats.is_empty():
		_beats[_beats.size() - 1]["closed"] = true
	var beat := {"i": beat_index, "text": "", "closed": false}
	_beats.append(beat)
	_writer.append_beat(beat)


## A partial say_chunk for beat `index`: append it to that beat's shared
## buffer and let the typewriter chew through it at its own pace.
func say_chunk(beat_index: int, chunk: String) -> void:
	if chunk.is_empty():
		return
	for beat: Dictionary in _beats:
		if int(beat["i"]) == beat_index:
			beat["text"] = str(beat["text"]) + chunk
			hide_typing_indicator()
			return
	push_warning("TextBox: say_chunk for unknown beat %d ignored" % beat_index)


## The beat's say string closed. The display catches up asynchronously.
func end_beat(beat_index: int) -> void:
	for beat: Dictionary in _beats:
		if int(beat["i"]) == beat_index:
			beat["closed"] = true
			return


## The whole turn's stream finished. Already-closed beats keep revealing.
## If no say text arrived or all queued beats are already drained, clear the
## typing indicator and signal that all displayed content is done.
func end_turn() -> void:
	if not _beats.is_empty():
		_beats[_beats.size() - 1]["closed"] = true
	if _writer != null:
		_writer._maybe_advance_beat()
	var has_pending_beats := false
	for beat: Dictionary in _beats:
		if not bool(beat.get("closed", false)) or str(beat.get("text", "")).length() > 0:
			has_pending_beats = true
			break
	if not has_pending_beats or (_writer != null and _writer.is_complete()):
		hide_typing_indicator()
		all_displayed.emit()


## Abandon the queued beats (failed/cancelled turn) and clear the box.
func reset() -> void:
	_ensure_parts()
	_beats.clear()
	_writer.reset()
	_indicator.stop()
	_showing_indicator = false
	if _body != null:
		_body.text = ""


func _on_writer_revealed(_count: int) -> void:
	_body.text = _writer.get_visible_text()


func _on_writer_beat_drained(index: int) -> void:
	beat_displayed.emit(index)


func _on_writer_drained() -> void:
	all_displayed.emit()


## ── Typing indicator (diegetic, docs/02 §4) ────────────────────────────────


## Show "Leila is typing…" until the first say token lands.
func show_typing_indicator(speaker: String, at_stage: int) -> void:
	_ensure_parts()
	_indicator.begin(speaker, at_stage)
	_showing_indicator = true
	_body.text = _indicator.display_text()


func hide_typing_indicator() -> void:
	if _showing_indicator:
		_indicator.stop()
		_showing_indicator = false
		_body.text = _writer.get_visible_text() if _writer != null else ""


func is_showing_indicator() -> bool:
	return _showing_indicator


## Deterministic seed for the stage-5 "*you*" roll (tests / replays).
func set_indicator_seed(seed_value: int) -> void:
	_ensure_parts()
	_indicator.set_seed(seed_value)


## ── Speaker tag and fast-forward ───────────────────────────────────────────


func set_speaker(speaker_name: String) -> void:
	_speaker_name = speaker_name
	if _name_tag != null:
		_name_tag.text = speaker_name


func get_speaker() -> String:
	return _speaker_name


## Skip the current reveal (Enter / click). Queued beats keep their order.
func reveal_now() -> void:
	if _writer != null:
		_writer.reveal_now()


func is_revealing() -> bool:
	return _writer != null and _writer.is_revealing()


func get_visible_text() -> String:
	if _showing_indicator:
		return _indicator.display_text()
	return _writer.get_visible_text() if _writer != null else ""


## Reduced-motion / instant mode: no character-by-character reveal.
func set_instant(enabled: bool) -> void:
	_ensure_parts()
	_writer.instant = enabled


## Text of a beat (ChatUI logs it on beat_displayed).
func get_beat_text(beat_index: int) -> String:
	for beat: Dictionary in _beats:
		if int(beat["i"]) == beat_index:
			return str(beat["text"])
	return ""
