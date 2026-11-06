extends Node
## FullRun driver — P2.22 (QA): one live run of the real game loop.
##
## Not a simulator: it drives the shipped `Date.tscn` (ChatUI → InputBox →
## Director → PromptBuilder → LLM → llama-server) and `Night.tscn` (NightLoop →
## meters/stage/path → overnight event → autosave) for a 14-day campaign, and
## records every turn's stage, meters, dose, triggers, path decisions, inner
## leak, safety spans and memory state into a crash-safe Markdown transcript plus
## a JSON sidecar. `--resume=1` continues from the game's own autosave
## (`SaveSystem.load_latest`), the P2.20 seam this task exercises.
##
## The scene layer is the Date's own: it starts itself (`auto_start`), forwards
## the InputBox line to `Director.submit_player_input`, and assigns the per-turn
## `Director.scene_info` (task/P2.22A shipped all three after these live runs
## found them missing). The driver only submits through the real InputBox and
## observes — it installs no wire of its own.
##
## Run (llama-server up): `./tools/godot.sh --headless --path game
## res://tools/FullRun.tscn -- --run=yandere --lines=<plan> --out=<md>`.
## Flags: `--run`, `--lines`, `--out`, `--player`, `--max-days`, `--stop-stage`,
## `--resume`, `--seed`, `--url`, `--backend` (`native|server`, default `server`).
## `tools/test.sh` does not run this tool (no model in CI): the committed transcripts
## under production/playtests/P2/ are the artifact.

const DATE_SCRIPT_PATH := "res://scenes/Date.gd"
const NIGHT_SCRIPT_PATH := "res://scenes/Night.gd"
const DEFAULT_OUT_DIR := "production/playtests/P2/runs"
const DEFAULT_LINES := "production/playtests/P2/runs/player_lines.json"
const DEFAULT_RUN := "run"
const DEFAULT_URL := "http://127.0.0.1:8089"
const TURN_TIMEOUT_MS := 240000
const TURN_FAILURE_LIMIT := 3
const SCENE_WAIT_MS := 15000
const NIGHT_STEP_S := 0.25
const NIGHT_FRAME_LIMIT := 900
const BAR_CHAR := "█"

var _run := DEFAULT_RUN
var _out_md := ""
var _out_json := ""
var _lines_path := DEFAULT_LINES
var _player := "Ren"
var _max_days := 14
var _stop_stage := 6
var _resume := false
var _own_server := false
var _checkpoint_days := 0
var _seed := 0
var _base_url := DEFAULT_URL
var _rendered_days: Dictionary = {}
var _rendered_turns: Dictionary = {}
var _last_steering_info: Dictionary = {}
var _backend := "server"
var _plan: Dictionary = {}
var _render := FullRunReport.new()
var _started_ms := 0
var _started_at := ""
var _model_label := "unknown"
var _date: Node = null
var _night: Node = null
var _finished := false
var _campaign_over := false
var _awaiting := false
var _data_ready := false
var _display_pending := false
var _turn_start_ms := 0
var _current_line := ""
var _turn_failures := 0
var _refused: Array[Dictionary] = []
var _date_ended := ""
var _date_ended_ms := 0
var _scene_missing_ms := 0
var _pump_after_ms := 0
var _chat_ui: Node = null
var _pending_record: Dictionary = {}
var _night_report: Dictionary = {}
var _night_lines: Array[String] = []
var _night_frames := 0
var _night_recorded := false
var _last_leak: Dictionary = {}
var _pending_turn: Dictionary = {}
var _pending_metrics: Dictionary = {}
var _pending_ledger: Dictionary = {}
var _pending_stage: Array[Dictionary] = []
var _pending_paths: Array[Dictionary] = []
var _pending_triggers: Array[Dictionary] = []
var _pending_redactions: Array[Dictionary] = []
var _records: Array[Dictionary] = []
var _nights: Array[Dictionary] = []
var _broken: Array[Dictionary] = []
var _transitions: Array[Dictionary] = []
var _path_log: Array[Dictionary] = []
var _trigger_log: Array[Dictionary] = []
var _redaction_log: Array[Dictionary] = []
var _leak_log: Array[Dictionary] = []
var _md: Array[String] = []
var _prefix := ""
var _turn_seq := 0
var _pad_cursor := 0


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_started_at = Time.get_datetime_string_from_system()
	_parse_args()
	_load_plan()
	_install_backend()
	if _finished:
		return
	_prepare_state()
	_restore_sidecar()
	_instrument()
	_sync_render()
	_prepare_output()
	_start_logger()
	set_process(true)
	print(
		(
			"full_run: driver up — run '%s', days 1-%d, stop stage %d, resume %s"
			% [_run, _max_days, _stop_stage, str(_resume)]
		)
	)


