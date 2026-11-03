extends Node
## PromptBuilder — assembles the layered prompt (docs/08).

const DEFAULT_PLAYER_NAME := "Senpai"

var player_name := "Senpai"


func set_player_name(new_name: String) -> void:
	player_name = new_name if not new_name.is_empty() else DEFAULT_PLAYER_NAME


func get_player_name() -> String:
	if has_node("/root/GameState"):
		var gs: Node = get_node("/root/GameState")
		if "player_name" in gs and not str(gs.player_name).is_empty():
			return str(gs.player_name)
	return player_name


## Build the message array for one turn (docs/08 §1).
func build(ctx: Dictionary = {}) -> Dictionary:
	var name_to_use := String(ctx.get("player_name", "")).strip_edges()
	if name_to_use.is_empty():
		name_to_use = get_player_name()
	return {
		"messages":
		[
			{
				"role": "system",
				"content": "The player is a boy called %s." % name_to_use,
			}
		],
		"player_name": name_to_use,
		"debug": {"player_name": name_to_use},
	}
