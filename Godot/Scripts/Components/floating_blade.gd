class_name FloatingBlade
extends Node

## A blade that floats around the player, similar to health orbs.
## Integrates with player.gd component system - signals connected externally.

signal blade_hidden
signal blade_shown

@export_group("Blade Appearance")
@export var blade_texture: Texture2D = preload("res://assets/sprites/mira/Spritesheets/Mira_Wandsword.png")
@export var blade_scale: Vector2 = Vector2(2, 2)
@export var blade_z_index: int = 1
@export var blade_modulate: Color = Color.WHITE

@export_group("Float Position")
@export var float_radius: float = 24.0
@export var center_offset: Vector2 = Vector2(0, 0)
@export var base_angle: float = 45.0
@export var point_outward: bool = true
@export var rotation_offset: float = 0.0

@export_group("Float Physics")
## Uses same physics model as health orbs for consistency
@export var return_smoothing: float = 8.0
@export var max_speed: float = 350.0
@export var movement_influence: float = 0.5

@export_group("Hover Animation")
@export var hover_amplitude: float = 3.0
@export var hover_speed: float = 2.5
@export var rotation_wobble: float = 8.0
@export var rotation_wobble_speed: float = 1.8

@export_group("Hide/Show Animation")
@export var hide_duration: float = 0.08
@export var show_duration: float = 0.15
@export var show_delay: float = 0.1

var _blade_instance: Node2D
var _blade_velocity: Vector2 = Vector2.ZERO
var _parent: Node2D
var _parent_prev_pos: Vector2
var _parent_velocity: Vector2
var _time_elapsed: float = 0.0
var _hover_phase: float = 0.0
var _is_hidden: bool = false
var _pending_show: bool = false
var _facing_direction: float = 1.0


func _ready() -> void:
	_parent = get_parent() as Node2D
	if _parent:
		_parent_prev_pos = _parent.global_position
	
	_hover_phase = randf() * TAU
	_spawn_blade()


func _process(delta: float) -> void:
	_time_elapsed += delta
	_update_parent_velocity(delta)
	_update_facing_direction()
	
	if _blade_instance and _blade_instance.visible:
		_update_blade_physics(delta)


func _update_facing_direction() -> void:
	if not _parent:
		return
	
	# Get facing from player's movement component or direct property
	if _parent.has_method("get") and "movement" in _parent:
		var movement = _parent.get("movement")
		if movement and "facing_direction" in movement:
			_facing_direction = movement.facing_direction
	elif "facing_direction" in _parent:
		_facing_direction = _parent.facing_direction


func _update_parent_velocity(delta: float) -> void:
	if not _parent:
		return
	
	if delta > 0.0:
		_parent_velocity = (_parent.global_position - _parent_prev_pos) / delta
	_parent_prev_pos = _parent.global_position


func _get_target_position() -> Vector2:
	if not _parent:
		return Vector2.ZERO
	
	var angle := deg_to_rad(base_angle)
	var offset := Vector2(cos(angle), -sin(angle)) * float_radius
	
	# Flip X position based on facing direction
	offset.x *= _facing_direction
	
	# Hover animation
	var hover_offset := Vector2(
		0,
		sin(_time_elapsed * hover_speed + _hover_phase) * hover_amplitude
	)
	
	# center_offset stays constant regardless of facing
	return _parent.global_position + center_offset + offset + hover_offset


func _get_target_rotation() -> float:
	if not point_outward:
		return deg_to_rad(rotation_offset)
	
	var angle := deg_to_rad(base_angle)
	var wobble := sin(_time_elapsed * rotation_wobble_speed) * deg_to_rad(rotation_wobble)
	
	# Mirror rotation when facing left
	if _facing_direction < 0:
		angle = PI - angle
	
	return angle + deg_to_rad(rotation_offset) + wobble