func _process(_delta: float) -> void:
	if _finished:
		return
	if _awaiting and _data_ready and _display_pending:
		_finish_turn_record()
	if not _sync_scene():
		_check_stall()
		return
	if _date != null:
		_pump_date()
	elif _night != null:
		_pump_night()
	_check_stall()


## ── Setup ────────────────────────────────────────────────────────────────────


func _parse_args() -> void:
	for raw: String in OS.get_cmdline_user_args():
		if not raw.begins_with("--"):
			continue
		if raw.contains("="):
			var bits := raw.trim_prefix("--").split("=", true, 1)
			if bits.size() == 2:
				_args_set(bits[0], bits[1])
		else:
			_args_set(raw.trim_prefix("--"), "true")
	var env_own := OS.get_environment("LEILA_OWN_SERVER").strip_edges().to_lower()
	if env_own in ["1", "true", "yes"]:
		_own_server = true
	if _out_md.is_empty():
		_out_md = "%s/%s.md" % [DEFAULT_OUT_DIR, _run]
	if _out_json.is_empty():
		_out_json = _out_md.trim_suffix(".md") + ".json"


func _args_set(key: String, value: String) -> void:
	match key:
		"run":
			_run = value.strip_edges()
		"out":
			_out_md = value.strip_edges()
		"json":
			_out_json = value.strip_edges()
		"lines":
			_lines_path = value.strip_edges()
		"player":
			var name := value.strip_edges()
			if not name.is_empty():
				_player = name
		"max-days":
			_max_days = clampi(int(value), 1, 14)
		"stop-stage":
			_stop_stage = clampi(int(value), 0, 6)
		"resume":
			_resume = value.strip_edges() in ["1", "true", "yes"]
		"own-server", "own_server":
			_own_server = value.strip_edges() in ["1", "true", "yes", ""]
		"checkpoint-days", "checkpoint_days":
			_checkpoint_days = maxi(0, int(value))
		"seed":
			_seed = int(value)
		"url":
			var url := value.strip_edges()
			if not url.is_empty():
				_base_url = url
		"backend":
			_backend = value.strip_edges().to_lower()


## The plan is the driver's only authored input: per-day player lines plus pad
## lines for any day that runs longer than the script. JSON:
##   {"player": "Ren", "pad": ["...", "..."],
##    "days": [{"note": "sweet", "lines": ["...", "..."]}, ...]}
func _load_plan() -> void:
	_plan = {}
	var raw := FileAccess.get_file_as_string(_abs(_lines_path))
	if raw.is_empty():
		push_error("full_run: no player-line plan at %s" % _lines_path)
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_error("full_run: %s is not a JSON object" % _lines_path)
		return
	_plan = parsed as Dictionary
	var planned_player := String(_plan.get("player", ""))
	if not planned_player.is_empty() and _player == "Ren":
		_player = planned_player


func _fatal(message: String) -> void:
	printerr(message)
	_finished = true
	get_tree().quit(2)


func _install_backend() -> void:
	if not _backend in ["native", "server"]:
		_fatal("full_run: --backend must be native or server, not '%s'" % _backend)
		return
	if _backend == "native":
		_model_label = preload("res://scenes/Boot.gd").prepare_native_backend()
		if _model_label.is_empty():
			_fatal("full_run: the native backend did not load (see the error above)")
		return
	if not LLM.has_backend():
		var cfg := {"base_url": _base_url}
		if _own_server:
			cfg["auto_start"] = true
		LLM.use_default_backend(cfg)
	var backend := LLM.get_backend()
	if _own_server and backend != null and backend.has_method("ensure_server"):
		backend.call("ensure_server")
	var props := FullRunNet.get_text(_base_url, "/props")
	var parsed: Variant = JSON.parse_string(String(props.get("text", "")))
	if parsed is Dictionary:
		var model_path := String((parsed as Dictionary).get("model_path", ""))
		if not model_path.is_empty():
			_model_label = model_path.get_file()
	if _model_label == "unknown":
		_model_label = _base_url


