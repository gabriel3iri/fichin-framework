class_name EdgeExit
extends Area2D
## Franja en el borde de una zona exterior (de unos px adentro a bastante afuera del mapa): al pisarla, la pantalla se
## desliza a la zona vecina. Mientras el jugador esté adentro se reintenta cada cuadro: si en ese momento había otra
## transición en curso (ZoneManager._busy), antes se perdía el pedido y el jugador seguía de largo fuera del mapa.

@export var target_zone: String = ""


func _physics_process(_delta: float) -> void:
	if ZoneManager.current_zone == "" or ZoneManager.get("_busy"):
		return
	for body: Node2D in get_overlapping_bodies():
		if body is PlayerController:
			ZoneManager.walk_through(target_zone)
			return
