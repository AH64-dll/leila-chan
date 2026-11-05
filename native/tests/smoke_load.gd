extends SceneTree

# Smoke check: the GDExtension loads and LeilaLLM can be instantiated and called.
func _init() -> void:
	var obj = ClassDB.instantiate("LeilaLLM")
	if obj == null:
		printerr("smoke_load: ClassDB.instantiate(\"LeilaLLM\") returned null")
		quit(1)
		return
	print(obj.version())
	quit(0)
