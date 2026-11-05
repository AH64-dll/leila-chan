extends Control
## P4.08 loading screen, the first scene of a native launch (docs/07 section 6). It checks
## the model file, loads the model on a Thread with a progress bar, then moves on. Each
## failure shows one in-fiction line and a plain fix. Nothing flashes, shakes or fades,
## so it is safe under photosensitive mode.

const BootScript := preload("res://scenes/Boot.gd")
const DATA_PATH := "res://data/loading.json"
const CACHE_PATH := "user://model_check.json"
## The hash takes the first share of the bar; the engine load takes the rest.
const HASH_SHARE := 0.3
const LINE_INTERVAL_MS := 2500
const BUTTON_LABELS := {
	"retry": "Try again",
	"quit": "Quit",
	"continue": "Continue",
	"fast": "Fast mode (shorter replies)",
}
const FALLBACK_ERROR := {
	"fiction": "Something went wrong.",
	"fix": "Verify the game files in Steam, or reinstall the game.",
	"actions": ["quit"],
}

## Test seams: a test sets these before the screen enters the tree.
var expected_override: Dictionary = {}
var cache_path := CACHE_PATH
var navigate_on_finish := true
## The scene _finish() chose. Empty until the screen is done.
var finished_scene := ""

var _data: Dictionary = {}
var _backend: NativeBackend = null
var _job: LoadJob = null
var _thread: Thread = null
var _attempt_started_ms := 0
var _bar_value := 0.0
var _line_index := -1
var _actions: Array = []
var _finished := false

@onready var _line: Label = $Column/Line
@onready var _progress: ProgressBar = $Column/Progress
@onready var _fix: Label = $Column/Fix
@onready var _actions_box: HBoxContainer = $Column/Actions


func _ready() -> void:
	_data = _read_json(DATA_PATH)
	_backend = LLM.get_backend() as NativeBackend
	if _backend == null:
		_finish()
		return
	_begin_attempt()


func _process(_delta: float) -> void:
	if _job == null:
		return
	var snap := _job.snapshot()
	_advance_bar(snap)
	_update_line(Time.get_ticks_msec() - _attempt_started_ms)
	if not bool(snap.get("done", false)):
		return
	_thread.wait_to_finish()
	_thread = null
	_job = null
	var result: Dictionary = snap.get("result", {})
	_on_job_done(result)


## Leaving the tree during a load: cancel the check and the engine load first, so the wait
## ends at the next cancel point rather than after the whole load.
func _exit_tree() -> void:
	if _thread != null:
		if _job != null:
			_job.cancel()
		if _backend != null:
			_backend.cancel_load()
		_thread.wait_to_finish()
		_thread = null
		_job = null


## The action names on screen now, in order. Tests read this.
func current_actions() -> Array:
	return _actions.duplicate()


func _begin_attempt() -> void:
	_clear_actions()
	_fix.text = ""
	_line_index = -1
	_bar_value = 0.0
	_progress.value = 0.0
	if not _backend.has_engine():
		_show_error("no_extension", {})
		return
	_update_line(0)
	_attempt_started_ms = Time.get_ticks_msec()
	_job = LoadJob.new(_backend, _backend.resolved_model_path(), _expected(), cache_path)
	_thread = Thread.new()
	_thread.start(_job.run)


func _expected() -> Dictionary:
	if not expected_override.is_empty():
		return expected_override
	return ModelPreflight.load_expected()


func _advance_bar(snap: Dictionary) -> void:
	var target := bar_target(
		bool(snap.get("check_done", false)),
		bool(snap.get("hashed", false)),
		float(snap.get("hash_fraction", 0.0)),
		_backend.load_progress()
	)
	_bar_value = maxf(_bar_value, target)
	_progress.value = _bar_value


func _update_line(elapsed_ms: int) -> void:
	var lines: Array = _data.get("lines", [])
	if lines.is_empty():
		return
	var index := line_index(elapsed_ms, lines.size())
	if index == _line_index:
		return
	_line_index = index
	_line.text = String(lines[index])


## A cancelled job means the screen is closing, so it shows nothing.
func _on_job_done(result: Dictionary) -> void:
	if String(result.get("code", "")) == "cancelled":
		return
	if not bool(result.get("ok", false)):
		var values := {
			"path": String(result.get("path", "")),
			"detail": String(result.get("detail", "")),
		}
		_show_error(String(result.get("code", "load_failed")), values)
		return
	_progress.value = 1.0
	var info := _backend.device_info()
	if bool(info.get("fell_back", false)):
		_show_error("gpu_oom", {"where": _where(info)})
	elif _runs_on_cpu(info):
		_show_error("no_gpu", {})
	else:
		_finish()


## Where the model runs after a fallback, for the gpu_oom fix text.
static func _where(info: Dictionary) -> String:
	if String(info.get("device_type", "")) == "cpu":
		return "on your processor"
	return "partly on your graphics card"


## True when the load ran on the processor. An engine that reports device_type decides by
## it. An older engine, which does not, is judged by its device list.
func _runs_on_cpu(info: Dictionary) -> bool:
	if info.has("device_type"):
		return String(info["device_type"]) == "cpu"
	var devices: Variant = _backend.last_load_info().get("devices")
	return devices is Array and not gpu_present(devices)


func _show_error(code: String, values: Dictionary) -> void:
	var errors: Dictionary = _data.get("errors", {})
	var entry: Dictionary = errors.get(code, {})
	if entry.is_empty():
		push_error("Loading: no text for error %s" % code)
		entry = FALLBACK_ERROR
	_line.text = String(entry.get("fiction", ""))
	_fix.text = String(entry.get("fix", "")).format(values)
	_show_actions(entry.get("actions", ["quit"]))


