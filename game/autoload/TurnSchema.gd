extends Node
## TurnSchema autoload shim (docs/02 §2–§3, P1.07).
## Exposes TurnSchema methods when accessed as an Autoload or Node.


func build_turn_schema(ctx: Variant = 0, offered_actions: Array = []) -> Dictionary:
	return TurnSchema.build_turn_schema(ctx, offered_actions)


func build_schema(ctx: Variant = 0, offered_actions: Array = []) -> Dictionary:
	return TurnSchema.build_schema(ctx, offered_actions)


func validate_turn(
	turn: Variant, stage: int = 0, offered_actions: Array = [], options: Dictionary = {}
) -> Array[String]:
	return TurnSchema.validate_turn(turn, stage, offered_actions, options)


func get_allowed_cues(stage: int) -> Array[String]:
	return TurnSchema.get_allowed_cues(stage)


func get_allowed_music(stage: int) -> Array[String]:
	return TurnSchema.get_allowed_music(stage)


func get_allowed_fx(stage: int) -> Array[String]:
	return TurnSchema.get_allowed_fx(stage)


func get_allowed_actions(stage: int, offered_actions: Array = []) -> Array[String]:
	return TurnSchema.get_allowed_actions(stage, offered_actions)


func is_meta_unlocked(stage: int) -> bool:
	return TurnSchema.is_meta_unlocked(stage)
