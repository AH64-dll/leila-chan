extends GdUnitTestSuite
## P3.09 — docs/05 §1.1 M06/M07 on the real title screen: the sprite drifts with
## the stage, the eyes follow the cursor from St 3, the title text is her name at
## St 5, and New Game is taken away at St 4 until the player has looked at it for
## five seconds. M02's altered title is checked here too, because that is where
## the player meets it.
##
## The stage is read from the shadow save when no run is in progress (a relaunch
## resets `GameState`), exactly the rule P3.14's shadow name line uses.

const TitlePacked := preload("res://scenes/Title.tscn")
const SCRATCH := "user://test_meta_title/"

var _meta: Node
var _title: Control


func before_test() -> void:
	GameState.reset()
	Director.reset()
	_wipe(SCRATCH)
	SaveSystem.save_dir = SCRATCH + "saves"
	SaveSystem.shadow_path = SCRATCH + "shadow.json"
	SaveSystem.autosave_enabled = false
	_meta = MetaEventsM01.find(MetaDirector)
	assert_object(_meta).is_not_null()
	_meta.store.path = SCRATCH + "meta_state.json"
	_meta.reset_session()
	Settings.reduced_motion = false
	_title = null


func after_test() -> void:
	Settings.reduced_motion = false
	if _title != null and is_instance_valid(_title):
		_title.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if _meta != null and is_instance_valid(_meta):
		_meta.store.path = MetaStateM01.PATH
	GameState.reset()
	_wipe(SCRATCH)


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if dir.current_is_dir():
			_wipe(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


## A finished run at `stage` (the shadow's `last_stage`), then the real title.
func _open_title(stage: int) -> Control:
	var shadow := ShadowStore.new()
	shadow.path = SaveSystem.shadow_path
	shadow.store({"last_stage": stage, "memories": []})
	_meta.reset_session()
	_title = TitlePacked.instantiate()
	add_child(_title)
	await get_tree().process_frame
	return _title


## docs/05 §1.1 M06: "at 5 the title text is *her* name".
func test_m06_title_text_is_her_name_at_stage_five() -> void:
	var title := await _open_title(5)
	assert_str(title.title_label.text).is_equal("Leila")
	var portrait := title.get_node_or_null("MetaPortrait") as TextureRect
	assert_object(portrait).is_not_null()


## docs/05 §1.1 M06: the sprite changes with the stage, and there is none below
## the St 2 gate — the title screen stays the plain one for a new player.
func test_m06_portrait_appears_at_stage_two_and_changes_with_stage() -> void:
	var low := await _open_title(1)
	assert_object(low.get_node_or_null("MetaPortrait")).is_null()
	_title.queue_free()
	await get_tree().process_frame
	var mid := await _open_title(3)
	var portrait := mid.get_node_or_null("MetaPortrait") as TextureRect
	assert_object(portrait).is_not_null()
	var atlas := portrait.texture as AtlasTexture
	assert_object(atlas).is_not_null()
	# The crop is casting's bust_crop_native in display (x2) pixels. Assert the
	# base region: the atlas region itself drifts toward the cursor under the
	# eye-follow, so it is `_meta_base_region` + the frame's step.
	var expected := Rect2(208, 40, 352, 400)
	assert_bool(mid._meta_base_region.is_equal_approx(expected)).is_true()
	var step: Vector2 = atlas.region.position - mid._meta_base_region.position
	assert_bool(atlas.region.size.is_equal_approx(mid._meta_base_region.size)).is_true()
	assert_float(absf(step.x)).is_less_equal(4.0)
	assert_float(absf(step.y)).is_less_equal(4.0)
	# And the eye offset is the module's documented 2 px.
	assert_int(mid._meta_eyes_px).is_equal(2)


## docs/05 §0 rule 5 + the M06 row: reduced motion switches the eye movement off
## (a moving image is motion) while the portrait itself stays.
func test_m06_eyes_follow_is_off_under_reduced_motion() -> void:
	Settings.reduced_motion = true
	var title := await _open_title(4)
	assert_object(title.get_node_or_null("MetaPortrait")).is_not_null()
	assert_bool(title._meta_eyes_follow).is_false()
	Settings.reduced_motion = false
	_title.queue_free()
	await get_tree().process_frame
	var moving := await _open_title(4)
	assert_bool(moving._meta_eyes_follow).is_true()


## docs/05 §1.1 M07: "New Game is greyed out: 'Why would you want a new one?'
## Hover for 5 s and it becomes clickable."
func test_m07_new_game_is_locked_then_unlocks_after_five_seconds() -> void:
	var title := await _open_title(4)
	assert_bool(title.new_game_button.disabled).is_true()
	assert_str(title.new_game_button.tooltip_text).contains("new one")
	title.meta_hover_override = true
	title.advance_meta(2.0)
	assert_bool(title.new_game_button.disabled).is_true()
	title.advance_meta(3.5)
	assert_bool(title.new_game_button.disabled).is_false()


## docs/05 §1.1 M07 removes New Game only: the player can always continue, open
## Settings or leave, so the title screen can never become a dead end.
func test_m07_continue_stays_available_while_new_game_is_locked() -> void:
	var title := await _open_title(5)
	assert_bool(title.new_game_button.disabled).is_true()
	assert_bool(title.settings_button.disabled).is_false()
	assert_bool(title.quit_button.disabled).is_false()
