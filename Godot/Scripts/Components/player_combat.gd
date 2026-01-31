class_name PlayerCombat
extends Node

## Handles player combat mechanics.
## Parrying happens automatically during a short window at the start of an attack.

signal attack_started
signal attack_ended
signal hit_enemy(enemy: Node, damage: float)
signal parry_succeeded(projectile: Node)

@export_group("Attack")
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 0.25
@export var attack_knockback: float = 350.0
@export var attack_knockback_vertical: float = -200.0
@export var attack_duration: float = 0.35

@export_group("Parry")
@export var parry_freeze_duration: float = 0.05
@export var parry_damage_multiplier: float = 1.5

var attack_hitbox: Area2D
var parry_hitbox: Area2D
var parent: CharacterBody2D

var _is_attacking: bool = false
var _attack_cooldown_timer: float = 0.0
var _attack_timer: float = 0.0

var _facing_direction: float = 1.0


func _ready() -> void:
	parent = get_parent() as CharacterBody2D
	_setup_hitbox()


func _process(delta: float) -> void:
	_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)
	
	if _is_attacking:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_end_attack()


func _setup_hitbox() -> void:
	attack_hitbox = parent.get_node_or_null("combat/AttackHitbox")
	
	if not attack_hitbox:
		var combat_node: Node = parent.get_node_or_null("combat")
		if not combat_node:
			combat_node = Node2D.new()
			combat_node.name = "combat"
			parent.add_child(combat_node)
		
		attack_hitbox = Area2D.new()
		attack_hitbox.name = "AttackHitbox"
		combat_node.add_child(attack_hitbox)
		
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var shape := RectangleShape2D.new()
		shape.size = Vector2(40, 30)
		collision.shape = shape
		collision.position = Vector2(20, 0)
		attack_hitbox.add_child(collision)
	
	attack_hitbox.collision_layer = 8
	attack_hitbox.collision_mask = 6
	attack_hitbox.monitoring = true
	attack_hitbox.monitorable = true
	
	if not attack_hitbox.area_entered.is_connected(_on_hitbox_area_entered):
		attack_hitbox.area_entered.connect(_on_hitbox_area_entered)
	if not attack_hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		attack_hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	_setup_parry_hitbox()


func _setup_parry_hitbox() -> void:
	parry_hitbox = parent.get_node_or_null("combat/ParryHitbox")
	
	if not parry_hitbox:
		push_warning("PlayerCombat: No ParryHitbox found at combat/ParryHitbox - create one to enable parrying")
		return
	
	parry_hitbox.collision_layer = 16  # Layer 5 for parry hitbox
	parry_hitbox.collision_mask = 4    # Detect projectiles (layer 3)
	parry_hitbox.monitoring = false    # Disabled until attack
	parry_hitbox.monitorable = true
	
	if not parry_hitbox.area_entered.is_connected(_on_parry_hitbox_area_entered):
		parry_hitbox.area_entered.connect(_on_parry_hitbox_area_entered)


func process_combat(facing: float) -> void:
	_facing_direction = facing
	
	if Input.is_action_just_pressed("combat_attack"):
		try_attack()


func try_attack() -> bool:
	if _attack_cooldown_timer > 0.0 or _is_attacking:
		return false
	
	_start_attack()
	return true


func _start_attack() -> void:
	_is_attacking = true
	_attack_cooldown_timer = attack_cooldown
	_attack_timer = attack_duration
	
	if attack_hitbox:
		attack_hitbox.scale.x = _facing_direction
		attack_hitbox.monitoring = true
	
	if parry_hitbox:
		parry_hitbox.scale.x = _facing_direction
		parry_hitbox.monitoring = true
	
	attack_started.emit()


func _end_attack() -> void:
	_is_attacking = false
	
	if attack_hitbox:
		attack_hitbox.monitoring = false
	
	if parry_hitbox:
		parry_hitbox.monitoring = false
	
	attack_ended.emit()


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body == parent or not _is_attacking:
		return
	
	var dir: float = sign(body.global_position.x - parent.global_position.x)
	if dir == 0.0:
		dir = _facing_direction
	
	var knockback := Vector2(dir * attack_knockback, attack_knockback_vertical)
	
	if body.has_method("take_damage"):
		body.take_damage(attack_damage, parent, knockback)
		hit_enemy.emit(body, attack_damage)
	elif body.has_method("apply_knockback"):
		body.apply_knockback(knockback)


func _on_hitbox_area_entered(_area: Area2D) -> void:
	# Attack hitbox only damages enemies, doesn't parry
	pass


func _on_parry_hitbox_area_entered(area: Area2D) -> void:
	if not _is_attacking:
		return
	
	# Find projectile - could be the area itself or its parent
	var projectile: Node = null
	if area.has_method("parry"):
		projectile = area
	elif area.get_parent() and area.get_parent().has_method("parry"):
		projectile = area.get_parent()
	if not projectile:
		return	
	# Try to parry - projectile decides if timing is right
	var was_parried: bool = projectile.parry(parent, attack_damage * parry_damage_multiplier)
	if was_parried:
		_successful_parry(projectile)
func _successful_parry(projectile: Node) -> void:
	# Freeze frame effect
	if parry_freeze_duration > 0.0:
		Engine.time_scale = 0.05
		await parent.get_tree().create_timer(parry_freeze_duration, true, false, true).timeout
		Engine.time_scale = 1.0
	await get_tree().create_timer(.5).timeout  # This makes it more clean by letting the animation finish
	parry_succeeded.emit(projectile)
func is_attacking() -> bool:
	return _is_attacking
func is_parrying() -> bool:
	return false  # Parry is now instant, not a state
func force_end_attack() -> void:
	if _is_attacking:
		_end_attack()
