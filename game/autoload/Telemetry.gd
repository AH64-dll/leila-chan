extends Node
## Telemetry — the engine-event layer behind docs/01 §5's "E" triggers and the
## docs/05 §1.3 input/window events (M19–M21, M30, T09–T12, T31, T32).
##
## One seam, one shape. Every detector normalizes to an engine event:
##   {trigger, event, stage_min, line, data, seq, ts}
## and `_record()` hands it to Triggers (P2.08 owns matching, caps and
## escalation) while queueing the docs/08 §6 EVENT line for the next turn. The
## Director drains that queue at docs/02 §4 step 0 (`take_turn_events`), so the
## line reaches ctx["events"] → PromptBuilder → the model. Detection is
## ungated; `stage_min` is the docs/05 gate for when she may react.
##
## Privacy (docs/05 §0, docs/09): the deleted draft lives only in
## `_private_draft` — never in GameState, a save, the transcript or any file.
## `take_turn_events()` quotes it once at the docs/05 M21 stage (≥ 3), clears
## it, and returns the exact words so the caller can scrub whatever it
## persists. Nothing here touches the network or the filesystem.
##
## Scope: detectors that describe a date only record while a Date is active
## (`set_date_active`), so a title-screen resize or stray keypress can never
## become a turn event. Close requests are observed session-wide (docs/05 M04
## records how you quit) and are never intercepted: quitting always stays one
## press (docs/05 §0); P2.10's close intercept owns M01.

signal engine_event(event: Dictionary)  ## One normalized engine event (docs/01 §5 "E").

const DATA_PATH := "res://data/telemetry.json"

const DRAFT_KIND := "draft_deleted"
const FOCUS_KIND := "focus_lost"
const CLOSE_KIND := "close_requested"
const IDLE_KIND := "idle"
const RESIZE_KIND := "window_resized"
const SCREENSHOT_KIND := "screenshot"
const REPEAT_KIND := "message_repeated"

## docs/01 §5 T31: "Take a screenshot (F12 / in-game camera)". Print Screen is
## the same intent on keyboards that have no F12 row.
const SCREENSHOT_KEYS: Array[int] = [KEY_F12, KEY_PRINT]
## The F3 debug trigger's stand-in draft. Dev-only, invented here on purpose:
## a debug button must never resurrect a player's real deleted words.
const DEBUG_DRAFT_TEXT := "Do you even like me?"

const DEFAULT_LIMITS := {
	"draft_min_chars": 2,
	"draft_quote_stage": 3,
	"draft_quote_max_chars": 160,
	"idle_threshold_s": 60,
	"repeat_window": 3,
	"resize_min_delta": 16,
	"resize_cooldown_ms": 1000,
	"screenshot_cooldown_ms": 250,
}

## In-code fallback mirroring data/telemetry.json (docs/01 §5 + docs/05 §1.3),
## so a missing or partial data file degrades to the documented behaviour
## instead of to silence. The data file is authoritative.
const FALLBACK_EVENTS := {
	"draft_deleted":
	{
		"trigger": "T08",
		"meta": "M21",
		"stage_min": 1,
		"line": "EVENT: The player typed something and deleted it without sending it.",
		"quote_line": 'EVENT: The player typed this and deleted it without sending it: "{text}"',
	},
	"focus_lost":
	{
		"trigger": "T09",
		"meta": "M20",
		"stage_min": 1,
		"line": "EVENT: The game window lost focus while you were talking. The player looked away.",
	},
	"close_requested":
	{
		"trigger": "T10",
		"meta": "M01",
		"stage_min": 3,
		"line": "EVENT: The player tried to close the game.",
	},
	"idle":
	{
		"trigger": "T11",
		"meta": "M30",
		"stage_min": 2,
		"line":
		"EVENT: The player has been silent for {seconds} seconds while you wait for an answer.",
	},
	"window_resized":
	{
		"trigger": "T32",
		"meta": "M19",
		"stage_min": 2,
		"line": "EVENT: The player resized the game window.",
	},
	"screenshot":
	{
		"trigger": "T31",
		"meta": "",
		"stage_min": 0,
		"line": "EVENT: The player took a screenshot of you.",
	},
	"message_repeated":
	{
		"trigger": "T12",
		"meta": "",
		"stage_min": 0,
		"line":
		"EVENT: The player sent the same message again ({count} times in the last few messages).",
	},
}

var _events: Dictionary = {}
var _limits: Dictionary = {}

