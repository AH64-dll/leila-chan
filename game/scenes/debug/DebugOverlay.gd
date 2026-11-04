class_name DebugOverlay
extends CanvasLayer
## DebugOverlay — the F3 Director overlay dev panel (P1.17, docs/07 §5).
## Displays live GameState meters (affection, trust, stress, instability,
## fixation, lucidity, stage, path), steering dose, last turn's read and
## inner monologue, AudioDirector cue budget & music state, FX cooldowns,
## and offered actions.
##
## Dev-only: stripped from release export builds (OS.has_feature("release")).
## Built programmatically for clean dev tooling without binary scene drift.

const MARGIN := 8
const FONT_SIZE := 9
const HEADER_SIZE := 11
const PANEL_WIDTH := 368
const PANEL_HEIGHT := 650

const COLOR_HEADER := Color(1.0, 0.84, 0.45)
const COLOR_SECTION := Color(0.55, 0.8, 1.0)
const COLOR_LABEL := Color(0.85, 0.85, 0.88)
const COLOR_MUTED := Color(0.6, 0.6, 0.65)
const COLOR_READY := Color(0.55, 0.85, 0.6)
const COLOR_COOLDOWN := Color(0.9, 0.5, 0.5)
const COLOR_INNER := Color(0.92, 0.8, 0.95)

var _affection_label: Label
var _trust_label: Label
var _stress_label: Label
var _instability_label: Label
var _fixation_label: Label
var _lucidity_label: Label
var _stage_label: Label
var _path_label: Label
var _day_turn_label: Label
var _dose_label: Label
var _last_read_label: Label
var _last_inner_label: Label
var _music_label: Label
var _cue_budget_label: Label
var _offers_label: Label
var _last_turn_data: Dictionary = {}
var _fx_labels: Dictionary = {}  # fx_name -> Label


static func is_dev_build() -> bool:
	return not OS.has_feature("release")


func _enter_tree() -> void:
	if not is_dev_build():
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		queue_free()


