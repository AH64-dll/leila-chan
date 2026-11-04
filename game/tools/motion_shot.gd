extends Node
## P2.14 dev tool — captures the intensity-driven motion for the handoff.
## The amplitude ladder is data (casting.motion_intensity), so the tool stages the very
## packet Character.apply_beat() consumes — one sprite, one preset, one scale — and
## nothing else on screen changes, which makes the stills/frames comparable.
##
## Run it as a scene (not --script): the project's autoloads must exist because
## Character.gd compiles against FX / SpriteResolver.
##
##   xvfb-run -a ./tools/godot.sh --path game res://tools/MotionShot.tscn -- \
##       "$PWD/production/handoffs/media/P2.14/lean_in_i3.png" lean_in 1.4
##   xvfb-run -a ./tools/godot.sh --path game res://tools/MotionShot.tscn -- \
##       "$PWD/out/bounce_i3" bounce 1.4 40      # 40 frames into a new directory
## Args: <out.png | out dir> <motion> <motion_scale> [frames]

const CharScene := preload("res://scenes/character/Character.tscn")
const SPRITE := "01"  # the neutral sheet sprite: motion is the only variable
const SETTLE_FRAMES := 45


func _ready() -> void:
	Engine.max_fps = 60
	var args := OS.get_cmdline_user_args()
	var out := "user://motion_shot.png"
	var motion := "lean_in"
	var scale := 1.0
	var frames := 0
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		motion = args[1]
	if args.size() > 2:
		scale = float(args[2])
	if args.size() > 3:
		frames = int(args[3])
	# Time-slowed capture: the renderer under xvfb is slower than the tween, so a
	# 1:1 frame grab would sample the 180 ms hop two or three times. 0.2x spreads
	# it over enough frames to read; the GIF is a slow-motion view of the preset.
	# It must be set BEFORE the beat starts or the first frames eat the hop.
	if frames > 0:
		Engine.time_scale = 0.2
	var character: Node = CharScene.instantiate()
	add_child(character)
	await get_tree().process_frame
	character.apply_beat({"sprite": SPRITE, "motion": motion, "motion_scale": scale})
	if frames > 0:
		DirAccess.make_dir_recursive_absolute(out)
		for i: int in frames:
			get_tree().root.get_texture().get_image().save_png("%s/f_%03d.png" % [out, i])
			await get_tree().process_frame
		print("motion_shot: %d frames -> %s (%s x%s)" % [frames, out, motion, scale])
	else:
		for i: int in SETTLE_FRAMES:
			await get_tree().process_frame
		var err := get_tree().root.get_texture().get_image().save_png(out)
		print("motion_shot: saved %s err=%d (%s x%s)" % [out, err, motion, scale])
	get_tree().quit(0)
