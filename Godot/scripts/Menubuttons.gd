extends Node

signal button_pressed(button_name: String) # establishes signal for console

func _ready() -> void:
	_connect_buttons(self)
	
func _connect_buttons(node: Node) -> void: 
	for child in node.get_children():
		if child is Button:
			child.pressed.connect(_on_button_pressed.bind(child))
		elif child.get_child_count() > 0:
			_connect_buttons(child)
func _on_button_pressed(button: Button) -> void: 
	print(button.name, " pressed! ")
	emit_signal("button_pressed", button.name) #Sends signal to console with button name
