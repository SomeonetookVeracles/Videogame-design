class_name StunnerEnemy
extends CharacterBody2D

## Stunner enemy that fires slowing projectiles from long range.
## Panics and runs away when player gets too close. Dies in one hit, deals no damage.

signal died
signal fired_projectile(projectile: Node)
signal panicked
signal calmed_down

@export_group("Movement")
@export var wander_speed: float = 30.0
@export var panic_speed: float = 180.0
@export var stunner_gravity: float = 900.0
@export var wander_area: Vector2 = Vector2(60, 0)
@export var wander_pause_min: float = 1.5
@export var wander_pause_max: float = 3.0

@export_group("Attack Range")
@export var attack_range_min: float = 150.0  ## Start shooting at this distance
@export var attack_range_max: float = 300.0  ## Stop shooting beyond this
@export var preferred_distance: float = 200.0  ## Ideal shooting distance

@export_group("Panic")
@export var panic_range: float = 80.0  ## Run away when player is this close
@export var safe_range: float = 140.0  ## Stop panicking when player is this far
@export var panic_jump_chance: float = 0.3  ## Chance to jump when panicking
@export var panic_jump_force: float = -300.0

@export_group("Combat")
@export var fire_rate: float = 0.8  ## Shots per second
@export var projectile_speed: float = 120.0
@export var slow_amount: float = 0.5  ## Multiplier applied to player speed (0.5 = 50% speed)
@export var slow_duration: float = 2.0
@export var aim_prediction: float = 0.3  ## How much to lead the target

@export_group("Visual")
@export var flash_on_hit: bool = true
@export var flash_color: Color = Color(1, 1, 1, 1)
@export var panic_color: Color = Color(1, 0.7, 0.7, 1)

enum State { IDLE, WANDER, ATTACK, PANIC, DEAD }

var current_state: State = State.IDLE
var facing_direction: float = 1.0

var _spawn_position: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _fire_timer: float = 0.0
var _panic_jump_cooldown: float = 0.0
var _player: Node2D = null

var _ledge_ray_left: RayCast2D
var _ledge_ray_right: RayCast2D
var _panic_anim_started: bool = false

@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null
@onready var animation_player: AnimationPlayer = $animations/AnimationPlayer if has_node("animations/AnimationPlayer") else null
@onready var projectile_spawn: Marker2D = $ProjectileSpawn if has_node("ProjectileSpawn") else null


func _ready() -> void:
	add_to_group("enemies")
	_spawn_position = global_position
	_pick_wander_target()
	
	_setup_ledge_detection()


func _setup_ledge_detection() -> void:
	var ray_x_offset: float = 12.0
	var ray_y_start: float = 0.0
	var ray_length: float = 20.0
	
	var main_collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if main_collision and main_collision.shape:
		if main_collision.shape is RectangleShape2D:
			ray_x_offset = main_collision.shape.size.x * 0.5 + 4.0
			ray_y_start = main_collision.shape.size.y * 0.5
		elif main_collision.shape is CapsuleShape2D:
			ray_x_offset = main_collision.shape.radius + 4.0
			ray_y_start = main_collision.shape.height * 0.5
		elif main_collision.shape is CircleShape2D:
			ray_x_offset = main_collision.shape.radius + 4.0
			ray_y_start = main_collision.shape.radius
	
	_ledge_ray_left = RayCast2D.new()
	_ledge_ray_left.name = "LedgeRayLeft"
	_ledge_ray_left.position = Vector2(-ray_x_offset, ray_y_start)
	_ledge_ray_left.target_position = Vector2(0, ray_length)
	_ledge_ray_left.enabled = true
	add_child(_ledge_ray_left)
	
	_ledge_ray_right = RayCast2D.new()
	_ledge_ray_right.name = "LedgeRayRight"
	_ledge_ray_right.position = Vector2(ray_x_offset, ray_y_start)
	_ledge_ray_right.target_position = Vector2(0, ray_length)
	_ledge_ray_right.enabled = true
	add_child(_ledge_ray_right)


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
	
	_update_timers(delta)
	_find_player()
	_update_state()
	_process_state(delta)
	_apply_gravity(delta)
	_update_facing()
	
	move_and_slide()


