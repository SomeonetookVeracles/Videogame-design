# File: MainMenu.gd
extends Control
@onready var start_button: Button = $PlayButton
@onready var settings_button: Button = $SettingsButton
@onready var exit_button: Button = $QuitButton
func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/LevelSelect.tscn")
	globals.log("Level select pressed")
func _on_settings_pressed() -> void:
	var settings_menu = preload("res://scenes/SettingsMenu.tscn").instantiate()
	get_tree().current_scene.add_child(settings_menu)
	globals.log("Settings Button Pressed")
func _on_exit_pressed() -> void:
	get_tree().quit()
	globals.log("Exit Button Pressed")
