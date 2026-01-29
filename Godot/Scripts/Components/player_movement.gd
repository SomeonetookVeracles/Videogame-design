class_name PlayerMovement
extends Node

## Handles all player movement physics including walking, jumping, dashing.
## Designed for tight, responsive 2D platformer controls.

signal jumped(is_double_jump: bool)
signal landed
signal dash_started(direction: int)
signal dash_ended

@export_group("Walking")
@export var walk_speed: float = 280.0
@export var acceleration: float = 6000.0
@export var friction: float = 4500.0
@export var air_acceleration: float = 4000.0
@export var turn_multiplier: float = 2.0

@export_group("Jumping")
@export var jump_velocity: float = -620.0
@export var gravity: float = 1300.0
@export var fall_gravity_multiplier: float = 1.6
@export var jump_release_multiplier: float = 3.0
@export var max_jumps: int = 2
@export var coyote_time: float = 0.15
@export var jump_buffer_time: float = 0.15
@export var terminal_velocity_multiplier: float = 2.0

@export_group("Dashing")
@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.4

var parent: CharacterBody2D
var facing_direction: float = 1.0

var _jumps_remaining: int = 2
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _is_jump_held: bool = false
var _was_on_floor: bool = false

var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: int = 0

const MIN_VELOCITY_SQ: float = 25.0


func _ready() -> void:
	parent = get_parent() as CharacterBody2D
	_jumps_remaining = max_jumps


func process_movement(delta: float, can_move: bool = true) -> void:
	_update_timers(delta)
	_update_coyote_time()
	_apply_gravity(delta)
	
	if can_move:
		_process_dash()
		_process_jump()
		_process_horizontal_movement(delta)


func _update_timers(delta: float) -> void:
	if _is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_is_dashing = false
			dash_ended.emit()
	
	_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)


func _update_coyote_time() -> void:
	var on_floor := parent.is_on_floor()
	
	if on_floor:
		_coyote_timer = coyote_time
		if not _was_on_floor:
			_jumps_remaining = max_jumps
			landed.emit()
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - parent.get_physics_process_delta_time())
	
	_was_on_floor = on_floor


func _apply_gravity(delta: float) -> void:
	if parent.is_on_floor() or _is_dashing:
		return
	
	var _is_falling := parent.velocity.y > 0.0
	_is_jump_held = Input.is_action_pressed("movement_jump")
	
	if parent.velocity.y < 0.0 and not _is_jump_held:
		parent.velocity.y += gravity * jump_release_multiplier * delta
	else:
		var multiplier := fall_gravity_multiplier if is_falling else 1.0
		parent.velocity.y += gravity * multiplier * delta
	
	parent.velocity.y = minf(parent.velocity.y, gravity * terminal_velocity_multiplier)


func _process_dash() -> void:
	if not Input.is_action_just_pressed("movement_dash"):
		return
	
	if _dash_cooldown_timer > 0.0 or _is_dashing:
		return
	
	var direction := Input.get_axis("movement_left", "movement_right")
	if direction == 0.0:
		direction = facing_direction
	
	_dash_direction = int(sign(direction))
	_is_dashing = true
	_dash_timer = dash_duration
	_dash_cooldown_timer = dash_cooldown
	
	dash_started.emit(_dash_direction)


func _process_jump() -> void:
	if Input.is_action_just_pressed("movement_jump"):
		_jump_buffer_timer = jump_buffer_time
	
	if _jump_buffer_timer <= 0.0:
		return
	
	var can_coyote_jump := _coyote_timer > 0.0 and _jumps_remaining == max_jumps
	var can_multi_jump := _jumps_remaining > 0
	
	if can_coyote_jump or can_multi_jump:
		var is_double_jump := _jumps_remaining < max_jumps
		
		parent.velocity.y = jump_velocity
		_jumps_remaining -= 1
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_is_jump_held = true
		
		jumped.emit(is_double_jump)


func _process_horizontal_movement(delta: float) -> void:
	if _is_dashing:
		parent.velocity.x = _dash_direction * dash_speed
		parent.velocity.y = 0.0
		return
	
	var direction := Input.get_axis("movement_left", "movement_right")
	var on_floor := parent.is_on_floor()
	
	if direction != 0.0:
		var accel := acceleration if on_floor else air_acceleration
		parent.velocity.x = move_toward(parent.velocity.x, direction * walk_speed, accel * delta)
		
		# Snappier turning on ground
		if on_floor and sign(direction) != sign(parent.velocity.x) and parent.velocity.x * parent.velocity.x > MIN_VELOCITY_SQ:
			parent.velocity.x = move_toward(parent.velocity.x, direction * walk_speed, acceleration * turn_multiplier * delta)
		
		facing_direction = sign(direction)
	else:
		var decel := friction if on_floor else air_acceleration * 0.75
		parent.velocity.x = move_toward(parent.velocity.x, 0.0, decel * delta)


func apply_knockback(force: Vector2) -> void:
	if not _is_dashing:
		parent.velocity = force


func is_dashing() -> bool:
	return _is_dashing


func is_moving() -> bool:
	return parent.velocity.x * parent.velocity.x > MIN_VELOCITY_SQ


func is_falling() -> bool:
	return parent.velocity.y > 0.0 and not parent.is_on_floor()


func is_rising() -> bool:
	return parent.velocity.y < 0.0


func reset_jumps() -> void:
	_jumps_remaining = max_jumps


func get_jumps_remaining() -> int:
	return _jumps_remaining
