extends CharacterBody2D

## Main player controller orchestrating movement, combat, health, and visuals.
## Uses component-based architecture for clean separation of concerns.
##
## Required children:
## - HealthComponent (auto-created if missing)
## - PlayerMovement (auto-created if missing)  
## - PlayerCombat (auto-created if missing)
## - PlayerVisuals (auto-created if missing)
## - PlayerStateMachine (auto-created if missing)

# Preload component scripts for type resolution
const HealthComponentScript = preload("res://Scripts/Components/health_component.gd")
const PlayerMovementScript = preload("res://Scripts/Components/player_movement.gd")
const PlayerCombatScript = preload("res://Scripts/Components/player_combat.gd")
const PlayerVisualsScript = preload("res://Scripts/Components/player_visuals.gd")
const PlayerStateMachineScript = preload("res://Scripts/Components/player_state_machine.gd")

signal died
signal respawned
signal health_changed(current: int, maximum: int)

@export_group("Health")
@export var max_health_orbs: int = 5
@export var damage_per_orb: float = 1.0

@export_group("Death")
@export var respawn_delay: float = 1.0
@export var game_over_scene: String = "res://Scenes/MainMenu.tscn"
@export var death_transition_delay: float = 1.5

@export_group("Spawn")
@export var spawn_delay: float = 0.5

@export_group("Camera")
@export var camera_look_ahead: float = 120.0
@export var camera_smoothing: float = 12.0

@export_group("Effects")
@export var double_jump_particle_scene: PackedScene

@export_group("Abilities")
@export var dash_enabled: bool = true
@export var double_jump_enabled: bool = true
@export var health_visible: bool = true
@export var combat_enabled: bool = true

# Component references (using Node type for compatibility)
var health: Node
var movement: Node
var combat: Node
var visuals: Node
var state_machine: Node

# Node references
var camera: Camera2D
var damage_hurtbox: Area2D
var attack_hitbox: Area2D

# State
var spawn_position: Vector2 = Vector2.ZERO
var is_spawning: bool = true

const MIN_KNOCKBACK_SQ: float = 0.01


func _ready() -> void:
	spawn_position = global_position
	add_to_group("player")
	
	# Check level root for ability overrides
	_check_level_ability_settings()
	
	_setup_components()
	_setup_damage_detection()
	_setup_camera()
	_connect_signals()
	
	# Apply ability settings
	_apply_ability_settings()
	
	# Spawn delay
	await get_tree().create_timer(spawn_delay).timeout
	is_spawning = false
	visuals.show_sprite("idle")
	visuals.play_animation("Idle")


func _check_level_ability_settings() -> void:
	var level_root: Node = get_tree().current_scene
	if not level_root:
		return
	
	if "player_dash_enabled" in level_root:
		dash_enabled = level_root.player_dash_enabled
	if "player_double_jump_enabled" in level_root:
		double_jump_enabled = level_root.player_double_jump_enabled
	if "player_health_visible" in level_root:
		health_visible = level_root.player_health_visible
	if "player_combat_enabled" in level_root:
		combat_enabled = level_root.player_combat_enabled


func _apply_ability_settings() -> void:
	if movement:
		if not dash_enabled:
			movement.dash_cooldown = 999999.0
		if not double_jump_enabled:
			movement.max_jumps = 1
	
	if health and not health_visible:
		for orb in health._orb_instances:
			if is_instance_valid(orb):
				orb.visible = false


func _setup_components() -> void:
	# Health Component
	health = _get_or_create_component("HealthComponent", HealthComponentScript)
	health.max_orbs = max_health_orbs
	health.damage_per_orb = damage_per_orb
	health.current_orbs = max_health_orbs
	
	# State Machine
	state_machine = _get_or_create_component("PlayerStateMachine", PlayerStateMachineScript)
	
	# Movement Component
	movement = _get_or_create_component("PlayerMovement", PlayerMovementScript)
	
	# Combat Component
	combat = _get_or_create_component("PlayerCombat", PlayerCombatScript)
	attack_hitbox = get_node_or_null("combat/AttackHitbox") as Area2D
	
	# Visuals Component
	visuals = _get_or_create_component("PlayerVisuals", PlayerVisualsScript)


func _get_or_create_component(node_name: String, component_script: Script) -> Node:
	var component: Node = get_node_or_null(node_name)
	if component:
		return component
	
	component = component_script.new()
	component.name = node_name
	add_child(component)
	return component


