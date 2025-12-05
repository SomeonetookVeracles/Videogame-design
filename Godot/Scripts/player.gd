extends CharacterBody2D

# Movement parameters
@export_group("Movement")
@export var walk_speed := 300.0
@export var run_speed := 500.0
@export var jump_velocity := -400.0
@export var gravity := 980.0
@export var max_jumps := 2

@export_group("Dash")
@export var dash_speed := 800.0
@export var dash_duration := 0.2
@export var dash_cooldown := 1.0

@export_group("Spawn")
@export var respawn_delay := 2.0
@export var spawn_delay := 2.0
@export var double_jump_particle_scene: PackedScene

# Node references
@onready var animation_player := $"animations/debug-animations"
@onready var animations_node := $animations
@onready var sprites := {
	"idle": $animations/sprites/Idle,
	"run": $animations/sprites/Run,
	"jump": $animations/sprites/Jump,
	"dash": $animations/sprites/Dash
}
@onready var particles := {
	"jump": $"particles/jump-particles",
	"dash": $"particles/dash-particles",
	"death": $"particles/death-particles"
}

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

enum AnimState { IDLE, RUN, JUMP, DASH }

func _ready() -> void:
	spawn_position = global_position
	_hide_all_sprites()
	await get_tree().create_timer(spawn_delay).timeout
	_spawn_in()

func _physics_process(delta: float) -> void:
	if is_dead or is_spawning:
		return
	
	_update_timers(delta)
	_apply_gravity(delta)
	_handle_dash()
	_handle_jump()
	_handle_movement()
	_update_animation()
	move_and_slide()

func _update_timers(delta: float) -> void:
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
	
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

func _apply_gravity(delta: float) -> void:
	if not is_on_floor() and not is_dashing:
		velocity.y += gravity * delta
	elif is_on_floor():
		jumps_remaining = max_jumps

func _handle_dash() -> void:
	if not Input.is_action_just_pressed("movement_dash") or is_dashing or dash_cooldown_timer > 0:
		return
	
	var direction := Input.get_axis("movement_left", "movement_right")
	if direction == 0:
		direction = 1 if animations_node.scale.x > 0 else -1
	
	dash_direction = direction
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	
	_trigger_particles("dash", -1 if dash_direction < 0 else 1)
	_play_animation("Dash")

func _handle_jump() -> void:
	if not Input.is_action_just_pressed("movement_jump") or jumps_remaining <= 0:
		return
	
	velocity.y = jump_velocity
	jumps_remaining -= 1
	
	var is_double_jump := jumps_remaining < max_jumps - 1
	
	if is_double_jump:
		_play_animation("Jump")
		_trigger_particles("jump", animations_node.scale.x)
		_spawn_double_jump_particles()

func _handle_movement() -> void:
	var direction := Input.get_axis("movement_left", "movement_right")
	var current_speed := run_speed if Input.is_action_pressed("movement_run") else walk_speed
	
	if is_dashing:
		velocity.x = dash_direction * dash_speed
		velocity.y = 0
	elif direction != 0:
		velocity.x = direction * current_speed
		animations_node.scale.x = -1 if direction < 0 else 1
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

func _update_animation() -> void:
	var just_landed := was_in_air and is_on_floor()
	was_in_air = not is_on_floor()
	
	var state: AnimState
	if is_dashing:
		state = AnimState.DASH
	elif not is_on_floor() or just_landed:
		state = AnimState.JUMP
	elif Input.get_axis("movement_left", "movement_right") != 0:
		state = AnimState.RUN
	else:
		state = AnimState.IDLE
	
	_set_animation_state(state)

func _set_animation_state(state: AnimState) -> void:
	var anim_names: Array[String] = ["Idle", "Run", "Jump", "Dash"]
	var sprite_keys: Array[String] = ["idle", "run", "jump", "dash"]
	var active_key: String = sprite_keys[state] as String
	
	# Update sprite visibility
	for key in sprites:
		sprites[key].visible = (key == active_key)
	
	# Update animation
	var anim_name: String = anim_names[state] as String
	if animation_player.current_animation != anim_name:
		animation_player.stop()
		animation_player.play(anim_name)

func _hide_all_sprites() -> void:
	for sprite in sprites.values():
		sprite.visible = false

func _show_sprite(key: String) -> void:
	_hide_all_sprites()
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

func _spawn_in() -> void:
	_trigger_particles("death")
	is_spawning = false
	_show_sprite("idle")

func _play_animation(anim_name: String) -> void:
	if animation_player:
		animation_player.stop()
		animation_player.play(anim_name)

func _on_death_zone_entered(body) -> void:
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
	is_dead = false
	
	_trigger_particles("death")
	_show_sprite("idle")