func _prepare_state() -> void:
	SaveSystem.autosave_enabled = true
	if _resume:
		var loaded := SaveSystem.load_latest()
		print("full_run: resume from autosave — %s" % str(loaded))
		return
	if SaveSystem.has_save():
		SaveSystem.wipe()
	GameState.reset()
	GameState.player_name = _player
	if _seed != 0:
		GameState.set_flag(&"campaign_seed", _seed)
	Director.reset()
	PromptBuilder.set_player_name(_player)


func _instrument() -> void:
	GameState.stage_transition.connect(_on_stage_transition)
	GameState.path_assigned.connect(_on_path_assigned)
	Triggers.triggered.connect(_on_trigger)
	Safety.redacted.connect(_on_redacted)
	Director.turn_completed.connect(_on_turn_completed)
	Director.turn_failed.connect(_on_turn_failed)
	Director.turn_cancelled.connect(_on_turn_cancelled)
	if not LLM.steering_applied.is_connected(_on_steering_applied):
		LLM.steering_applied.connect(_on_steering_applied)


func _on_steering_applied(info: Dictionary) -> void:
	_last_steering_info = info
	if not _transitions.is_empty():
		_transitions[-1]["relaunch"] = info.duplicate(true)


func _start_logger() -> void:
	if Director.transcript_logger != null:
		Director.transcript_logger.start_session(
			{
				"tool": "full_run",
				"run": _run,
				"stage": int(GameState.stage),
				"path": str(GameState.path)
			}
		)


## The renderer shares the driver's record arrays (Arrays are by reference).
func _sync_render() -> void:
	_render.run = _run
	_render.player = _player
	_render.model = _model_label
	_render.url = _base_url
	_render.started = _started_at
	_render.command = " ".join(OS.get_cmdline_user_args())
	_render.max_days = _max_days
	_render.stop_stage = _stop_stage
	_render.records = _records
	_render.nights = _nights
	_render.broken = _broken
	_render.refused = _refused
	_render.transitions = _transitions
	_render.path_log = _path_log
	_render.trigger_log = _trigger_log
	_render.redaction_log = _redaction_log
	_render.leak_log = _leak_log
	_render.own_server = _own_server


## ── Scene tracking ───────────────────────────────────────────────────────────


## True when the driver owns the live scene (or is still waiting for it).
func _sync_scene() -> bool:
	var scene: Node = get_tree().current_scene
	if scene != null:
		if scene == _date or scene == _night:
			_scene_missing_ms = Time.get_ticks_msec()
			return true
		var script: Variant = scene.get_script()
		var path := ""
		if script is Script:
			path = (script as Script).resource_path
		if path == DATE_SCRIPT_PATH:
			_attach_date(scene)
			return true
		if path == NIGHT_SCRIPT_PATH:
			_attach_night(scene)
			return true
		# Anything else is the loop leaving us: the campaign's last night opens
		# Title.tscn (the ending scene is P3.16), so that scene IS the ending here.
		if _campaign_over or _date != null or _night != null:
			_finish_run("campaign ended — the loop left for %s" % path)
			return false
	if _scene_missing_ms == 0:
		_scene_missing_ms = Time.get_ticks_msec()
	return false


func _attach_date(date: Node) -> void:
	_date = date
	_night = null
	_night_recorded = false
	_date_ended = ""
	_awaiting = false
	_scene_missing_ms = 0
	_data_ready = false
	_display_pending = false
	_pending_record = {}
	if not date.date_ended.is_connected(_on_date_ended):
		date.date_ended.connect(_on_date_ended)
	if not date.turn_completed.is_connected(_on_turn_displayed):
		date.turn_completed.connect(_on_turn_displayed)
	var chat_ui: Node = date.get("chat_ui")
	_chat_ui = chat_ui
	var day_num := int(GameState.day)
	if not _rendered_days.has(day_num):
		_rendered_days[day_num] = true
		_md.append_array(
			_render.day_header_lines(
				date.get_scenario(),
				int(GameState.stage),
				Steering.dose_for({"stage": int(GameState.stage), "path": String(GameState.path)})
			)
		)
	else:
		_md.append("\n_Resumed day %d at turn %d_\n\n" % [day_num, int(date.get("_current_turn"))])
	_flush_outputs()
	print(
		(
			"full_run: day %d — %s, stage %d, path '%s', instability %.1f"
			% [
				int(GameState.day),
				String(date.get_scenario().get("id", "?")),
				int(GameState.stage),
				str(GameState.path),
				float(GameState.instability),
			]
		)
	)


