extends Node
## Reloj del loop. Cada segundo real = TIME_SCALE minutos de juego.
## Canon 09: el loop va de 06:00 a 17:47 = 707 minutos de juego = 11 min 47 s reales (60x).

signal minute_changed(hour: int, minute: int)
signal loop_end_reached

## Comienzo y fin de la jornada (data/game.json, "day"): en Rabenholz, 06:00 a 17:47.
var day_start: int = GameConfig.day_start()
var day_end: int = GameConfig.day_end()
## Minutos de juego por segundo real (60x = 1.0). El jugador puede elegir 40x/60x/80x (canon 09 §11).
var time_scale: float = 1.0

## Fin del loop de hoy. Normalmente 17:47; si el 409 sale con retraso (fracaso 2e) descarrila a las 17:59.
var loop_end: int = day_end

var minutes: float = day_start
var running: bool = false

var hour: int:
	get: return int(minutes) / 60  # división entera a propósito
var minute: int:
	get: return int(minutes) % 60

var _last_minute: int = -1


func _process(delta: float) -> void:
	if not running:
		return
	minutes += delta * time_scale
	if int(minutes) != _last_minute:
		_last_minute = int(minutes)
		minute_changed.emit(hour, minute)
	if minutes >= loop_end:
		running = false
		loop_end_reached.emit()


## Salta `amount` minutos de juego (trabajo, esperas). Respeta el fin del loop.
func advance_minutes(amount: int) -> void:
	minutes += amount
	if int(minutes) != _last_minute:
		_last_minute = int(minutes)
		minute_changed.emit(hour, minute)
	if minutes >= loop_end:
		minutes = loop_end
		running = false
		loop_end_reached.emit()


func start() -> void:
	running = true


func pause() -> void:
	running = false


## Vuelve al principio de la jornada. No avisa minute_changed en el acto: el aviso llega en el primer cuadro (con
## _last_minute = -1), cuando ya está el mundo nuevo. Avisarlo acá lo recibía el mundo viejo (al cargar una partida,
## el diario anotaba lo que «veía» a las 06:00 en la zona de la que se venía).
func reset() -> void:
	minutes = day_start
	loop_end = day_end
	_last_minute = -1


func get_time_string() -> String:
	return "%02d:%02d" % [hour, minute]


## Minutos desde medianoche (para condiciones de diálogo).
func now_minutes() -> int:
	return int(minutes)


## "16:45" -> 1005
static func parse_clock(text: String) -> int:
	var parts: PackedStringArray = text.split(":")
	return int(parts[0]) * 60 + int(parts[1])


## 1005 -> "16:45"
static func format_clock(total_minutes: int) -> String:
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]
