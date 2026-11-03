extends SceneTree
## P1.13 dev tool — renders the ChatUI composite and saves a screenshot for
## the handoff. Needs a real display server (run under xvfb or a desktop;
## --headless produces a blank viewport). Usage:
##   xvfb-run -a ./tools/godot.sh --path game --script res://tools/ui_shot.gd -- out.png [typing]
## Modes: default = post-turn state · "typing" = mid-turn, diegetic indicator up.

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")


func _init() -> void:
	var out := "user://ui_shot.png"
	var mode := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.ends_with(".png"):
			out = arg
		elif arg == "typing":
			mode = arg
	var ui: Control = ChatUIScene.instantiate()
	root.add_child(ui)
	await process_frame
	if mode == "typing":
		ui.input_box.text = "are you there?"
		ui.input_box.text_submitted.emit("are you there?")
	else:
		ui.set_reduced_motion(true)
		ui.input_box.text = "you look nice today"
		ui.input_box.text_submitted.emit("you look nice today")
		ui.begin_beat(0)
		ui.say_chunk(0, "Flattery will get you everywhere, you know. ")
		ui.say_chunk(0, "Say it again.")
		ui.end_beat(0)
		ui.end_turn()
	for i: int in 5:
		await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(out)
	print("ui_shot: saved ", out, " err=", err, " size=", img.get_size())
	quit(err)
