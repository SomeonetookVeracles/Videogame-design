# Enables global logging for debugging
extends Node

var enable_logging = true

func log(message: String) -> void: # NOTE Logging must be done on the script where this is called, you can't use it in this file.
	if enable_logging:
		print(message)
		
func quit() -> void: # To quit the game entirely
	get_tree().quit()
	
func exit_to_menu() -> void: # To exit to main menu
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
 