var _clock: Callable = Callable()
var _pending: Dictionary = {}
var _pending_order: Array[String] = []
var _private_draft := ""
var _recent_messages: Array[String] = []
var _seq := 0
var _date_active := false
var _turn_open := false
var _focused := true
var _idle_armed := true
var _last_activity_ms := 0.0
var _last_resize_emit_ms := 0.0
var _resize_origin := Vector2i.ZERO
var _last_screenshot_ms := 0.0
var _close_requests := 0
var _screenshots := 0


func _ready() -> void:
	load_catalog()
	_connect_window()
	reset_session()


func _exit_tree() -> void:
	_disconnect_window()


func _process(_delta: float) -> void:
	poll_idle()


func _input(event: InputEvent) -> void:
	# Activity keeps the docs/05 M30 idle timer honest; T31 is F12/Print Screen.
	# Never consume the event: the input box, menus and the Director's F3 key
	# must see everything they saw before.
	var key := event as InputEventKey
	if key != null:
		if key.pressed and not key.echo:
			note_activity()
			if _is_screenshot_key(key):
				note_screenshot()
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		note_activity()


## ── Catalogue ─────────────────────────────────────────────────────────────


## Reads data/telemetry.json over the documented fallback (content is data,
## docs/07 §2). Returns false when the file is missing or unusable; every
## already-merged row still works, so a bad file is never fatal.
func load_catalog() -> bool:
	_limits = DEFAULT_LIMITS.duplicate(true)
	_events = FALLBACK_EVENTS.duplicate(true)
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("Telemetry: %s missing; using the docs fallback" % DATA_PATH)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		push_warning("Telemetry: %s is not a JSON object; using the docs fallback" % DATA_PATH)
		return false
	var document: Dictionary = parsed
	var limits: Variant = document.get("limits")
	if limits is Dictionary:
		for key: Variant in limits:
			_limits[str(key)] = limits[key]
	var events: Variant = document.get("events")
	if events is Dictionary:
		for kind: Variant in events:
			var spec: Variant = events[kind]
			if not (spec is Dictionary):
				continue
			var fallback: Variant = FALLBACK_EVENTS.get(str(kind), {})
			var merged: Dictionary = (
				(fallback as Dictionary).duplicate(true) if fallback is Dictionary else {}
			)
			merged.merge(spec as Dictionary, true)
			_events[str(kind)] = merged
	return true


## The merged catalogue (fallback + data), for the F3 overlay and tests.
func catalog() -> Dictionary:
	return _events.duplicate(true)


## The known event kinds in catalogue order (the F3 overlay builds its buttons
## from this, so a data-added event is testable without touching the overlay).
func catalog_kinds() -> Array[String]:
	var kinds: Array[String] = []
	for kind: Variant in _events:
		kinds.append(str(kind))
	return kinds


## One limit from data/telemetry.json with the documented default.
func _limit(name: String) -> Variant:
	return _limits.get(name, DEFAULT_LIMITS.get(name))


## ── Session / date scope ─────────────────────────────────────────────────


## A Date scene is (or is no longer) the active conversation. Date owns this
## call in `_ready`/`_exit_tree`; leaving a date drops stale pending events so
## a resize or draft can never leak into the next scene's first turn.
func set_date_active(active: bool) -> void:
	if _date_active == active:
		if active:
			note_activity()
		return
	_date_active = active
	_turn_open = false
	_recent_messages.clear()
	_clear_pending()
	_idle_armed = true
	note_activity()


## What the overlay and tests read in one call: the pending events (copies, no
## private text — the draft is only reachable through `take_turn_events` or
## `take_private_draft`) plus the state the docs/05 M20/M30 gates depend on.
func state() -> Dictionary:
	var pending: Array = []
	for kind: String in _pending_order:
		if _pending.has(kind):
			pending.append((_pending[kind] as Dictionary).duplicate(true))
	return {
		"date_active": _date_active,
		"turn_open": _turn_open,
		"idle_seconds": _idle_seconds(),
		"draft_pending": not _private_draft.is_empty(),
		"pending": pending,
	}


## Her line is on screen (ChatUI.begin_turn_wait → true, turn close → false).
## docs/05 M20 only exists "during her line", so focus loss without this is not
## an event.
func note_turn_open(open: bool) -> void:
	_turn_open = open
	note_activity()


## Any player input (key, click, draft edit) resets the docs/05 M30 idle clock
## and re-arms the next idle event.
func note_activity() -> void:
	_last_activity_ms = _now_ms()
	_idle_armed = true


## Seconds since the player's last input, at the injected clock.
func _idle_seconds() -> float:
	return maxf(0.0, (_now_ms() - _last_activity_ms) / 1000.0)


