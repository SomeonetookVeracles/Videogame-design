extends Area2D
func _on_body_entered(body):
	if body.has_method("_on_death_zone_entered"):
		body._on_death_zone_entered()
