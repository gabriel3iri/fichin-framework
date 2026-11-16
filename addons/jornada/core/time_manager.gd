extends Node
## Reloj del loop. Cada segundo real = TIME_SCALE minutos de juego.
## A velocidad normal (60x), un minuto de juego dura un segundo real.

signal minute_changed(hour: int, minute: int)
signal loop_end_reached

## Comienzo y fin de la jornada (data/game.json, "day").
var day_start: int = GameConfig.day_start()
var day_end: int = GameConfig.day_end()
## Minutos de juego por segundo real (60x = 1.0). El jugador puede elegir 40x/60x/80x (Opciones).
var time_scale: float = 1.0

## Fin de la jornada de hoy: el de data/game.json, salvo que el juego lo corra (un final que llega más tarde).
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


## Saltos del reloj (advance_minutes: una tarea, la G, una prueba): quien camina no recupera ese rato de golpe.
var jumps: int = 0
## Verdadero mientras se avisa el minuto de un salto (no el del paso normal del reloj).
var jumping: bool = false


## Salta `amount` minutos de juego (trabajo, esperas). Respeta el fin del loop.
func advance_minutes(amount: int) -> void:
	jumps += 1
	minutes += amount
	if int(minutes) != _last_minute:
		_last_minute = int(minutes)
		jumping = true
		minute_changed.emit(hour, minute)
		jumping = false
	if minutes >= loop_end:
		minutes = loop_end
		running = false
		loop_end_reached.emit()


func start() -> void:
	# Charla, diario u orden de trabajo sostienen el reloj: no se puede forzar a correr.
	if GameManager.day_clock_held():
		running = false
		return
	running = true


func pause() -> void:
	running = false


## Cómo avanza el mundo (día de la marmota): con el reloj andando, todo sale de él (lo que camina cada uno, cuándo
## habla, cuánto dura un globo), no de lo que tarda cada cuadro; con el reloj frenado por una charla, el diario o la
## orden, queda quieto; frenado por otra cosa (el final del día, una prueba), en tiempo real.
enum World { CLOCK, HELD, FREE }


func world() -> World:
	if running:
		return World.CLOCK
	return World.HELD if GameManager.day_clock_held() else World.FREE


## Segundos de juego entre dos horas del reloj (`since` -> ahora); 0 si el reloj volvió atrás.
func seconds_since(since: float) -> float:
	return maxf(0.0, minutes - since) / maxf(time_scale, 0.001)


## Vuelve al principio de la jornada. No avisa minute_changed en el acto: el aviso llega en el primer cuadro (con
## _last_minute = -1), cuando ya está el mundo nuevo. Avisarlo acá lo recibía el mundo viejo (al cargar una partida,
## el diario anotaba lo que «veía» a las 06:00 en la zona de la que se venía).
func reset() -> void:
	minutes = day_start
	loop_end = day_end
	_last_minute = -1


## Una jornada especial con otro horario (LoopManager.special_day): empieza en `start` y termina en `end`.
func set_window(start_minutes: int, end_minutes: int) -> void:
	minutes = start_minutes
	loop_end = end_minutes
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
