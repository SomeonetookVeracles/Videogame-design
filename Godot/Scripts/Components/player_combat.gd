class_name PlayerCombat
extends Node

## Handles player combat mechanics including attacks and hitbox management.

signal attack_started
signal attack_ended
signal hit_enemy(enemy: Node, damage: float)
signal parried_projectile(projectile: Node)

@export_group("Attack")
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 0.25
@export var attack_knockback: float = 350.0
@export var attack_knockback_vertical: float = -200.0
@export var attack_duration: float = 0.2

var attack_hitbox: Area2D
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
	if attack_hitbox:
		attack_hitbox.monitoring = false
		attack_hitbox.area_entered.connect(_on_hitbox_area_entered)
		attack_hitbox.body_entered.connect(_on_hitbox_body_entered)


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
	
	attack_started.emit()


func _end_attack() -> void:
	_is_attacking = false
	
	if attack_hitbox:
		attack_hitbox.monitoring = false
	
	attack_ended.emit()


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
	# Handle parrying projectiles
	if area.name == "ParryHitbox":
		var projectile := area.get_parent()
		if projectile and projectile.has_method("_parry"):
			projectile._parry(parent)
			parried_projectile.emit(projectile)


func is_attacking() -> bool:
	return _is_attacking


func force_end_attack() -> void:
	if _is_attacking:
		_end_attack()
