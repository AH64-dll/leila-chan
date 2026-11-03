extends CanvasLayer
## FxMenu — the F6 debug panel for FX v1 (P1.11). One row per implemented
## effect: name, a trigger button (FX.debug_trigger — bypasses budgets, still
## respects reduced motion) and the status a real Director trigger would get
## right now. "End turn" advances FX.turn_count so cooldowns can be watched
## expiring. Dev-only: FX only creates this on debug builds.
##
## Built entirely in code: it is a dev panel, not a designed UI screen — the
## authored pixel skin for game UI belongs to META's widgets.

const MARGIN := 8
const FONT_SIZE := 10

var _rows := {}  # effect name -> {status: Label, hint: Label}
var _turn_label: Label
var _host_label: Label


func _ready() -> void:
	layer = 64
	var panel := PanelContainer.new()
	panel.position = Vector2(MARGIN, MARGIN)
	panel.modulate = Color(1, 1, 1, 0.92)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var title := Label.new()
	title.text = "FX debug (F6)"
	title.add_theme_font_size_override("font_size", FONT_SIZE + 2)
	box.add_child(title)
	_turn_label = _line(box, "")
	_host_label = _line(box, "")
	var hint := _line(box, "btns bypass budgets; status = a real trigger's verdict")
	hint.modulate = Color(0.72, 0.68, 0.72)

	for name: String in FX.IMPLEMENTED:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		box.add_child(row)
		var button := Button.new()
		button.text = name
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.pressed.connect(_on_trigger.bind(name))
		row.add_child(button)
		var status := _line(row, "")
		_rows[name] = {"status": status}

	var end := Button.new()
	end.text = "end turn"
	end.add_theme_font_size_override("font_size", FONT_SIZE)
	end.pressed.connect(_on_end_turn)
	box.add_child(end)

	FX.fx_dropped.connect(func(_n: String, _r: String) -> void: refresh())
	FX.fx_triggered.connect(func(_n: String) -> void: refresh())
	FX.turn_ended.connect(func(_t: int) -> void: refresh())
	refresh()


func _line(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	parent.add_child(label)
	return label


func _on_trigger(name: String) -> void:
	var skipped := FX.debug_trigger(name)
	var status: Label = _rows[name]["status"]
	status.text = "-> %s" % skipped if not skipped.is_empty() else "-> fired"
	refresh_statuses()


func _on_end_turn() -> void:
	FX.end_turn()


func refresh() -> void:
	if _turn_label == null:
		return
	_turn_label.text = "turn %d (end_turn advances)" % FX.turn_count
	_host_label.text = "host: %s" % ("Character" if FX.has_host() else "none — trigger drops")
	refresh_statuses()


func refresh_statuses() -> void:
	for name: String in _rows:
		var status: Label = _rows[name]["status"]
		var verdict := FX.status_for(name)
		status.text = verdict if not verdict.is_empty() else "ready"
		status.modulate = Color(0.55, 0.85, 0.6) if verdict.is_empty() else Color(0.85, 0.5, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE and visible:
		visible = false
		get_viewport().set_input_as_handled()