func _update_timers(delta: float) -> void:
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_wander_timer = maxf(0.0, _wander_timer - delta)
	_panic_jump_cooldown = maxf(0.0, _panic_jump_cooldown - delta)


func _find_player() -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")


func _update_state() -> void:
	if current_state == State.DEAD:
		return
	
	if not _player:
		if current_state != State.WANDER and current_state != State.IDLE:
			current_state = State.IDLE
			_pick_wander_target()
		return
	
	var distance_to_player := global_position.distance_to(_player.global_position)
	
	# Check for panic first - highest priority
	if distance_to_player <= panic_range:
		if current_state != State.PANIC:
			current_state = State.PANIC
			_panic_anim_started = false
			panicked.emit()
			if sprite:
				sprite.modulate = panic_color
			_play_panic_start()
		return
	
	# Check if we can calm down from panic
	if current_state == State.PANIC:
		if distance_to_player >= safe_range:
			current_state = State.IDLE
			_panic_anim_started = false
			calmed_down.emit()
			if sprite:
				sprite.modulate = Color.WHITE
				sprite.rotation = 0.0
				sprite.scale = Vector2.ONE
			_pick_wander_target()
		return
	
	# Check for attack range
	if distance_to_player >= attack_range_min and distance_to_player <= attack_range_max:
		current_state = State.ATTACK
	else:
		if current_state == State.ATTACK:
			current_state = State.IDLE
			_pick_wander_target()


func _process_state(delta: float) -> void:
	match current_state:
		State.IDLE:
			_process_idle(delta)
			_play_animation("Idle")
		State.WANDER:
			_process_wander()
			_play_animation("Idle")
		State.ATTACK:
			_process_attack(delta)
		State.PANIC:
			_process_panic(delta)
			# Only play Run after Panic has finished
			if _panic_anim_started:
				_play_animation("Run")


func _process_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, wander_speed * 2.0 * delta)
	
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		current_state = State.WANDER
		_pick_wander_target()


func _process_wander() -> void:
	var dir: float = sign(_wander_target.x - global_position.x)
	
	if _is_ledge_ahead(dir):
		current_state = State.IDLE
		_wander_timer = randf_range(wander_pause_min, wander_pause_max)
		velocity.x = 0.0
		return
	
	velocity.x = dir * wander_speed
	
	if absf(global_position.x - _wander_target.x) < 5.0 or is_on_wall():
		current_state = State.IDLE
		_wander_timer = randf_range(wander_pause_min, wander_pause_max)


func _process_attack(delta: float) -> void:
	if not _player:
		return
	
	var dir_to_player: float = sign(_player.global_position.x - global_position.x)
	facing_direction = dir_to_player
	
	# Stay relatively still while attacking, maybe slight adjustment
	var distance_to_player := global_position.distance_to(_player.global_position)
	
	if distance_to_player < preferred_distance - 20.0:
		# Back up slightly
		if not _is_ledge_ahead(-dir_to_player):
			velocity.x = -dir_to_player * wander_speed
		else:
			velocity.x = 0.0
	elif distance_to_player > preferred_distance + 20.0:
		# Move closer slightly
		if not _is_ledge_ahead(dir_to_player):
			velocity.x = dir_to_player * wander_speed * 0.5
		else:
			velocity.x = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, wander_speed * 3.0 * delta)
	
	# Fire projectile
	if _fire_timer <= 0.0:
		_fire_projectile()


