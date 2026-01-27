class_name AlienEnemy
extends CharacterBody2D

## Basic alien enemy that wanders, aggros on player, and fires projectiles.
## Dies after taking a configurable amount of hits.

signal died
signal fired_projectile(projectile: Node)
signal damaged_player(player: Node)

@export_group("Health")
@export var max_hits: int = 3
@export var invincibility_duration: float = 0.2

@export_group("Movement")
@export var wander_speed: float = 40.0
@export var chase_speed: float = 80.0
@export var aggro_speed: float = 120.0
@export var alien_gravity: float = 900.0
@export var wander_area: Vector2 = Vector2(80, 0)
@export var wander_pause_min: float = 2.0
@export var wander_pause_max: float = 4.0

@export_group("Aggro")
@export var aggro_range: float = 120.0
@export var deaggro_range: float = 200.0
@export var lose_aggro_time: float = 3.0
@export var preferred_distance: float = 100.0
@export var distance_tolerance: float = 20.0

@export_group("Combat")
@export var contact_damage: float = 1.0
@export var knockback_force: float = 250.0
@export var projectile_scene: PackedScene
@export var fire_rate: float = 0.5
@export var projectile_speed: float = 150.0
@export var aim_at_player: bool = true
@export var min_fire_distance: float = 40.0

@export_group("Visual")
@export var flash_on_hit: bool = true
@export var flash_color: Color = Color(1, 1, 1, 1)

enum State { IDLE, WANDER, AGGRO, ATTACK, HURT, DEAD }

var current_state: State = State.IDLE
var current_hits: int = 0
var facing_direction: float = 1.0

var _spawn_position: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _fire_timer: float = 0.0
var _invincible: bool = false
var _invincibility_timer: float = 0.0
var _aggro_timer: float = 0.0
var _player: Node2D = null
var _contact_cooldown: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null
@onready var animation_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var contact_area: Area2D = $ContactDamageArea if has_node("ContactDamageArea") else null
@onready var projectile_spawn: Marker2D = $ProjectileSpawn if has_node("ProjectileSpawn") else null


func _ready() -> void:
	add_to_group("enemies")
	_spawn_position = global_position
	current_hits = 0
	_pick_wander_target()
	
	_setup_contact_damage()


func _setup_contact_damage() -> void:
	if not contact_area:
		contact_area = Area2D.new()
		contact_area.name = "ContactDamageArea"
		add_child(contact_area)
		
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		contact_area.add_child(collision)
		
		var main_collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
		if main_collision and main_collision.shape:
			collision.shape = main_collision.shape.duplicate()
		else:
			var shape := CircleShape2D.new()
			shape.radius = 16.0
			collision.shape = shape
	
	contact_area.collision_layer = 4
	contact_area.collision_mask = 1
	contact_area.monitoring = true
	contact_area.monitorable = true
	
	if not contact_area.body_entered.is_connected(_on_contact_body_entered):
		contact_area.body_entered.connect(_on_contact_body_entered)


func _on_contact_body_entered(body: Node2D) -> void:
	if _contact_cooldown > 0.0:
		return
	
	if body.is_in_group("player"):
		_deal_contact_damage(body)


func _deal_contact_damage(player: Node2D) -> void:
	if _contact_cooldown > 0.0:
		return
	
	_contact_cooldown = 0.5
	
	var dir: float = sign(player.global_position.x - global_position.x)
	if dir == 0.0:
		dir = facing_direction
	
	var knockback := Vector2(dir * knockback_force, -knockback_force * 0.5)
	
	if player.has_method("take_damage"):
		player.take_damage(contact_damage, self, knockback)
		damaged_player.emit(player)


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
	
	_update_timers(delta)
	_find_player()
	_update_state()
	_process_state(delta)
	_apply_gravity(delta)
	_update_facing()
	_check_contact_damage()
	
	move_and_slide()


func _update_timers(delta: float) -> void:
	if _invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			_invincible = false
			if sprite:
				sprite.modulate = Color.WHITE
	
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_wander_timer = maxf(0.0, _wander_timer - delta)
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)


func _find_player() -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")


func _check_contact_damage() -> void:
	if not _player or _contact_cooldown > 0.0:
		return
	
	var distance := global_position.distance_to(_player.global_position)
	if distance < 25.0:
		_deal_contact_damage(_player)


