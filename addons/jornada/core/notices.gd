extends Node
## Carteles que frenan el juego cuando pasa algo nuevo que el jugador tiene que notar (data/game.json "notices"):
##   {"flag": <flag>, "loop_max": <opcional>, "title": <clave>, "text": <clave>, "button": <clave>}
## Al ganar el flag se pone en cola y se abre apenas termina la charla en curso (nunca encima de un diálogo). Mientras el
## cartel está abierto el juego queda en pausa: leerlo no gasta tiempo de juego.

signal opened(flag: String)

## Falso: no abre carteles (las pruebas lo apagan: un cartel pausa el juego en medio de lo que se está probando).
var enabled: bool = true
var _notices: Array = []
var _pending: Array = []
var _card: NoticeCard = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_notices = GameConfig.value("notices", [])
	if _notices.is_empty():
		set_process(false)
		return
	LoopManager.knowledge_gained.connect(_on_knowledge_gained)
	LoopManager.loop_started.connect(func(_n: int) -> void: _clear())
	LoopManager.game_reset.connect(_clear)
	DialogueManager.dialogue_ended.connect(func(_id: String) -> void: _try_open())


## ¿Hay un cartel abierto o esperando su turno? (quien arranca algo después, como EscortSystem, espera a que no haya)
func is_busy() -> bool:
	return is_instance_valid(_card) or not _pending.is_empty()


## Empieza otro loop o una partida nueva: lo que esperaba o estaba abierto ya no corresponde.
func _clear() -> void:
	_pending.clear()
	if is_instance_valid(_card):
		_card.queue_free()
		get_tree().paused = false
	_card = null


func _on_knowledge_gained(flag: String) -> void:
	if not enabled:
		return
	for notice: Dictionary in _notices:
		if str(notice.get("flag", "")) != flag:
			continue
		if notice.has("loop_max") and LoopManager.loop_number > int(notice["loop_max"]):
			continue
		_pending.append(notice)
	_try_open()


func _process(_delta: float) -> void:
	if not _pending.is_empty():
		_try_open()


func _try_open() -> void:
	if _pending.is_empty() or is_instance_valid(_card) or DialogueManager.is_active or ZoneManager.player == null:
		return
	if get_tree().paused:
		return   # el diario, la pausa u otra pantalla: espera a que se cierre
	var notice: Dictionary = _pending.pop_front()
	_card = NoticeCard.new()
	_card.closed.connect(func() -> void: _card = null)
	get_tree().root.add_child(_card)
	_card.setup(str(notice["title"]), str(notice["text"]), str(notice.get("button", "notice_ok")))
	opened.emit(str(notice["flag"]))
