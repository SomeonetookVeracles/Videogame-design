extends CharacterBody2D

# Movement parameters
@export_group("Movement")
@export var walk_speed := 280.0
@export var jump_velocity := -420.0
@export var gravity := 1300.0
@export var max_jumps := 2
@export var acceleration := 6000.0
@export var friction := 4500.0
@export var air_acceleration := 4000.0
@export var coyote_time := 0.15
@export var jump_buffer_time := 0.15
@export var jump_release_multiplier := 3.0

@export_group("Dash")
@export var dash_speed := 900.0
@export var dash_duration := 0.15
@export var dash_cooldown := 0.4

@export_group("Combat")
@export var attack_damage := 10.0
@export var attack_cooldown := 0.25
@export var attack_knockback := 350.0

@export_group("Spawn")
@export var respawn_delay := 1.0
@export var spawn_delay := 0.5
@export var double_jump_particle_scene: PackedScene

@export_group("Camera")
@export var camera_look_ahead := 120.0
@export var camera_smoothing := 12.0

# Node references
@onready var animation_player: AnimationPlayer = $"animations/debug-animations"
@onready var animations_node: Node2D = $animations
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
}
@onready var attack_hitbox: Area2D = $combat/AttackHitbox
@onready var camera: Camera2D = $"player-camera"

# State flags
var is_dashing := false
var is_attacking := false
var is_dead := false
var is_spawning := true
var is_jump_held := false

# Jump state
var jumps_remaining := max_jumps
var was_in_air := false

# Timers
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var attack_cooldown_timer := 0.0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0

# Cached values
var dash_direction := 0
var spawn_position := Vector2.ZERO
var last_on_floor := false

enum AnimState { IDLE, RUN, JUMP, DASH, ATTACK }

func _ready() -> void:
	spawn_position = global_position
	_hide_all_sprites()
	attack_hitbox.monitoring = false
	animation_player.animation_finished.connect(_on_attack_animation_finished)
	_setup_camera()
	await get_tree().create_timer(spawn_delay).timeout
	is_spawning = false
	sprites["idle"].visible = true
	animation_player.play("Idle")

func _setup_camera() -> void:
	if camera:
		camera.enabled = true
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = camera_smoothing

func _physics_process(delta: float) -> void:
	if is_dead or is_spawning:
		return
	
	_update_timers(delta)
	_update_coyote_time(delta)
	_apply_gravity(delta)
	_check_deadly_collision()
	
	_handle_dash()
	_handle_jump()
	_handle_movement(delta)
	_handle_attack()
	_update_animation()
	_update_camera(delta)
	move_and_slide()

func _update_camera(delta: float) -> void:
	if not camera:
		return
	
	var facing_direction: float = sign(animations_node.scale.x)
	var target_offset := Vector2(camera_look_ahead * facing_direction, 0.0)
	camera.position = camera.position.lerp(target_offset, camera_smoothing * delta)

func _update_timers(delta: float) -> void:
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
	
	dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	attack_cooldown_timer = maxf(0.0, attack_cooldown_timer - delta)
	jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)

func _check_deadly_collision() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_collider().is_in_group("deadly"):
			_die()
			return

func _update_coyote_time(delta: float) -> void:
	var on_floor := is_on_floor()
	
	if on_floor:
		coyote_timer = coyote_time
		if not last_on_floor:
			jumps_remaining = max_jumps
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
	
	last_on_floor = on_floor

func _apply_gravity(delta: float) -> void:
	if is_on_floor() or is_dashing:
		return
	
	is_jump_held = Input.is_action_pressed("movement_jump")
	
	if velocity.y < 0 and not is_jump_held:
		velocity.y += gravity * jump_release_multiplier * delta
	else:
		var multiplier := 1.6 if velocity.y > 0 else 1.0
		velocity.y += gravity * multiplier * delta
	
	velocity.y = minf(velocity.y, gravity * 2.0)

func _handle_dash() -> void:
	if Input.is_action_just_pressed("movement_dash"):
		if dash_cooldown_timer <= 0 and not is_dashing and not is_attacking:
			var direction := Input.get_axis("movement_left", "movement_right")
			if direction == 0:
				direction = 1.0 if animations_node.scale.x > 0 else -1.0
			
			dash_direction = int(direction)
			is_dashing = true
			dash_timer = dash_duration
			dash_cooldown_timer = dash_cooldown
			
			_trigger_particles("dash", float(dash_direction))
			animation_player.play("Dash")

