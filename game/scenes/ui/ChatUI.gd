extends Control
## ChatUI — the composed conversation UI (docs/07 §2): ChatLog on top,
## TextBox (NameTag + typewriter + typing indicator), InputBox at the bottom.
## The Date scene (P1.16) instantiates this and drives the Director-facing
## half; this composite owns wiring, stage data and keyboard-only play.
##
## Turn flow (docs/02 §4):
##   player submits → player_turn_sent(text) → log stores the line, input
##   locks, "Leila is typing…" shows → streamed begin_beat / say_chunk /
##   end_beat feed the typewriter → each fully-shown beat's spoken text lands
##   in the log → end_turn → when the last beat is on screen the input unlocks
##   and grabs focus again.
##
## The inner-voice leak (docs/03 §5, docs/05 M41, P2.07) hangs off the same
## object: `InnerLeak` decides per turn whether her private thought surfaces,
## `leak_inner()` scans it with Safety and plays `InnerLeakLabel` — the ghost
## line drawn behind the text box.

signal player_turn_sent(text: String)  ## The Director (SYS) starts the turn from this.
signal turn_displayed  ## Every beat of her reply is on screen; safe to enable input.
signal pause_requested  ## Esc pressed anywhere in the UI (docs/05 §0 — always opens safe pause).
signal log_toggled(open: bool)  ## Tab toggled the scroll-back log.

var stage := 0  # Instability stage from GameState — drives the indicator flavour
## Safety scan injection point (docs/07 §3.4): a driver that pre-scans may set
## a pass-through; unset warns once per turn that text arrived un-scanned.
## Date.gd sets the pass-through because SaySafetyGate (replies) and
## `_scan_opening_say` (opening beats) already scanned the text — P1.19 CODE-19.
var text_filter: Callable = Callable()
## docs/07 §3.4 corruption stage. Optional `CorruptionSession` (res://llm/
## CorruptionSession.gd) installed by the scene that owns the pipeline
## (Date._ready). It runs AFTER the injected text_filter (Safety) and BEFORE
## the typewriter, exactly as the documented pipeline orders them. Null = the
## filter is off (bare UI tests, non-Date hosts).
var corruption: CorruptionSession = null
## Accessibility mirror for the text effects: reduced motion switches off the
## corruption effects that exist only as visual jitter/smear (Corruption data
## `reduced_motion.disable`). `set_reduced_motion()` writes it; the Settings
## autoload can only force it on, never off.
var reduced_motion := false
## Inner-voice leak (docs/03 §5, docs/05 M41): seeded roll override for tests
## and replays (0 = production). Production draws from `_turn_seq`, like the
## corruption session's seed — no RNG state is stored in the transcript.
var inner_leak_salt := 0

var _player_name := "Senpai"
var _leila_name := "Leila"
var _turn_open := false  # a turn is in flight (input locked, reply streaming)
var _end_pending := false  # end_turn() arrived; waiting for the last beat to display
var _log_open := true
var _config := {}
var _filter_warning_emitted_this_turn := false
var _turn_seq := 0  # seeded per-turn counter for the corruption filter
var _inner_leaked_turn := -1  # `_turn_seq` of the turn whose thought already leaked

@onready var chat_log: ScrollContainer = $Margin/VBox/ChatLog
@onready var text_box: PanelContainer = $Margin/VBox/TextBox
@onready var input_box: LineEdit = $Margin/VBox/InputBox
@onready var inner_leak: InnerLeakLabel = $InnerLeak


func _ready() -> void:
	add_to_group(&"chat_ui")  # Settings pushes text_speed through this path (P3.13)
	_config = UiConfig.load_config()
	apply_config(_config)
	_apply_stored_settings()
	if text_box != null and not text_box.resized.is_connected(_on_text_box_resized):
		text_box.resized.connect(_on_text_box_resized)


## P3.13: the screen inherits the player's stored speed setting the moment it
## exists — a chat opened after the choice never plays one unscaled character.
## (Reduced motion and the content level are already read live per call by
## is_reduced_motion()/_content_level(), so they need no one-shot apply.)
func _apply_stored_settings() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	var scale: Variant = settings.get("text_speed")
	if scale is float or scale is int:
		text_box.set_speed_scale(float(scale))


## The leak's own timeline (a 1 s hold, or word by word then a hold) is stepped
## here exactly like the typewriter's, so the UI owns all of its animation
## clocks and a test can advance it by hand. The label also re-pins itself to the
## box each tick: the TextBox is laid out by its container, so its rect can still
## move a pixel or two on the frame a new indicator/log line lands — the ghost
## line must stay glued to its top edge while it is visible.
func _process(delta: float) -> void:
	if inner_leak != null and inner_leak.is_leaking():
		_place_inner_leak()
		inner_leak.advance(delta)


