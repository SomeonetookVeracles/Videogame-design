class_name PlayerCombat
extends Node

## Handles player combat mechanics including attacks, parrying, and hitbox management.

signal attack_started
signal attack_ended
signal hit_enemy(enemy: Node, damage: float)
signal parry_started
signal parry_succeeded(projectile: Node)
signal parry_failed

@export_group("Attack")
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 0.25
@export var attack_knockback: float = 350.0
@export var attack_knockback_vertical: float = -200.0
@export var attack_duration: float = 0.2

@export_group("Parry")
@export var parry_window: float = 0.15
@export var parry_cooldown: float = 0.3
@export var parry_freeze_duration: float = 0.05
@export var parry_damage_multiplier: float = 1.5

var attack_hitbox: Area2D
var parry_hitbox: Area2D
var parent: CharacterBody2D

var _is_attacking: bool = false
var _is_parrying: bool = false
var _attack_cooldown_timer: float = 0.0
var _attack_timer: float = 0.0
var _parry_timer: float = 0.0
var _parry_cooldown_timer: float = 0.0

var _facing_direction: float = 1.0


func _ready() -> void:
	parent = get_parent() as CharacterBody2D
	_setup_hitbox()
	_setup_parry_hitbox()


func _process(delta: float) -> void:
	_attack_cooldown_timer = maxf(0.0, _attack_cooldown_timer - delta)
	_parry_cooldown_timer = maxf(0.0, _parry_cooldown_timer - delta)
	
	if _is_attacking:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_end_attack()
	
	if _is_parrying:
		_parry_timer -= delta
		if _parry_timer <= 0.0:
			_end_parry(false)


func _setup_hitbox() -> void:
	attack_hitbox = parent.get_node_or_null("combat/AttackHitbox")
	
	# Create hitbox if it doesn't exist
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
	
	# Configure collision - detect enemies (layer 2) and projectiles (layer 4)
	attack_hitbox.collision_layer = 0
	attack_hitbox.collision_mask = 6  # Layers 2 (enemies) and 3 (not used) - binary 110 = 6
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = false
	
	if not attack_hitbox.area_entered.is_connected(_on_hitbox_area_entered):
		attack_hitbox.area_entered.connect(_on_hitbox_area_entered)
	if not attack_hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		attack_hitbox.body_entered.connect(_on_hitbox_body_entered)


func _setup_parry_hitbox() -> void:
	parry_hitbox = parent.get_node_or_null("combat/ParryHitbox")
	
	# Create parry hitbox if it doesn't exist
	if not parry_hitbox:
		var combat_node: Node = parent.get_node_or_null("combat")
		if not combat_node:
			combat_node = Node2D.new()
			combat_node.name = "combat"
			parent.add_child(combat_node)
		
		parry_hitbox = Area2D.new()
		parry_hitbox.name = "ParryHitbox"
		combat_node.add_child(parry_hitbox)
		
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var shape := CircleShape2D.new()
		shape.radius = 30.0
		collision.shape = shape
		parry_hitbox.add_child(collision)
	
	parry_hitbox.monitoring = false
	parry_hitbox.monitorable = true
	
	if not parry_hitbox.area_entered.is_connected(_on_parry_area_entered):
		parry_hitbox.area_entered.connect(_on_parry_area_entered)


func process_combat(facing: float) -> void:
	_facing_direction = facing
	
	if Input.is_action_just_pressed("combat_attack"):
		try_attack()
	
	if Input.is_action_just_pressed("combat_parry"):
		try_parry()


func try_attack() -> bool:
	if _attack_cooldown_timer > 0.0 or _is_attacking or _is_parrying:
		return false
	
	_start_attack()
	return true


func try_parry() -> bool:
	if _parry_cooldown_timer > 0.0 or _is_parrying or _is_attacking:
		return false
	
	_start_parry()
	return true


func _start_attack() -> void:
	_is_attacking = true
	_attack_cooldown_timer = attack_cooldown
	_attack_timer = attack_duration
	
	if attack_hitbox:
		attack_hitbox.scale.x = _facing_direction
		attack_hitbox.monitoring = true
	
	attack_started.emit()


func _end_attack() -> void:
	_is_attacking = false
	
	if attack_hitbox:
		attack_hitbox.monitoring = false
	
	attack_ended.emit()


func _start_parry() -> void:
	_is_parrying = true
	_parry_timer = parry_window
	_parry_cooldown_timer = parry_cooldown
	
	if parry_hitbox:
		parry_hitbox.scale.x = _facing_direction
		parry_hitbox.monitoring = true
	
	parry_started.emit()


func _end_parry(succeeded: bool) -> void:
	_is_parrying = false
	
	if parry_hitbox:
		parry_hitbox.monitoring = false
	
	if not succeeded:
		parry_failed.emit()


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body == parent:
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


func _on_hitbox_area_entered(area: Area2D) -> void:
	# Check if this is a parryable projectile's hitbox
	var projectile := area.get_parent()
	if projectile and projectile.has_method("parry"):
		projectile.parry(parent, attack_damage * parry_damage_multiplier)
		parry_succeeded.emit(projectile)


func _on_parry_area_entered(area: Area2D) -> void:
	if not _is_parrying:
		return
	
	# Check if this is a parryable projectile
	var projectile := area.get_parent()
	if projectile and projectile.has_method("parry"):
		_successful_parry(projectile)


func _successful_parry(projectile: Node) -> void:
	# Apply parry effect
	projectile.parry(parent, attack_damage * parry_damage_multiplier)
	
	# Freeze frame effect
	if parry_freeze_duration > 0.0:
		Engine.time_scale = 0.1
		await parent.get_tree().create_timer(parry_freeze_duration, true, false, true).timeout
		Engine.time_scale = 1.0
	
	_end_parry(true)
	parry_succeeded.emit(projectile)


func is_attacking() -> bool:
	return _is_attacking


func is_parrying() -> bool:
	return _is_parrying


func force_end_attack() -> void:
	if _is_attacking:
		_end_attack()