func _handle_jump() -> void:
	if Input.is_action_just_pressed("movement_jump"):
		jump_buffer_timer = jump_buffer_time
	
	if is_attacking or jump_buffer_timer <= 0:
		return
	
	var can_jump := (coyote_timer > 0 and jumps_remaining == max_jumps) or jumps_remaining > 0
	
	if can_jump:
		velocity.y = jump_velocity
		jumps_remaining -= 1
		jump_buffer_timer = 0
		coyote_timer = 0
		is_jump_held = true
		
		if jumps_remaining < max_jumps - 1:
			animation_player.play("Jump")
			_trigger_particles("jump", animations_node.scale.x)
			if double_jump_particle_scene:
				var particle: Node = double_jump_particle_scene.instantiate()
				get_parent().add_child(particle)
				particle.global_position = global_position

func _handle_movement(delta: float) -> void:
	if is_dashing:
		velocity.x = dash_direction * dash_speed
		velocity.y = 0
		return
	
	var direction := Input.get_axis("movement_left", "movement_right")
	
	if direction != 0:
		var accel: float = acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, direction * walk_speed, accel * delta)
		
		# Snappier turn on ground
		if is_on_floor() and sign(direction) != sign(velocity.x) and absf(velocity.x) > 5.0:
			velocity.x = move_toward(velocity.x, direction * walk_speed, acceleration * 2.0 * delta)
		
		# Update facing direction
		var new_scale: float = sign(direction)
		if animations_node.scale.x != new_scale:
			animations_node.scale.x = new_scale
			attack_hitbox.scale.x = new_scale
	else:
		var decel: float = friction if is_on_floor() else air_acceleration * 0.75
		velocity.x = move_toward(velocity.x, 0, decel * delta)

func _handle_attack() -> void:
	if not Input.is_action_just_pressed("combat_attack") or attack_cooldown_timer > 0 or is_attacking:
		return
	
	is_attacking = true
	attack_cooldown_timer = attack_cooldown
	
	animation_player.play("Attack", -1, 2.5)
	attack_hitbox.monitoring = true
	
	await get_tree().create_timer(0.03).timeout
	if is_attacking and particles.has("attack"):
		particles["attack"].direction.x = 1.0 if animations_node.scale.x > 0 else -1.0
		particles["attack"].restart()

func _on_attack_animation_finished(anim_name: String) -> void:
	if anim_name == "Attack":
		is_attacking = false
		attack_hitbox.monitoring = false

func _update_animation() -> void:
	if is_dead:
		return
	
	var just_landed := was_in_air and is_on_floor()
	was_in_air = not is_on_floor()
	
	# Attack animation takes priority
	if is_attacking:
		sprites["attack"].visible = true
		for key in sprites:
			if key != "attack":
				sprites[key].visible = false
		return
	
	var state: AnimState
	if is_dashing:
		state = AnimState.DASH
	elif not is_on_floor() or just_landed:
		state = AnimState.JUMP
	elif absf(velocity.x) > 5.0:
		state = AnimState.RUN
	else:
		state = AnimState.IDLE
	
	var keys: Array[String] = ["idle", "run", "jump", "dash", "attack"]
	var active := keys[state]
	
	for key in sprites:
		sprites[key].visible = (key == active)
	
	var anims: Array[String] = ["Idle", "Run", "Jump", "Dash", "Attack"]
	var anim := anims[state]
	if animation_player.current_animation != anim:
		animation_player.play(anim)

func _hide_all_sprites() -> void:
	for sprite in sprites.values():
		sprite.visible = false

func _trigger_particles(key: String, flip_x: float = 1.0) -> void:
	if particles.has(key):
		particles[key].scale.x = flip_x
		particles[key].restart()

func _on_attack_hitbox_body_entered(body: Node2D) -> void:
	if body == self:
		return
	
	if body.has_method("take_damage"):
		body.take_damage(attack_damage)
	
	if body is CharacterBody2D and body.has_method("apply_knockback"):
		var dir: float = sign(body.global_position.x - global_position.x)
		if dir == 0:
			dir = 1.0 if animations_node.scale.x > 0 else -1.0
		body.apply_knockback(Vector2(dir * attack_knockback, -200.0))

func take_damage(_amount: float) -> void:
	_die()

func apply_knockback(force: Vector2) -> void:
	if not is_dashing:
		velocity = force

func _die() -> void:
	if is_dead:
		return
	
	is_dead = true
	_hide_all_sprites()
	velocity = Vector2.ZERO
	
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	is_dashing = false
	is_attacking = false
	is_dead = false
	jumps_remaining = max_jumps
	
	dash_timer = 0.0
	dash_cooldown_timer = 0.0
	attack_cooldown_timer = 0.0
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	is_jump_held = false
	
	_trigger_particles("death")
	sprites["idle"].visible = true
	animation_player.play("Idle")
