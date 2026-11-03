extends SceneTree
## Regenerates the PromptBuilder golden fixtures (P1.06) from the shared cases
## in game/tests/helpers/PromptGoldenCases.gd:
##   ./tools/godot.sh --headless --path game --script res://tests/tools/prompt_builder_goldens.gd
##
## Run it only when a prompt change is intended; the diff of
## game/tests/fixtures/prompts/*.json is the review artifact. The suite
## (res://tests/test_prompt_builder.gd) compares against the committed files.
## Exits 0 when every case was written, 1 otherwise.

const Cases := preload("res://tests/helpers/PromptGoldenCases.gd")
const BuilderScript := preload("res://autoload/PromptBuilder.gd")
const OUT_DIR := "res://tests/fixtures/prompts/"


func _initialize() -> void:
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		var made := DirAccess.make_dir_recursive_absolute(OUT_DIR)
		if made != OK:
			printerr("prompt_builder_goldens: cannot create ", OUT_DIR, " (", made, ")")
			quit(1)
			return
	var builder: Node = BuilderScript.new()
	var written := 0
	var failed := 0
	for name: String in Cases.case_names():
		var result: Dictionary = builder.build(Cases.ctx(name))
		var path := OUT_DIR + name + ".json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("prompt_builder_goldens: cannot write ", path)
			failed += 1
			continue
		file.store_string(JSON.stringify(result, "  ") + "\n")
		file.close()
		print("wrote ", path)
		written += 1
	builder.free()
	print("prompt_builder_goldens: %d written, %d failed" % [written, failed])
	quit(1 if failed > 0 else 0)
