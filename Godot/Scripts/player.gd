extends CharacterBody2D

# Movement parameters
@export_group("Movement")
@export var walk_speed := 300.0
@export var run_speed := 500.0
@export var jump_velocity := -400.0
@export var gravity := 980.0
@export var max_jumps := 2
@export var acceleration := 2000.0
@export var friction := 1500.0
@export var air_acceleration := 1200.0
@export var coyote_time := 0.15
@export var jump_buffer_time := 0.15
@export var min_jump_velocity := -200.0  # Minimum jump height when released early
@export var jump_release_multiplier := 2.5  # How fast to cut jump short

@export_group("Dash")
@export var dash_speed := 800.0
@export var dash_duration := 0.2
@export var dash_cooldown := 1.0
@export var dash_input_buffer := 0.1  # Buffer time for dash input

@export_group("Spawn")
@export var respawn_delay := 2.0
@export var spawn_delay := 2.0
@export var double_jump_particle_scene: PackedScene

@export_group("Combat")
@export var attack_damage := 10.0
@export var attack_cooldown := 0.5
@export var attack_knockback := 300.0
@export var attack_animation_speed := 1.0
@export var attack_particle_delay := 0.1

# Cached node references
@onready var animation_player := $"animations/debug-animations"
@onready var animations_node := $animations
@onready var sprites := {
	"idle": $animations/sprites/Idle,
	"run": $animations/sprites/Run,
	"jump": $animations/sprites/Jump,
	"dash": $animations/sprites/Dash,
	"attack": $animations/sprites/combat_attack
}
@onready var particles := {
	"jump": $"particles/jump-particles",
	"dash": $"particles/dash-particles",
	"death": $"particles/death-particles",
	"attack": $"particles/attack-particles"
}
@onready var attack_hitbox := $combat/AttackHitbox

# State variables
var jumps_remaining := max_jumps
var was_in_air := false
var is_dashing := false
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_direction := 0
var spawn_position := Vector2.ZERO
var is_dead := false
var is_spawning := true
var is_attacking := false
var attack_cooldown_timer := 0.0

# Coyote time and jump buffering
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var dash_buffer_timer := 0.0
var last_on_floor := false
var is_jump_held := false  # Track if jump button is being held

enum AnimState { IDLE, RUN, JUMP, DASH, ATTACK }

func _ready() -> void:
	spawn_position = global_position
	_hide_all_sprites()
	_disable_hitbox()
	
	# Connect animation finished signal
	if animation_player:
		animation_player.animation_finished.connect(_on_attack_animation_finished)
	
	await get_tree().create_timer(spawn_delay).timeout
	_spawn_in()

func _physics_process(delta: float) -> void:
	if is_dead or is_spawning:
		return
	
	_update_timers(delta)
	_update_coyote_time(delta)
	_apply_gravity(delta)
	
	# Keep attack sprite visible during attack
	if is_attacking:
		if sprites.has("attack") and sprites["attack"]:
			sprites["attack"].visible = true
	
	# Combat takes priority over other actions
	if not is_attacking:
		_handle_dash()
		_handle_jump()
		_handle_movement(delta)
	else:
		# Slow down during attack with friction
		velocity.x = move_toward(velocity.x, 0, friction * delta)
	
	_handle_attack()
	_update_animation()
	move_and_slide()

func _update_timers(delta: float) -> void:
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
	
	dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	attack_cooldown_timer = maxf(0.0, attack_cooldown_timer - delta)
	
	# Jump buffer timer - allows queuing jump before landing
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	
	# Dash buffer timer - allows queuing dash input
	if dash_buffer_timer > 0:
		dash_buffer_timer -= delta

func _update_coyote_time(delta: float) -> void:
	# Update coyote time - gives a grace period to jump after leaving ground
	var on_floor := is_on_floor()
	
	if on_floor:
		coyote_timer = coyote_time
		if not last_on_floor:
			jumps_remaining = max_jumps
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
	
	last_on_floor = on_floor

