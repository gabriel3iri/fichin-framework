class_name PocketWatch
extends Control
## Reloj de bolsillo analógico (canon 09: PocketWatchHUD). La esfera es un sprite; las agujas se
## dibujan pixel a pixel (Bresenham) para que queden nítidas. Desde las 17:40 se ponen rojas.

const FACE: Texture2D = preload("res://addons/jornada/ui/skin/ui_watch.png")
const CENTER: Vector2i = Vector2i(18, 22)
const MINUTE_LENGTH: float = 11.0
const HOUR_LENGTH: float = 7.0
const DANGER_FROM: int = 17 * 60 + 40
const COLOR_HANDS: Color = Color(0.122, 0.122, 0.122)
const COLOR_DANGER: Color = Color(0.902, 0.224, 0.275)


func _ready() -> void:
	custom_minimum_size = FACE.get_size()
	TimeManager.minute_changed.connect(_on_minute_changed)


func _exit_tree() -> void:
	TimeManager.minute_changed.disconnect(_on_minute_changed)


func _on_minute_changed(_hour: int, _minute: int) -> void:
	queue_redraw()


func _draw() -> void:
	draw_texture(FACE, Vector2.ZERO)
	var now: int = TimeManager.now_minutes()
	var color: Color = COLOR_DANGER if now >= DANGER_FROM else COLOR_HANDS
	var minute_angle: float = deg_to_rad((now % 60) * 6.0)
	var hour_angle: float = deg_to_rad(((now / 60) % 12 + (now % 60) / 60.0) * 30.0)
	_hand(hour_angle, HOUR_LENGTH, color)
	_hand(minute_angle, MINUTE_LENGTH, color)
	draw_rect(Rect2(CENTER.x - 1, CENTER.y - 1, 2, 2), color)   # eje


func _hand(angle: float, length: float, color: Color) -> void:
	var end := Vector2i(
		CENTER.x + int(round(sin(angle) * length)),
		CENTER.y - int(round(cos(angle) * length)))
	var x0: int = CENTER.x
	var y0: int = CENTER.y
	var dx: int = absi(end.x - x0)
	var dy: int = -absi(end.y - y0)
	var sx: int = 1 if x0 < end.x else -1
	var sy: int = 1 if y0 < end.y else -1
	var err: int = dx + dy
	while true:
		draw_rect(Rect2(x0, y0, 1, 1), color)
		if x0 == end.x and y0 == end.y:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