func _show_actions(actions: Array) -> void:
	_clear_actions()
	_actions = actions.duplicate()
	var first: Button = null
	for action: String in _actions:
		var button := Button.new()
		button.text = String(BUTTON_LABELS.get(action, action))
		button.pressed.connect(_on_action.bind(action))
		_actions_box.add_child(button)
		if first == null:
			first = button
	if first != null:
		first.grab_focus()


func _clear_actions() -> void:
	_actions = []
	for child in _actions_box.get_children():
		_actions_box.remove_child(child)
		child.queue_free()


func _on_action(action: String) -> void:
	match action:
		"retry":
			_backend.reset_load()
			_begin_attempt()
		"quit":
			get_tree().quit()
		"continue":
			_finish()
		"fast":
			Settings.set_fast_mode(true)
			_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	finished_scene = BootScript.next_scene()
	if navigate_on_finish:
		get_tree().change_scene_to_file.call_deferred(finished_scene)


## Which line of text is showing after elapsed_ms: one more every LINE_INTERVAL_MS, then
## it stays on the last line.
static func line_index(elapsed_ms: int, count: int) -> int:
	if count <= 0:
		return 0
	var steps := floori(float(maxi(elapsed_ms, 0)) / float(LINE_INTERVAL_MS))
	return mini(steps, count - 1)


## True when at least one device is a GPU. A dictionary entry counts through its name or
## its type; a bare string is its own name. An empty list has no GPU.
static func gpu_present(devices: Array) -> bool:
	for device: Variant in devices:
		if device is Dictionary:
			var entry: Dictionary = device
			if _is_gpu_name(String(entry.get("name", ""))):
				return true
			if _is_gpu_name(String(entry.get("type", ""))):
				return true
		elif _is_gpu_name(String(device)):
			return true
	return false


static func _is_gpu_name(text: String) -> bool:
	var clean := text.strip_edges().to_upper()
	return not clean.is_empty() and clean != "CPU"


## The bar's target at one moment. Hash progress fills the first HASH_SHARE, then the
## engine load fills the rest. A cache hit has no hash, so the load fills the whole bar.
static func bar_target(
	check_done: bool, hashed: bool, hash_fraction: float, load_fraction: float
) -> float:
	if not check_done:
		if hashed:
			return HASH_SHARE * clampf(hash_fraction, 0.0, 1.0)
		return 0.0
	var head := HASH_SHARE if hashed else 0.0
	return head + (1.0 - head) * clampf(load_fraction, 0.0, 1.0)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


## The check and the load, run on the worker thread. The main thread polls snapshot().
## Touches no Node and no signal.
class LoadJob:
	extends RefCounted

	var _backend: NativeBackend
	var _model_path: String
	var _expected: Dictionary
	var _cache_path: String
	var _lock := Mutex.new()
	var _hashed := false  # guarded by _lock
	var _hash_fraction := 0.0  # guarded by _lock
	var _check_done := false  # guarded by _lock
	var _done := false  # guarded by _lock
	var _result: Dictionary = {}  # guarded by _lock
	var _cancelled := false  # guarded by _lock

	func _init(
		backend: NativeBackend, model_path: String, expected: Dictionary, cache_path: String
	) -> void:
		_backend = backend
		_model_path = model_path
		_expected = expected
		_cache_path = cache_path

	## Worker thread. The check runs first; the engine loads only once it passes. A cancel
	## skips the engine, and a failed result from a cancel reports as cancelled.
	func run() -> void:
		var check := ModelPreflight.check(
			_model_path,
			_expected,
			_cache_path,
			Callable(self, "_on_hash"),
			Callable(self, "_is_cancelled")
		)
		_lock.lock()
		_check_done = true
		_lock.unlock()
		var result := {"ok": true, "path": _model_path}
		if not bool(check.get("ok", false)):
			result = {
				"ok": false,
				"code": String(check.get("code", "missing_model")),
				"path": _model_path,
				"detail": "",
			}
		elif not _is_cancelled():
			var loaded := _backend.ensure_loaded()
			if not bool(loaded.get("ok", false)):
				result = {
					"ok": false,
					"code": "load_failed",
					"path": _model_path,
					"detail": error_detail(loaded),
				}
		if not bool(result.get("ok", false)) and _is_cancelled():
			result["code"] = "cancelled"
		_lock.lock()
		_result = result
		_done = true
		_lock.unlock()

	func snapshot() -> Dictionary:
		_lock.lock()
		var out := {
			"check_done": _check_done,
			"hashed": _hashed,
			"hash_fraction": _hash_fraction,
			"done": _done,
			"result": _result.duplicate(),
		}
		_lock.unlock()
		return out

	## Asks the job to stop at its next check. Called from the main thread; the worker reads
	## the flag under _lock.
	func cancel() -> void:
		_lock.lock()
		_cancelled = true
		_lock.unlock()

	func _is_cancelled() -> bool:
		_lock.lock()
		var out := _cancelled
		_lock.unlock()
		return out

	## The message a failed load reports, for the fix text.
	static func error_detail(loaded: Dictionary) -> String:
		var error: Variant = loaded.get("error", {})
		if error is Dictionary:
			var text := String(error.get("message", ""))
			if text.is_empty():
				text = String(error.get("code", ""))
			if not text.is_empty():
				return text
		return "none reported"

	func _on_hash(fraction: float) -> void:
		_lock.lock()
		_hashed = true
		_hash_fraction = fraction
		_lock.unlock()