func _process_panic(delta: float) -> void:
	if not _player:
		current_state = State.IDLE
		return
	
	var dir_away_from_player: float = sign(global_position.x - _player.global_position.x)
	if dir_away_from_player == 0.0:
		dir_away_from_player = 1.0 if randf() > 0.5 else -1.0
	
	facing_direction = -dir_away_from_player  # Look at player while running
	
	# Check for ledge
	if _is_ledge_ahead(dir_away_from_player):
		# Cornered! Try to jump or just cower
		velocity.x = 0.0
		
		if is_on_floor() and _panic_jump_cooldown <= 0.0 and randf() < panic_jump_chance:
			velocity.y = panic_jump_force
			_panic_jump_cooldown = 0.5
	elif is_on_wall():
		# Hit a wall, try jumping over
		if is_on_floor() and _panic_jump_cooldown <= 0.0:
			velocity.y = panic_jump_force
			_panic_jump_cooldown = 0.5
	else:
		velocity.x = dir_away_from_player * panic_speed


func _fire_projectile() -> void:
	_fire_timer = 1.0 / fire_rate
	
	# Play Attack animation
	_play_animation("Attack")
	
	var projectile := SlowProjectile.new()
	get_parent().add_child(projectile)
	
	if projectile_spawn:
		projectile.global_position = projectile_spawn.global_position
	else:
		projectile.global_position = global_position + Vector2(facing_direction * 12, -8)
	
	# Aim with prediction
	var target_pos := _player.global_position
	if aim_prediction > 0.0 and "velocity" in _player:
		target_pos += _player.velocity * aim_prediction
	
	projectile.set_direction_to_target(target_pos)
	projectile.speed = projectile_speed
	projectile.slow_amount = slow_amount
	projectile.slow_duration = slow_duration
	projectile.launch(self)
	
	fired_projectile.emit(projectile)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += stunner_gravity * delta
	else:
		velocity.y = 0.0


func _update_facing() -> void:
	if sprite:
		sprite.flip_h = facing_direction < 0
	if projectile_spawn:
		projectile_spawn.position.x = absf(projectile_spawn.position.x) * facing_direction


func _play_animation(anim_name: String) -> void:
	if not animation_player:
		return
	
	if animation_player.current_animation != anim_name:
		# Don't interrupt Attack or Panic animations
		if animation_player.current_animation in ["Attack", "Panic"] and animation_player.is_playing():
			return
		animation_player.play(anim_name)


func _play_panic_start() -> void:
	if not animation_player:
		_panic_anim_started = true
		return
	
	animation_player.play("Panic")
	
	# Wait for animation to finish, then allow Run
	await animation_player.animation_finished
	if current_state == State.PANIC:
		_panic_anim_started = true


func _pick_wander_target() -> void:
	var offset := randf_range(-wander_area.x, wander_area.x)
	_wander_target = _spawn_position + Vector2(offset, 0)
	_wander_timer = randf_range(wander_pause_min, wander_pause_max)


func _is_ledge_ahead(direction: float) -> bool:
	if not is_on_floor():
		return false
	
	if direction > 0 and _ledge_ray_right:
		return not _ledge_ray_right.is_colliding()
	elif direction < 0 and _ledge_ray_left:
		return not _ledge_ray_left.is_colliding()
	
	return false


func take_damage(_amount: float, _source: Node = null, knockback: Vector2 = Vector2.ZERO) -> void:
	if current_state == State.DEAD:
		return
	
	# Die in one hit
	_die()


func _die() -> void:
	current_state = State.DEAD
	velocity = Vector2.ZERO
	
	died.emit()
	
	if sprite:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
		tween.tween_property(sprite, "scale", Vector2(1.5, 0.2), 0.3)
		tween.finished.connect(queue_free)
	else:
		queue_free()


func is_alive() -> bool:
	return current_state != State.DEAD


# ============================================================================
# SLOW PROJECTILE - Inner class for the slowing projectile
# ============================================================================

