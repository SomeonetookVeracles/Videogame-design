class_name HealthComponent
extends Node

## Orb-based health system inspired by Hollow Knight's mask system.
## Each orb has independent physics, reacting to player movement and settling into a halo.

signal health_changed(current: int, maximum: int)
signal health_depleted
signal damage_taken(amount: float, source: Node)
signal healed(amount: int)
signal invincibility_started
signal invincibility_ended
signal orb_lost(orb_index: int)
signal orb_restored(orb_index: int)

@export_group("Health")
@export var max_orbs: int = 5 : set = set_max_orbs
@export var damage_per_orb: float = 1.0

@export_group("Invincibility")
@export var invincibility_duration: float = 1.0
@export var flash_interval: float = 0.1

@export_group("Halo Shape")
@export var halo_radius: float = 48.0
@export var halo_center_offset: Vector2 = Vector2(0, -10)
@export var halo_arc_degrees: float = 120.0

@export_group("Orb Appearance")
@export var orb_scene: PackedScene
@export var orb_texture: Texture2D = preload("res://assets/sprites/mira/mira_health.png")
@export var orb_scale: Vector2 = Vector2.ONE
@export var orb_z_index: int = -1
@export var orb_modulate: Color = Color.WHITE

@export_group("Orb Physics")
@export var orb_return_force: float = 180.0
@export var orb_damping: float = 16.0
@export var orb_max_speed: float = 400.0
@export var movement_influence: float = 0.6
@export var separation_force: float = 60.0
@export var separation_radius: float = 32.0

@export_group("Orb Hover")
@export var hover_amplitude: float = 1.5
@export var hover_speed_min: float = 2.0
@export var hover_speed_max: float = 3.5

var current_orbs: int = 5 : set = set_current_orbs
var is_invincible: bool = false
var invincibility_timer: float = 0.0

var _orb_instances: Array[Node2D] = []
var _orb_velocities: Array[Vector2] = []
var _orb_hover_phases: Array[float] = []
var _orb_hover_speeds: Array[float] = []
var _parent: Node2D = null
var _parent_prev_pos: Vector2 = Vector2.ZERO
var _parent_velocity: Vector2 = Vector2.ZERO
var _flash_timer: float = 0.0
var _time_elapsed: float = 0.0

# Legacy compatibility
var max_health: float:
	get: return float(max_orbs) * damage_per_orb
	set(value): max_orbs = ceili(value / damage_per_orb)

var current_health: float:
	get: return float(current_orbs) * damage_per_orb
	set(value): current_orbs = ceili(value / damage_per_orb)


func _ready() -> void:
	_parent = get_parent() as Node2D
	if _parent:
		_parent_prev_pos = _parent.global_position
	current_orbs = max_orbs
	_spawn_orbs()


func _process(delta: float) -> void:
	_time_elapsed += delta
	_update_parent_velocity(delta)
	_update_invincibility(delta)
	_update_orb_physics(delta)


func _update_parent_velocity(delta: float) -> void:
	if not _parent:
		return
	
	if delta > 0.0:
		_parent_velocity = (_parent.global_position - _parent_prev_pos) / delta
	_parent_prev_pos = _parent.global_position


func _update_invincibility(delta: float) -> void:
	if not is_invincible:
		return
	
	invincibility_timer -= delta
	_flash_timer -= delta
	
	if _flash_timer <= 0.0:
		_flash_timer = flash_interval
		_toggle_parent_visibility()
	
	if invincibility_timer <= 0.0:
		_end_invincibility()


func _toggle_parent_visibility() -> void:
	if _parent:
		_parent.modulate.a = 0.3 if _parent.modulate.a > 0.5 else 1.0


func _end_invincibility() -> void:
	is_invincible = false
	invincibility_timer = 0.0
	if _parent:
		_parent.modulate.a = 1.0
	invincibility_ended.emit()


