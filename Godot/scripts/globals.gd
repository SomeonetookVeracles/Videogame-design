# Enables global logging for debugging
extends Node

var enable_logging = true

func log(message: String) -> void:
	if enable_logging:
		print(message)
