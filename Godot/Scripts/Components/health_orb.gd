class_name HealthOrb
extends Node2D

## Visual representation of a single health orb.
## Can be customized with different appearances and effects.

@export_group("Appearance")
@export var orb_color: Color = Color(0.4, 0.8, 1.0, 1.0)
@export var glow_color: Color = Color(0.6, 0.9, 1.0, 0.5)
@export var orb_radius: float = 6.0
@export var glow_radius: float = 10.0

@export_group("Animation")
@export var pulse_enabled: bool = true
@export var pulse_speed: float = 2.0
@export var pulse_amount: float = 0.15
@export var rotation_speed: float = 0.5

var _time: float = 0.0
var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_base_scale = scale
	_create_visuals()


func _process(delta: float) -> void:
	_time += delta
	
	if pulse_enabled:
		var pulse := 1.0 + sin(_time * pulse_speed) * pulse_amount
		scale = _base_scale * pulse
	
	rotation += rotation_speed * delta


func _create_visuals() -> void:
	# Create glow sprite
	var glow := Sprite2D.new()
	glow.name = "Glow"
	glow.texture = _create_gradient_texture(int(glow_radius * 2), glow_color)
	glow.z_index = -1
	add_child(glow)
	
	# Create main orb sprite
	var orb := Sprite2D.new()
	orb.name = "Orb"
	orb.texture = _create_orb_texture(int(orb_radius * 2), orb_color)
	add_child(orb)


func _create_orb_texture(size: int, color: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0 - 1.0
	
	for x in size:
		for y in size:
			var pos := Vector2(x, y)
			var dist := pos.distance_to(center)
			
			if dist <= radius:
				var t := dist / radius
				var alpha := 1.0 - t * 0.3
				var brightness := 1.0 - t * 0.4
				var pixel_color := Color(
					color.r * brightness + 0.3 * (1.0 - t),
					color.g * brightness + 0.3 * (1.0 - t),
					color.b * brightness + 0.3 * (1.0 - t),
					alpha
				)
				image.set_pixel(x, y, pixel_color)
			elif dist <= radius + 1.0:
				var alpha := 1.0 - (dist - radius)
				image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha * 0.5))
	
	return ImageTexture.create_from_image(image)


func _create_gradient_texture(size: int, color: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0
	
	for x in size:
		for y in size:
			var pos := Vector2(x, y)
			var dist := pos.distance_to(center)
			
			if dist <= radius:
				var t := dist / radius
				var alpha := (1.0 - t * t) * color.a
				image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	
	return ImageTexture.create_from_image(image)


func animate_loss() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", _base_scale * 1.5, 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.finished.connect(func(): visible = false; scale = _base_scale; modulate.a = 1.0)


func animate_restore() -> void:
	visible = true
	scale = Vector2.ZERO
	modulate.a = 0.0
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", _base_scale, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
