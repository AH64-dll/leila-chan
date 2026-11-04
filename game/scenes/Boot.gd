extends Node
## Boot — entry scene (docs/07 §2). Will own data loading, schema validation and
## the diegetic loading screen (docs/07 §6). For now it smokes-tests the autoload ring
## and transitions to the Title screen (P1.14).

const TITLE_SCENE_PATH := "res://scenes/Title.tscn"

const EXPECTED_AUTOLOADS: PackedStringArray = [
	"GameState",
	"Director",
	"LLM",
	"PromptBuilder",
	"SpriteResolver",
	"AudioDirector",
	"FX",
	"MetaDirector",
	"Triggers",
	"Memory",
	"Safety",
	"Steering",
	"SaveSystem",
	"Settings",
	"Telemetry",
]

var auto_advance := true


func _ready() -> void:
	var missing: PackedStringArray = []
	for autoload_name: String in EXPECTED_AUTOLOADS:
		if not has_node("/root/" + autoload_name):
			missing.append(autoload_name)
	if missing.is_empty():
		print(
			(
				"Boot: %d/%d autoloads registered"
				% [EXPECTED_AUTOLOADS.size() - missing.size(), EXPECTED_AUTOLOADS.size()]
			)
		)
		# P1.02: the prototype transport attaches to tools/llm/serve.ps1 by
		# default. A later boot task can pass auto_start=true to own the process.
		if not LLM.has_backend():
			LLM.use_default_backend()
		if auto_advance:
			_transition_to_title()
	else:
		push_error("Boot: missing autoloads: " + ", ".join(missing))
		get_tree().quit(1)


func _transition_to_title() -> void:
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE_PATH)
