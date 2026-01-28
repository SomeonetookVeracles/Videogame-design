extends Control

@onready var menu_items = $MenuOptions
@onready var cursor = $cursor
@onready var fullscreen_option = $MenuOptions/Fullscreen

var current_selection = 0
var menu_options = []
var can_navigate = true
var cursor_base_x = 0  # Base X position for horizontal bobbing

func _ready():
	fullscreen_option.set_text("Fullscreen: Disabled")		
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
	if menu_options.size() == 0 or cursor == null:
		return
	
	var selected_item = menu_options[current_selection]
	var item_pos = selected_item.global_position
	var item_size = selected_item.size
	
	var cursor_height = 0.0
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
	pass # Add sound here

func select_current_option():
	var selected_node = menu_options[current_selection]
	
	match current_selection:
		0: # Start Game
			call_deferred("_start_game")
		1: # Fullscreen toggle
			call_deferred("_toggle_fullscreen")
		2: # Back
			call_deferred("_back_to_main")

# ---------------------
# Deferred helper functions
# ---------------------

func _start_game():
	print("Start game selected")
	# get_tree().change_scene_to_file("res://scenes/game.tscn")
	get_tree().quit()

func _back_to_main():
	print("Quit game selected")
	play_side_transition("res://scenes/main/menus/MainMenu.tscn")
func _toggle_fullscreen():
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		print("Fullscreen enabled")
		fullscreen_option.set_text("Fullscreen: Enabled")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		print("Fullscreen disabled")
		fullscreen_option.set_text("Fullscreen: Disabled")
	
	can_navigate = true  # re-enable menu navigation
func play_side_transition(next_scene_path: String):
	# Create a full-screen ColorRect as overlay
	var overlay = ColorRect.new()
	overlay.color = Color.BLACK
	
	overlay.size = get_viewport_rect().size
	overlay.position = Vector2(overlay.size.x, 0)  # Start off-screen right
	add_child(overlay)
	
	# Tween to slide overlay from right to left
	var tween = create_tween()
	tween.tween_property(overlay, "position:x", 0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		# Once overlay covers the screen, change scene
		get_tree().change_scene_to_file(next_scene_path)
	)
