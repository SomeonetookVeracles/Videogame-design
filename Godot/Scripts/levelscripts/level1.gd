extends Node2D
@export_group("FUCK")
@export var player_dash_enabled: bool = true
@export var player_double_jump_enabled: bool = true
@export var player_health_visible: bool = true
@export var player_combat_enabled: bool = true


@onready var player_camera: Camera2D = $"Character/player-camera"
@onready var cutscene_camera: Camera2D = $CSCamera
@onready var camera_area: Area2D = $CSCamera/CameraArea
@onready var scroll: ScrollContainer = $Control/ScrollContainer
@export var scrollspeed := 50.0
@export var exit_duration := 1.0
@export var exit_buffer_time := 2.0

var is_in_camera_zone := false
var is_transitioning := false
var is_exiting := false
var scroller_started := false

var active_tween: Tween
var cutscene_camera_original_position: Vector2
var cutscene_camera_original_zoom: Vector2
var player_camera_zoom: Vector2

var exit_transition_progress := 0.0
var exit_buffer_timer := 0.0

func _ready():
	cutscene_camera_original_position = cutscene_camera.global_position
	cutscene_camera_original_zoom = cutscene_camera.zoom
	player_camera_zoom = player_camera.zoom

	camera_area.body_entered.connect(_on_camera_area_entered)
	camera_area.body_exited.connect(_on_camera_area_exited)

	cutscene_camera.enabled = false
func _process(delta):
	# Exit buffer countdown
	if not is_in_camera_zone and cutscene_camera.enabled and not is_transitioning:
		exit_buffer_timer += delta
		if exit_buffer_timer >= exit_buffer_time:
			start_exit_transition()

	# Handle exit transition
	if is_exiting:
		exit_transition_progress -= delta / exit_duration
		exit_transition_progress = max(exit_transition_progress, 0.0)

		var player_position = $Character.global_position

		cutscene_camera.global_position = cutscene_camera.global_position.lerp(
			player_position,
			1.0 - exit_transition_progress
		)

		cutscene_camera.zoom = cutscene_camera.zoom.lerp(
			player_camera_zoom,
			1.0 - exit_transition_progress
		)

		if exit_transition_progress <= 0.0:
			finish_exit()

func _on_camera_area_entered(body):
	if body.name != "Character":
		return

	is_in_camera_zone = true
	exit_buffer_timer = 0.0

	if not cutscene_camera.enabled and not is_transitioning:
		enter_camera_zone()

func _on_camera_area_exited(body):
	if body.name != "Character":
		return

	is_in_camera_zone = false
	exit_buffer_timer = 0.0

func enter_camera_zone():
	if is_transitioning:
		return

	is_transitioning = true
	is_exiting = false

	if active_tween and active_tween.is_valid():
		active_tween.kill()

	cutscene_camera.global_position = player_camera.global_position
	cutscene_camera.zoom = player_camera_zoom
	cutscene_camera.enabled = true
	player_camera.enabled = false

	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.set_ease(Tween.EASE_IN_OUT)
	active_tween.set_trans(Tween.TRANS_CUBIC)

	active_tween.tween_property(
		cutscene_camera,
		"global_position",
		cutscene_camera_original_position,
		1.2
	)

	active_tween.tween_property(
		cutscene_camera,
		"zoom",
		cutscene_camera_original_zoom,
		1.2
	)

	await active_tween.finished
	is_transitioning = false


func start_exit_transition():
	if is_transitioning or is_exiting:
		return

	is_exiting = true
	is_transitioning = true
	exit_transition_progress = 1.0

func finish_exit():
	is_exiting = false
	is_transitioning = false
	scroller_started = false

	cutscene_camera.enabled = false
	player_camera.enabled = true

	cutscene_camera.global_position = cutscene_camera_original_position
	cutscene_camera.zoom = cutscene_camera_original_zoom
