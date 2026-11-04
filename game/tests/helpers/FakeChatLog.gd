extends RefCounted
## The save log seam (P2.20): the two methods SaveSystem drives on the ChatLog
## (`get_entries`/`restore_entries`) without a Control tree, so a save round
## trip runs headless. The real ChatLog is exercised by SaveFlowTest.

var entries: Array = []


func get_entries() -> Array:
	return entries.duplicate(true)


func restore_entries(restored: Array) -> void:
	entries = restored.duplicate(true)
