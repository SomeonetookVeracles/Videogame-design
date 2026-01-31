extends Control

@onready var menu_items = $MenuOptions
@onready var cursor = $cursor

var current_selection := 0
var menu_options := []
var can_navigate := true
var cursor_base_x := 0


func _ready():
	menu_options = menu_items.get_children()

	if cursor == null:
		push_warning("Cursor node not found!")
		return

	cursor.visible = true
	update_cursor_position()
	add_cursor_bob()


func _input(event):
	if cursor == null or not can_navigate:
		return

	if event.is_action_pressed("ui_down"):
		current_selection = (current_selection + 1) % menu_options.size()
		update_cursor_position()
		play_move_sound()

	elif event.is_action_pressed("ui_up"):
		current_selection = (current_selection - 1 + menu_options.size()) % menu_options.size()
		update_cursor_position()
		play_move_sound()

	elif event.is_action_pressed("ui_accept"):
		can_navigate = false
		play_flash_animation()


func update_cursor_position():
	if menu_options.is_empty():
		return

	var selected_item = menu_options[current_selection]
	var item_pos = selected_item.global_position
	var item_size = selected_item.size

	var cursor_height := 0.0
	if cursor.texture:
		cursor_height = cursor.texture.get_height() * cursor.scale.y

	cursor_base_x = item_pos.x - 50
	var cursor_y = item_pos.y + (item_size.y / 2) - (cursor_height / 2)
	cursor.global_position = Vector2(cursor_base_x, cursor_y)

	add_cursor_bob()

	for option in menu_options:
		option.modulate = Color.WHITE


func add_cursor_bob():
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.kill()

	var tween = create_tween().set_loops()
	tween.tween_property(cursor, "global_position:x", cursor_base_x - 4, 0.4).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cursor, "global_position:x", cursor_base_x, 0.4).set_ease(Tween.EASE_IN_OUT)


func play_flash_animation():
	var selected_item = menu_options[current_selection]

	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.kill()

	var tween = create_tween()
	for i in range(6):
		tween.tween_property(selected_item, "modulate", Color(0, 0, 0, 0), 0.05)
		tween.parallel().tween_property(cursor, "modulate", Color(0, 0, 0, 0), 0.05)
		tween.tween_property(selected_item, "modulate", Color.WHITE, 0.05)
		tween.parallel().tween_property(cursor, "modulate", Color.WHITE, 0.05)

	tween.tween_callback(select_current_option)


func play_move_sound():
	pass # Add SFX if you want


func select_current_option():
	match current_selection:
		0:
			load_level("res://scenes/main/levels/Level1.tscn")
		1:
			load_level("res://scenes/main/levels/Level2.tscn")
		2:
			load_level("res://scenes/main/levels/Level3.tscn")
		3:
			go_back()


# ---------------------
# Helper functions
# ---------------------

func load_level(scene_path: String):
	print("Loading:", scene_path)
	get_tree().change_scene_to_file(scene_path)


func go_back():
	print("Back to main menu")
	play_side_transition("res://scenes/main/menus/MainMenu.tscn")


func play_side_transition(next_scene_path: String):
	var overlay = ColorRect.new()
	overlay.color = Color.BLACK
	overlay.size = get_viewport_rect().size
	overlay.position = Vector2(overlay.size.x, 0)

	add_child(overlay)

	var tween = create_tween()
	tween.tween_property(
		overlay,
		"position:x",
		0,
		0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_callback(func():
		get_tree().change_scene_to_file(next_scene_path)
	)
