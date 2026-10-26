class_name Minigame
extends PanelContainer
## Base de los minijuegos de trabajo (Control nodes, 2D). Emiten `finished(success, data)`.
## data: extra_minutes (int), forced/shock/cancelled (bool), toast_key (aviso que se muestra al terminar).
## Esc cancela sin gastar tiempo. Cada juego hace los suyos extendiendo esta clase ("minigame" en data/work.json).

signal finished(success: bool, data: Dictionary)

var task: Dictionary = {}

var _body: VBoxContainer
var _attempts: int = 0
var _closed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(300, 0)
	add_theme_stylebox_override("panel", UiStyle.panel())
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	add_child(_body)
	_body.add_child(UiStyle.label(tr(task["name_key"]), UiStyle.ACCENT))
	_build(_body)
	var hint := UiStyle.label(tr("mg_exit_hint"), UiStyle.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_body.add_child(hint)


## Las subclases arman su interfaz acá.
func _build(_box: VBoxContainer) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_end(false, {"cancelled": true})
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