class SlowProjectile extends Area2D:
	signal hit_target(target: Node)
	signal destroyed
	
	var speed: float = 120.0
	var direction: Vector2 = Vector2.RIGHT
	var lifetime: float = 5.0
	var slow_amount: float = 0.5
	var slow_duration: float = 2.0
	
	var _velocity: Vector2 = Vector2.ZERO
	var _is_launched: bool = false
	var _lifetime_timer: float = 0.0
	var _source: Node = null
	
	func _ready() -> void:
		_setup_collision()
		_setup_visuals()
		
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)
	
	func _setup_collision() -> void:
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var shape := CircleShape2D.new()
		shape.radius = 6.0
		collision.shape = shape
		add_child(collision)
		
		collision_layer = 4  # Projectile layer
		collision_mask = 1   # Player layer only
		monitoring = true
		monitorable = true
	
	func _setup_visuals() -> void:
		# Create a simple visual for the slow projectile
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		
		var size := 12
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var center := Vector2(size / 2.0, size / 2.0)
		
		# Draw a blue-ish orb
		for x in size:
			for y in size:
				var dist := Vector2(x, y).distance_to(center)
				if dist <= size / 2.0 - 1:
					var t := dist / (size / 2.0)
					var alpha := 1.0 - t * 0.3
					image.set_pixel(x, y, Color(0.4, 0.6, 1.0, alpha))
				elif dist <= size / 2.0:
					image.set_pixel(x, y, Color(0.6, 0.8, 1.0, 0.5))
		
		sprite.texture = ImageTexture.create_from_image(image)
		add_child(sprite)
	
	func _process(delta: float) -> void:
		if not _is_launched:
			return
		
		global_position += _velocity * delta
		
		# Rotate to face direction
		if _velocity.length_squared() > 0.01:
			rotation = _velocity.angle()
		
		_lifetime_timer += delta
		if _lifetime_timer >= lifetime:
			_destroy()
	
	func launch(from_source: Node = null) -> void:
		_source = from_source
		_velocity = direction.normalized() * speed
		_is_launched = true
		_lifetime_timer = 0.0
	
	func set_direction_to_target(target_position: Vector2) -> void:
		direction = (target_position - global_position).normalized()
	
	func _on_body_entered(body: Node2D) -> void:
		if body == _source:
			return
		
		if body.is_in_group("player"):
			_apply_slow(body)
			_destroy()
			return
		
		if body.is_in_group("terrain") or body.is_in_group("walls"):
			_destroy()
	
	func _on_area_entered(area: Area2D) -> void:
		var area_parent := area.get_parent()
		
		# Check for player's hurtbox
		if area.name == "DamageHurtbox" and area_parent:
			if area_parent.is_in_group("player"):
				_apply_slow(area_parent)
				_destroy()
				return
		
		# Can be parried/deflected by attack
		if area.name == "AttackHitbox" or area.name == "ParryHitbox":
			_destroy()
	
	func _apply_slow(target: Node) -> void:
		if not target:
			return
		
		hit_target.emit(target)
		
		# Try to apply slow effect
		if target.has_method("apply_slow"):
			target.apply_slow(slow_amount, slow_duration)
		elif "movement" in target and target.movement:
			if target.movement.has_method("apply_slow"):
				target.movement.apply_slow(slow_amount, slow_duration)
			else:
				# Fallback: directly modify speed temporarily
				_apply_slow_fallback(target)
		else:
			_apply_slow_fallback(target)
	
	func _apply_slow_fallback(target: Node) -> void:
		# Create a temporary slow effect by modifying velocity
		if "velocity" in target:
			target.velocity *= slow_amount
		
		# Try to find and slow movement component
		var movement = target.get_node_or_null("PlayerMovement")
		if movement and "move_speed" in movement:
			var original_speed: float = movement.move_speed
			movement.move_speed *= slow_amount
			
			# Restore after duration
			var tree := target.get_tree()
			if tree:
				await tree.create_timer(slow_duration).timeout
				if is_instance_valid(movement):
					movement.move_speed = original_speed
	
	func _destroy() -> void:
		destroyed.emit()
		queue_free()
