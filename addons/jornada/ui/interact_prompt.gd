class_name InteractPrompt
extends Node2D
## Tecla [E] flotante sobre lo interactuable. Aparece con un fundido corto y rebota 1 px.
## El origen del nodo es el borde inferior-centro del icono.

@onready var _sprite: Sprite2D = $Sprite2D

var _time: float = 0.0
var _tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func set_active(active: bool) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	if active:
		visible = true
		_tween.tween_property(self, "modulate:a", 1.0, 0.1)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, 0.08)
		_tween.tween_callback(func() -> void: visible = false)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	# Rebote en pasos de 1 px para no romper la grilla de píxeles.
	_sprite.position.y = -14.0 - float(int(_time * 3.0) % 2)