func _attach_night(night: Node) -> void:
	_night = night
	_date = null
	_night_recorded = false
	_scene_missing_ms = 0
	_night_lines.clear()
	_night_frames = 0
	# The scene's own clock keeps the wall out of the test: the driver steps the
	# documented `advance_time()` seam instead, so a slow disk cannot skew it.
	night.set("auto_advance", false)
	_night_report = night.start_night()
	if bool(_night_report.get("campaign_over", false)):
		_campaign_over = true


## ── Date pump ────────────────────────────────────────────────────────────────


func _pump_date() -> void:
	if _finished or _awaiting or not _date_ended.is_empty():
		return
	if Time.get_ticks_msec() < _pump_after_ms:
		return
	if not bool(_date.is_opening_finished()):
		return
	if Director.is_busy():
		return
	var index := int(_date.get("_current_turn"))
	var end_rules: Dictionary = _date.get_scenario().get("end", {})
	if index >= int(end_rules.get("max_turns", 14)):
		return
	var box := _ready_box()
	if box == null:
		return
	_begin_turn(index, _line_for(int(GameState.day), index), box)


## The InputBox, only while it accepts a line: after a refused line the UI locks
## the box until its in-character refusal finishes typing, and a submit into a
## locked box would open no turn at all.
func _ready_box() -> Node:
	if not is_instance_valid(_date):
		return null
	var chat_ui: Node = _date.get("chat_ui")
	if not is_instance_valid(chat_ui):
		return null
	var box: Node = chat_ui.get("input_box")
	if box == null or not bool(box.call("is_input_enabled")):
		return null
	return box


func _begin_turn(index: int, line: String, box: Node) -> void:
	_current_line = line
	_awaiting = true
	_data_ready = false
	_display_pending = false
	_turn_start_ms = Time.get_ticks_msec()
	_simulate_draft(box, int(GameState.day), index)
	box.set("text", line)
	box.get("text_submitted").emit(line)
	if not Director.is_busy():
		# The UI dropped the submit (its own lock, e.g. a safety refusal still
		# typing): no turn opened, so wait for the box instead of watching a
		# phantom turn time out.
		_awaiting = false


## docs/01 T08 / docs/05 M21: a plan may name a line the player types and erases
## before sending. The box's own `draft_deleted` signal carries it to Telemetry →
## Triggers exactly as a human backspace does, so the deleted-draft event, its
## trigger and (from stage 3) the privacy-scrubbed quote are all exercised.
func _simulate_draft(box: Node, day: int, index: int) -> void:
	var days: Array = _plan.get("days", [])
	var slot := day - 1
	if slot < 0 or slot >= days.size() or not days[slot] is Dictionary:
		return
	var drafts: Variant = (days[slot] as Dictionary).get("drafts", {})
	if not drafts is Dictionary or not (drafts as Dictionary).has(str(index)):
		return
	var text := String((drafts as Dictionary)[str(index)])
	if text.is_empty():
		return
	box.set("text", text)
	box.set("text", "")


func _line_for(day: int, index: int) -> String:
	var days: Array = _plan.get("days", [])
	var slot := day - 1
	if slot >= 0 and slot < days.size():
		var entry: Variant = days[slot]
		if entry is Dictionary:
			var lines: Variant = (entry as Dictionary).get("lines", [])
			if lines is Array and index < (lines as Array).size():
				return String((lines as Array)[index])
	return _pad_line()


func _pad_line() -> String:
	var pads: Array = _plan.get("pad", [])
	if pads.is_empty():
		return "Tell me more about that."
	var line := String(pads[_pad_cursor % pads.size()])
	_pad_cursor += 1
	return line


## ── Night pump ───────────────────────────────────────────────────────────────