## Fresh start: boot, `Director.reset()`, or a test. Caps are per session
## (docs/05 §3), so they restart here too.
func reset_session() -> void:
	_pending.clear()
	_pending_order.clear()
	_private_draft = ""
	_recent_messages.clear()
	_seq = 0
	_close_requests = 0
	_screenshots = 0
	_date_active = false
	_turn_open = false
	_focused = true
	_idle_armed = true
	_last_activity_ms = _now_ms()
	_last_resize_emit_ms = 0.0
	_last_screenshot_ms = 0.0
	_sync_window_size()


## Deterministic tests: Callable() -> float milliseconds. Callable() restores
## the engine clock. Same seam TranscriptLogger uses (`set_clock`).
func set_clock(clock: Callable) -> void:
	_clock = clock


## ── Input detectors ──────────────────────────────────────────────────────


## docs/05 M21 / docs/01 T08: a non-empty draft was erased without sending.
## The words move to `_private_draft` only; one event per turn window so a
## player experimenting in the box cannot flood the prompt. Returns true when
## an event was recorded.
func note_draft_deleted(text: String) -> bool:
	if not _date_active:
		return false
	var trimmed := text.strip_edges()
	if trimmed.length() < int(_limit("draft_min_chars")):
		return false
	_private_draft = trimmed
	if _pending.has(DRAFT_KIND):
		var pending: Dictionary = _pending[DRAFT_KIND]
		var data: Dictionary = pending.get("data", {})
		data["chars"] = trimmed.length()
		return true
	_record(DRAFT_KIND, {"chars": trimmed.length()})
	return true


## docs/01 T12: the same message again within the last `repeat_window`
## submissions (normalized: case, outer and repeated whitespace). The event
## carries a count and a length — never the words (they are already the
## player's chat line, but a repeat is a behavioural fact).
func note_player_message(text: String) -> bool:
	if not _date_active:
		return false
	var normalized := _normalise_message(text)
	if normalized.is_empty():
		return false
	var seen := 0
	for previous: String in _recent_messages:
		if previous == normalized:
			seen += 1
	if seen > 0:
		_record(REPEAT_KIND, {"count": seen + 1, "chars": normalized.length()})
	var window := maxi(1, int(_limit("repeat_window")))
	_recent_messages.push_front(normalized)
	if _recent_messages.size() > window:
		_recent_messages.resize(window)
	return seen > 0


## docs/05 M20 / docs/01 T09: the window lost focus while her line was on
## screen. Returns true when an event was recorded.
func note_focus_lost() -> bool:
	_focused = false
	if not _date_active or not _turn_open:
		return false
	_record(FOCUS_KIND, {})
	return true


## docs/05 M30: the player has been silent for the threshold while she waits.
## One event per idle stretch: activity re-arms it. Skipped while her line is
## still on screen (that is her turn, not the player's silence).
func poll_idle() -> void:
	if not _date_active or not _focused or _turn_open or not _idle_armed:
		return
	var threshold := float(_limit("idle_threshold_s"))
	var idle := _idle_seconds()
	if idle < threshold:
		return
	_idle_armed = false
	_record(IDLE_KIND, {"seconds": int(idle)})


## The submit-time telemetry dict's `idle_seconds` path (docs/02 §4 step 0).
## Returns true when the threshold was crossed and an event was recorded.
func note_idle_seconds(seconds: float) -> bool:
	if not _date_active or seconds < float(_limit("idle_threshold_s")):
		return false
	_idle_armed = false
	_record(IDLE_KIND, {"seconds": int(seconds)})
	return true


## ── Window detectors ─────────────────────────────────────────────────────


## docs/05 M01 / docs/01 T10: the player asked to close the window. Recorded
## only — auto_accept_quit is never touched, so closing still works in one
## press (docs/05 §0). The count lets M01's "intercepted once per session"
## rule and M04's quit memory read the same fact.
func note_close_requested() -> void:
	_close_requests += 1
	_record(CLOSE_KIND, {"count": _close_requests})


