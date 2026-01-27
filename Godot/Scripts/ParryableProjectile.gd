class_name ParryableProjectile
extends Area2D

## A projectile that can be parried by the player.
## When parried, it reflects back toward the source with increased damage.
##
## Usage:
## 1. Instantiate this scene
## 2. Set direction and speed
## 3. Call launch() or set auto_launch = true

signal hit_target(target: Node)
signal parried(by: Node)
signal destroyed

@export_group("Movement")
@export var speed: float = 300.0
@export var direction: Vector2 = Vector2.RIGHT
@export var auto_launch: bool = true
@export var lifetime: float = 5.0
@export var projectile_gravity: float = 0.0

@export_group("Damage")
@export var damage: float = 1.0
@export var knockback_force: float = 200.0

@export_group("Parry")
@export var parryable: bool = true
@export var parry_speed_multiplier: float = 1.5
@export var max_parry_count: int = 3

@export_group("Visual")
@export var rotate_to_direction: bool = true
@export var parry_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var parry_flash_duration: float = 0.1

var _velocity: Vector2 = Vector2.ZERO
var _is_launched: bool = false
var _lifetime_timer: float = 0.0
var _parry_count: int = 0
var _source: Node = null
var _current_target_group: String = "player"

# Collision shape reference
var _collision: CollisionShape2D


func _ready() -> void:
	_setup_collision()
	
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	if auto_launch:
		launch()


func _setup_collision() -> void:
	_collision = get_node_or_null("CollisionShape2D")
	
	if not _collision:
		_collision = CollisionShape2D.new()
		_collision.name = "CollisionShape2D"
		var shape := CircleShape2D.new()
		shape.radius = 8.0
		_collision.shape = shape
		add_child(_collision)
	
	# Set up collision - projectile detects player and enemies
	monitoring = true
	monitorable = true


func _process(delta: float) -> void:
	if not _is_launched:
		return
	
	# Apply gravity
	if projectile_gravity != 0.0:
		_velocity.y += projectile_gravity * delta
	
	# Move projectile
	global_position += _velocity * delta
	
	# Rotate to face direction
	if rotate_to_direction and _velocity.length_squared() > 0.01:
		rotation = _velocity.angle()
	
	# Lifetime
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		_destroy()


func launch(from_source: Node = null) -> void:
	_source = from_source
	_velocity = direction.normalized() * speed
	_is_launched = true
	_lifetime_timer = 0.0
	
	if rotate_to_direction:
		rotation = _velocity.angle()


func set_direction_to_target(target_position: Vector2) -> void:
	direction = (target_position - global_position).normalized()


func parry(by_node: Node, reflected_damage: float = -1.0) -> void:
	if not parryable:
		return
	
	_parry_count += 1
	
	if _parry_count > max_parry_count:
		_destroy()
		return
	
	# Update damage if specified
	if reflected_damage > 0.0:
		damage = reflected_damage
	
	# Reverse direction toward source or original shooter
	var new_target: Vector2
	if _source and is_instance_valid(_source):
		new_target = _source.global_position
	else:
		new_target = global_position - _velocity.normalized() * 100.0
	
	direction = (new_target - global_position).normalized()
	_velocity = direction * speed * parry_speed_multiplier
	
	# Swap target group
	if _current_target_group == "player":
		_current_target_group = "enemies"
	else:
		_current_target_group = "player"
	
	# Update source to parrying node
	_source = by_node
	
	# Visual feedback
	_flash_parry()
	
	parried.emit(by_node)


func _flash_parry() -> void:
	var original_modulate := modulate
	modulate = parry_flash_color
	
	var tween := create_tween()
	tween.tween_property(self, "modulate", original_modulate, parry_flash_duration)


func _on_body_entered(body: Node2D) -> void:
	# Don't hit source
	if body == _source:
		return
	
	# Check if body is in target group
	if not body.is_in_group(_current_target_group):
		# Check for walls/terrain
		if body.is_in_group("terrain") or body.is_in_group("walls"):
			_destroy()
		return
	
	_deal_damage_to(body)
	_destroy()


func _on_area_entered(area: Area2D) -> void:
	var area_parent := area.get_parent()
	
	# Check for player's damage hurtbox
	if area.name == "DamageHurtbox" and area_parent:
		if area_parent.is_in_group(_current_target_group):
			_deal_damage_to(area_parent)
			_destroy()
			return
	
	# Check for attack hitbox (player slashing projectile)
	if area_parent and area_parent.is_in_group("player"):
		if area.name == "AttackHitbox":
			parry(area_parent, damage * 1.5)


func _deal_damage_to(target: Node) -> void:
	if target.has_method("take_damage"):
		var dir: float = sign(target.global_position.x - global_position.x)
		if dir == 0.0:
			dir = sign(_velocity.x)
		var knockback := Vector2(dir * knockback_force, -knockback_force * 0.5)
		target.take_damage(damage, self, knockback)
	
	hit_target.emit(target)


func _destroy() -> void:
	destroyed.emit()
	queue_free()


# --- Public API for AI ---

func get_damage() -> float:
	return damage


func get_knockback_force() -> float:
	return knockback_force


func is_parryable() -> bool:
	return parryable and _parry_count < max_parry_count
