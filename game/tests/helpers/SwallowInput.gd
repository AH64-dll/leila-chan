extends Control
## Test double for PauseMenuTest: a "meta-event screen" that swallows every
## unhandled input. Esc must never reach it — the PauseMenu autoload reads
## `_input`, which runs before any scene's `_unhandled_*`.

var seen: Array[InputEvent] = []


func _unhandled_input(event: InputEvent) -> void:
	seen.append(event)
	get_viewport().set_input_as_handled()