## docs/05 M19 / docs/01 T32: a meaningful window resize. Dragging fires a
## burst of size_changed signals, so this coalesces: movement is measured from
## the last reported size and one event lands per cooldown, with no event for
## sub-threshold jitter. Returns true when an event was recorded.
func note_resized(current: Vector2i) -> bool:
	if not _date_active:
		_resize_origin = current
		return false
	var min_delta := int(_limit("resize_min_delta"))
	var delta := current - _resize_origin
	if absi(delta.x) < min_delta and absi(delta.y) < min_delta:
		return false
	var now := _now_ms()
	var cooldown := float(_limit("resize_cooldown_ms"))
	if _last_resize_emit_ms > 0.0 and now - _last_resize_emit_ms < cooldown:
		return false
	var previous := _resize_origin
	_resize_origin = current
	_last_resize_emit_ms = now
	_record(
		RESIZE_KIND,
		{
			"width": current.x,
			"height": current.y,
			"from_width": previous.x,
			"from_height": previous.y,
		}
	)
	return true


## docs/01 T31: an in-game screenshot key was pressed. Print Screen and F12
## both count; the cooldown keeps a held key or a rapid double-tap to one
## event. The in-game camera can call this directly.
func note_screenshot() -> void:
	if not _date_active:
		return
	var now := _now_ms()
	var cooldown := float(_limit("screenshot_cooldown_ms"))
	if _last_screenshot_ms > 0.0 and now - _last_screenshot_ms < cooldown:
		return
	_last_screenshot_ms = now
	_screenshots += 1
	_record(SCREENSHOT_KIND, {"count": _screenshots})


## ── Turn consumption ─────────────────────────────────────────────────────


## Drain the pending events as the docs/08 §6 lines this turn should see.
## Returns {"lines": Array[String], "private": Array[String], "events": Array}.
## Events below their docs/05 stage gate are consumed but not spoken — they
## only ever describe the next turn (docs/08 §6: "this turn only") — and the
## deleted draft is quoted once at stage ≥ `draft_quote_stage`, then cleared.
## `private` holds the exact words the caller must scrub from anything it
## persists; the game never shows them again.
func take_turn_events(stage: int) -> Dictionary:
	var lines: Array[String] = []
	var private_terms: Array[String] = []
	var drained: Array[Dictionary] = []
	for kind: String in _pending_order:
		if not _pending.has(kind):
			continue
		var event: Dictionary = _pending[kind]
		drained.append(event.duplicate(true))
		if stage < int(event.get("stage_min", 0)):
			continue
		var line := str(event.get("line", "")).strip_edges()
		var quote := _draft_quote_line(stage) if kind == DRAFT_KIND else ""
		# At stage >= draft_quote_stage the quote subsumes the bare fact:
		# one line per event per turn.
		if quote.is_empty() and not line.is_empty() and not lines.has(line):
			lines.append(line)
		if not quote.is_empty() and not lines.has(quote):
			lines.append(quote)
			var quoted := _sanitise_draft(_private_draft)
			if not _private_draft.is_empty() and not private_terms.has(_private_draft):
				private_terms.append(_private_draft)
			if not quoted.is_empty() and quoted != _private_draft and not private_terms.has(quoted):
				private_terms.append(quoted)
	_clear_pending()
	return {"lines": lines, "private": private_terms, "events": drained}


## One-shot read of the deleted draft (P2.10 may quote it itself); clears it.
func take_private_draft() -> String:
	var text := _private_draft
	_private_draft = ""
	return text


## ── Dev tooling ──────────────────────────────────────────────────────────


## F3 overlay trigger (dev builds only): fires one detector's event with
## synthetic data, bypassing the date/focus gates so every meta event is
## testable from the overlay even mid-title (role checklist, docs/05 §3).
func debug_fire(kind: String) -> bool:
	if OS.has_feature("release"):
		return false
	match kind:
		DRAFT_KIND:
			_private_draft = DEBUG_DRAFT_TEXT
			_record(DRAFT_KIND, {"chars": DEBUG_DRAFT_TEXT.length()})
		FOCUS_KIND:
			_record(FOCUS_KIND, {})
		CLOSE_KIND:
			note_close_requested()
		IDLE_KIND:
			_record(IDLE_KIND, {"seconds": int(_limit("idle_threshold_s"))})
		RESIZE_KIND:
			_record(RESIZE_KIND, {"width": 0, "height": 0, "from_width": 384, "from_height": 688})
		SCREENSHOT_KIND:
			_screenshots += 1
			_record(SCREENSHOT_KIND, {"count": _screenshots})
		REPEAT_KIND:
			_record(REPEAT_KIND, {"count": 2, "chars": 0})
		_:
			return false
	return true


## ── Internals ────────────────────────────────────────────────────────────


