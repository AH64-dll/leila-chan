class_name MetaDialogsM01
extends CanvasLayer
## MetaDialogsM01 — the in-game replicas docs/05 §1.1 M09–M11 needs: a fake OS
## error dialog, a fake update screen and fake credits. They are Controls drawn
## by this game, never a real OS dialog, never a second window (docs/05 §0
## rules 1–2). Every button leads back into the game, and nothing here reads
## input in `_input`: `PauseMenu` owns `Esc` ahead of every scene, so a replica
## on screen can never trap the panic key (docs/05 §0 rule 3).
##
## The three stages are self-contained and dismissible by keyboard alone:
##   crash    "leila.exe has stopped responding" — [Wait] [Close], both continue
##   update   "Update available: Leila 2.0" — [Install] then a bar that stalls
##            at 99% while she talks; [Later] is always there
##   credits  her name only, rolling, then "That's not how it ends." and out
##
## Accessibility (docs/05 §0 rule 5): reduced motion skips the shake, the
## credits scroll becomes a still page and the black-out is instant. No flicker
## exists in any branch, so photosensitive mode has nothing to disable here.
##
## The clock is a public `advance(seconds)` seam: the node drives itself from
## `_process` in play, and a suite steps the same timeline by hand.

signal dialog_closed(id: String, button: String)  ## A replica's button was pressed.
signal black_out_finished  ## The screen is fully black (M02 quits here).

const LAYER := 90
const DIM := Color(0.0, 0.0, 0.0, 0.58)
const PANEL_BG := Color(0.13, 0.12, 0.14, 0.98)
const PANEL_EDGE := Color(0.5, 0.45, 0.5, 1.0)
const TITLE_COLOR := Color(0.92, 0.9, 0.92)
const BODY_COLOR := Color(0.78, 0.76, 0.8)
const HER_COLOR := Color(0.85, 0.25, 0.3)
const CREDITS_STOP_HOLD := 3.0  ## seconds the stop line stays before it goes
const SHAKE_PX := 4.0  ## the replica's in-window jolt (docs/05 §1.1 M09)

var reduced_motion := false

var _root: Control
var _center: CenterContainer
var _panel: PanelContainer
var _body: VBoxContainer
var _progress: ProgressBar
var _progress_label: Label
var _phase := ""  ## "", "crash", "update", "credits", "black"
var _id := ""
var _elapsed := 0.0
var _progress_seconds := 6.0
var _stall_at := 0.99
var _progress_value := 0.0
var _line_shown := false
var _credits_rows: Array[Control] = []
var _credits_total := 6.0
var _stop_shown := false
var _stop_label: Label
var _black: ColorRect
var _black_seconds := 0.0
var _black_done := false
var _shake_left := 0.0
var _shake_offset := Vector2.ZERO


func _process(delta: float) -> void:
	if _phase.is_empty():
		return
	advance(delta)


## The whole timeline in one place: `_process` calls it in play, suites call it
## with a fixed step. Idempotent per phase, never throws.
func advance(seconds: float) -> void:
	if seconds <= 0.0 or _phase.is_empty():
		return
	_elapsed += seconds
	match _phase:
		"update":
			_advance_update()
		"credits":
			_advance_credits(seconds)
		"black":
			_advance_black()
		"crash":
			_advance_shake(seconds)


## docs/05 §1.1 M09: the replica of an OS error dialog. Both buttons lead back
## into the game; the panel is this node's own Control.
func show_crash(texts: Dictionary, reduced: bool) -> void:
	_close_existing()
	reduced_motion = reduced
	_id = "M09"
	_phase = "crash"
	_build_panel()
	_body.add_child(_label(String(texts.get("window_title", "leila.exe")), HER_COLOR, 13))
	_body.add_child(_label(String(texts.get("title", "")), TITLE_COLOR, 15))
	_body.add_child(_label(String(texts.get("body", "")), BODY_COLOR, 12, true))
	var row := _button_row()
	_add_button(row, "CrashWait", String(texts.get("wait", "Wait")))
	_add_button(row, "CrashClose", String(texts.get("close", "Close")))
	_body.add_child(row)
	# docs/05 §0 rule 5: reduced motion keeps the replica and drops the jitter.
	_shake_left = 0.0 if reduced_motion else 0.35
	_focus_first()