func apply_config(config: Dictionary) -> void:
	_config = config
	_leila_name = str(config.get("names", {}).get("leila", "Leila"))
	_player_name = str(config.get("names", {}).get("default_player", "Senpai"))
	text_box.configure(config)
	chat_log.configure(config.get("chat_log", {}))
	input_box.configure(config.get("input", {}))
	if not input_box.submitted.is_connected(_on_input_submitted):
		input_box.submitted.connect(_on_input_submitted)
		input_box.pause_requested.connect(_on_pause_requested)
		input_box.log_toggle_requested.connect(_toggle_log)
		text_box.beat_displayed.connect(_on_beat_displayed)
		text_box.all_displayed.connect(_on_all_displayed)
	# Input telemetry (P2.09, docs/02 §4 step 0): the draft hooks live here
	# because this composite owns the InputBox wiring. Telemetry keeps the
	# deleted words in memory only; it is resolved by path so a ChatUI test
	# without the autoload still instantiates.
	if not input_box.draft_deleted.is_connected(_on_draft_deleted):
		input_box.draft_deleted.connect(_on_draft_deleted)
	if not input_box.draft_changed.is_connected(_on_draft_changed):
		input_box.draft_changed.connect(_on_draft_changed)
	_log_open = true
	chat_log.visible = true
	input_box.set_input_enabled(true)


func set_stage(new_stage: int) -> void:
	stage = new_stage


func set_player_name(new_name: String) -> void:
	_player_name = new_name if not new_name.is_empty() else "Senpai"


func get_player_name() -> String:
	return _player_name


## ── Player side ───────────────────────────────────────────────────────────


func _on_input_submitted(text: String) -> void:
	if not input_box.is_input_enabled():
		return
	_note_telemetry("note_activity", [])
	chat_log.append_entry("player", _player_name, text)
	begin_turn_wait()
	player_turn_sent.emit(text)


## The InputBox reports every edit while composing; a clear-without-send is
## the docs/05 M21 / docs/01 T08 deleted draft. The words never touch a file
## or GameState — Telemetry holds them until the next turn spends them.
func _on_draft_changed(_text: String) -> void:
	_note_telemetry("note_activity", [])


func _on_draft_deleted(text: String) -> void:
	_note_telemetry("note_draft_deleted", [text])


## The P2.09 telemetry seam, resolved lazily like the Director's ChatUI seam.
func _note_telemetry(method: String, args: Array) -> void:
	var tel: Node = get_node_or_null("/root/Telemetry")
	if tel != null and tel.has_method(method):
		tel.callv(method, args)


## Lock input and show the diegetic typing indicator until her first say
## token (docs/02 §4). Called on submit; the Director may also call it when a
## turn starts without player input (M30 monologue).
func begin_turn_wait() -> void:
	# The submit calls this to show the indicator, then the Director calls it
	# again at step 1 (`_start_turn`) for the same turn. Only the first call of
	# a turn advances the corruption seed counter, or every reply would be
	# seeded from twice its turn index.
	var turn_start := not _turn_open
	_turn_open = true
	_end_pending = false
	_filter_warning_emitted_this_turn = false
	# A leaked thought belongs to the turn that spoke it: the hold never
	# survives into the next reply.
	if inner_leak != null:
		inner_leak.dismiss()
	if turn_start:
		_turn_seq += 1
		_begin_corruption_turn()
	input_box.set_input_enabled(false)
	text_box.reset()
	text_box.set_speaker(_leila_name)
	text_box.show_typing_indicator(_leila_name, stage)
	# docs/05 M20: focus loss only counts while her line is on screen.
	_note_telemetry("note_turn_open", [true])


## Pipeline context for the docs/07 §3.4 corruption stage: the seeded turn
## counter, the stage the UI is showing, the player's name (the stage-3 "wrong
## name" slip targets it) and the accessibility/content switches. The session
## re-plans every beat, so a stage change between turns is picked up by the
## next begin_turn_wait.
func _begin_corruption_turn() -> void:
	var session := corruption
	if session == null:
		return
	(
		session
		. begin_turn(
			{
				"turn": _turn_seq,
				"stage": stage,
				"player_name": _player_name,
				"reduced_motion": is_reduced_motion(),
				"content_level": _content_level(),
			}
		)
	)


## ── Inner-voice leak (docs/03 §5, docs/05 M41) ─────────────────────────────


