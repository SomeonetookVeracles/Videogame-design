class_name ParryableProjectile
extends Area2D

## A projectile that can be parried by the player.
## SIMPLE: Parryable when within distance. Turns GREEN when you can parry it.

signal hit_target(target: Node)
signal parried(by: Node)
signal destroyed

@export_group("Movement")
@export var speed: float = 180.0
@export var direction: Vector2 = Vector2.RIGHT
@export var auto_launch: bool = true
@export var lifetime: float = 10.0

@export_group("Damage")
@export var damage: float = 1.0
@export var knockback_force: float = 200.0

@export_group("Parry")
@export var parryable: bool = true
@export var parry_speed_multiplier: float = 1.5
@export var max_parry_count: int = 3
## Distance from player when parry window OPENS (turns green)
@export var parry_distance: float = 120.0

@export_group("Visuals")
## Color when parryable - BRIGHT GREEN
@export var parryable_color: Color = Color(0.2, 1.0, 0.2, 1.0)
## Scale multiplier when parryable
@export var parryable_scale: float = 2.0

var _velocity: Vector2 = Vector2.ZERO
var _is_launched: bool = false
var _lifetime_timer: float = 0.0
var _parry_count: int = 0
var _source: Node = null
var _current_target_group: String = "player"
var _player_ref: Node2D = null

var _original_modulate: Color
var _original_scale: Vector2
var _is_in_parry_range: bool = false


func _ready() -> void:
	_setup_collision()
	_original_modulate = modulate
	_original_scale = scale
	
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	if auto_launch:
		launch()


func _setup_collision() -> void:
	var col = get_node_or_null("CollisionShape2D")
	if not col:
		col = CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var shape := CircleShape2D.new()
		shape.radius = 8.0
		col.shape = shape
		add_child(col)
	
	collision_layer = 4
	collision_mask = 151
	monitoring = true
	monitorable = true


func _process(delta: float) -> void:
	if not _is_launched:
		return
	
	# Find player
	if not _player_ref or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player")
	
	# Move
	global_position += _velocity * delta
	
	# Rotate to face movement
	if _velocity.length_squared() > 1.0:
		rotation = _velocity.angle()
	
	# Update parry visuals based on distance
	_update_parry_visuals()
	
	# Lifetime
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		queue_free()


func _update_parry_visuals() -> void:
	if not parryable or _current_target_group != "player":
		_reset_visuals()
		return
	
	var dist := _get_player_distance()
	var in_range := dist <= parry_distance
	
	if in_range:
		# IN PARRY RANGE - BRIGHT GREEN + BIG
		_is_in_parry_range = true
		var pulse := (sin(Time.get_ticks_msec() * 0.015) + 1.0) * 0.5
		modulate = parryable_color.lerp(Color.WHITE, pulse * 0.3)
		scale = _original_scale * (parryable_scale + pulse * 0.4)
	else:
		_is_in_parry_range = false
		_reset_visuals()


func _reset_visuals() -> void:
	modulate = _original_modulate
	scale = _original_scale


func _get_player_distance() -> float:
	if not _player_ref:
		return 9999.0
	return global_position.distance_to(_player_ref.global_position)


func launch(from_source: Node = null) -> void:
	_source = from_source
	_velocity = direction.normalized() * speed
	_is_launched = true
	_lifetime_timer = 0.0


func set_direction_to_target(target_pos: Vector2) -> void:
	direction = (target_pos - global_position).normalized()


func is_in_parry_window() -> bool:
	return parryable and _is_in_parry_range and _parry_count < max_parry_count


func parry(by_node: Node, reflected_damage: float = -1.0) -> bool:
	if not is_in_parry_window():
		return false
	
	_parry_count += 1
	
	if _parry_count > max_parry_count:
		queue_free()
		return true
	
	if reflected_damage > 0.0:
		damage = reflected_damage
	
	# Reflect back to source
	var target_pos: Vector2
	if _source and is_instance_valid(_source):
		target_pos = _source.global_position
	else:
		target_pos = global_position - _velocity.normalized() * 100.0
	
	direction = (target_pos - global_position).normalized()
	_velocity = direction * speed * parry_speed_multiplier
	
	# Swap who it hurts
	_current_target_group = "enemies" if _current_target_group == "player" else "player"
	_source = by_node
	_is_in_parry_range = false
	
	# Flash white
	modulate = Color.WHITE
	scale = _original_scale * 2.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate", _original_modulate, 0.15)
	tw.tween_property(self, "scale", _original_scale, 0.15)
	
	parried.emit(by_node)
	return true


func _on_body_entered(body: Node2D) -> void:
	if body == _source:
		return
	
	if body.is_in_group("terrain") or body.is_in_group("walls"):
		queue_free()
		return
	
	if not body.is_in_group(_current_target_group):
		return
	
	# Deal damage
	if body.has_method("take_damage"):
		var dir = sign(body.global_position.x - global_position.x)
		if dir == 0.0:
			dir = sign(_velocity.x)
		body.take_damage(damage, self, Vector2(dir * knockback_force, -knockback_force * 0.5))
	
	hit_target.emit(body)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Find the player node
	var player: Node = null
	if area.owner and area.owner.is_in_group("player"):
		player = area.owner
	else:
		var p = area.get_parent()
		while p:
			if p.is_in_group("player"):
				player = p
				break
			p = p.get_parent()
	
	# Damage hurtbox = deal damage
	if area.name == "DamageHurtbox" and player:
		if player.is_in_group(_current_target_group):
			if player.has_method("take_damage"):
				var dir = sign(player.global_position.x - global_position.x)
				player.take_damage(damage, self, Vector2(dir * knockback_force, -knockback_force * 0.5))
			hit_target.emit(player)
			queue_free()
			return
	
	# Parry or Attack hitbox = try to parry
	if area.name in ["ParryHitbox", "AttackHitbox"] and player:
		parry(player, damage * 1.5)