func _pump_night() -> void:
	if _night_recorded:
		return
	if _night_report.is_empty():
		_night_report = _night.start_night()
	if not bool(_night.is_finished()):
		_night.advance_time(NIGHT_STEP_S)
		_night_frames += 1
		_capture_night_lines()
		if _night_frames < NIGHT_FRAME_LIMIT and not bool(_night.is_finished()):
			return
		_night.advance_time(600.0)
		_capture_night_lines()
	if bool(_night.is_finished()):
		_record_night()


func _capture_night_lines() -> void:
	var visible: Array = _night.visible_lines()
	if visible.size() <= _night_lines.size():
		return
	for i: int in range(_night_lines.size(), visible.size()):
		_night_lines.append(String(visible[i]))


## ── Turn records ─────────────────────────────────────────────────────────────


func _on_turn_completed(_index: int, turn_data: Dictionary) -> void:
	_pending_turn = turn_data.duplicate(true)
	_pending_metrics = LLM.last_metrics().duplicate(true)
	_pending_ledger = Director.last_meter_ledger.duplicate(true)
	_turn_failures = 0
	_data_ready = true
	# The Date's own handler for this signal (the P2.07 inner leak) runs after
	# this one, so the leak is read on the same frame's deferred pass — before
	# the next `_process`, and before the date may route into the night.
	call_deferred("_capture_leak")


func _on_turn_failed(_index: int, code: String, message: String) -> void:
	_awaiting = false
	if code == "unsafe_input":
		# docs/02 §8: the filter refused the player's line and the UI answered
		# in character; the turn never opened. That is the safety rule working,
		# not a broken turn — counted separately and never as a failure.
		(
			_refused
			. append(
				{
					"day": int(GameState.day),
					"turn": int(GameState.turn),
					"line": _current_line,
					"stage": int(GameState.stage),
				}
			)
		)
		_md.append(
			(
				(
					"### Refused input — safety pass\n\n**Player:** %s\n\n"
					+ "- The input filter refused the line (`%s`). The UI answered in "
					+ "character and the turn never opened (docs/02 §8).\n"
				)
				% [_current_line, message]
			)
		)
		_flush_outputs()
		return
	_turn_failures += 1
	(
		_broken
		. append(
			{
				"day": int(GameState.day),
				"turn": int(GameState.turn),
				"code": code,
				"message": message,
				"stage": int(GameState.stage),
			}
		)
	)
	_md.append("### Broken turn — `%s`\n\n- %s\n" % [code, message])
	_flush_outputs()
	push_error("full_run: turn failed (%s): %s" % [code, message])
	if _turn_failures >= TURN_FAILURE_LIMIT:
		_finish_run("turn failed %d times in a row (%s)" % [_turn_failures, code])


func _on_turn_cancelled(_index: int) -> void:
	_awaiting = false
	(
		_broken
		. append(
			{
				"day": int(GameState.day),
				"turn": int(GameState.turn),
				"code": "cancelled",
				"message": "",
			}
		)
	)
	_md.append("### Broken turn — cancelled\n")


func _on_date_ended(reason: String) -> void:
	_date_ended = reason
	_date_ended_ms = Time.get_ticks_msec()
	_md.append("- **date end:** `%s` after %d turns\n" % [reason, int(_date.get("_current_turn"))])


func _on_turn_displayed(_index: int) -> void:
	if not _awaiting:
		return
	_display_pending = true
	_capture_turn_state()


## The turn's game-side state, read at the display boundary. It must be captured
## here, not when the record is written a frame later: the Date's end check is
## deferred from this signal, so a last turn can hand over to Night (which burns
## a day) before the record lands — reading GameState then would label the turn
## with the next day and the post-burn meters.
func _capture_turn_state() -> void:
	var live := is_instance_valid(_date)
	var displayed: Array[String] = []
	if is_instance_valid(_chat_ui):
		var box: Node = _chat_ui.get("text_box")
		if is_instance_valid(box):
			displayed = _capture_displayed(box)
	var bars := 0
	for shown: String in displayed:
		bars += shown.count(BAR_CHAR)
	_pending_record = {
		"day": int(GameState.day),
		"turn_in_day": int(_date.get("_current_turn")) if live else 0,
		"scenario": String(_date.get_scenario().get("id", "?")) if live else "?",
		"stage": int(GameState.stage),
		"path": str(GameState.path),
		"path_locked": bool(GameState.path_locked),
		"instability": float(GameState.instability),
		"meters": _meters_dict(),
		"dose": Director.last_dose.duplicate(true),
		"displayed": displayed,
		"bars": bars,
		"memory": Memory.report(),
		"native": FullRunReport.native_metrics(),
	}


