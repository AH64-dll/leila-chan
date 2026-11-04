extends Node
## FullRun — P2.22 full-run playtest bootstrap (QA).
##
## The driver must survive the real scene changes (Date → Night → Date), and a
## `change_scene_to_file()` frees the current scene — so this scene is only the
## entry point: it adds the driver as a direct child of the tree root and then
## starts the campaign exactly as NewGame does (`res://scenes/Date.tscn`). The
## driver then observes `get_tree().current_scene` and steers the real pipeline.
##
## Run (llama-server must be up; see tools/llm/serve.sh):
##   ./tools/godot.sh --headless --path game res://tools/FullRun.tscn -- \
##     --run=yandere --lines=production/playtests/P2/runs/yandere_lines.json \
##     --out=production/playtests/P2/runs/yandere.md
##
## Every flag is parsed by the driver (`tools/full_run_driver.gd`); this file
## carries none. `tools/test.sh` does not run this tool (no model in CI).

const DRIVER_SCRIPT := preload("res://tools/full_run_driver.gd")
const FIRST_SCENE := "res://scenes/Date.tscn"


func _ready() -> void:
	var driver: Node = DRIVER_SCRIPT.new()
	driver.name = "FullRunDriver"
	# Root child, not scene child: it must outlive every change_scene_to_file().
	get_tree().root.add_child.call_deferred(driver)
	get_tree().change_scene_to_file.call_deferred(FIRST_SCENE)
