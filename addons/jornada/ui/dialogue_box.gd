class_name DialogueBox
extends CanvasLayer
## Caja de diálogo inferior con placa de nombre, texto que se va escribiendo y opciones.
## Espacio/Enter avanza (o completa el texto si aún se está escribiendo), 1-9 elige una
## opción (canon 09 §12). E también avanza; eso lo procesa el jugador.

const COLOR_OPTION: Color = Color(1.0, 0.804, 0.612)
## Retratos de 64x64 (addons/jornada/tools/pixel/figures.py), a la izquierda de la caja. Los objetos examinables no tienen.
const PORTRAIT_PATH: String = "res://assets/generated_assets/portraits/%s.png"
const COLOR_OPTION_HOVER: Color = Color(0.945, 0.98, 0.933)

@onready var _box: Control = $Box
@onready var _speaker: Label = $Box/PlateRow/NamePlate/SpeakerLabel
@onready var _text: Label = $Box/Panel/VBox/TextLabel
@onready var _stage: Label = $Box/Panel/VBox/StageLabel
@onready var _options: VBoxContainer = $Box/Panel/VBox/Options
@onready var _arrow: TextureRect = $Box/Panel/VBox/ArrowRow/Arrow

var _portrait: TextureRect
var _reveal: Tween
var _pending_stage: String = ""
var _pending_has_options: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box.visible = false
	_portrait = _make_portrait()
	DialogueManager.dialogue_started.connect(_on_started)
	DialogueManager.line_shown.connect(_on_line)
	DialogueManager.dialogue_ended.connect(_on_ended)
	DialogueManager.skip_typing_requested.connect(_finish_reveal)


func _exit_tree() -> void:
	DialogueManager.dialogue_started.disconnect(_on_started)
	DialogueManager.line_shown.disconnect(_on_line)
	DialogueManager.dialogue_ended.disconnect(_on_ended)
	DialogueManager.skip_typing_requested.disconnect(_finish_reveal)


func _process(_delta: float) -> void:
	if _arrow.visible:
		# Parpadeo de la flecha "continuar".
		_arrow.modulate.a = 1.0 if int(Time.get_ticks_msec() / 350) % 2 == 0 else 0.25


func _unhandled_input(event: InputEvent) -> void:
	if not DialogueManager.is_active:
		return
	if DialogueManager.has_options and not DialogueManager.text_revealing:
		var key := event as InputEventKey
		if key != null and key.pressed and not key.echo:
			var number: int = key.keycode - KEY_1
			if number >= 0 and number < _options.get_child_count():
				DialogueManager.choose(number)
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		DialogueManager.advance()
		get_viewport().set_input_as_handled()


func _on_started(npc_id: String) -> void:
	_box.visible = true
	var path: String = PORTRAIT_PATH % npc_id
	_portrait.texture = load(path) if ResourceLoader.exists(path) else null
	_portrait.visible = _portrait.texture != null


## Mismo anclaje que la caja (abajo al centro), pegado a su borde izquierdo y apoyado en su base.
func _make_portrait() -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "Portrait"
	rect.anchor_left = 0.5
	rect.anchor_right = 0.5
	rect.anchor_top = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = _box.offset_left - 70.0
	rect.offset_right = _box.offset_left - 6.0
	rect.offset_top = _box.offset_bottom - 64.0
	rect.offset_bottom = _box.offset_bottom
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.visible = false
	add_child(rect)
	return rect


func _on_line(speaker: String, text: String, stage_direction: String, options: Array, _has_next: bool) -> void:
	_speaker.text = speaker
	_text.text = text
	_pending_stage = stage_direction
	_pending_has_options = not options.is_empty()
	_build_options(options)
	_stage.visible = false
	_options.visible = false
	_arrow.visible = false
	if _reveal != null:
		_reveal.kill()
	_text.visible_ratio = 0.0
	AudioManager.play_sfx("dialogue_blip", -8.0, 0.05)
	DialogueManager.text_revealing = true
	_reveal = create_tween()
	_reveal.tween_property(_text, "visible_ratio", 1.0, maxf(0.05, text.length() / SettingsManager.text_chars_per_second()))
	_reveal.finished.connect(_finish_reveal)


func _finish_reveal() -> void:
	if _reveal != null:
		_reveal.kill()
	_text.visible_ratio = 1.0
	DialogueManager.text_revealing = false
	_stage.text = _pending_stage
	_stage.visible = _pending_stage != ""
	_options.visible = _pending_has_options
	_arrow.visible = not _pending_has_options


func _build_options(options: Array) -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	for i in options.size():
		var row := Label.new()
		row.text = "%d. %s" % [i + 1, options[i]]
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.add_theme_color_override("font_color", COLOR_OPTION)
		row.mouse_entered.connect(row.add_theme_color_override.bind("font_color", COLOR_OPTION_HOVER))
		row.mouse_exited.connect(row.add_theme_color_override.bind("font_color", COLOR_OPTION))
		row.gui_input.connect(_on_option_gui_input.bind(i))
		_options.add_child(row)


func _on_option_gui_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not DialogueManager.text_revealing:
		DialogueManager.choose(index)


func _on_ended(_npc_id: String) -> void:
	if _reveal != null:
		_reveal.kill()
	DialogueManager.text_revealing = false
	_box.visible = false
	_portrait.visible = false