## docs/05 §1.1 M10: "Update available: Leila 2.0 — she's better now."
## [Install] runs a bar that slows to a stop at `stall_at` while she talks;
## [Later] is on screen from the first frame, so the screen is never a trap.
func show_update(texts: Dictionary, reduced: bool) -> void:
	_close_existing()
	reduced_motion = reduced
	_id = "M10"
	_phase = "update"
	_progress_value = 0.0
	_progress_seconds = maxf(0.1, float(texts.get("progress_seconds", 6.0)))
	_stall_at = clampf(float(texts.get("stall_at", 0.99)), 0.1, 1.0)
	_build_panel()
	_body.add_child(_label(String(texts.get("title", "Update available")), TITLE_COLOR, 15))
	_body.add_child(_label(String(texts.get("body", "")), BODY_COLOR, 12, true))
	var row := _button_row()
	_add_button(row, "UpdateInstall", String(texts.get("install", "Install")))
	_add_button(row, "UpdateLater", String(texts.get("later", "Later")))
	_body.add_child(row)
	var progress := ProgressBar.new()
	progress.name = "UpdateProgress"
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.step = 0.001
	progress.value = 0.0
	progress.visible = false
	progress.custom_minimum_size = Vector2(320, 14)
	_body.add_child(progress)
	_progress = progress
	_progress_label = _label(String(texts.get("stall", "")), HER_COLOR, 12, true)
	_progress_label.name = "UpdateStall"
	_progress_label.visible = false
	_body.add_child(_progress_label)
	_focus_first()


## docs/05 §1.1 M11: credits with only her name, then they stop.
func show_credits(texts: Dictionary, reduced: bool) -> void:
	_close_existing()
	reduced_motion = reduced
	_id = "M11"
	_phase = "credits"
	_credits_total = maxf(0.5, float(texts.get("seconds", 6.0)))
	_build_root()
	# No panel and no buttons: the whole screen is the credits roll.
	var holder := Control.new()
	holder.name = "CreditsHolder"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(holder)
	_credits_rows = []
	var lines: Array = texts.get("lines", []) as Array
	var y := 0.0
	for i: int in range(lines.size()):
		var text := String(lines[i])
		if text.is_empty():
			y += 26.0
			continue
		var label := _label(text, TITLE_COLOR if i == 0 else BODY_COLOR, 20 if i == 0 else 14)
		label.name = "Credit%d" % i
		holder.add_child(label)
		label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		label.position.y = y
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_credits_rows.append(label)
		y += 34.0
	# The roll starts just below the screen; reduced motion lays the page still.
	for label: Control in _credits_rows:
		if not reduced_motion:
			label.position.y += 400.0
	_stop_label = _label(String(texts.get("stop_line", "")), HER_COLOR, 22)
	_stop_label.name = "CreditsStop"
	_stop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stop_label.visible = false
	holder.add_child(_stop_label)
	_stop_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_stop_label.position.y = 300.0


## M02: the screen cuts to black, then `black_out_finished`. Reduced motion
## makes the cut immediate instead of a fade (no motion, same end).
func fade_to_black(seconds: float, reduced: bool) -> void:
	_close_existing()
	reduced_motion = reduced
	_phase = "black"
	_id = "M02"
	_black_seconds = 0.0 if reduced_motion else maxf(0.0, seconds)
	_black_done = false
	_build_root()
	_black = ColorRect.new()
	_black.name = "BlackOut"
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_black)
	_advance_black()


## Takes the replica (or the credits, or the black-out) off the screen. Safe to
## call twice; the game underneath is untouched.
func dismiss() -> void:
	_phase = ""
	_id = ""
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_center = null
	_panel = null
	_body = null
	_progress = null
	_progress_label = null
	_stop_label = null
	_credits_rows.clear()


func is_showing() -> bool:
	return not _phase.is_empty()


func current_id() -> String:
	return _id


## The update bar's value (0–1) for the F3 view and the suite.
func progress_value() -> float:
	return _progress_value


## True once the credits have stopped on her line (docs/05 §1.1 M11).
func stop_line_shown() -> bool:
	return _stop_shown


## The button texts on screen right now — the replica's own words, so a test
## can prove [Wait] [Close] are in-game labels and not OS chrome.
func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if _body == null:
		return out
	for node: Node in _body.get_children():
		if node is HBoxContainer:
			for child: Node in node.get_children():
				if child is Button:
					out.append((child as Button).text)
	return out