## Normalize one detection into the engine-event shape and fan it out: the
## Triggers seam first (every detection, for caps/escalation), then the queue
## the next turn drains (one line per kind, newest facts win).
func _record(kind: String, data: Dictionary) -> Dictionary:
	var fallback: Variant = _events.get(kind, {})
	var spec: Dictionary = fallback if fallback is Dictionary else {}
	if spec.is_empty():
		push_warning("Telemetry: '%s' is not in %s; the event has no line" % [kind, DATA_PATH])
	var event := {
		"trigger": str(spec.get("trigger", "")),
		"event": kind,
		"stage_min": int(spec.get("stage_min", 0)),
		"line": _format_line(str(spec.get("line", "")), data),
		"data": data.duplicate(true),
		"seq": _seq,
		"ts": int(_now_ms() / 1000.0),
	}
	_seq += 1
	_pending[kind] = event
	if not _pending_order.has(kind):
		_pending_order.append(kind)
	engine_event.emit(event.duplicate(true))
	var triggers: Node = get_node_or_null("/root/Triggers")
	if triggers != null and triggers.has_method("handle_engine_event"):
		triggers.call("handle_engine_event", event.duplicate(true))
	return event


func _clear_pending() -> void:
	_pending.clear()
	_pending_order.clear()
	_private_draft = ""


func _draft_quote_line(stage: int) -> String:
	if _private_draft.is_empty():
		return ""
	if stage < int(_limit("draft_quote_stage")):
		return ""
	var spec: Dictionary = _events.get(DRAFT_KIND, {}) as Dictionary
	var template := str(spec.get("quote_line", "")).strip_edges()
	if template.is_empty():
		return ""
	return _format_line(template, {"text": _sanitise_draft(_private_draft)})


## The draft as prompt text: one line, quotes flattened, length-capped, so a
## pasted novel cannot blow the prompt. The original is what gets scrubbed.
func _sanitise_draft(text: String) -> String:
	var max_chars := int(_limit("draft_quote_max_chars"))
	var out := text.replace("\r", " ").replace("\n", " ").replace('"', "'").strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	if max_chars > 1 and out.length() > max_chars:
		out = out.substr(0, max_chars - 1) + "…"
	return out


func _format_line(template: String, values: Dictionary) -> String:
	if template.is_empty():
		return ""
	var out := template
	for key: Variant in values:
		var token := "{" + str(key) + "}"
		if out.contains(token):
			out = out.replace(token, str(values[key]))
	return out.strip_edges()


func _normalise_message(text: String) -> String:
	var out := (
		text.replace("\t", " ").replace("\r", " ").replace("\n", " ").strip_edges().to_lower()
	)
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out


func _now_ms() -> float:
	if _clock.is_valid():
		return float(_clock.call())
	return float(Time.get_ticks_msec())


func _is_screenshot_key(key: InputEventKey) -> bool:
	if SCREENSHOT_KEYS.has(int(key.keycode)):
		return true
	return SCREENSHOT_KEYS.has(int(key.physical_keycode))


func _sync_window_size() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	_resize_origin = tree.root.size


func _connect_window() -> void:
	if not is_inside_tree():
		return
	var root_window := get_tree().root
	if root_window == null:
		return
	if not root_window.close_requested.is_connected(_on_window_close_requested):
		root_window.close_requested.connect(_on_window_close_requested)
	if not root_window.focus_exited.is_connected(_on_window_focus_exited):
		root_window.focus_exited.connect(_on_window_focus_exited)
	if not root_window.focus_entered.is_connected(_on_window_focus_entered):
		root_window.focus_entered.connect(_on_window_focus_entered)
	if not root_window.size_changed.is_connected(_on_window_size_changed):
		root_window.size_changed.connect(_on_window_size_changed)


func _disconnect_window() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var root_window := tree.root
	if root_window.close_requested.is_connected(_on_window_close_requested):
		root_window.close_requested.disconnect(_on_window_close_requested)
	if root_window.focus_exited.is_connected(_on_window_focus_exited):
		root_window.focus_exited.disconnect(_on_window_focus_exited)
	if root_window.focus_entered.is_connected(_on_window_focus_entered):
		root_window.focus_entered.disconnect(_on_window_focus_entered)
	if root_window.size_changed.is_connected(_on_window_size_changed):
		root_window.size_changed.disconnect(_on_window_size_changed)


func _on_window_close_requested() -> void:
	note_close_requested()


func _on_window_focus_exited() -> void:
	note_focus_lost()


## Focus came back: treat it as activity (the player is here again) so M30's
## idle clock does not count the time they were away twice.
func _on_window_focus_entered() -> void:
	_focused = true
	note_activity()


func _on_window_size_changed() -> void:
	note_resized(get_tree().root.size)
