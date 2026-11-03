extends Label
## NameTag — the speaker label above the text box (docs/03 §5 name-tag effects
## are applied by the meta layer from stage 2; this component only renders
## the name it is given). Speaker identity is data: res://data/ui.json
## "names". The player's tag is set through set_player_name() — the stage-5
## trick of swapping it for hers is a renderer-side effect the caller drives.


func set_display_name(new_name: String) -> void:
	text = new_name


func get_display_name() -> String:
	return text
