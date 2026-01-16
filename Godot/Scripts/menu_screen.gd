extends Control

@onready var menu_items = $VBoxContainer
@onready var cursor = $Cursor

var current_selection = 0
var menu_options = []

func _ready():
	# Get all menu option nodes
	menu_options = menu_items.get_children()
	
	# Set up pixel-perfect rendering for that retro look
	get_viewport().set_scaling_3d_mode(Viewport.SCALING_3D_MODE_BILINEAR)
	
	update_cursor_position()

func _input(event):
	if event.is_action_pressed("ui_down"):
		current_selection = (current_selection + 1) % menu_options.size()
		update_cursor_position()
		# Optional: play menu sound
		
	elif event.is_action_pressed("ui_up"):
		current_selection = (current_selection - 1) % menu_options.size()
		if current_selection < 0:
			current_selection = menu_options.size() - 1
		update_cursor_position()
		
	elif event.is_action_pressed("ui_accept"):
		select_current_option()

func update_cursor_position():
	if menu_options.size() > 0:
		var selected_item = menu_options[current_selection]
		# Position cursor to the left of the selected item
		cursor.global_position = Vector2(
			selected_item.global_position.x + 150,
			selected_item.global_position.y + selected_item.size.y / 2
		)
		
		# Optional: highlight the selected text
		for i in menu_options.size():
			if i == current_selection:
				menu_options[i].modulate = Color(1, 1, 0.5) # Slight yellow tint
			else:
				menu_options[i].modulate = Color.WHITE

func select_current_option():
	match current_selection:
		0: # Start Game
			get_tree().change_scene_to_file("res://game_scene.tscn")
		1: # Options
			get_tree().change_scene_to_file("res://options_menu.tscn")
		2: # Quit
			get_tree().quit()
