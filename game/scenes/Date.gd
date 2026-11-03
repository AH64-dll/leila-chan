extends Control
## Date — the core conversation scene (P1.14 flow destination, assembled in P1.16).
## Wires ChatUI with GameState and PromptBuilder.

signal pause_requested

@onready var chat_ui: Control = $ChatUI


func _ready() -> void:
	var player_name := "Senpai"
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		if tree.root.has_node("GameState"):
			var gs: Node = tree.root.get_node("GameState")
			player_name = str(gs.get("player_name"))
			if player_name.is_empty():
				player_name = "Senpai"

		if tree.root.has_node("PromptBuilder"):
			var pb: Node = tree.root.get_node("PromptBuilder")
			if pb.has_method("set_player_name"):
				pb.call("set_player_name", player_name)

	if chat_ui != null:
		chat_ui.set_player_name(player_name)
		chat_ui.pause_requested.connect(_on_pause_requested)


func get_player_name() -> String:
	if chat_ui != null and chat_ui.has_method("get_player_name"):
		return str(chat_ui.call("get_player_name"))
	return "Senpai"


func _on_pause_requested() -> void:
	pause_requested.emit()
