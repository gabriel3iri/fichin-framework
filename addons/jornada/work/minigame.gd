class_name Minigame
extends PanelContainer
## Base de los minijuegos de trabajo (Control nodes, 2D). Emiten `finished(success, data)`.
## data: extra_minutes (int), forced/shock/cancelled (bool), toast_key (aviso que se muestra al terminar).
## Esc cancela sin gastar tiempo. Cada juego hace los suyos extendiendo esta clase ("minigame" en data/work.json).
##
## Antes de empezar se muestra un cartel con lo que hay que hacer (`_briefing_key`) y el juego arranca recién cuando
## el jugador aprieta Espacio: así no se lee la consigna mientras el minijuego ya corre. Sin cartel, arranca de una.

signal finished(success: bool, data: Dictionary)

var task: Dictionary = {}

var _body: VBoxContainer
var _attempts: int = 0
var _closed: bool = false
var _started: bool = false
var _briefing: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(300, 0)
	add_theme_stylebox_override("panel", UiStyle.panel())
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	add_child(_body)
	_body.add_child(UiStyle.label(tr(task["name_key"]), UiStyle.ACCENT))
	set_process(false)   # el juego no corre hasta que empieza
	if _briefing_key() == "":
		_start()
	else:
		_show_briefing()


## Clave del CSV con lo que hay que hacer. Las subclases la definen; vacía = sin cartel previo.
func _briefing_key() -> String:
	return ""


## Las subclases arman su interfaz acá (se llama al empezar, no al abrirse).
func _build(_box: VBoxContainer) -> void:
	pass


## Una entrada del jugador ya empezado el juego. Devuelve true si la usó.
func _game_input(_event: InputEvent) -> bool:
	return false


func _show_briefing() -> void:
	_briefing = VBoxContainer.new()
	_briefing.add_theme_constant_override("separation", 6)
	var text := UiStyle.label(tr(_briefing_key()))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(300, 0)
	_briefing.add_child(text)
	var go := UiStyle.button(tr("mg_start"))
	go.pressed.connect(_start)
	_briefing.add_child(go)
	_briefing.add_child(_exit_hint())
	_body.add_child(_briefing)


func _start() -> void:
	if _started:
		return
	_started = true
	if _briefing != null:
		_body.remove_child(_briefing)
		_briefing.queue_free()
		_briefing = null
	_build(_body)
	_body.add_child(_exit_hint())
	set_process(true)


func _exit_hint() -> Label:
	var hint := UiStyle.label(tr("mg_exit_hint"), UiStyle.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return hint


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_end(false, {"cancelled": true})
		get_viewport().set_input_as_handled()
		return
	if not _started:
		var key := event as InputEventKey
		if key != null and key.pressed and not key.echo and (key.keycode == KEY_SPACE or key.keycode == KEY_ENTER):
			_start()
			get_viewport().set_input_as_handled()
		return
	if _game_input(event):
		get_viewport().set_input_as_handled()


func _end(success: bool, data: Dictionary = {}) -> void:
	if _closed:
		return
	_closed = true
	finished.emit(success, data)


func _row(parent: Control, left: Control, right: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.add_child(left)
	if right != null:
		row.add_child(right)
	parent.add_child(row)
	return row
