class_name TowerClock
extends Node2D
## Agujas del reloj de la torre (la esfera está dibujada en el sprite del edificio).
## Se dibujan píxel a píxel para que no queden líneas suavizadas.
## Puede ir adelantado (buildings.json, tercer número de "clock").

const OFFSET_MINUTES: float = 4.0

## Minutos de adelanto de este reloj (buildings.json: tercer número de "clock"; sin él, OFFSET_MINUTES).
var offset_minutes: float = OFFSET_MINUTES
const HOUR_LEN: float = 3.0
const MINUTE_LEN: float = 5.0
const INK: Color = Color("#1F1F1F")


func _ready() -> void:
	TimeManager.minute_changed.connect(queue_redraw.unbind(2))


func _draw() -> void:
	var minutes: float = TimeManager.minutes + offset_minutes
	_hand(fmod(minutes, 60.0) / 60.0 * TAU, MINUTE_LEN)
	_hand(fmod(minutes / 60.0, 12.0) / 12.0 * TAU, HOUR_LEN)
	draw_rect(Rect2(0, 0, 1, 1), INK)


func _hand(angle: float, length: float) -> void:
	var tip := Vector2(sin(angle), -cos(angle)) * length
	var steps: int = int(ceil(length))
	for i in range(1, steps + 1):
		var p: Vector2 = (tip * i / steps).round()
		draw_rect(Rect2(p, Vector2.ONE), INK)