func _ready() -> void:
	if not is_dev_build():
		return

	layer = 120
	visible = false
	_build_ui()
	_connect_signals()
	refresh()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "OverlayPanel"
	panel.position = Vector2(MARGIN, MARGIN)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.94)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - MARGIN * 2, PANEL_HEIGHT - MARGIN * 2)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(root_vbox)

	# --- Header ---
	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(header_row)

	var title := Label.new()
	title.text = "Director Overlay (F3)"
	title.add_theme_font_size_override("font_size", HEADER_SIZE)
	title.modulate = COLOR_HEADER
	header_row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	close_btn.pressed.connect(func() -> void: visible = false)
	header_row.add_child(close_btn)

	var hint := _create_label(
		root_vbox, "[F3 toggle / ESC close] live updates every turn", COLOR_MUTED
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# --- GameState Section ---
	_create_section_header(root_vbox, "GAME STATE & METERS")
	_day_turn_label = _create_label(root_vbox, "Day: 1 | Turn: 0", COLOR_LABEL)
	_stage_label = _create_label(root_vbox, "Stage: 0", COLOR_LABEL)
	_path_label = _create_label(root_vbox, "Path: NONE", COLOR_LABEL)

	var meter_grid := GridContainer.new()
	meter_grid.columns = 2
	meter_grid.add_theme_constant_override("h_separation", 6)
	meter_grid.add_theme_constant_override("v_separation", 2)
	root_vbox.add_child(meter_grid)

	_affection_label = _create_label(meter_grid, "Affection: 0.0", COLOR_LABEL)
	_trust_label = _create_label(meter_grid, "Trust: 0.0", COLOR_LABEL)
	_stress_label = _create_label(meter_grid, "Stress: 0", COLOR_LABEL)
	_instability_label = _create_label(meter_grid, "Instability: 0.0", COLOR_LABEL)
	_fixation_label = _create_label(meter_grid, "Fixation: 0.0", COLOR_LABEL)
	_lucidity_label = _create_label(meter_grid, "Lucidity: 0.0", COLOR_LABEL)

	# --- Steering Section ---
	_create_section_header(root_vbox, "STEERING & DOSE")
	_dose_label = _create_label(root_vbox, "Steering Dose: (none)", COLOR_LABEL)

	# --- Last Turn Dialogue & Monologue ---
	_create_section_header(root_vbox, "LAST TURN")
	_last_read_label = _create_label(root_vbox, "Last Read: (none)", COLOR_LABEL)
	_last_inner_label = _create_label(root_vbox, "Last Inner: (none)", COLOR_INNER)
	_last_inner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# --- Audio Director Section ---
	_create_section_header(root_vbox, "AUDIO DIRECTOR")
	_music_label = _create_label(root_vbox, "Music: none", COLOR_LABEL)
	_cue_budget_label = _create_label(root_vbox, "Cue Budget: tokens 0.0 / 1.0", COLOR_LABEL)

	# --- FX Cooldowns Section ---
	_create_section_header(root_vbox, "FX COOLDOWNS")
	var fx_container := VBoxContainer.new()
	fx_container.add_theme_constant_override("separation", 1)
	root_vbox.add_child(fx_container)

	for fx_name: String in FX.IMPLEMENTED:
		var lbl := _create_label(fx_container, "%s: ready" % fx_name, COLOR_READY)
		_fx_labels[fx_name] = lbl

	# --- Offered Actions Section ---
	_create_section_header(root_vbox, "OFFERED ACTIONS")
	_offers_label = _create_label(root_vbox, "Offered Actions: (none)", COLOR_LABEL)
	_offers_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _create_section_header(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.modulate = COLOR_SECTION
	parent.add_child(label)
	return label


func _create_label(parent: Container, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.modulate = color
	parent.add_child(label)
	return label


func _connect_signals() -> void:
	if GameState != null:
		GameState.meter_changed.connect(func(_m: StringName, _v: float) -> void: refresh())
		GameState.stage_changed.connect(func(_p: int, _c: int) -> void: refresh())
		GameState.path_assigned.connect(func(_p: StringName, _l: bool) -> void: refresh())
		GameState.day_changed.connect(func(_d: int) -> void: refresh())
		GameState.state_reset.connect(func() -> void: refresh())

	if Director != null:
		Director.turn_started.connect(func(_idx: int, _input: String) -> void: refresh())
		Director.turn_completed.connect(_on_turn_completed)

	if AudioDirector != null:
		AudioDirector.music_changed.connect(func(_s: StringName, _p: String) -> void: refresh())
		AudioDirector.cue_played.connect(
			func(_c: StringName, _f: String, _b: StringName) -> void: refresh()
		)
		AudioDirector.cue_denied.connect(func(_c: StringName, _r: StringName) -> void: refresh())

	if FX != null:
		FX.turn_ended.connect(func(_t: int) -> void: refresh())
		FX.fx_triggered.connect(func(_n: String) -> void: refresh())
		FX.fx_dropped.connect(func(_n: String, _r: String) -> void: refresh())


func _on_turn_completed(_idx: int, data: Dictionary) -> void:
	_last_turn_data = data.duplicate(true)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not is_dev_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE and visible:
		visible = false
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F3:
		# If Director exists, let Director toggle; otherwise toggle directly.
		if Director == null or Director.get_debug_overlay() != self:
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if not is_dev_build():
		visible = false
		return
	visible = not visible
	if visible:
		refresh()


func is_open() -> bool:
	return visible


func refresh() -> void:
	if not is_instance_valid(_affection_label):
		return

	# --- GameState meters ---
	if GameState != null:
		_day_turn_label.text = "Day: %d | Turn: %d" % [GameState.day, GameState.turn]
		_stage_label.text = "Stage: %d" % GameState.stage

		var path_str := String(GameState.path)
		if path_str.is_empty():
			path_str = "NONE"
		var lock_str := " [LOCKED]" if GameState.path_locked else " [SOFT]"
		_path_label.text = "Path: %s%s" % [path_str, lock_str]

		_affection_label.text = "Affection: %.1f / 100.0" % GameState.affection
		_trust_label.text = "Trust: %.1f [-50..50]" % GameState.trust

		_stress_label.text = "Stress: %d [-3..3]" % GameState.last_stress

		_instability_label.text = (
			"Instability: %.1f (floor: %.1f, peak: %.1f)"
			% [GameState.instability, GameState.instability_floor, GameState.instability_peak]
		)
		_fixation_label.text = "Fixation: %.1f / 100.0" % GameState.fixation
		_lucidity_label.text = "Lucidity: %.1f / 100.0" % GameState.lucidity

	# --- Steering Dose ---
	# docs/06 §3 (P2.04): the schedule's control-vector scales for the last turn
	# — or this turn's, before the first one runs — e.g. "malice 4.5/12 · path 3.0".
	if _dose_label != null:
		var dose: Dictionary = Director.get_current_dose()
		var dose_str := "none"
		if Steering != null and Steering.has_method("describe"):
			dose_str = Steering.describe(dose)
		_dose_label.text = "Steering Dose: %s" % dose_str

	# --- Last Turn Read & Inner ---
	if _last_read_label != null:
		var r := Director.get_last_read()
		if r.is_empty():
			r = str(_last_turn_data.get("read", ""))
		_last_read_label.text = "Last Read: %s" % (r if not r.is_empty() else "(none)")

	if _last_inner_label != null:
		var inn := Director.get_last_inner()
		if inn.is_empty():
			inn = str(_last_turn_data.get("inner", ""))
		_last_inner_label.text = "Last Inner: %s" % (inn if not inn.is_empty() else "(none)")

	# --- AudioDirector ---
	if _music_label != null:
		var cur_music := "none"
		var pend_music := ""
		if AudioDirector != null:
			if AudioDirector.has_method("current_music"):
				cur_music = String(AudioDirector.current_music())
			if AudioDirector.has_method("pending_music"):
				pend_music = String(AudioDirector.pending_music())
		var mus_text := "Music: %s" % cur_music
		if not pend_music.is_empty():
			mus_text += " (pending: %s)" % pend_music
		_music_label.text = mus_text

	if _cue_budget_label != null:
		var b: Dictionary = AudioDirector.cue_budget()
		_cue_budget_label.text = (
			"Cue Budget: tokens %.2f / %.2f (+%.2f/t)"
			% [
				float(b.get("tokens", 0.0)),
				float(b.get("cap", 1.0)),
				float(b.get("per_turn", 0.5)),
			]
		)

	# --- FX Cooldowns ---
	if FX != null and "IMPLEMENTED" in FX:
		var cur_stage := int(GameState.stage) if GameState != null else 0
		for fx_name: String in FX.IMPLEMENTED:
			if _fx_labels.has(fx_name):
				var status: String = FX.status_for(fx_name, cur_stage)
				var lbl: Label = _fx_labels[fx_name]
				if status.is_empty():
					lbl.text = "%s: ready" % fx_name
					lbl.modulate = COLOR_READY
				else:
					lbl.text = "%s: %s" % [fx_name, status]
					lbl.modulate = COLOR_COOLDOWN

	# --- Offered Actions ---
	if _offers_label != null:
		var offers: Array = Director.get_offered_actions()
		if offers.is_empty():
			_offers_label.text = "Offered Actions: (none)"
		else:
			_offers_label.text = "Offered Actions: %s" % str(offers)


# --- Helper accessors for testing and inspection ---


func get_meter_value(meter_name: String) -> String:
	var label: Label = null
	match meter_name:
		"affection":
			label = _affection_label
		"trust":
			label = _trust_label
		"stress":
			label = _stress_label
		"instability":
			label = _instability_label
		"fixation":
			label = _fixation_label
		"lucidity":
			label = _lucidity_label
	return label.text if label != null else ""


func get_stage_text() -> String:
	return _stage_label.text if _stage_label != null else ""


func get_path_text() -> String:
	return _path_label.text if _path_label != null else ""


func get_day_turn_text() -> String:
	return _day_turn_label.text if _day_turn_label != null else ""


func get_dose_text() -> String:
	return _dose_label.text if _dose_label != null else ""


func get_last_read_text() -> String:
	return _last_read_label.text if _last_read_label != null else ""


func get_last_inner_text() -> String:
	return _last_inner_label.text if _last_inner_label != null else ""


func get_music_state_text() -> String:
	return _music_label.text if _music_label != null else ""


func get_cue_budget_text() -> String:
	return _cue_budget_label.text if _cue_budget_label != null else ""


func get_fx_status_text(fx_name: String) -> String:
	if _fx_labels.has(fx_name):
		return (_fx_labels[fx_name] as Label).text
	return ""


func get_offered_actions_text() -> String:
	return _offers_label.text if _offers_label != null else ""
