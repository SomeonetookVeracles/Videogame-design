extends Node
@export var master_bus_name: String
@export var sfx_bus_name: String
@export var music_bus_name: String
var master_bus_id
var sfx_bus_id
var music_bus_id
func _ready():
	master_bus_id = AudioServer.get_bus_index("Master")
	sfx_bus_id = AudioServer.get_bus_index("SFX")
	music_bus_id = AudioServer.get_bus_index("Music")
func _on_master_control_value_changed(value: float) -> void:
	print(value)
	var Mdb = linear_to_db(value)
	AudioServer.set_bus_volume_db(master_bus_id, Mdb)
func _on_sfx_control_value_changed(value: float) -> void:
	print(value)
	var Sdb = linear_to_db(value)
	AudioServer.set_bus_volume_db(sfx_bus_id, Sdb)
func _on_music_control_value_changed(value: float) -> void:
	print(value)
	var MUdb = linear_to_db(value)
	AudioServer.set_bus_volume_db(music_bus_id, MUdb)