func _apply_gravity(delta: float) -> void:
	if not is_on_floor() and not is_dashing:
		# Variable jump height - cut jump short when button is released
		if velocity.y < 0 and not is_jump_held:
			# Cut jump short by applying extra downward force
			velocity.y += gravity * jump_release_multiplier * delta
		else:
			# Normal gravity (falling or holding jump)
			var gravity_multiplier := 1.0
			if velocity.y > 0:  # Falling
				gravity_multiplier = 1.5  # Fall slightly faster for better feel
			velocity.y += gravity * gravity_multiplier * delta
		
		# Terminal velocity
		velocity.y = minf(velocity.y, gravity * 2.0)
	
	# Track jump button state for variable jump height
	is_jump_held = Input.is_action_pressed("movement_jump")

func _handle_dash() -> void:
	# Buffer dash input
	if Input.is_action_just_pressed("movement_dash"):
		dash_buffer_timer = dash_input_buffer
	
	# Check if we can dash (either just pressed or buffered)
	if dash_buffer_timer <= 0:
		return
	
	if is_dashing or dash_cooldown_timer > 0 or is_attacking:
		return
	
	var direction := Input.get_axis("movement_left", "movement_right")
	if direction == 0:
		direction = 1.0 if animations_node.scale.x > 0 else -1.0
	
	dash_direction = int(direction)
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_buffer_timer = 0  # Consume buffered dash
	
	_trigger_particles("dash", -1.0 if dash_direction < 0 else 1.0)
	_play_animation("Dash")

func _handle_jump() -> void:
	# Jump buffering - remember jump input for a short time before landing
	if Input.is_action_just_pressed("movement_jump"):
		jump_buffer_timer = jump_buffer_time
	
	# Check if we can jump (including coyote time)
	var can_jump := false
	
	if is_attacking:
		return
	
	# Ground jump or coyote time jump (allows jumping shortly after leaving ground)
	if coyote_timer > 0 and jumps_remaining == max_jumps:
		can_jump = true
	# Air jump (double jump, etc.)
	elif jumps_remaining > 0:
		can_jump = true
	
	# Only jump if we have a buffered input and can jump
	if not can_jump or jump_buffer_timer <= 0:
		return
	
	# Execute jump
	velocity.y = jump_velocity
	jumps_remaining -= 1
	jump_buffer_timer = 0  # Consume buffered jump
	coyote_timer = 0  # Consume coyote time
	is_jump_held = true  # Mark that jump is being held
	
	var is_double_jump := jumps_remaining < max_jumps - 1
	
	if is_double_jump:
		_play_animation("Jump")
		_trigger_particles("jump", animations_node.scale.x)
		_spawn_double_jump_particles()

func _handle_movement(delta: float) -> void:
	var direction := Input.get_axis("movement_left", "movement_right")
	var current_speed := run_speed if Input.is_action_pressed("movement_run") else walk_speed
	
	if is_dashing:
		velocity.x = dash_direction * dash_speed
		velocity.y = 0
	elif direction != 0:
		# Smooth acceleration
		var accel := acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, direction * current_speed, accel * delta)
		
		# Update facing direction
		var new_scale := -1.0 if direction < 0 else 1.0
		if animations_node.scale.x != new_scale:
			animations_node.scale.x = new_scale
			_flip_attack_hitbox()
	else:
		# Apply friction
		var decel := friction if is_on_floor() else air_acceleration * 0.5
		velocity.x = move_toward(velocity.x, 0, decel * delta)

func _handle_attack() -> void:
	if not Input.is_action_just_pressed("combat_attack"):
		return
		
	if attack_cooldown_timer > 0 or is_attacking:
		return
	
	is_attacking = true
	attack_cooldown_timer = attack_cooldown
	
	# Force show attack sprite and hide others
	for key in sprites:
		if sprites[key]:
			sprites[key].visible = (key == "attack")
	
	# Flip attack hitbox to match facing direction
	_flip_attack_hitbox()
	
	# Play attack animation
	if animation_player:
		animation_player.stop()
		animation_player.play("Attack", -1, attack_animation_speed)
	
	_enable_hitbox()
	_schedule_attack_particles()

func _flip_attack_hitbox() -> void:
	if not attack_hitbox:
		return
	
	var facing_right: bool = animations_node.scale.x > 0
	
	# Flip the entire hitbox node and its children
	attack_hitbox.scale.x = 1.0 if facing_right else -1.0

func _on_attack_animation_finished(anim_name: String) -> void:
	if anim_name == "Attack":
		is_attacking = false
		_disable_hitbox()