func _update_blade_physics(delta: float) -> void:
	if not _blade_instance:
		return
	
	var pos := _blade_instance.global_position
	var target := _get_target_position()
	
	# Movement influence - blade trails behind when player moves (like health orbs)
	var player_speed := _parent_velocity.length()
	var speed_factor := clampf(player_speed / 250.0, 0.0, 1.0)
	
	var trail_offset := Vector2.ZERO
	if player_speed > 15.0:
		var move_dir := _parent_velocity.normalized()
		trail_offset = -move_dir * 12.0 * speed_factor * movement_influence
	
	var adjusted_target := target + trail_offset
	var to_target := adjusted_target - pos
	var distance := to_target.length()
	
	# Smoothing - tighter when still, looser when moving (matches health orbs)
	var smoothing := lerpf(return_smoothing, return_smoothing * 0.5, speed_factor)
	var distance_bonus := clampf(distance / 80.0, 0.0, 1.5)
	smoothing *= (1.0 + distance_bonus)
	
	var target_vel := to_target * smoothing
	
	# Blend toward target velocity
	var accel := lerpf(6.0, 3.5, speed_factor)
	_blade_velocity = _blade_velocity.lerp(target_vel, accel * delta)
	
	# Speed limit
	var current_speed := _blade_velocity.length()
	if current_speed > max_speed:
		_blade_velocity = _blade_velocity * (max_speed / current_speed)
	
	_blade_instance.global_position = pos + _blade_velocity * delta
	
	# Rotation
	var target_rot := _get_target_rotation()
	_blade_instance.rotation = lerp_angle(_blade_instance.rotation, target_rot, 8.0 * delta)


func _spawn_blade() -> void:
	if _blade_instance:
		_blade_instance.queue_free()
	
	_blade_instance = Node2D.new()
	_blade_instance.name = "FloatingBlade"
	var sprite := Sprite2D.new()
	sprite.texture = blade_texture
	_blade_instance.add_child(sprite)
	
	_setup_blade()


func _setup_blade() -> void:
	if not _blade_instance:
		return
	
	# Add as sibling of parent (like health orbs)
	if _parent and _parent.get_parent():
		_parent.get_parent().call_deferred("add_child", _blade_instance)
	
	_blade_instance.z_index = blade_z_index
	_blade_instance.scale = blade_scale
	_blade_instance.modulate = blade_modulate
	
	_blade_instance.global_position = _get_target_position()
	_blade_instance.rotation = _get_target_rotation()


# --- Public API (called by player.gd signal handlers) ---

func on_attack_started() -> void:
	hide_blade()


func on_attack_ended() -> void:
	if show_delay > 0.0:
		_pending_show = true
		await get_tree().create_timer(show_delay).timeout
		if _pending_show:
			show_blade()
			_pending_show = false
	else:
		show_blade()


func hide_blade() -> void:
	_pending_show = false
	
	if _is_hidden or not _blade_instance:
		return
	
	_is_hidden = true
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_blade_instance, "scale", Vector2.ZERO, hide_duration)
	tween.tween_property(_blade_instance, "modulate:a", 0.0, hide_duration)
	tween.finished.connect(func():
		if _blade_instance:
			_blade_instance.visible = false
	)
	
	blade_hidden.emit()


func show_blade() -> void:
	if not _is_hidden or not _blade_instance:
		return
	
	_is_hidden = false
	_blade_instance.visible = true
	_blade_instance.global_position = _get_target_position()
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_blade_instance, "scale", blade_scale, show_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_blade_instance, "modulate:a", blade_modulate.a, show_duration)
	
	blade_shown.emit()


func hide_immediate() -> void:
	_pending_show = false
	_is_hidden = true
	if _blade_instance:
		_blade_instance.visible = false
		_blade_instance.scale = Vector2.ZERO
		_blade_instance.modulate.a = 0.0


func show_immediate() -> void:
	_pending_show = false
	_is_hidden = false
	if _blade_instance:
		_blade_instance.visible = true
		_blade_instance.scale = blade_scale
		_blade_instance.modulate = blade_modulate
		_blade_instance.global_position = _get_target_position()


func is_visible() -> bool:
	return not _is_hidden


func get_blade_instance() -> Node2D:
	return _blade_instance