## Her private `inner` thought for this turn, if the stage's roll says it leaks.
## This is the only path from model inner text to the screen: the line is
## scanned by the Safety autoload first (fail closed to bars), and only the
## scanned string reaches the label. Returns true when a leak was displayed.
##
## `force` is the F3 dev trigger: it bypasses the docs gate, chance and the
## per-turn cap so a tester can see either style at any stage — it never
## bypasses Safety.
func leak_inner(inner_text: String, force: bool = false) -> bool:
	if inner_leak == null:
		return false
	var text := inner_text.strip_edges()
	if text.is_empty():
		return false
	var plan_dict := InnerLeak.plan(stage, _leak_context())
	if not force:
		if _inner_leaked_turn == _turn_seq:
			return false
		if not InnerLeak.roll(plan_dict, _turn_seq, inner_leak_salt):
			return false
	var scanned := _scan_inner(text)
	if scanned.strip_edges().is_empty():
		return false
	inner_leak.play(scanned, plan_dict)
	_place_inner_leak()
	_inner_leaked_turn = _turn_seq
	return true


## The plan inputs the Settings menu and the scene own (docs/02 §8 calmer,
## docs/05 §0 reduced motion), resolved once for the leak's roll and look.
func _leak_context() -> Dictionary:
	return {"reduced_motion": is_reduced_motion(), "content_level": _content_level()}


## docs/02 §8: any `inner` that will be leaked passes the Safety filter first.
## Fail closed — a build without the scan API shows bars, never raw model text.
func _scan_inner(text: String) -> String:
	var safety_node: Node = get_node_or_null("/root/Safety")
	if safety_node == null or not safety_node.has_method("filter_text"):
		return SaySafetyGate.redact(text)
	var res: Variant = safety_node.call("filter_text", text, {"stage": stage})
	if res is Dictionary:
		var filtered: Variant = (res as Dictionary).get("text")
		if filtered is String:
			return str(filtered)
		return SaySafetyGate.redact(text)
	if res is String:
		return str(res)
	return SaySafetyGate.redact(text)


## The leak is drawn *behind* the box (docs/03 §5): the label sits at z -1 with
## its bottom `behind_overlap` px under the TextBox's top border, so the panel
## occludes that strip. ChatUI.tscn puts the ChatLog on z -2 (it is the bottom
## layer anyway), so the leak draws over the log panel but still under the box —
## a literal "behind everything" draw would sit under the log's 75%-opaque panel
## and read as black.
## Re-placed on every play and each tick it is on screen (the box can settle).
func _place_inner_leak() -> void:
	if inner_leak == null or text_box == null:
		return
	var origin := get_global_rect().position
	var box := text_box.get_global_rect()
	inner_leak.place_above(Rect2(box.position - origin, box.size), InnerLeak.layout())


func _on_text_box_resized() -> void:
	if inner_leak != null and inner_leak.is_leaking():
		_place_inner_leak()


## ── Streamed beat events (IncrementalJson order) ───────────────────────────


func begin_beat(beat_index: int) -> void:
	text_box.hide_typing_indicator()
	if corruption != null:
		corruption.begin_beat(beat_index)
	text_box.begin_beat(beat_index)


## say_chunk: model text passes the injected text_filter before it can reach
## the screen (docs/07 §3.4). The Director's SaySafetyGate scans upstream, so
## in production this seam is a pass-through marker, not a second scan.
func say_chunk(beat_index: int, chunk: String) -> void:
	var filtered := chunk
	if text_filter.is_valid():
		filtered = str(text_filter.call(chunk))
	else:
		if not _filter_warning_emitted_this_turn:
			_filter_warning_emitted_this_turn = true
			push_warning("ChatUI: text_filter unset — say chunk bypassed safety scan")
	# Safety first, corruption second: the corruption stage consumes only
	# already-scanned text (docs/07 §3.4 pipeline order).
	if corruption != null:
		filtered = corruption.push(beat_index, filtered)
	text_box.say_chunk(beat_index, filtered)


## Overwrite a queued beat's text (docs/02 §7 post-stream repairs). Runs the
## same injected safety filter as say_chunk — corrected text is still model
## text and must never bypass the scan. `corrupt = false` is for game-authored
## safety refusals: a redacted refusal must stay legible, so it is displayed
## exactly as the Safety path wrote it.
func replace_beat(beat_index: int, text: String, corrupt: bool = true) -> void:
	var filtered := text
	if text_filter.is_valid():
		filtered = str(text_filter.call(text))
	elif not _filter_warning_emitted_this_turn:
		_filter_warning_emitted_this_turn = true
		push_warning("ChatUI: text_filter unset — replace_beat bypassed safety scan")
	if corrupt and corruption != null:
		filtered = corruption.transform_beat(beat_index, filtered)
	text_box.replace_beat_text(beat_index, filtered)


