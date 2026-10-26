class_name IntroCard
extends CanvasLayer
## Al empezar una partida nueva (primera jornada, a la hora de inicio): quién es el personaje y qué vino a hacer, sobre
## negro, antes de despertar. Los textos salen de data/game.json "intro" (title, lines, continue). El juego queda en
## pausa mientras se lee; se sigue solo con el botón [Continuar], que aparece cuando terminó de mostrarse el texto (no
## se cierra sin querer con una tecla suelta). Un clic (o E) apura: termina el párrafo que está apareciendo y pasa al
## siguiente.

## Cada párrafo tarda PARAGRAPH_FADE en aparecer y espera PARAGRAPH_GAP antes del siguiente; el botón sale al final.
const PARAGRAPH_FADE: float = 1.0
const PARAGRAPH_GAP: float = 1.6

var _black: ColorRect
var _box: VBoxContainer
var _button: Button
var _leaving: bool = false
## El paso que se está mostrando (un párrafo con su pausa, o el botón): un clic lo termina de golpe.
var _step: Tween
## Tras apurar hasta el final, el botón tarda un poco en aceptar clics: así el último clic de la ráfaga no lo aprieta.
const BUTTON_GUARD: float = 0.4

signal finished


func _ready() -> void:
	layer = 98
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_black)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	center.add_child(_box)
	var intro: Dictionary = GameConfig.value("intro", {})
	var title := _line(intro.get("title", ""), UiStyle.ACCENT)
	title.add_theme_font_size_override("font_size", 18)
	_box.add_child(title)
	for key: String in intro.get("lines", []):
		_box.add_child(_line(key, UiStyle.TEXT))
	var row := CenterContainer.new()
	_button = UiStyle.button(tr(intro.get("continue", "intro_continue")), false, true)
	_button.custom_minimum_size = Vector2(150, 0)
	_button.modulate.a = 0.0
	_button.disabled = true
	_button.pressed.connect(_leave)
	row.add_child(_button)
	_box.add_child(row)
	_reveal()


func _line(key: String, color: Color) -> Label:
	var label := UiStyle.label(tr(key), color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(460, 0)
	label.modulate.a = 0.0
	return label


## El texto aparece de a un párrafo, con tiempo para leerlo; al final, el botón para seguir.
func _reveal() -> void:
	var hurried: bool = false
	for child: Node in _box.get_children():
		if child is Label:
			_step = create_tween()
			_step.tween_property(child, "modulate:a", 1.0, PARAGRAPH_FADE)
			_step.tween_interval(PARAGRAPH_GAP)
			await _step.finished
			hurried = hurried or _step.get_meta("hurried", false)
	_step = create_tween()
	_step.tween_property(_button, "modulate:a", 1.0, 0.6)
	await _step.finished
	if hurried or _step.get_meta("hurried", false):
		await get_tree().create_timer(BUTTON_GUARD, true, false, true).timeout
	_step = null
	_button.disabled = false
	_button.grab_focus()


## Termina de golpe el paso que se está mostrando.
func hurry() -> void:
	if _step != null and _step.is_running():
		_step.set_meta("hurried", true)
		_step.custom_step(60.0)


func _input(event: InputEvent) -> void:
	if not _button.disabled or _leaving:
		return   # el texto ya está entero: los clics son para el botón
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if click or (event.is_action_pressed("interact") and not event.is_echo()):
		hurry()
		get_viewport().set_input_as_handled()


func _unhandled_input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()   # mientras se lee no se mueve nadie ni se abre la pausa


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	var tween := create_tween()
	tween.tween_property(_box, "modulate:a", 0.0, 0.5)
	tween.tween_property(_black, "modulate:a", 0.0, 1.2)
	await tween.finished
	get_tree().paused = false
	finished.emit()
	queue_free()
