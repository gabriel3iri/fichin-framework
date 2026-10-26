class_name DeductionScreen
extends CanvasLayer
## Pantalla de deducción (canon 09 §7): el juego se detiene, los bordes se oscurecen y las piezas
## se conectan en el centro. Sin voz y sin música nueva; solo el sonido de un sello.

## Lo consulta el diario para no abrirse mientras la deducción está en pantalla.
static var is_playing: bool = false

const VIGNETTE_SHADER: String = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(1.0, 0.8);
	float edge = smoothstep(0.18, 0.62, length(p));
	COLOR = vec4(0.0, 0.0, 0.03, (0.35 + 0.55 * edge) * strength);
}
"""
const MIN_HOLD: float = 0.9
const PIECE_SIZE: Vector2 = Vector2(184, 22)

var _queue: Array[String] = []
var _root: Control
var _board: Control
var _vignette: ColorRect
var _can_continue: bool = false
var _line_progress: Array[float] = []
var _from_points: Array[Vector2] = []
var _to_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 85
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	DeductionSystem.deduction_made.connect(func(id: String) -> void: _queue.append(id))


func _exit_tree() -> void:
	is_playing = false


func _process(_delta: float) -> void:
	if is_playing or _queue.is_empty():
		return
	# Espera a que termine el diálogo o el minijuego que dio la última pieza.
	if GameManager.state != GameManager.State.PLAYING or DialogueManager.is_active or WorkManager.active_task != "":
		return
	_play(_queue.pop_front())


func _input(event: InputEvent) -> void:
	if not is_playing:
		return
	get_viewport().set_input_as_handled()
	if _can_continue and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed)):
		_can_continue = false
		_finish()


func _play(deduction_id: String) -> void:
	is_playing = true
	GameManager.pause_game()
	var def: Dictionary = {}
	for candidate: Dictionary in DeductionSystem.definitions():
		if candidate["id"] == deduction_id:
			def = candidate
	var parts: Dictionary = DeductionSystem.pieces(def)
	var flags: Array[String] = []
	flags.assign(parts["met"])
	if not (parts["any_met"] as Array).is_empty():
		flags.append(parts["any_met"][0])
	_build_board(def, flags)

	_root.visible = true
	_root.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_property(_vignette.material, "shader_parameter/strength", 1.0, 0.5)
	for i in flags.size():
		var piece: Control = _board.get_child(i)
		tween.tween_property(piece, "modulate:a", 1.0, 0.18)
		tween.parallel().tween_property(piece, "position:x", piece.position.x, 0.18).from(piece.position.x - 18.0)
		tween.tween_interval(0.12)
	for i in _line_progress.size():
		tween.tween_method(_set_line.bind(i), 0.0, 1.0, 0.35)
	tween.tween_callback(_stamp.bind(def))
	tween.tween_interval(MIN_HOLD)
	tween.tween_callback(func() -> void: _can_continue = true)


func _build_board(def: Dictionary, flags: Array[String]) -> void:
	if _board != null:
		_board.queue_free()
	_vignette = ColorRect.new()
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("strength", 0.0)
	_vignette.material = material
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)

	_board = Control.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.draw.connect(_draw_lines)
	_root.add_child(_board)

	_from_points.clear()
	_line_progress.clear()
	var count: int = flags.size()
	var top: float = 180.0 - (count * (PIECE_SIZE.y + 14.0) - 14.0) / 2.0
	for i in count:
		var piece := PanelContainer.new()
		piece.add_theme_stylebox_override("panel", UiStyle.panel(true))
		piece.custom_minimum_size = PIECE_SIZE
		piece.position = Vector2(52.0, top + i * (PIECE_SIZE.y + 14.0))
		piece.modulate.a = 0.0
		var label := UiStyle.label(tr("flag_" + flags[i]), UiStyle.TEXT)
		label.clip_text = true
		piece.add_child(label)
		_board.add_child(piece)
		_from_points.append(piece.position + Vector2(PIECE_SIZE.x, PIECE_SIZE.y / 2.0))
		_line_progress.append(0.0)
	_to_point = Vector2(388.0, 180.0)

	var result := PanelContainer.new()
	result.name = "Result"
	result.add_theme_stylebox_override("panel", UiStyle.panel())
	result.custom_minimum_size = Vector2(190, 50)
	result.position = Vector2(388.0, 180.0 - 25.0)
	result.pivot_offset = Vector2(95, 25)
	result.modulate.a = 0.0
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var stamp := UiStyle.label(tr("ui_deduction_stamp"), UiStyle.BAD)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var name_label := UiStyle.label(tr("flag_" + def["id"]), UiStyle.ACCENT)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(174, 0)
	box.add_child(stamp)
	box.add_child(name_label)
	result.add_child(box)
	_board.add_child(result)
	var hint := UiStyle.label(tr("ui_deduction_continue"), UiStyle.DIM)
	hint.name = "Hint"
	hint.modulate.a = 0.0
	hint.position = Vector2(236.0, 326.0)
	_board.add_child(hint)


func _set_line(value: float, index: int) -> void:
	_line_progress[index] = value
	_board.queue_redraw()


func _draw_lines() -> void:
	for i in _from_points.size():
		var from: Vector2 = _from_points[i]
		var end: Vector2 = from.lerp(_to_point, _line_progress[i])
		_board.draw_line(from.round(), end.round(), UiStyle.ACCENT, 1.0)


func _stamp(_def: Dictionary) -> void:
	AudioManager.play_sfx("medallion_activate", -2.0)
	var result: Control = _board.get_node("Result")
	var tween: Tween = create_tween()
	tween.tween_property(result, "modulate:a", 1.0, 0.05)
	tween.parallel().tween_property(result, "scale", Vector2.ONE, 0.14).from(Vector2(1.5, 1.5))
	tween.tween_property(_board.get_node("Hint"), "modulate:a", 1.0, 0.4).set_delay(MIN_HOLD)


func _finish() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		_root.visible = false
		for child in _root.get_children():
			child.queue_free()
		_board = null
		is_playing = false
		GameManager.resume_game())
