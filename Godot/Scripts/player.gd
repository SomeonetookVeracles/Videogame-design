extends CharacterBody2D

# Movement parameters
@export_group("Movement")
@export var speed: float = 300.0
@export var acceleration: float = 2000.0
@export var friction: float = 2000.0

# Jump parameters
@export_group("Jump")
@export var jump_velocity: float = -400.0
@export var gravity: float = 980.0
@export var fall_gravity_multiplier: float = 1.5
@export var jump_buffer_time: float = 0.1
@export var coyote_time: float = 0.1

# Internal state
var jump_buffer_timer: float = 0.0
var coyote_timer: float = 0.0
var was_on_floor: bool = false

func _ready() -> void:
	# Any init code here
	pass

func _physics_process(delta: float) -> void:
	# Handle timers
	_update_timers(delta)
	
	# gravity
	_apply_gravity(delta)
	
	# jump input
	_handle_jump()
	
	# horizontal movement
	_handle_movement(delta)
	
	# Move character
	move_and_slide()
	
	# Update state tracking
	was_on_floor = is_on_floor()

func _update_timers(delta: float) -> void:
	# Coyote time: grace period after leaving ground
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = max(0, coyote_timer - delta)
	
	# Jump buffer: grace period for early jump presses
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		# Apply stronger gravity when falling for better jump feel
		var gravity_multiplier = fall_gravity_multiplier if velocity.y > 0 else 1.0
		velocity.y += gravity * gravity_multiplier * delta

func _handle_jump() -> void:
	# Detect jump input
	if Input.is_action_just_pressed("ui_accept"):  # Space bar by default
		jump_buffer_timer = jump_buffer_time
	
	# Execute jump if conditions are met
	var can_jump = (is_on_floor() or coyote_timer > 0) and jump_buffer_timer > 0
	
	if can_jump:
		velocity.y = jump_velocity
		jump_buffer_timer = 0
		coyote_timer = 0

func _handle_movement(delta: float) -> void:
	# Get input direction
	var direction = Input.get_axis("ui_left", "ui_right")
	
	if direction != 0:
		# Accelerate towards target speed
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
	else:
		# Apply friction when no input
		velocity.x = move_toward(velocity.x, 0, friction * delta)


# Called when the character lands on the ground
func _on_landed() -> void:
	pass  # Add landing effects, particles, sounds, etc.

# Called when the character leaves the ground
func _on_left_ground() -> void:
	pass  # Add jump effects, particles, sounds, etc.

# Add dash ability
func _handle_dash() -> void:
	pass  # Implement dash mechanics here

# Add wall jump ability
func _handle_wall_jump() -> void:
	pass  # Implement wall jump mechanics here

# Add attack system
func _handle_attack() -> void:
	pass  # Implement attack mechanics here