func _update_animation() -> void:
	if is_attacking:
		return
	
	var just_landed := was_in_air and is_on_floor()
	was_in_air = not is_on_floor()
	
	var state: AnimState
	if is_dashing:
		state = AnimState.DASH
	elif not is_on_floor() or just_landed:
		state = AnimState.JUMP
	elif absf(velocity.x) > 10.0:  # Threshold to prevent idle while sliding
		state = AnimState.RUN
	else:
		state = AnimState.IDLE
	
	_set_animation_state(state)

func _set_animation_state(state: AnimState) -> void:
	var anim_names: Array[String] = ["Idle", "Run", "Jump", "Dash", "Attack"]
	var sprite_keys: Array[String] = ["idle", "run", "jump", "dash", "attack"]
	var active_key: String = sprite_keys[state]
	
	# Update sprite visibility
	for key in sprites:
		if sprites[key]:
			sprites[key].visible = (key == active_key)
	
	# Update animation
	var anim_name: String = anim_names[state]
	if animation_player and animation_player.current_animation != anim_name:
		animation_player.stop()
		animation_player.play(anim_name)

func _hide_all_sprites() -> void:
	for sprite in sprites.values():
		if sprite:
			sprite.visible = false

func _show_sprite(key: String) -> void:
	_hide_all_sprites()
	if sprites.has(key) and sprites[key]:
		sprites[key].visible = true

func _trigger_particles(key: String, flip_x: float = 1.0) -> void:
	if particles.has(key) and particles[key]:
		particles[key].scale.x = flip_x
		particles[key].restart()

func _spawn_double_jump_particles() -> void:
	if double_jump_particle_scene:
		var particle_instance := double_jump_particle_scene.instantiate()
		get_parent().add_child(particle_instance)
		particle_instance.global_position = global_position

func _schedule_attack_particles() -> void:
	await get_tree().create_timer(attack_particle_delay).timeout
	
	if is_attacking and particles.has("attack") and particles["attack"]:
		var particle_node = particles["attack"]
		var facing_right: bool = animations_node.scale.x > 0
		
		if particle_node is GPUParticles2D:
			particle_node.process_material.direction.x = 1.0 if facing_right else -1.0
			particle_node.restart()
		elif particle_node is CPUParticles2D:
			particle_node.direction.x = 1.0 if facing_right else -1.0
			particle_node.restart()
		else:
			particle_node.scale.x = 1.0 if facing_right else -1.0
			particle_node.restart()

func _spawn_in() -> void:
	_trigger_particles("death")
	is_spawning = false
	_show_sprite("idle")

func _play_animation(anim_name: String, speed: float = 1.0) -> void:
	if animation_player:
		animation_player.stop()
		animation_player.play(anim_name, -1, speed)

func _enable_hitbox() -> void:
	if attack_hitbox:
		attack_hitbox.monitoring = true

func _disable_hitbox() -> void:
	if attack_hitbox:
		attack_hitbox.monitoring = false

func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if body == self:
		return
	
	if body.has_method("take_damage"):
		body.take_damage(attack_damage)
	
	if body is CharacterBody2D:
		var knockback_dir: float = sign(body.global_position.x - global_position.x)
		if knockback_dir == 0:
			knockback_dir = 1.0 if animations_node.scale.x > 0 else -1.0
		
		if body.has_method("apply_knockback"):
			body.apply_knockback(Vector2(knockback_dir * attack_knockback, -200.0))

func take_damage(_amount: float) -> void:
	_on_death_zone_entered(self)

func apply_knockback(force: Vector2) -> void:
	if not is_dashing:
		velocity = force

func _on_death_zone_entered(_body: Node) -> void:
	if is_dead:
		return
	
	is_dead = true
	_trigger_particles("death")
	_hide_all_sprites()
	velocity = Vector2.ZERO
	
	await get_tree().create_timer(respawn_delay).timeout
	respawn()

func respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	is_dashing = false
	dash_timer = 0.0
	dash_cooldown_timer = 0.0
	dash_buffer_timer = 0.0
	is_dead = false
	jumps_remaining = max_jumps
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	is_jump_held = false
	
	_trigger_particles("death")
	_show_sprite("idle")