func end_beat(beat_index: int) -> void:
	# The beat's trailing partial word (and the stage-5 bleed/reverse echoes)
	# must land before the typewriter closes the beat, or they would be lost.
	if corruption != null:
		var tail := corruption.flush(beat_index)
		if not tail.is_empty():
			text_box.say_chunk(beat_index, tail)
	text_box.end_beat(beat_index)


func end_turn() -> void:
	text_box.end_turn()
	_end_pending = true
	_maybe_close_turn()


## Turn died mid-stream (failed / cancelled): clear partial text, drop the
## indicator and hand control back (docs/05 §0 — never leave the player stuck).
func abort_turn() -> void:
	_turn_open = false
	_end_pending = false
	if corruption != null:
		corruption.abort()
	if inner_leak != null:
		inner_leak.dismiss()
	text_box.reset()
	_unlock_input()
	_note_telemetry("note_turn_open", [false])


## A line that never became a turn (docs/02 §4 step 0 safety rejection): the
## submit locked the input, so the refusal is shown as one short beat and the
## turn is ended — the same unlock path her reply takes. Self-sufficient: it
## drops whatever an earlier turn left queued, so a driver never has to clear
## the box first. The Director passes text it already scanned; no second scan.
## Corruption is skipped: a safety refusal must read as written (`corrupt =
## false`), and an abandoned stream's pending word is dropped first.
func reject_turn(text: String) -> void:
	if corruption != null:
		corruption.abort()
	if inner_leak != null:
		inner_leak.dismiss()
	text_box.reset()
	begin_beat(0)
	replace_beat(0, text, false)
	end_beat(0)
	end_turn()


func _on_beat_displayed(beat_index: int) -> void:
	var spoken := str(text_box.get_beat_text(beat_index))
	if not spoken.is_empty():
		chat_log.append_entry("her", _leila_name, spoken)


func _on_all_displayed() -> void:
	_maybe_close_turn()


func _maybe_close_turn() -> void:
	if not _turn_open or not _end_pending:
		return
	if text_box.is_revealing():
		return
	_turn_open = false
	_end_pending = false
	text_box.hide_typing_indicator()
	_unlock_input()
	_note_telemetry("note_turn_open", [false])
	turn_displayed.emit()


func _unlock_input() -> void:
	input_box.set_input_enabled(true)


func is_turn_open() -> bool:
	return _turn_open


## ── Keyboard-only play and pause ───────────────────────────────────────────


## docs/05 §0 rule 3: `PauseMenu._input` owns Esc and pauses before this
## handler runs, so the `ui_cancel` branch only fires in a build without the
## autoload (the suites drive it directly). The scrolling branches are live.
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_pause_requested()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up") and _log_open:
		chat_log.page_scroll(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down") and _log_open:
		chat_log.page_scroll(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_home") and _log_open:
		chat_log.scroll_to_top()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_end") and _log_open:
		chat_log.scroll_to_end()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Tab toggles the scroll-back log (VNs always offer one).
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_log()
		get_viewport().set_input_as_handled()
	# Enter/Space while her text is revealing fast-forwards the typewriter.
	elif event.is_action_pressed("ui_accept") and text_box.is_revealing():
		text_box.reveal_now()
		get_viewport().set_input_as_handled()


func _toggle_log() -> void:
	_log_open = not _log_open
	chat_log.visible = _log_open
	log_toggled.emit(_log_open)


func is_log_open() -> bool:
	return _log_open


func _on_pause_requested() -> void:
	pause_requested.emit()


## Reduced-motion / instant mode for the typewriter (accessibility, docs/05 §0).
## The corruption stage reads the same flag through `is_reduced_motion()`: the
## visual-jitter effects (zalgo, bleed) are switched off there, the textual
## ones (hesitation, strike, repetition, wrong name, redaction, reverse) stay.
func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	text_box.set_instant(enabled)


## Reduced motion as the settings menu and tests define it: the scene's flag
## OR the global Settings switch (the global can only force it on).
func is_reduced_motion() -> bool:
	if reduced_motion:
		return true
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return false
	return bool(settings.get("reduced_motion"))


## Settings.text_speed (P3.13): the settings screen's slider writes through
## Settings, which pushes the scale here so a running reveal changes pace
## mid-line rather than at the next scene.
func set_text_speed_scale(scale: float) -> void:
	text_box.set_speed_scale(scale)


## docs/02 §8 content level for the corruption plan (`calmer` caps the stage).
func _content_level() -> String:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return ""
	var level: Variant = settings.get("content_level")
	return String(level) if level is String else ""
