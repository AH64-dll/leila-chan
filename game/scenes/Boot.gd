extends Node
## Boot — entry scene (docs/07 §2). Will own data loading, schema validation and
## the diegetic loading screen (docs/07 §6). For now it smokes-tests the autoload ring.

const EXPECTED_AUTOLOADS: PackedStringArray = [
	"GameState", "Director", "LLM", "PromptBuilder", "SpriteResolver",
	"AudioDirector", "FX", "MetaDirector", "Triggers", "Memory",
	"Safety", "Steering", "SaveSystem", "Settings",
]


func _ready() -> void:
	var missing: PackedStringArray = []
	for autoload_name: String in EXPECTED_AUTOLOADS:
		if not has_node("/root/" + autoload_name):
			missing.append(autoload_name)
	if missing.is_empty():
		print("Boot: %d/%d autoloads registered" % [
			EXPECTED_AUTOLOADS.size() - missing.size(), EXPECTED_AUTOLOADS.size()
		])
	else:
		push_error("Boot: missing autoloads: " + ", ".join(missing))
		get_tree().quit(1)