func _get_target_position(orb_index: int) -> Vector2:
	if not _parent:
		return Vector2.ZERO
	
	var visible_count := current_orbs
	if visible_count == 0:
		return _parent.global_position + halo_center_offset
	
	# Calculate arc distribution
	var arc_radians := deg_to_rad(halo_arc_degrees)
	var start_angle := PI / 2.0 + arc_radians / 2.0
	
	var t: float
	if visible_count == 1:
		t = 0.5
	else:
		# Remap index to only visible orbs
		var visible_index := 0
		for i in orb_index + 1:
			if i < current_orbs:
				if i == orb_index:
					break
				visible_index += 1
		t = float(visible_index) / float(visible_count - 1) if visible_count > 1 else 0.5
	
	var angle := start_angle - t * arc_radians
	var arc_pos := Vector2(
		cos(angle) * halo_radius,
		-sin(angle) * halo_radius
	)
	
	# Add hover offset
	var phase := _time_elapsed * _orb_hover_speeds[orb_index] + _orb_hover_phases[orb_index]
	var hover_offset := Vector2(0, sin(phase) * hover_amplitude)
	
	return _parent.global_position + halo_center_offset + arc_pos + hover_offset


func _update_orb_physics(delta: float) -> void:
	if not _parent or _orb_instances.is_empty():
		return
	
	# Calculate player speed for spread effect
	var player_speed := _parent_velocity.length()
	var speed_factor := clampf(player_speed / 300.0, 0.0, 1.0)  # 0 at rest, 1 at 300+ speed
	
	for i in _orb_instances.size():
		var orb := _orb_instances[i]
		if not is_instance_valid(orb) or not orb.visible:
			continue
		
		if i >= _orb_velocities.size():
			continue
		
		var vel := _orb_velocities[i]
		var pos := orb.global_position
		var target := _get_target_position(i)
		
		# Calculate spread offset based on movement
		# Orbs spread outward perpendicular to movement direction
		var spread_offset := Vector2.ZERO
		if player_speed > 20.0:
			var move_dir := _parent_velocity.normalized()
			var perp := Vector2(-move_dir.y, move_dir.x)  # Perpendicular to movement
			
			# Each orb spreads differently based on its index
			var orb_spread_dir := 1.0 if i % 2 == 0 else -1.0
			var spread_amount := 15.0 + (i % 3) * 8.0  # Vary spread per orb
			spread_offset = perp * orb_spread_dir * spread_amount * speed_factor
			
			# Also trail behind slightly
			spread_offset -= move_dir * 10.0 * speed_factor
		
		var adjusted_target := target + spread_offset
		var to_target := adjusted_target - pos
		var distance := to_target.length()
		
		# Smoothing increases when player is still (tighter formation)
		# Decreases when moving (looser, more trailing)
		var base_smoothing := lerpf(8.0, 4.0, speed_factor)  # 8 when still, 4 when moving
		var distance_bonus := clampf(distance / 120.0, 0.0, 1.5)
		var smoothing := base_smoothing * (1.0 + distance_bonus)
		
		# Smooth interpolation toward target
		var target_vel := to_target * smoothing
		
		# Blend current velocity toward target velocity
		var accel_smoothing := lerpf(6.0, 3.0, speed_factor)  # Snappier when still
		vel = vel.lerp(target_vel, accel_smoothing * delta)
		
		# Gentle separation from other orbs - stronger when still
		var sep_strength := lerpf(1.0, 0.4, speed_factor)
		for j in _orb_instances.size():
			if i == j:
				continue
			var other := _orb_instances[j]
			if not is_instance_valid(other) or not other.visible:
				continue
			
			var diff := pos - other.global_position
			var dist := diff.length()
			if dist < separation_radius and dist > 0.1:
				var push_strength := (1.0 - dist / separation_radius)
				push_strength *= push_strength
				var push := diff.normalized() * separation_force * push_strength * sep_strength * 0.5
				vel += push * delta
		
		# Soft speed limit
		var max_speed := orb_max_speed * (1.0 + distance / 80.0)
		var current_speed := vel.length()
		if current_speed > max_speed:
			vel = vel * (max_speed / current_speed)
		
		# Update position
		pos += vel * delta
		
		_orb_velocities[i] = vel
		orb.global_position = pos


