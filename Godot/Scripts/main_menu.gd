extends Control

@onready var menu_items = $MenuOptions
@onready var cursor = $cursor

var current_selection = 0
var menu_options = []
var can_navigate = true
var cursor_base_x = 0  # Track base position for bobbing

func _ready():
	menu_options = menu_items.get_children()
	
	if cursor == null:
		push_warning("Cursor node not found!")
		return
	
	cursor.visible = true
	update_cursor_position()
	
	# Add cursor bobbing animation after initial position is set
	add_cursor_bob()

func _input(event):
	if cursor == null or not can_navigate:
		return
		
	if event.is_action_pressed("ui_down"):
		current_selection = (current_selection + 1) % menu_options.size()
		update_cursor_position()
		play_move_sound()
		
	elif event.is_action_pressed("ui_up"):
		current_selection = (current_selection - 1) % menu_options.size()
		if current_selection < 0:
			current_selection = menu_options.size() - 1
		update_cursor_position()
		play_move_sound()
		
	elif event.is_action_pressed("ui_accept"):
		can_navigate = false
		play_flash_animation()

func update_cursor_position():
	if menu_options.size() > 0 and cursor != null:
		var selected_item = menu_options[current_selection]
		
		var target_pos = selected_item.global_position
		
		var cursor_height = 0
		if cursor.texture:
			cursor_height = cursor.texture.get_height() * cursor.scale.y
		
		# Calculate the base position
		cursor_base_x = target_pos.x + (selected_item.size.x / 2) - (cursor_height / 2)
		
		cursor.position = Vector2(
			target_pos.x - 50,
			cursor_base_x
		)
		
		# Restart the bobbing animation at the new position
		add_cursor_bob()
		
		# Reset all items to normal
		for i in menu_options.size():
			menu_options[i].modulate = Color.WHITE

func add_cursor_bob():
	# Kill any existing tween
	var existing_tweens = get_tree().get_processed_tweens()
	for tween in existing_tweens:
		if tween.is_valid():
			tween.kill()
	
	# Create new bobbing animation from current position
	var tween = create_tween().set_loops()
	tween.tween_property(cursor, "position:x", cursor_base_x + 4, 0.4).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cursor, "position:x", cursor_base_x, 0.4).set_ease(Tween.EASE_IN_OUT)

func play_flash_animation():
	var selected_item = menu_options[current_selection]
	
	# Kill bobbing animation during flash
	var existing_tweens = get_tree().get_processed_tweens()
	for tween in existing_tweens:
		if tween.is_valid():
			tween.kill()
	
	# Flash the selected option and cursor
	var tween = create_tween()
	
	# Flashing
	for i in range(6):
		tween.tween_property(selected_item, "modulate", Color(0, 0, 0, 0), 0.05)
		tween.tween_property(cursor, "modulate", Color(0, 0, 0, 0), 0.0)
		tween.tween_property(selected_item, "modulate", Color.WHITE, 0.05)
		tween.tween_property(cursor, "modulate", Color.WHITE, 0.0)
	
	# After flashing, execute the selection
	tween.tween_callback(select_current_option)

func play_move_sound():
	# Add your menu navigation sound here
	# Example: $MenuMoveSound.play()
	pass

func select_current_option():
	# Add your selection sound here
	# Example: $MenuSelectSound.play()
	
	match current_selection:
		0:
			await get_tree().create_timer(0.1).timeout
			print("Start game selected")
			# get_tree().change_scene_to_file("res://game_scene.tscn")
			get_tree().quit()
		1:
			await get_tree().create_timer(0.1).timeout
			print("Options selected")
			# get_tree().change_scene_to_file("res://options_menu.tscn")
			get_tree().quit()
		2:
			await get_tree().create_timer(0.1).timeout
			get_tree().quit()
