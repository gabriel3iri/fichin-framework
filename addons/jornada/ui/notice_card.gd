class_name NoticeCard
extends CanvasLayer
## Cartel que frena el juego: un título, un texto y [Entendido]. Mientras está abierto el reloj y el mundo quedan quietos,
## así que leerlo no gasta tiempo. Lo abre Notices (data/game.json "notices"). Se cierra con el botón, con un clic o con E.

## Un E o un clic dentro de este margen después de abrir no cierra el cartel: suele ser el mismo E que cerró la charla.
const GUARD_SECONDS: float = 0.6

signal closed

var _button: Button
var _ready_to_close: bool = false


func setup(title_key: String, text_key: String, button_key: String) -> void:
	layer = 97
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(false))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := UiStyle.label(tr(title_key), UiStyle.ACCENT)
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := UiStyle.label(tr(text_key), UiStyle.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(300, 0)
	box.add_child(body)
	var row := CenterContainer.new()
	_button = UiStyle.button(tr(button_key), false, true)
	_button.custom_minimum_size = Vector2(120, 0)
	_button.disabled = true
	_button.pressed.connect(_close)
	row.add_child(_button)
	box.add_child(row)
	get_tree().paused = true
	await get_tree().create_timer(GUARD_SECONDS, true, false, true).timeout   # sigue corriendo con el juego en pausa
	_ready_to_close = true
	_button.disabled = false
	_button.grab_focus()


func _input(event: InputEvent) -> void:
	if _ready_to_close and event.is_action_pressed("interact") and not event.is_echo():
		_close()
		get_viewport().set_input_as_handled()


func _unhandled_input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()   # mientras se lee no se mueve nadie ni se abre la pausa


func _close() -> void:
	if not _ready_to_close:
		return
	_ready_to_close = false
	get_tree().paused = false
	closed.emit()
	queue_free()
