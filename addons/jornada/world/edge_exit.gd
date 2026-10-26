class_name EdgeExit
extends Area2D
## Franja en el borde de una zona exterior: al pisarla, la pantalla se desliza a la zona vecina.

@export var target_zone: String = ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController:
		ZoneManager.walk_through.call_deferred(target_zone)