func _setup_damage_detection() -> void:
	damage_hurtbox = get_node_or_null("DamageHurtbox")
	if not damage_hurtbox:
		damage_hurtbox = Area2D.new()
		damage_hurtbox.name = "DamageHurtbox"
		add_child(damage_hurtbox)
		
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		damage_hurtbox.add_child(collision)
		
		var player_collision := get_node_or_null("CollisionShape2D")
		if player_collision and player_collision.shape:
			collision.shape = player_collision.shape.duplicate()
			collision.position = player_collision.position
	
	damage_hurtbox.monitoring = true
	damage_hurtbox.monitorable = false
	damage_hurtbox.collision_layer = 0
	damage_hurtbox.collision_mask = 0xFFFFFFFF
	
	if not damage_hurtbox.area_entered.is_connected(_on_damage_area_entered):
		damage_hurtbox.area_entered.connect(_on_damage_area_entered)
	if not damage_hurtbox.body_entered.is_connected(_on_damage_body_entered):
		damage_hurtbox.body_entered.connect(_on_damage_body_entered)


func _setup_camera() -> void:
	camera = get_node_or_null("player-camera")
	if camera:
		camera.enabled = true
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = camera_smoothing


func _connect_signals() -> void:
	# Health signals
	health.health_depleted.connect(_on_health_depleted)
	health.damage_taken.connect(_on_damage_taken)
	health.health_changed.connect(_on_health_changed)
	
	# Movement signals
	movement.jumped.connect(_on_jumped)
	movement.landed.connect(_on_landed)
	movement.dash_started.connect(_on_dash_started)
	movement.dash_ended.connect(_on_dash_ended)
	
	# Combat signals
	combat.attack_started.connect(_on_attack_started)
	combat.attack_ended.connect(_on_attack_ended)
	
	# Visual signals
	visuals.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	if state_machine.current_state == PlayerStateMachineScript.State.DEAD or is_spawning:
		return
	
	_check_deadly_collision()
	
	var can_move: bool = state_machine.can_attack() # Using this as general "can act" check
	movement.process_movement(delta, can_move)
	
	if combat_enabled and state_machine.can_attack():
		combat.process_combat(movement.facing_direction)
	
	_update_state()
	_update_visuals()
	_update_camera(delta)
	
	move_and_slide()


func _check_deadly_collision() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider and collider.is_in_group("deadly"):
			_on_instant_death_terrain()
			return


func _on_instant_death_terrain() -> void:
	# Lose one orb and respawn
	health.current_orbs -= 1
	
	if health.current_orbs <= 0:
		# Actually dead - full death sequence
		return
	
	# Quick respawn without full death
	_quick_respawn()


func _quick_respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	movement.reset_jumps()
	
	# Brief invincibility
	health._start_invincibility()
	
	visuals.trigger_particles("death")


func _update_state() -> void:
	if combat.is_attacking():
		state_machine.current_state = PlayerStateMachineScript.State.ATTACK
	elif movement.is_dashing():
		state_machine.current_state = PlayerStateMachineScript.State.DASH
	elif not is_on_floor():
		if movement.is_falling():
			state_machine.current_state = PlayerStateMachineScript.State.FALL
		else:
			state_machine.current_state = PlayerStateMachineScript.State.JUMP
	elif movement.is_moving():
		state_machine.current_state = PlayerStateMachineScript.State.RUN
	else:
		state_machine.current_state = PlayerStateMachineScript.State.IDLE


func _update_visuals() -> void:
	visuals.update_facing(movement.facing_direction)
	
	if attack_hitbox:
		attack_hitbox.scale.x = movement.facing_direction
	
	var sprite_key: String
	var anim_name: String
	
	match state_machine.current_state:
		PlayerStateMachineScript.State.ATTACK:
			sprite_key = "attack"
			anim_name = "Attack"
		PlayerStateMachineScript.State.DASH:
			sprite_key = "dash"
			anim_name = "Dash"
		PlayerStateMachineScript.State.JUMP, PlayerStateMachineScript.State.FALL:
			sprite_key = "jump"
			anim_name = "Jump"
		PlayerStateMachineScript.State.RUN:
			sprite_key = "run"
			anim_name = "Run"
		_:
			sprite_key = "idle"
			anim_name = "Idle"
	
	visuals.set_sprite_visible(sprite_key)
	visuals.play_animation(anim_name)


func _update_camera(delta: float) -> void:
	if not camera:
		return
	
	var target_offset := Vector2(camera_look_ahead * movement.facing_direction, 0.0)
	camera.position = camera.position.lerp(target_offset, camera_smoothing * delta)


# --- Damage Handling ---

