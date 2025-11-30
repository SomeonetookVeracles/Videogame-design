extends CharacterBody2D
# Movement parameters
@export var walk_speed = 300.0
@export var run_speed = 500.0
@export var jump_velocity = -400.0
@export var gravity = 980.0
@export var max_jumps = 2
@export var dash_speed = 800.0
@export var dash_duration = 0.2
@export var dash_cooldown = 1.0
@export var respawn_delay = 2.0
@export var spawn_delay = 2.0
# Particle scene to instantiate for double jump (assign a .tscn file in the Inspector)
@export var double_jump_particle_scene: PackedScene
# Reference to AnimationPlayer (assign in editor or use @onready)
@onready var animation_player = $"animations/debug-animations"
@onready var animations_node = $animations
@onready var idle_sprite = $animations/sprites/Idle
@onready var run_sprite = $animations/sprites/Run
@onready var jump_sprite = $animations/sprites/Jump
@onready var dash_sprite = $animations/sprites/Dash
@onready var jump_particles = $"particles/jump-particles"
@onready var dash_particles = $"particles/dash-particles"
@onready var death_particles = $"particles/death-particles"

var jumps_remaining = max_jumps
var was_in_air = false
var is_dashing = false
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var dash_direction = 0
var spawn_position = Vector2.ZERO
var is_dead = false
var is_spawning = true

func _ready():
	# Store spawn position for respawning
	spawn_position = global_position
	
	# Hide all sprites initially
	if idle_sprite and run_sprite and jump_sprite and dash_sprite:
		idle_sprite.visible = false
		run_sprite.visible = false
		jump_sprite.visible = false
		dash_sprite.visible = false
	
	# Wait for spawn delay, then spawn in
	await get_tree().create_timer(spawn_delay).timeout
	
	# Play spawn particles
	if death_particles:
		death_particles.restart()
	
	is_spawning = false
	
	# Show idle sprite
	if idle_sprite:
		idle_sprite.visible = true

func _physics_process(delta: float):
	# Don't process movement if dead or spawning
	if is_dead or is_spawning:
		return
		
	# Handle dash timer
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
	
	# Handle dash cooldown
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	
	# Apply gravity (not during dash)
	if not is_on_floor() and not is_dashing:
		velocity.y += gravity * delta
	else:
		# Reset jumps when on the ground
		jumps_remaining = max_jumps
		
	# Dash
	if Input.is_action_just_pressed("movement_dash") and not is_dashing and dash_cooldown_timer <= 0:
		var direction = Input.get_axis("movement_left", "movement_right")
		# Use last facing direction if no input
		if direction == 0:
			direction = 1 if animations_node.scale.x > 0 else -1
		dash_direction = direction
		is_dashing = true
		dash_timer = dash_duration
		dash_cooldown_timer = dash_cooldown
		
		# Trigger dash particles and flip based on direction
		if dash_particles:
			# Flip particles based on dash direction
			dash_particles.scale.x = -1 if dash_direction < 0 else 1
			dash_particles.restart()
		
		if animation_player:
			animation_player.stop()
			animation_player.play("Dash")
		
	# Jump
	if Input.is_action_just_pressed("movement_jump") and jumps_remaining > 0:
		velocity.y = jump_velocity
		jumps_remaining -= 1
		
		# Restart jump animation on double jump
		if jumps_remaining < max_jumps - 1 and animation_player:
			animation_player.stop()
			animation_player.play("Jump")
		
		# Trigger jump particles on SECOND jump (double jump)
		if jumps_remaining == max_jumps - 2 and jump_particles:
			# Flip particles based on facing direction
			jump_particles.scale.x = animations_node.scale.x
			jump_particles.restart()
		
		# Spawn particles on double jump
		if jumps_remaining < max_jumps - 1 and double_jump_particle_scene:
			var particles = double_jump_particle_scene.instantiate()
			get_parent().add_child(particles)
			particles.global_position = global_position
	
	# Get input direction
	var direction = Input.get_axis("movement_left", "movement_right")
	
	# Check if sprinting
	var current_speed = run_speed if Input.is_action_pressed("movement_run") else walk_speed
	
	# Set horizontal velocity
	if is_dashing:
		# Override velocity during dash
		velocity.x = dash_direction * dash_speed
		velocity.y = 0  # Keep horizontal during dash
	elif direction != 0:
		velocity.x = direction * current_speed
		# Flip sprite based on direction
		if animations_node:
			animations_node.scale.x = -1 if direction < 0 else 1
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
	
	# Handle animations
	if animation_player:
		# Check if we just landed
		var just_landed = was_in_air and is_on_floor()
		was_in_air = not is_on_floor()
		
		if is_dashing:
			# Show dash animation
			if idle_sprite and run_sprite and jump_sprite and dash_sprite:
				idle_sprite.visible = false
				run_sprite.visible = false
				jump_sprite.visible = false
				dash_sprite.visible = true
			if animation_player.current_animation != "Dash":
				animation_player.stop()
				animation_player.play("Dash")
		elif is_on_floor() and not just_landed:
			if direction == 0:
				# Switch to idle
				if idle_sprite and run_sprite and jump_sprite and dash_sprite:
					idle_sprite.visible = true
					run_sprite.visible = false
					jump_sprite.visible = false
					dash_sprite.visible = false
				if animation_player.current_animation != "Idle":
					if animation_player.current_animation != "Run" or not animation_player.is_playing():
						animation_player.stop()
						animation_player.play("Idle")
			else:
				# Switch to run
				if idle_sprite and run_sprite and jump_sprite and dash_sprite:
					idle_sprite.visible = false
					run_sprite.visible = true
					jump_sprite.visible = false
					dash_sprite.visible = false
				if animation_player.current_animation != "Run":
					animation_player.stop()
					animation_player.play("Run")
		else:
			# In air - show jump animation
			if idle_sprite and run_sprite and jump_sprite and dash_sprite:
				idle_sprite.visible = false
				run_sprite.visible = false
				jump_sprite.visible = true
				dash_sprite.visible = false
			if animation_player.current_animation != "Jump":
				animation_player.stop()
				animation_player.play("Jump")
	
	move_and_slide()

func _on_death_zone_entered(body):
	if is_dead:
		return
		
	is_dead = true
	
	# Trigger death particles
	if death_particles:
		death_particles.restart()
	
	# Hide all sprites
	if idle_sprite and run_sprite and jump_sprite and dash_sprite:
		idle_sprite.visible = false
		run_sprite.visible = false
		jump_sprite.visible = false
		dash_sprite.visible = false
	
	# Stop all movement
	velocity = Vector2.ZERO
	
	# Wait for respawn delay, then respawn
	await get_tree().create_timer(respawn_delay).timeout
	respawn()

func respawn():
	# Reset to spawn position
	global_position = spawn_position
	velocity = Vector2.ZERO
	is_dashing = false
	dash_timer = 0.0
	dash_cooldown_timer = 0.0
	is_dead = false
	
	# Play spawn particles
	if death_particles:
		death_particles.restart()
	
	# Show idle sprite
	if idle_sprite:
		idle_sprite.visible = true
