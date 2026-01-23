extends Control
@export var transition_time := 2
var can_transition = true

func _input(event):
	if event is InputEventKey and event.pressed and can_transition:
		can_transition = false  # Prevent multiple presses
		fade_out()

func fade_out():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, transition_time )
	tween.tween_callback(change_scene)

func change_scene():
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
