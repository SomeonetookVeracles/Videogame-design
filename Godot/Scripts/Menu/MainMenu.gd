extends Control

## Enable to add a "Dev Quickstart" option to the menu
@export var dev_mode: bool = false

@onready var menu_items = $MenuOptions
@onready var cursor = $cursor

var current_selection = 0
var menu_options = []
var can_navigate = true
var cursor_base_x = 0  # Base X position for horizontal bobbing

func _ready():
	if dev_mode:
		_add_dev_option()
	
	menu_options = menu_items.get_children()
	
	if cursor == null:
		push_warning("Cursor node not found!")
		return
	
	cursor.visible = true
	update_cursor_position()
	add_cursor_bob()

func _add_dev_option():
	if menu_items == null or menu_items.get_child_count() == 0:
		push_warning("MenuOptions has no children to clone for dev option")
		return
	
	# Clone the first menu item as a template
	var template = menu_items.get_child(0)
	var dev_option = template.duplicate()
	dev_option.text = "Dev Quickstart"
	dev_option.name = "DevQuickstart"
	menu_items.add_child(dev_option)
	menu_items.move_child(dev_option, 0)

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
	
	# Get cursor dimensions
	var cursor_height = 0.0
	if cursor.texture:
		cursor_height = cursor.texture.get_height() * cursor.scale.y
	
	# Position cursor to the left of the menu item, vertically centered
	cursor_base_x = item_pos.x - 50  # 50 pixels to the left of the item
	var cursor_y = item_pos.y + (item_size.y / 2) - (cursor_height / 2)
	
	cursor.global_position = Vector2(cursor_base_x, cursor_y)
	
	# Restart bobbing at new position
	add_cursor_bob()
	
	# Reset all items to normal color
	for option in menu_options:
		option.modulate = Color.WHITE

func add_cursor_bob():
	# Kill any existing cursor tweens
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.kill()
	
	# Horizontal bobbing animation
	var tween = create_tween().set_loops()
	tween.tween_property(cursor, "global_position:x", cursor_base_x - 4, 0.4).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cursor, "global_position:x", cursor_base_x, 0.4).set_ease(Tween.EASE_IN_OUT)

func play_flash_animation():
	var selected_item = menu_options[current_selection]
	
	# Stop bobbing during flash
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.kill()
	
	var tween = create_tween()
	
	# Flash both the selected option and cursor
	for i in range(6):
		tween.tween_property(selected_item, "modulate", Color(0, 0, 0, 0), 0.05)
		tween.parallel().tween_property(cursor, "modulate", Color(0, 0, 0, 0), 0.05)
		tween.tween_property(selected_item, "modulate", Color.WHITE, 0.05)
		tween.parallel().tween_property(cursor, "modulate", Color.WHITE, 0.05)
	
	tween.tween_callback(select_current_option)

func play_move_sound():
	# TODO: Add menu navigation sound
	# Example: $MenuMoveSound.play()
	pass

func select_current_option():
	# TODO: Add selection sound
	# Example: $MenuSelectSound.play()
	
	var selected_node = menu_options[current_selection]
	
	# Handle dev option by node name for flexibility
	if selected_node.name == "DevQuickstart":
		await get_tree().create_timer(0.1).timeout
		print("Dev Quickstart selected")
		get_tree().change_scene_to_file("res://scenes/demo/Demo world.tscn")
		return
	
	match current_selection:
		0:
			await get_tree().create_timer(0.1).timeout
			print("Start game selected")
			# get_tree().change_scene_to_file("res://scenes/game.tscn")
			play_side_transition("res://scenes/main/menus/levelselect.tscn")
			
		1:
			await get_tree().create_timer(0.1).timeout
			print("Options selected")
			# Play smooth side transition to OptionsMenu
			play_side_transition("res://scenes/menus/OptionsMenu.tscn")
			
		2:
			await get_tree().create_timer(0.1).timeout
			get_tree().quit()

# -----------------------
# Side transition function
# -----------------------
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
