extends GdUnitTestSuite
## P4.08b loading screen layout. The screen sits in a SubViewport the size of the window
## (384 x 688), so the layout is measured the way the player sees it. Every error's text is
## filled with a long path and a long detail, and no visible control may leave the 24 px
## margin on either side.

const SCENE := preload("res://scenes/Loading.tscn")
const MODEL_PATH := "user://loading_layout_model.bin"
const CACHE_PATH := "user://loading_layout_cache.json"
const HELLO_SHA256 := "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
const EXPECTED := {"file": "loading_layout_model.bin", "bytes": 5, "sha256": HELLO_SHA256}
const VIEW_SIZE := Vector2i(384, 688)
const MARGIN := 24.0
const WHERE := "partly on your graphics card"

## 90 characters with no spaces or punctuation, so only a forced break can wrap it.
var _long_path := "abcdefghij".repeat(9)
var _long_detail := "cudaerrorcode".repeat(6)
var _saved_backend: LLMBackend = null


func before_test() -> void:
	_saved_backend = LLM.get_backend()
	_remove_files()


func after_test() -> void:
	LLM.set_backend(_saved_backend)
	_remove_files()


func test_every_error_fits_inside_the_margins() -> void:
	assert_int(_long_path.length()).is_equal(90)
	var screen := _build()
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_float(screen.size.x).is_equal(float(VIEW_SIZE.x))
	assert_float(screen.size.y).is_equal(float(VIEW_SIZE.y))
	var column: Control = screen.get_node("Margin/Column")
	var errors: Dictionary = _read_loading_data().get("errors", {})
	assert_int(errors.size()).is_greater_equal(5)
	for code: String in errors:
		screen.call("_show_error", code, _values())
		await get_tree().process_frame
		await get_tree().process_frame
		assert_float(column.size.x).is_equal_approx(float(VIEW_SIZE.x) - 2.0 * MARGIN, 0.5)
		_assert_inside_margins(code, column)


func test_the_bar_hides_during_an_error_and_returns_on_retry() -> void:
	var screen := _build()
	var bar: ProgressBar = screen.get_node("Margin/Column/Progress")
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_bool(bar.visible).is_false()
	assert_bool(_press(screen, "Try again")).is_true()
	assert_bool(bar.visible).is_true()
	var again := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(again).is_true()
	assert_bool(bar.visible).is_false()


## Builds the screen in a window-sized SubViewport that is in the tree. The model file is
## absent, so the first attempt ends in the missing-model error on the worker thread.
func _build() -> Control:
	LLM.set_backend(NativeBackend.new({"model_path": MODEL_PATH}, FakeLoadEngine.new()))
	var view := auto_free(SubViewport.new()) as SubViewport
	view.size = VIEW_SIZE
	add_child(view)
	var screen: Control = SCENE.instantiate()
	screen.set("navigate_on_finish", false)
	screen.set("cache_path", CACHE_PATH)
	screen.set("expected_override", EXPECTED)
	view.add_child(screen)
	return screen


func _values() -> Dictionary:
	return {"path": _long_path, "where": WHERE, "detail": _long_detail}


## Every visible control under the column, and the column itself, sits inside the margins.
func _assert_inside_margins(code: String, column: Control) -> void:
	var right_limit := float(VIEW_SIZE.x) - MARGIN
	var column_msg := "%s: the column is %s px wide" % [code, column.size.x]
	assert_float(column.size.x).override_failure_message(column_msg).is_less_equal(right_limit)
	for control: Control in column.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		var label := "%s: %s" % [code, control.name]
		var right_msg := "%s right edge is %s" % [label, rect.end.x]
		var left_msg := "%s left edge is %s" % [label, rect.position.x]
		assert_float(rect.end.x).override_failure_message(right_msg).is_less_equal(right_limit)
		assert_float(rect.position.x).override_failure_message(left_msg).is_greater_equal(MARGIN)


func _remove_files() -> void:
	for path: String in [MODEL_PATH, CACHE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _wait_until(predicate: Callable, timeout_ms := 8000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _fix(screen: Node) -> String:
	return (screen.get_node("Margin/Column/Fix") as Label).text


func _press(screen: Node, label: String) -> bool:
	for child in screen.get_node("Margin/Column/Actions").get_children():
		var button := child as Button
		if button != null and button.text == label:
			button.pressed.emit()
			return true
	return false


func _read_loading_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/loading.json")
	)
	if parsed is Dictionary:
		return parsed
	return {}


## A stand-in engine. The layout cases never reach a load, so it only has to exist.
class FakeLoadEngine:
	extends RefCounted

	func load_model(_config: Dictionary) -> Dictionary:
		return {"ok": true, "devices": ["CUDA0"]}

	func cancel_load() -> void:
		pass

	func load_progress() -> float:
		return 0.0

	func is_loaded() -> bool:
		return false

	func unload() -> void:
		pass

	func set_control_vectors(_vectors: Array) -> Dictionary:
		return {"ok": true, "applied": true, "set_ms": 0.0}
