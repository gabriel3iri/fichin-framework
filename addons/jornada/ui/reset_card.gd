class_name ResetCard
extends CanvasLayer
## Pantalla de reset entre loops (canon 07 §9): negro y una línea con el motivo, 4 segundos.
## Sin contador de loops. Desde el loop 5 se añade [Continuar] [No volver a intentarlo].

const FADE_IN: float = 0.9

var _root: Control
var _black: ColorRect
var _label: Label
var _buttons: HBoxContainer
var _choice: int = -1   # 0 = continuar, 1 = no volver a intentarlo

signal chosen


func _ready() -> void:
	layer = 97
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.modulate.a = 0.0
	_root.add_child(_black)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_label = UiStyle.label("", UiStyle.TEXT)
	_label.add_theme_font_size_override("font_size", 20)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(440, 0)
	_label.modulate.a = 0.0
	box.add_child(_label)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.modulate.a = 0.0
	box.add_child(_buttons)


## Cuando viene de otra pantalla negra no hay que volver a fundir.
func start_opaque() -> void:
	if _black == null:
		await ready
	_black.modulate.a = 1.0


## Muestra el motivo `hold` segundos. Devuelve true si el jugador eligió "No volver a intentarlo".
func show_reason(key: String, with_choice: bool, hold: float) -> bool:
	if _black == null:
		await ready
	AudioManager.play_sfx("loop_reset", -6.0)
	_label.text = tr(key)
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", 1.0, FADE_IN)
	tween.tween_property(_label, "modulate:a", 1.0, 0.6)
	await tween.finished
	if not with_choice:
		await get_tree().create_timer(hold, true, false, true).timeout
		return false
	await get_tree().create_timer(minf(hold, 2.0), true, false, true).timeout
	var go_on := _button("ui_reset_continue", 0)
	_button("ui_reset_give_up", 1)
	create_tween().tween_property(_buttons, "modulate:a", 1.0, 0.5)
	go_on.grab_focus()
	await chosen
	return _choice == 1


func fade_out() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_label, "modulate:a", 0.0, 0.5)
	tween.tween_property(_buttons, "modulate:a", 0.0, 0.3)
	tween.chain().tween_property(_black, "modulate:a", 0.0, 1.4)
	await tween.finished


func _button(key: String, value: int) -> Button:
	var button := UiStyle.button(tr(key), false, true)
	button.custom_minimum_size = Vector2(150, 0)
	button.pressed.connect(func() -> void:
		_choice = value
		chosen.emit())
	_buttons.add_child(button)
	return button