func _spawn_orbs() -> void:
	_clear_orbs()
	
	if orb_scene:
		# Use custom scene
		for i in max_orbs:
			var orb: Node2D = orb_scene.instantiate()
			_setup_orb(orb, i)
	elif orb_texture:
		# Use custom texture with default orb structure
		for i in max_orbs:
			var orb := _create_orb_with_texture(orb_texture)
			_setup_orb(orb, i)
	else:
		# Use procedurally generated orbs
		_create_default_orbs()


func _create_orb_with_texture(texture: Texture2D) -> Node2D:
	var orb := Node2D.new()
	orb.name = "HealthOrb"
	
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	orb.add_child(sprite)
	
	return orb


func _create_default_orbs() -> void:
	for i in max_orbs:
		var orb := _create_default_orb()
		_setup_orb(orb, i)


func _create_default_orb() -> Node2D:
	var orb := Node2D.new()
	orb.name = "HealthOrb"
	
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	orb.add_child(sprite)
	
	# Create a simple glowing circle texture
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := 6.0
	
	for x in size:
		for y in size:
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				var t := dist / radius
				var alpha := 1.0 - t * 0.3
				var brightness := 1.0 + (1.0 - t) * 0.3
				image.set_pixel(x, y, Color(
					minf(0.8 * brightness, 1.0),
					minf(0.9 * brightness, 1.0),
					1.0,
					alpha
				))
			elif dist <= radius + 1.5:
				var alpha := (1.0 - (dist - radius) / 1.5) * 0.4
				image.set_pixel(x, y, Color(0.6, 0.8, 1.0, alpha))
	
	sprite.texture = ImageTexture.create_from_image(image)
	
	return orb


func _setup_orb(orb: Node2D, index: int) -> void:
	if _parent and _parent.get_parent():
		_parent.get_parent().call_deferred("add_child", orb)
	
	# Apply appearance settings
	orb.z_index = orb_z_index
	orb.scale = orb_scale
	orb.modulate = orb_modulate
	
	# Initialize physics data
	_orb_velocities.append(Vector2.ZERO)
	_orb_hover_phases.append(randf() * TAU)
	_orb_hover_speeds.append(randf_range(hover_speed_min, hover_speed_max))
	
	# Calculate initial position
	var arc_radians := deg_to_rad(halo_arc_degrees)
	var start_angle := PI / 2.0 + arc_radians / 2.0
	
	var t: float
	if max_orbs == 1:
		t = 0.5
	else:
		t = float(index) / float(max_orbs - 1)
	
	var angle := start_angle - t * arc_radians
	var arc_pos := Vector2(
		cos(angle) * halo_radius,
		-sin(angle) * halo_radius
	)
	
	var base_pos := Vector2.ZERO
	if _parent:
		base_pos = _parent.global_position + halo_center_offset + arc_pos
	
	orb.global_position = base_pos
	orb.visible = index < current_orbs
	_orb_instances.append(orb)


func _clear_orbs() -> void:
	for orb in _orb_instances:
		if is_instance_valid(orb):
			orb.queue_free()
	_orb_instances.clear()
	_orb_velocities.clear()
	_orb_hover_phases.clear()
	_orb_hover_speeds.clear()


func set_max_orbs(value: int) -> void:
	var old_max := max_orbs
	max_orbs = maxi(1, value)
	
	if max_orbs != old_max and is_inside_tree():
		_spawn_orbs()
		current_orbs = mini(current_orbs, max_orbs)


