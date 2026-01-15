extends Control

# Menu state
var selected_index = 0
var menu_items = []

# Menu options - using get_node to be more flexible
@onready var menu_container = $Menu

func _ready():
	# Wait for nodes to be ready
	await get_tree().process_frame
	
	# Collect menu items from VBoxContainer children
	for child in menu_container.get_children():
		if child is Label:
			menu_items.append(child)
	
	if menu_items.is_empty():
		push_error("No menu items found! Make sure VBoxContainer has Label children.")
		return
	
	# Connect signals
	for i in range(menu_items.size()):
		var item = menu_items[i]
		item.mouse_entered.connect(_on_menu_item_mouse_entered.bind(i))
		item.gui_input.connect(_on_menu_item_gui_input.bind(i))
	
	# Set initial cursor position
	update_cursor_position()

func _input(event):
	if menu_items.is_empty():
		return
		
	if event.is_action_pressed("ui_down"):
		selected_index = (selected_index + 1) % menu_items.size()
		update_cursor_position()
		get_viewport().set_input_as_handled()
	
	elif event.is_action_pressed("ui_up"):
		selected_index = (selected_index - 1 + menu_items.size()) % menu_items.size()
		update_cursor_position()
		get_viewport().set_input_as_handled()
	
	elif event.is_action_pressed("ui_accept"):
		activate_menu_item(selected_index)
		get_viewport().set_input_as_handled()

func update_cursor_position():
	if selected_index >= menu_items.size():
		return
		
	var cursor = get_node_or_null("Cursor")
	if cursor == null:
		# If no cursor node exists, highlight the text instead
		highlight_selected_item()
		return
	
	var item = menu_items[selected_index]
	# Position cursor to the left of the menu item
	cursor.global_position = Vector2(
		item.global_position.x - 80,
		item.global_position.y + item.size.y / 2 - cursor.size.y / 2
	)
	
	# Also highlight the selected item
	highlight_selected_item()

func highlight_selected_item():
	# Reset all items to normal color
	for i in range(menu_items.size()):
		var item = menu_items[i]
		if i == selected_index:
			# Highlight selected (brighter orange)
			item.add_theme_color_override("font_color", Color("#FFB570"))
		else:
			# Normal color
			item.add_theme_color_override("font_color", Color("#FF8C42"))

func _on_menu_item_mouse_entered(index: int):
	selected_index = index
	update_cursor_position()

func _on_menu_item_gui_input(event: InputEvent, index: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activate_menu_item(index)

func activate_menu_item(index: int):
	if index >= menu_items.size():
		return
		
	var item_text = menu_items[index].text.to_upper()
	
	if "START" in item_text:
		start_game_pressed()
	elif "OPTION" in item_text:
		options_pressed()
	elif "EXIT" in item_text:
		exit_pressed()

func start_game_pressed():
	print("Starting game...")
	# Replace with your game scene
	# get_tree().change_scene_to_file("res://game.tscn")

func options_pressed():
	print("Opening options...")
	# Replace with your options scene
	# get_tree().change_scene_to_file("res://options.tscn")

func exit_pressed():
	print("Exiting game...")
	get_tree().quit()