func _on_damage_area_entered(area: Area2D) -> void:
	if area.name == "ParryHitbox":
		return
	
	var damage_source := area.get_parent()
	if not damage_source:
		return
	
	var damage := _get_damage_from_source(damage_source, area)
	var knockback := _get_knockback_from_source(damage_source)
	
	if damage > 0.0:
		take_damage(damage, damage_source, knockback)


func _on_damage_body_entered(body: Node2D) -> void:
	if not body.is_in_group("enemies"):
		return
	
	var damage := _get_damage_from_source(body, null)
	var knockback := _get_knockback_from_source(body)
	
	if damage > 0.0:
		take_damage(damage, body, knockback)


func _get_damage_from_source(source: Node, area: Area2D) -> float:
	# Contact damage area
	if area and area.name == "ContactDamageArea":
		if source.has_method("get_contact_damage"):
			return source.get_contact_damage()
		elif "contact_damage" in source:
			return source.contact_damage
		return 10.0
	
	# General damage
	if source.has_method("get_damage"):
		return source.get_damage()
	elif "damage" in source:
		return source.damage
	
	return 15.0


func _get_knockback_from_source(source: Node) -> Vector2:
	var force := 0.0
	
	if source.has_method("get_knockback_force"):
		force = source.get_knockback_force()
	elif "knockback_force" in source:
		force = source.knockback_force
	else:
		return Vector2.ZERO
	
	var dir: Vector2 = (global_position - source.global_position).normalized()
	if dir.length_squared() < MIN_KNOCKBACK_SQ:
		dir = Vector2.LEFT if movement.facing_direction > 0 else Vector2.RIGHT
	
	return dir * force


func take_damage(amount: float, source: Node = null, knockback: Vector2 = Vector2.ZERO) -> void:
	if health.take_damage(amount, source, knockback):
		if knockback.length_squared() > MIN_KNOCKBACK_SQ:
			movement.apply_knockback(knockback)


func apply_knockback(force: Vector2) -> void:
	movement.apply_knockback(force)


# --- Signal Handlers ---

func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_damage_taken(_amount: float, _source: Node) -> void:
	visuals.trigger_particles("death")
	state_machine.current_state = PlayerStateMachineScript.State.HURT
	state_machine.lock_state(0.1)


func _on_health_depleted() -> void:
	_die()


func _on_jumped(is_double_jump: bool) -> void:
	if is_double_jump:
		visuals.trigger_particles("jump", movement.facing_direction)
		if double_jump_particle_scene:
			var particle: Node = double_jump_particle_scene.instantiate()
			get_parent().add_child(particle)
			particle.global_position = global_position


func _on_landed() -> void:
	pass


func _on_dash_started(direction: int) -> void:
	visuals.trigger_particles("dash", float(direction))
	visuals.start_dash_afterimages()


func _on_dash_ended() -> void:
	visuals.stop_dash_afterimages()


func _on_attack_started() -> void:
	visuals.play_animation("Attack", 2.5)


func _on_attack_ended() -> void:
	pass


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "Attack":
		combat.force_end_attack()


# --- Death and Respawn ---

func _die() -> void:
	if state_machine.current_state == PlayerStateMachineScript.State.DEAD:
		return
	
	state_machine.current_state = PlayerStateMachineScript.State.DEAD
	visuals.set_sprite_visible("")
	velocity = Vector2.ZERO
	
	died.emit()
	
	# Transition to game over / main menu
	await get_tree().create_timer(death_transition_delay).timeout
	_go_to_game_over()


func _go_to_game_over() -> void:
	if game_over_scene.is_empty():
		# No scene set, just respawn instead
		_respawn()
		return
	
	if ResourceLoader.exists(game_over_scene):
		get_tree().change_scene_to_file(game_over_scene)
	else:
		push_warning("Game over scene not found: " + game_over_scene + ". Respawning instead.")
		_respawn()


func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	
	state_machine.current_state = PlayerStateMachineScript.State.IDLE
	movement.reset_jumps()
	combat.force_end_attack()
	
	health.heal_full()
	
	visuals.trigger_particles("death")
	visuals.show_sprite("idle")
	visuals.play_animation("Idle")
	
	respawned.emit()


# --- Public API ---

func get_health_percentage() -> float:
	return health.get_health_percentage()


func get_current_orbs() -> int:
	return health.current_orbs


func get_max_orbs() -> int:
	return health.max_orbs


func heal(orbs: int = 1) -> void:
	health.heal(orbs)


func is_alive() -> bool:
	return health.is_alive()
