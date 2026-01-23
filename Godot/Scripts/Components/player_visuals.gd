class_name PlayerVisuals
extends Node

## Handles all player visual effects including animations, afterimages, and particles.

signal animation_finished(anim_name: String)

@export_group("Afterimages - Dash")
@export var dash_afterimage_enabled: bool = true
@export var dash_afterimage_interval: float = 0.03
@export var dash_afterimage_lifetime: float = 0.3
@export var dash_afterimage_extension: float = 0.1

@export_group("Afterimages - Jump")
@export var jump_afterimage_enabled: bool = false
@export var jump_afterimage_min_velocity: float = 200.0
@export var jump_afterimage_max_interval: float = 0.08
@export var jump_afterimage_min_interval: float = 0.02
@export var jump_afterimage_lifetime: float = 0.25

@export_group("Node References")
@export var animation_player_path: NodePath = "animations/debug-animations"
@export var animations_root_path: NodePath = "animations"

var animation_player: AnimationPlayer
var animations_root: Node2D
var parent: CharacterBody2D

var sprites: Dictionary = {}
var particles: Dictionary = {}

var _current_sprite_key: String = "idle"
var _afterimage_timer: float = 0.0
var _afterimage_extension_timer: float = 0.0
var _jump_afterimage_timer: float = 0.0
var _is_creating_dash_afterimages: bool = false

const SPRITE_KEYS: Array[String] = ["idle", "run", "jump", "dash", "attack"]
const PARTICLE_KEYS: Array[String] = ["jump", "dash", "death"]


func _ready() -> void:
	parent = get_parent() as CharacterBody2D
	_cache_nodes()
	_connect_signals()
	_hide_all_sprites()


func _cache_nodes() -> void:
	animation_player = parent.get_node_or_null(animation_player_path)
	animations_root = parent.get_node_or_null(animations_root_path)
	
	# Cache sprite references
	var sprites_container := parent.get_node_or_null("animations/sprites")
	if sprites_container:
		sprites["idle"] = sprites_container.get_node_or_null("Idle")
		sprites["run"] = sprites_container.get_node_or_null("Run")
		sprites["jump"] = sprites_container.get_node_or_null("Jump")
		sprites["dash"] = sprites_container.get_node_or_null("Dash")
		sprites["attack"] = sprites_container.get_node_or_null("combat_attack")
	
	# Cache particle references
	var particles_container := parent.get_node_or_null("particles")
	if particles_container:
		particles["jump"] = particles_container.get_node_or_null("jump-particles")
		particles["dash"] = particles_container.get_node_or_null("dash-particles")
		particles["death"] = particles_container.get_node_or_null("death-particles")


func _connect_signals() -> void:
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)


func _on_animation_finished(anim_name: String) -> void:
	animation_finished.emit(anim_name)


func _process(delta: float) -> void:
	_update_afterimages(delta)


func _update_afterimages(delta: float) -> void:
	# Dash afterimages
	if _is_creating_dash_afterimages or _afterimage_extension_timer > 0.0:
		_afterimage_timer -= delta
		if _afterimage_timer <= 0.0:
			_create_afterimage(dash_afterimage_lifetime)
			_afterimage_timer = dash_afterimage_interval
	
	if _afterimage_extension_timer > 0.0:
		_afterimage_extension_timer -= delta
	
	# Jump afterimages
	if jump_afterimage_enabled and not parent.is_on_floor() and not _is_creating_dash_afterimages:
		var speed_sq := parent.velocity.length_squared()
		var min_vel_sq := jump_afterimage_min_velocity * jump_afterimage_min_velocity
		
		if speed_sq >= min_vel_sq:
			var speed := sqrt(speed_sq)
			var speed_factor := clampf((speed - jump_afterimage_min_velocity) / 400.0, 0.0, 1.0)
			var dynamic_interval := lerpf(jump_afterimage_max_interval, jump_afterimage_min_interval, speed_factor)
			
			_jump_afterimage_timer -= delta
			if _jump_afterimage_timer <= 0.0:
				_create_afterimage(jump_afterimage_lifetime)
				_jump_afterimage_timer = dynamic_interval


func _create_afterimage(lifetime: float) -> void:
	var current_sprite := _get_current_visible_sprite()
	if not current_sprite:
		return
	
	var afterimage := Sprite2D.new()
	afterimage.texture = current_sprite.texture
	afterimage.hframes = current_sprite.hframes
	afterimage.vframes = current_sprite.vframes
	afterimage.frame = current_sprite.frame
	afterimage.global_position = current_sprite.global_position
	afterimage.scale = current_sprite.global_scale
	afterimage.rotation = current_sprite.global_rotation
	afterimage.modulate = Color(1.0, 1.0, 1.0, 0.7)
	afterimage.z_index = current_sprite.z_index - 1
	
	parent.get_parent().add_child(afterimage)
	
	var tween := parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(afterimage, "modulate:a", 0.0, lifetime)
	tween.tween_property(afterimage, "scale", current_sprite.global_scale * 0.9, lifetime)
	tween.finished.connect(afterimage.queue_free)


func _get_current_visible_sprite() -> Sprite2D:
	for sprite in sprites.values():
		if sprite and sprite.visible:
			return sprite
	return null


func start_dash_afterimages() -> void:
	_is_creating_dash_afterimages = true
	_afterimage_timer = 0.0


func stop_dash_afterimages() -> void:
	_is_creating_dash_afterimages = false
	_afterimage_extension_timer = dash_afterimage_extension


func update_facing(direction: float) -> void:
	if animations_root:
		animations_root.scale.x = direction


func set_sprite_visible(sprite_key: String) -> void:
	if sprite_key == _current_sprite_key:
		return
	
	_current_sprite_key = sprite_key
	for key in sprites:
		if sprites[key]:
			sprites[key].visible = (key == sprite_key)


func _hide_all_sprites() -> void:
	for sprite in sprites.values():
		if sprite:
			sprite.visible = false


func show_sprite(sprite_key: String) -> void:
	if sprites.has(sprite_key) and sprites[sprite_key]:
		sprites[sprite_key].visible = true


func play_animation(anim_name: String, speed: float = 1.0) -> void:
	if animation_player and animation_player.current_animation != anim_name:
		animation_player.play(anim_name, -1, speed)


func trigger_particles(key: String, flip_x: float = 1.0) -> void:
	if particles.has(key) and particles[key]:
		particles[key].scale.x = flip_x
		particles[key].restart()


func get_animation_player() -> AnimationPlayer:
	return animation_player