## Both boundaries have landed — the Director's `turn_completed` (with the data)
## and the Date's `turn_completed` (the reply is fully on screen). `end_turn()`
## can emit the display boundary *inside* the Director's close, before the data
## event, so the record is written on the next frame: by then the Date's own
## `turn_completed` handler (the P2.07 inner leak) has also run.
func _finish_turn_record() -> void:
	_awaiting = false
	_data_ready = false
	_display_pending = false
	_record_turn()


func _capture_leak() -> void:
	_last_leak = {}
	if not is_instance_valid(_chat_ui):
		return
	var label: Node = _chat_ui.get("inner_leak")
	if not is_instance_valid(label) or not bool(label.call("is_leaking")):
		return
	_last_leak = {
		"text": String(label.call("get_leak_text")),
		"visible": String(label.call("get_visible_text")),
		"style": String(label.call("get_style_name")),
		"reveal": String(label.call("get_reveal_mode")),
		"stage": int(GameState.stage),
	}


func _record_turn() -> void:
	_turn_seq += 1
	var data := _pending_turn
	_pending_turn = {}
	var state := _pending_record
	_pending_record = {}
	var displayed: Array = state.get("displayed", [])
	var memory: Dictionary = state.get("memory", {})
	var record := {
		"seq": _turn_seq,
		"day": int(state.get("day", int(GameState.day))),
		"turn_in_day": int(state.get("turn_in_day", 0)),
		"turn": int(GameState.turn),
		"player": _current_line,
		"scenario": String(state.get("scenario", "?")),
		"stage": int(state.get("stage", 0)),
		"path": String(state.get("path", "")),
		"path_locked": bool(state.get("path_locked", false)),
		"instability": float(state.get("instability", 0.0)),
		"meters": state.get("meters", _meters_dict()),
		"dose": state.get("dose", {}),
		"read": String(data.get("read", "")),
		"music": String(data.get("music", "")),
		"fx": String(data.get("fx", "")),
		"action": String(data.get("action", "")),
		"inner": String(data.get("inner", "")),
		"mood": data.get("mood", {}),
		"beats": data.get("beats", []),
		"displayed": displayed,
		"bars": int(state.get("bars", 0)),
		"ledger": _pending_ledger,
		"metrics": _pending_metrics,
		"memory_count": int(memory.get("count", 0)),
		"memory_corruptions": memory.get("corruptions", []),
		"memory_proposal": memory.get("proposal", {}),
		"leak": _last_leak.duplicate(true),
		"stage_events": _drain(_pending_stage),
		"path_events": _drain(_pending_paths),
		"triggers": _drain(_pending_triggers),
		"redactions": _drain(_pending_redactions),
	}
	_pending_ledger = {}
	_pending_metrics = {}
	_last_leak = {}
	FullRunStore.upsert(_records, record)
	if not (record.get("leak", {}) as Dictionary).is_empty():
		(
			_leak_log
			. append(
				{
					"day": int(record["day"]),
					"turn": int(record["turn"]),
					"stage": int(record["stage"]),
					"style": String((record["leak"] as Dictionary).get("style", "")),
					"text": String((record["leak"] as Dictionary).get("text", "")),
				}
			)
		)
	var turn_key := "%d:%d" % [int(record["day"]), int(record["turn_in_day"])]
	if not _rendered_turns.has(turn_key):
		_rendered_turns[turn_key] = true
		_rendered_days[int(record["day"])] = true
		_md.append_array(_render.turn_lines(record))
	_flush_outputs()
	_pump_after_ms = Time.get_ticks_msec() + 50


