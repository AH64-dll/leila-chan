extends SceneTree

func _init() -> void:
	var parser := IncrementalJson.new()
	var chunk1 := '{"read":"greeting","inner":"Thinking...","music":"keep","fx":"none",'
	var chunk2 := '"beats":[{"feeling":"shy","intensity":2,"cue":"giggle","say":"Hello Senpai!"}],'
	var chunk3 := '"mood":{"affection":2,"trust":1,"stress":-1},"memory":"","action":"none"}'
	print("Feed 1:", parser.feed(chunk1))
	print("Feed 2:", parser.feed(chunk2))
	print("Feed 3:", parser.feed(chunk3))
	print("Finish:", parser.finish())
	print("Value:", parser.get_value())
	quit()
