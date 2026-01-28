extends Area2D

@export var next_level_path: String
@export var transition_key: String
@export var collision_layer_to_trigger: int = 1  # Only trigger for this layer

var player_inside = false

func _process(delta):
	# Check all bodies currently overlapping this area
	var bodies = get_overlapping_bodies()
	player_inside = false

	for body in bodies:
		# Check if the body's collision layer matches
		if body.collision_layer & (1 << (collision_layer_to_trigger - 1)) != 0:
			player_inside = true
			# If player presses jump/action, start transition
			if Input.is_action_just_pressed(transition_key):
				_start_transition()
			break

func _start_transition():
	# Prevent multiple triggers
	set_process(false)

	# Create overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)  # Start transparent
	overlay.size = get_viewport_rect().size
	overlay.position = Vector2.ZERO
	get_tree().root.add_child(overlay)

	# Tween to fade out
	var tween = overlay.create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(next_level_path)
	)
func _create_transition_overlay(next_scene: String) -> ColorRect:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0) # Start transparent
	overlay.size = get_viewport_rect().size
	overlay.position = Vector2.ZERO
	get_tree().root.add_child(overlay)

	var tween = overlay.create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(next_scene)
	)
	return overlay
