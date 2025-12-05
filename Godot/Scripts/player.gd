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

@export_group("Combat")
@export var attack_damage := 10.0
@export var attack_cooldown := 0.5
@export var attack_knockback := 300.0
@export var attack_animation_speed := 1.0
@export var attack_particle_delay := 0.1

# Node references
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
	_apply_gravity(delta)
	
	# Keep attack sprite visible during attack
	if is_attacking and sprites.has("attack") and sprites["attack"]:
		sprites["attack"].visible = true
		sprites["attack"].show()
	
	# Combat takes priority over other actions
	if not is_attacking:
		_handle_dash()
		_handle_jump()
		_handle_movement()
	else:
		# Slow down during attack
		velocity.x = move_toward(velocity.x, 0, walk_speed * delta * 2)
	
	_handle_attack()
	_update_animation()
	move_and_slide()

func _update_timers(delta: float) -> void:
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
	
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

func _apply_gravity(delta: float) -> void:
	if not is_on_floor() and not is_dashing:
		velocity.y += gravity * delta
	elif is_on_floor():
		jumps_remaining = max_jumps

func _handle_dash() -> void:
	if not Input.is_action_just_pressed("movement_dash") or is_dashing or dash_cooldown_timer > 0 or is_attacking:
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
	if not Input.is_action_just_pressed("movement_jump") or jumps_remaining <= 0 or is_attacking:
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

func _handle_attack() -> void:
	if not Input.is_action_just_pressed("combat_attack") or attack_cooldown_timer > 0 or is_attacking:
		return
	
	is_attacking = true
	attack_cooldown_timer = attack_cooldown
	
	# Force show attack sprite and hide others
	for key in sprites:
		if sprites[key]:
			sprites[key].visible = (key == "attack")
			# Force show if it's the attack sprite
			if key == "attack":
				sprites[key].show()
	
	# Play attack animation with speed
	if animation_player:
		animation_player.stop()
		animation_player.play("Attack", -1, attack_animation_speed)
	
	# Enable hitbox
	_enable_hitbox()
	
	# Schedule attack particles after delay
	_schedule_attack_particles()

func _on_attack_animation_finished(anim_name: String) -> void:
	if anim_name == "Attack":
		is_attacking = false
		_disable_hitbox()

func _update_animation() -> void:
	# Don't update animations while attacking
	if is_attacking:
		return
	
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
	var anim_names: Array[String] = ["Idle", "Run", "Jump", "Dash", "Attack"]
	var sprite_keys: Array[String] = ["idle", "run", "jump", "dash", "attack"]
	var active_key: String = sprite_keys[state] as String
	
	# Update sprite visibility
	for key in sprites:
		if sprites[key]:
			sprites[key].visible = (key == active_key)
	
	# Update animation
	var anim_name: String = anim_names[state] as String
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
	# Wait for the delay, then trigger particles
	await get_tree().create_timer(attack_particle_delay).timeout
	
	# Only trigger if still attacking
	if is_attacking and particles.has("attack") and particles["attack"]:
		var particle_node = particles["attack"]
		
		# Flip particles based on facing direction
		var facing_right: bool = animations_node.scale.x > 0
		
		# For GPUParticles2D
		if particle_node is GPUParticles2D:
			particle_node.process_material.direction.x = 1 if facing_right else -1
			particle_node.restart()
		# For CPUParticles2D
		elif particle_node is CPUParticles2D:
			particle_node.direction.x = 1 if facing_right else -1
			particle_node.restart()
		else:
			# Fallback: flip the entire node
			particle_node.scale.x = 1 if facing_right else -1
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
	
	# Apply damage if the body has a damage method
	if body.has_method("take_damage"):
		body.take_damage(attack_damage)
	
	# Apply knockback
	if body is CharacterBody2D:
		var knockback_dir: float = sign(body.global_position.x - global_position.x)
		if knockback_dir == 0:
			knockback_dir = 1 if animations_node.scale.x > 0 else -1
		
		if body.has_method("apply_knockback"):
			body.apply_knockback(Vector2(knockback_dir * attack_knockback, -200))

func take_damage(amount: float) -> void:
	# Trigger death if damaged
	_on_death_zone_entered(self)

func apply_knockback(force: Vector2) -> void:
	if not is_dashing:
		velocity = force

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