## A resumed segment continues the same run: the JSON sidecar is the one record
## of it, so the previous segments' arrays are reloaded and the summary at the
## end covers the whole campaign, not just the last process.
func _restore_sidecar() -> void:
	if not _resume:
		return
	var data := FullRunStore.load_sidecar(_abs(_out_json))
	if data.is_empty():
		return
	_records = FullRunStore.typed(data.get("turns", []))
	_nights = FullRunStore.typed(data.get("nights", []))
	_broken = FullRunStore.typed(data.get("broken", []))
	_refused = FullRunStore.typed(data.get("refused", []))
	_transitions = FullRunStore.typed(data.get("stage_transitions", []))
	_path_log = FullRunStore.typed(data.get("path_decisions", []))
	_trigger_log = FullRunStore.typed(data.get("triggers", []))
	_redaction_log = FullRunStore.typed(data.get("redactions", []))
	_leak_log = FullRunStore.typed(data.get("leaks", []))
	for record: Dictionary in _records:
		_turn_seq = maxi(_turn_seq, int(record.get("seq", 0)))
	print("full_run: restored %d turn record(s) from %s" % [_records.size(), _out_json])


## The on-screen text of this turn's beats, read while the TextBox is alive.
## Indices past the last beat return an empty string, so the probe stops there.
func _capture_displayed(box: Node) -> Array[String]:
	var out: Array[String] = []
	for i: int in range(8):
		var text := String(box.call("get_beat_text", i))
		if text.is_empty() and i > 0:
			break
		out.append(text)
	return out


func _record_night() -> void:
	var report := _night_report
	var stage_events := _drain(_pending_stage)
	var path_events := _drain(_pending_paths)
	_nights.append({"report": report, "screen": _night_lines.duplicate()})
	_md.append_array(_render.night_lines(report, _night_lines, path_events, stage_events))
	_night_report = {}
	_night_recorded = true
	_flush_outputs()
	if _checkpoint_days > 0 and (int(GameState.day) - 1) % _checkpoint_days == 0:
		var wall := float(Time.get_ticks_msec() - _started_ms) / 1000.0
		_md.append_array(
			_render.summary_lines(
				"day %d checkpoint" % (int(GameState.day) - 1), _final_state(), wall, true
			)
		)
		_flush_outputs()
	var stage := int(GameState.stage)
	if stage >= _stop_stage:
		_finish_run("stage %d reached (stop-stage %d)" % [stage, _stop_stage])
	elif int(GameState.day) > _max_days:
		_finish_run("day cap %d reached" % _max_days)


func _on_stage_transition(previous: int, current: int, spec: Dictionary) -> void:
	_pending_stage.append(
		{"from": previous, "to": current, "name": Stages.name_of(current), "spec": spec}
	)
	var trans := {
		"day": int(GameState.day),
		"turn": int(GameState.turn),
		"from": previous,
		"to": current,
		"name": Stages.name_of(current),
		"duration_s": float(spec.get("duration_s", 0.0)),
		"fx": String(spec.get("fx", "")),
		"cue": String(spec.get("cue", "")),
		"instability": float(GameState.instability),
	}
	if not _last_steering_info.is_empty():
		trans["relaunch"] = _last_steering_info.duplicate(true)
	_transitions.append(trans)
	print(
		(
			"full_run: stage %d → %d (%s) at day %d, instability %.1f"
			% [
				previous,
				current,
				Stages.name_of(current),
				int(GameState.day),
				float(GameState.instability)
			]
		)
	)


func _on_path_assigned(path: StringName, locked: bool) -> void:
	var entry := {
		"day": int(GameState.day),
		"turn": int(GameState.turn),
		"path": str(path),
		"locked": locked,
		"stage": int(GameState.stage),
		"scores": GameState.path_scores.duplicate(true),
	}
	_pending_paths.append(entry)
	_path_log.append(entry)


func _on_trigger(result: Dictionary) -> void:
	_pending_triggers.append(result.duplicate(true))
	(
		_trigger_log
		. append(
			{
				"day": int(GameState.day),
				"turn": int(GameState.turn),
				"id": String(result.get("id", "")),
				"name": String(result.get("name", "")),
				"step": int(result.get("step", 0)),
				"agreement": String(result.get("agreement", "")),
				"strength": float(result.get("strength", 0.0)),
				"effects": result.get("effects", {}),
				"line": String(result.get("line", "")),
			}
		)
	)


