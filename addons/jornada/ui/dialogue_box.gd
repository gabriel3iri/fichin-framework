class_name DialogueBox
extends CanvasLayer
## Caja de diálogo inferior con placa de nombre, texto que se va escribiendo y opciones.
## Espacio/Enter avanza (o completa el texto si aún se está escribiendo), 1-9 elige una
## opción (canon 09 §12). E también avanza; eso lo procesa el jugador.

const COLOR_OPTION: Color = Color(1.0, 0.804, 0.612)
## Retratos (addons/jornada/tools/pixel/portrait.py), a la izquierda de la caja y del tamaño de su imagen (96x96 en
## Rabenholz, 64x64 en el juego de ejemplo). Los objetos examinables no tienen.
const PORTRAIT_PATH: String = "res://assets/generated_assets/portraits/%s.png"
const COLOR_OPTION_HOVER: Color = Color(0.945, 0.98, 0.933)
## Opacidad de una opción ya usada (DialogueManager.option_used).
const USED_ALPHA: float = 0.5

@onready var _box: Control = $Box
@onready var _speaker: Label = $Box/PlateRow/NamePlate/SpeakerLabel
@onready var _text: RichTextLabel = $Box/Panel/VBox/TextLabel
@onready var _stage: Label = $Box/Panel/VBox/StageLabel
@onready var _options: VBoxContainer = $Box/Panel/VBox/Options
@onready var _arrow: TextureRect = $Box/Panel/VBox/ArrowRow/Arrow

var _portrait: TextureRect
var _trust_bar: TrustBar
var _person: String = ""
var _reveal: Tween
var _pending_stage: String = ""
var _pending_has_options: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box.visible = false
	_portrait = _make_portrait()
	_trust_bar = TrustBar.new()
	_trust_bar.name = "TrustBar"
	_trust_bar.anchor_left = 0.5
	_trust_bar.anchor_right = 0.5
	_trust_bar.anchor_top = 1.0
	_trust_bar.anchor_bottom = 1.0
	_trust_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trust_bar.visible = false
	add_child(_trust_bar)
	Trust.changed.connect(_on_trust_changed)
	DialogueManager.dialogue_started.connect(_on_started)
	DialogueManager.line_shown.connect(_on_line)
	DialogueManager.dialogue_ended.connect(_on_ended)
	DialogueManager.skip_typing_requested.connect(_finish_reveal)


func _exit_tree() -> void:
	DialogueManager.dialogue_started.disconnect(_on_started)
	DialogueManager.line_shown.disconnect(_on_line)
	DialogueManager.dialogue_ended.disconnect(_on_ended)
	DialogueManager.skip_typing_requested.disconnect(_finish_reveal)
	Trust.changed.disconnect(_on_trust_changed)


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
	if _portrait.texture != null:
		_place_portrait(_portrait.texture.get_size())
	_person = JournalManager.person_for_dialogue(npc_id)
	_trust_bar.visible = Trust.enabled and _person != "" and _portrait.visible
	if _trust_bar.visible:
		_trust_bar.low = Trust.min_level
		_trust_bar.high = Trust.max_level
		_trust_bar.set_level(Trust.level(_person))


func _on_trust_changed(person: String, level: int, _delta: int) -> void:
	if person == _person:
		_trust_bar.set_level(level)


## Mismo anclaje que la caja (abajo al centro), pegado a su borde izquierdo y apoyado en su base.
func _make_portrait() -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "Portrait"
	rect.anchor_left = 0.5
	rect.anchor_right = 0.5
	rect.anchor_top = 1.0
	rect.anchor_bottom = 1.0
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.visible = false
	add_child(rect)
	return rect


func _place_portrait(size: Vector2) -> void:
	_portrait.offset_left = _box.offset_left - size.x - 6.0
	_portrait.offset_right = _box.offset_left - 6.0
	_portrait.offset_top = _box.offset_bottom - size.y
	_portrait.offset_bottom = _box.offset_bottom
	# La barra de confianza, dentro del cuadro del retrato, sobre su borde de abajo.
	_trust_bar.offset_left = _portrait.offset_left + 4.0
	_trust_bar.offset_right = _portrait.offset_right - 4.0
	_trust_bar.offset_top = _portrait.offset_bottom - 9.0
	_trust_bar.offset_bottom = _portrait.offset_bottom - 4.0


func _on_line(speaker: String, text: String, stage_direction: String, options: Array, _has_next: bool) -> void:
	_speaker.text = speaker
	# Los nombres de la gente, de otro color: el técnico los anota (Identification.hear_text, en DialogueManager).
	_text.text = Identification.mark_names(text.replace("[", "[lb]"),
			"[color=#%s]" % UiStyle.DIALOGUE_NAME.to_html(false), "[/color]")
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
	_reveal.tween_property(_text, "visible_ratio", 1.0, maxf(0.05, _text.get_parsed_text().length() / SettingsManager.text_chars_per_second()))
	_reveal.finished.connect(_finish_reveal)


func _finish_reveal() -> void:
	if _reveal != null:
		_reveal.kill()
	_text.visible_ratio = 1.0
	DialogueManager.text_revealing = false
	if DialogueManager.line_discovers:
		DialogueManager.line_discovers = false   # suena una vez por línea, aunque se adelante el texto
		AudioManager.play_sfx("knowledge_gained", -4.0)
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
		if DialogueManager.option_used(i):
			row.modulate.a = USED_ALPHA   # ya la eligió hoy o ya sabe lo que contesta: sigue ahí, más tenue
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
	_trust_bar.visible = false
	_person = ""


## Confianza de quien habla (Trust): una barra que se llena según el nivel, roja en el mínimo, amarilla en 0 y verde en el
## máximo, con una marca por nivel.
class TrustBar extends Control:
	const RED: Color = Color(0.78, 0.22, 0.16)
	const YELLOW: Color = Color(0.88, 0.72, 0.2)
	const GREEN: Color = Color(0.32, 0.68, 0.26)
	var level: int = 0
	var low: int = -2
	var high: int = 3

	func set_level(value: int) -> void:
		level = value
		queue_redraw()

	func color_for(value: int) -> Color:
		if value <= 0:
			return RED.lerp(YELLOW, float(value - low) / float(maxi(1, -low)))
		return YELLOW.lerp(GREEN, float(value) / float(maxi(1, high)))

	func _draw() -> void:
		var steps: int = high - low + 1
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.06, 0.85))
		var inner: Rect2 = Rect2(Vector2.ONE, size - Vector2(2.0, 2.0))
		var filled: Rect2 = inner
		filled.size.x = roundf(inner.size.x * float(level - low + 1) / float(steps))
		draw_rect(filled, color_for(level))
		for i in range(1, steps):
			var x: float = roundf(inner.position.x + inner.size.x * i / steps)
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0.0, 0.0, 0.0, 0.35))
