extends Control
@onready var title: Label = $MainTitle 
@onready var main_buttons: VBoxContainer = $MainButtons
@onready var options: Panel = $OptionsPanel
@onready var keybindpanel: Panel = $KeybindPanel
@export var button_click_sound: AudioStream
func _ready():
	main_buttons.visible = true
	options.visible = false
	title.visible = true
	keybindpanel.visible = false
func _on_level_select_pressed() -> void:
	print("Level Select Pressed")
	get_tree().change_scene_to_file("")
func _on_options_pressed() -> void:
	print("Options Pressed")
	main_buttons.visible = false
	options.visible = true
	title.visible = false
func _on_exit_pressed() -> void:
	print("Exit Pressed")
	get_tree().quit()
func _on_back_pressed() -> void:
	main_buttons.visible = true
	options.visible = false
	title.visible = true
func _on_k_back_pressed() -> void:
	keybindpanel.visible = false
	options.visible = true
func _on_keybinds_pressed() -> void:
	options.visible = false
	keybindpanel.visible = true
func _fullscreen__toggle(toggled_on: bool) -> void:
	if toggled_on == true:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