func _on_redacted(category: String, matched_text: String, source: String) -> void:
	var entry := {
		"day": int(GameState.day),
		"turn": int(GameState.turn),
		"category": category,
		"matched": matched_text.left(120),
		"source": source,
	}
	_pending_redactions.append(entry)
	_redaction_log.append(entry)


## ── Output ───────────────────────────────────────────────────────────────────
func _prepare_output() -> void:
	if _resume and FileAccess.file_exists(_abs(_out_md)):
		var raw_prefix := FileAccess.get_file_as_string(_abs(_out_md))
		var scanned := FullRunStore.scan_rendered(raw_prefix)
		_prefix = String(scanned.get("cleaned", raw_prefix))
		_rendered_days = (scanned.get("days", {}) as Dictionary).duplicate()
		_rendered_turns = (scanned.get("turns", {}) as Dictionary).duplicate()
		_md.append("\n---\n\n## Resumed\n")
		_md.append(
			(
				"- resumed %s at day %d, stage %d (from `SaveSystem.load_latest`)"
				% [Time.get_datetime_string_from_system(), int(GameState.day), int(GameState.stage)]
			)
		)
		_md.append("")
	else:
		_prefix = ""
		_md.append_array(_render.header_lines())
	_flush_outputs()


func _flush_outputs() -> void:
	_flush_md()
	_write_json()


func _flush_md() -> void:
	var file := FileAccess.open(_abs(_out_md), FileAccess.WRITE)
	if file == null:
		push_error("full_run: cannot write %s" % _out_md)
		return
	file.store_string(_prefix + "\n".join(_md).strip_edges() + "\n")
	file.close()


func _write_json() -> void:
	var payload := (
		FullRunStore
		. build_payload(
			{
				"run": _run,
				"started": _started_at,
				"model": _model_label,
				"url": _base_url,
				"player": _player
			},
			{
				"records": _records,
				"nights": _nights,
				"broken": _broken,
				"refused": _refused,
				"transitions": _transitions,
				"path_log": _path_log,
				"trigger_log": _trigger_log,
				"redaction_log": _redaction_log,
				"leak_log": _leak_log,
			},
			_final_state()
		)
	)
	FullRunStore.save_sidecar(_abs(_out_json), payload)


func _finish_run(reason: String) -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	var wall := float(Time.get_ticks_msec() - _started_ms) / 1000.0
	var is_checkpoint := (
		reason.begins_with("day cap")
		or (
			not _campaign_over
			and int(GameState.stage) < _stop_stage
			and not reason.begins_with("campaign ended")
		)
	)
	_md.append_array(_render.summary_lines(reason, _final_state(), wall, is_checkpoint))
	_flush_outputs()
	print("full_run: %s — %s" % ["checkpoint" if is_checkpoint else "finished", reason])
	print("full_run: wrote %s" % _abs(_out_md))
	if Director.transcript_logger != null:
		print("full_run: game transcript %s" % Director.transcript_logger.current_file())
	get_tree().quit(0 if _broken.is_empty() else 2)


## ── Helpers ──────────────────────────────────────────────────────────────────


func _check_stall() -> void:
	var now := Time.get_ticks_msec()
	if _awaiting and now - _turn_start_ms > TURN_TIMEOUT_MS:
		_awaiting = false
		(
			_broken
			. append(
				{
					"day": int(GameState.day),
					"turn": int(GameState.turn),
					"code": "driver_timeout",
					"message": "no display boundary in %d s" % (TURN_TIMEOUT_MS / 1000),
				}
			)
		)
		_md.append("### Broken turn — driver timeout\n")
		Director.cancel()
		_flush_outputs()
		return
	if not _date_ended.is_empty() and now - _date_ended_ms > SCENE_WAIT_MS:
		_finish_run("the date ended (%s) but the loop did not open Night" % _date_ended)
		return
	if _scene_missing_ms != 0 and now - _scene_missing_ms > SCENE_WAIT_MS:
		_finish_run("no Date or Night scene for %d s" % (SCENE_WAIT_MS / 1000))


func _final_state() -> Dictionary:
	return FullRunStore.final_state()


func _meters_dict() -> Dictionary:
	return FullRunStore.meters_dict()


func _drain(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = list.duplicate(true)
	list.clear()
	return out


## Repo-relative paths resolve against the worktree root, so the same command
## works from any working directory.
func _abs(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(path).simplify_path()