## Presses one labelled button by its node name (a suite drives the same path a
## click does). Returns false when the replica is not on screen.
func press(button_name: String) -> bool:
	if _root == null:
		return false
	var button := _root.find_child(button_name, true, false) as Button
	if button == null:
		return false
	button.pressed.emit()
	return true


## ── Timeline ─────────────────────────────────────────────────────────────


func _advance_update() -> void:
	if _progress == null:
		return
	var install_visible := _root.find_child("UpdateInstall", true, false) as Button
	if install_visible != null and install_visible.visible:
		return
	# Slows near the stall point: 1-e^-5 is 99.3% of the way at
	# `progress_seconds`, so the bar is visibly crawling for the last stretch.
	var k := maxf(0.1, _progress_seconds / 5.0)
	_progress_value = _stall_at * (1.0 - exp(-_elapsed / k))
	_progress.value = _progress_value
	if _progress_label != null and not _progress_label.visible:
		if _elapsed >= _progress_seconds * 0.4:
			_progress_label.visible = true


func _advance_credits(seconds: float) -> void:
	if reduced_motion:
		if _elapsed >= 1.0 and not _stop_shown:
			_show_stop()
		elif _stop_shown and _elapsed >= 1.0 + CREDITS_STOP_HOLD:
			_finish("end")
		return
	if not _stop_shown:
		for label: Control in _credits_rows:
			label.position.y -= 40.0 * seconds
		if _elapsed >= _credits_total:
			_show_stop()
		return
	if _elapsed >= _credits_total + CREDITS_STOP_HOLD:
		_finish("end")


func _advance_black() -> void:
	if _black == null:
		return
	if _black_seconds <= 0.0:
		_black.color = Color(0.0, 0.0, 0.0, 1.0)
	else:
		_black.color = Color(0.0, 0.0, 0.0, clampf(_elapsed / _black_seconds, 0.0, 1.0))
	if not _black_done and _elapsed >= _black_seconds:
		_black_done = true
		black_out_finished.emit()


## The replica jolts a few pixels the way a hung window does — in-window only
## (docs/05 §0 rules 1–2: a replica, not `window_set_position`), and skipped
## under reduced motion. The root is a plain Control, so its position sticks;
## a container-managed panel would be re-laid out on the next frame.
func _advance_shake(delta: float) -> void:
	if _root == null:
		return
	if _shake_left <= 0.0:
		_root.position = Vector2.ZERO
		return
	_shake_left = maxf(0.0, _shake_left - delta)
	_shake_offset.x = -_shake_offset.x if is_equal_approx(_shake_offset.x, SHAKE_PX) else SHAKE_PX
	_root.position = _shake_offset if _shake_left > 0.0 else Vector2.ZERO


func _show_stop() -> void:
	_stop_shown = true
	if _stop_label != null:
		_stop_label.visible = true


## ── Building blocks ──────────────────────────────────────────────────────


func _close_existing() -> void:
	if _root != null:
		dismiss()


func _build_root() -> void:
	if _root != null:
		return
	layer = LAYER
	_root = Control.new()
	_root.name = "MetaDialogRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)


func _build_panel() -> void:
	_build_root()
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "MetaDialogPanel"
	_panel.custom_minimum_size = Vector2(420, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_EDGE
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_center.add_child(_panel)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 8)
	_panel.add_child(_body)


func _label(text: String, color: Color, size: int, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(380, 0)
	return label


func _button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	return row


func _add_button(row: HBoxContainer, node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(96, 30)
	button.pressed.connect(func() -> void: _on_button(node_name, text))
	row.add_child(button)
	return button


func _focus_first() -> void:
	if _body == null:
		return
	for node: Node in _body.get_children():
		if node is HBoxContainer:
			for child: Node in node.get_children():
				if child is Button:
					(child as Button).grab_focus()
					return


## Install is the one button that does not close the replica: it starts the
## bar. Every other button closes and hands control back (docs/05 §0 rule 3 —
## the player is never stuck in a meta screen).
func _on_button(node_name: String, text: String) -> void:
	if node_name == "UpdateInstall":
		var install := _root.find_child("UpdateInstall", true, false) as Button
		if install != null:
			install.visible = false
		if _progress != null:
			_progress.visible = true
		if _progress_label != null:
			_progress_label.visible = false
		_elapsed = 0.0
		var later := _root.find_child("UpdateLater", true, false) as Button
		if later != null:
			later.grab_focus()
		return
	_finish(text)


func _finish(button: String) -> void:
	var closed_id := _id
	dismiss()
	dialog_closed.emit(closed_id, button)