func set_current_orbs(value: int) -> void:
	var old_orbs := current_orbs
	current_orbs = clampi(value, 0, max_orbs)
	
	if current_orbs != old_orbs:
		_update_orb_visibility()
		health_changed.emit(current_orbs, max_orbs)
		
		if current_orbs < old_orbs:
			for i in range(current_orbs, old_orbs):
				orb_lost.emit(i)
		elif current_orbs > old_orbs:
			for i in range(old_orbs, current_orbs):
				orb_restored.emit(i)
		
		if current_orbs <= 0:
			health_depleted.emit()


func _update_orb_visibility() -> void:
	for i in _orb_instances.size():
		var orb := _orb_instances[i]
		if is_instance_valid(orb):
			var should_be_visible := i < current_orbs
			
			if orb.visible and not should_be_visible:
				_animate_orb_loss(orb, i)
			elif not orb.visible and should_be_visible:
				_animate_orb_restore(orb, i)


func _animate_orb_loss(orb: Node2D, index: int) -> void:
	# Burst outward
	if index < _orb_velocities.size():
		var burst_dir := (orb.global_position - _parent.global_position).normalized()
		if burst_dir.length_squared() < 0.1:
			burst_dir = Vector2.UP
		_orb_velocities[index] = burst_dir * 200.0 + Vector2(randf_range(-50, 50), randf_range(-80, -20))
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(orb, "scale", Vector2(1.8, 1.8), 0.08)
	tween.tween_property(orb, "modulate:a", 0.0, 0.25)
	tween.finished.connect(func(): 
		orb.visible = false
		orb.scale = Vector2.ONE
		orb.modulate.a = 1.0
	)


func _animate_orb_restore(orb: Node2D, index: int) -> void:
	orb.visible = true
	orb.scale = Vector2(0.0, 0.0)
	orb.modulate.a = 0.0
	
	# Start from player center
	if _parent:
		orb.global_position = _parent.global_position + halo_center_offset
	
	# Give initial velocity toward target
	if index < _orb_velocities.size():
		_orb_velocities[index] = Vector2(randf_range(-30, 30), randf_range(-50, -20))
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(orb, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(orb, "modulate:a", 1.0, 0.2)


func take_damage(amount: float, source: Node = null, knockback: Vector2 = Vector2.ZERO) -> bool:
	if is_invincible or current_orbs <= 0:
		return false
	
	var orbs_lost := ceili(amount / damage_per_orb)
	current_orbs -= orbs_lost
	
	damage_taken.emit(amount, source)
	
	# Scatter all orbs on damage
	_scatter_orbs_on_damage(knockback)
	
	_start_invincibility()
	
	if knockback.length_squared() > 0.01 and _parent and _parent.has_method("apply_knockback"):
		_parent.apply_knockback(knockback)
	
	return true


func _scatter_orbs_on_damage(knockback: Vector2) -> void:
	for i in _orb_velocities.size():
		if i >= current_orbs:
			continue
		var scatter := Vector2(randf_range(-80, 80), randf_range(-60, 60))
		if knockback.length_squared() > 0.1:
			scatter += knockback.normalized() * 40.0
		_orb_velocities[i] += scatter


func _start_invincibility() -> void:
	is_invincible = true
	invincibility_timer = invincibility_duration
	_flash_timer = flash_interval
	invincibility_started.emit()


func heal(orbs: int = 1) -> void:
	if current_orbs >= max_orbs:
		return
	
	var old_orbs := current_orbs
	current_orbs += orbs
	healed.emit(current_orbs - old_orbs)


func heal_full() -> void:
	heal(max_orbs - current_orbs)


func apply_knockback(force: Vector2) -> void:
	if _parent and _parent.has_method("apply_knockback"):
		_parent.apply_knockback(force)


func is_alive() -> bool:
	return current_orbs > 0


func get_health_percentage() -> float:
	return float(current_orbs) / float(max_orbs)