func _update_state() -> void:
	if current_state == State.HURT or current_state == State.DEAD:
		return
	
	if not _player:
		if current_state == State.AGGRO or current_state == State.ATTACK:
			current_state = State.IDLE
			_pick_wander_target()
		return
	
	var distance_to_player := global_position.distance_to(_player.global_position)
	
	if current_state == State.WANDER or current_state == State.IDLE:
		if distance_to_player <= aggro_range:
			current_state = State.AGGRO
			_aggro_timer = lose_aggro_time
	elif current_state == State.AGGRO or current_state == State.ATTACK:
		if distance_to_player > deaggro_range:
			_aggro_timer -= get_physics_process_delta_time()
			if _aggro_timer <= 0.0:
				current_state = State.IDLE
				_pick_wander_target()
		else:
			_aggro_timer = lose_aggro_time


func _process_state(delta: float) -> void:
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander()
		State.AGGRO:
			_process_aggro()
		State.ATTACK:
			_process_attack(delta)
		State.HURT:
			_process_hurt(delta)


func _process_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, wander_speed * 2.0 * delta)
	
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		current_state = State.WANDER
		_pick_wander_target()


func _process_wander() -> void:
	var dir: float = sign(_wander_target.x - global_position.x)
	velocity.x = dir * wander_speed
	
	if absf(global_position.x - _wander_target.x) < 5.0 or is_on_wall():
		current_state = State.IDLE
		_wander_timer = randf_range(wander_pause_min, wander_pause_max)


func _process_aggro() -> void:
	if not _player:
		current_state = State.IDLE
		return
	
	var distance_to_player := global_position.distance_to(_player.global_position)
	var dir_to_player: float = sign(_player.global_position.x - global_position.x)
	
	# Keep preferred distance
	if distance_to_player < preferred_distance - distance_tolerance:
		velocity.x = -dir_to_player * aggro_speed
	elif distance_to_player > preferred_distance + distance_tolerance:
		velocity.x = dir_to_player * chase_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, aggro_speed * 2.0 * get_physics_process_delta_time())
	
	facing_direction = dir_to_player
	
	if _fire_timer <= 0.0 and projectile_scene and distance_to_player >= min_fire_distance:
		_fire_projectile()


func _process_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, aggro_speed * 3.0 * delta)


func _process_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += alien_gravity * delta
	else:
		velocity.y = 0.0


func _update_facing() -> void:
	if sprite:
		sprite.flip_h = facing_direction < 0
	if projectile_spawn:
		projectile_spawn.position.x = absf(projectile_spawn.position.x) * facing_direction


func _pick_wander_target() -> void:
	var offset := randf_range(-wander_area.x, wander_area.x)
	_wander_target = _spawn_position + Vector2(offset, 0)
	_wander_timer = randf_range(wander_pause_min, wander_pause_max)


func _fire_projectile() -> void:
	if not projectile_scene:
		return
	
	_fire_timer = 1.0 / fire_rate
	
	var projectile: Node2D = projectile_scene.instantiate()
	get_parent().add_child(projectile)
	
	if projectile_spawn:
		projectile.global_position = projectile_spawn.global_position
	else:
		projectile.global_position = global_position + Vector2(facing_direction * 12, -8)
	
	if aim_at_player and _player:
		if projectile.has_method("set_direction_to_target"):
			projectile.set_direction_to_target(_player.global_position)
	else:
		if "direction" in projectile:
			projectile.direction = Vector2(facing_direction, 0)
	
	if "speed" in projectile:
		projectile.speed = projectile_speed
	
	if projectile.has_method("launch"):
		projectile.launch(self)
	
	if "_current_target_group" in projectile:
		projectile._current_target_group = "player"
	
	fired_projectile.emit(projectile)
	
	current_state = State.ATTACK
	await get_tree().create_timer(0.5).timeout
	if current_state == State.ATTACK:
		current_state = State.AGGRO


func take_damage(_amount: float, _source: Node = null, knockback: Vector2 = Vector2.ZERO) -> void:
	if _invincible or current_state == State.DEAD:
		return
	
	current_hits += 1
	
	if knockback.length_squared() > 0.01:
		velocity = knockback
	
	if flash_on_hit and sprite:
		sprite.modulate = flash_color
	
	_invincible = true
	_invincibility_timer = invincibility_duration
	current_state = State.HURT
	
	if current_hits >= max_hits:
		_die()
	else:
		await get_tree().create_timer(0.15).timeout
		if current_state == State.HURT:
			current_state = State.AGGRO if _player else State.IDLE


func _die() -> void:
	current_state = State.DEAD
	velocity = Vector2.ZERO
	
	died.emit()
	
	if sprite:
		var tween := create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
		tween.finished.connect(queue_free)
	else:
		queue_free()


func get_contact_damage() -> float:
	return contact_damage


func get_knockback_force() -> float:
	return knockback_force


func is_alive() -> bool:
	return current_state != State.DEAD
