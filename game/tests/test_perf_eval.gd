extends SceneTree

func _init() -> void:
	var vram_bytes: int = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	print("VRAM_BYTES: ", vram_bytes)
	quit()
