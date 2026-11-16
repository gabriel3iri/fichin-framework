extends Control
## Guía del diario (Journal._guide): oscurece todo menos lo que se explica, lo enmarca y lo señala con una flecha desde un
## cartel. Va paso a paso: E, Enter o clic sigue; Esc o J la salta entera. Al terminar emite `finished` y se borra.
## Cada paso: {"text": String, "before": Callable (opcional: cambia de pestaña, elige una fila...), "target": Callable
## que devuelve el Rect2 global a señalar (vacío = el cartel en el medio, sin flecha)}.

signal finished

const SHADE: Color = Color(0, 0, 0, 0.62)
const PAD: float = 3.0
const GAP: float = 14.0   # entre lo señalado y el cartel: ahí va la flecha
const BOX_WIDTH: float = 300.0
const MARGIN: float = 8.0
const ARROW_HALF: float = 6.0

enum Side { NONE, BELOW, ABOVE, RIGHT, LEFT }

var _steps: Array[Dictionary] = []
var _at: int = -1
var _busy: bool = false
var _rect: Rect2 = Rect2()
var _side: int = Side.NONE
var _time: float = 0.0
var _box: PanelContainer
var _text: Label
var _hint: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", UiStyle.panel(true))
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	add_child(_box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(column)
	_text = UiStyle.label("", UiStyle.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(BOX_WIDTH - 16.0, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_text)
	_hint = UiStyle.label("", UiStyle.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_hint)


func start(steps: Array[Dictionary]) -> void:
	_steps = steps
	_at = -1
	next()


func is_last() -> bool:
	return _at >= _steps.size() - 1


## El paso siguiente (o terminar). Mientras se arma uno (espera a que se acomode la pestaña), no se saltea otro.
func next() -> void:
	if _busy:
		return
	_at += 1
	if _at >= _steps.size():
		finish()
		return
	_busy = true
	var step: Dictionary = _steps[_at]
	_box.visible = false
	_rect = Rect2()
	queue_redraw()
	var before: Callable = step.get("before", Callable())
	if before.is_valid():
		before.call()
	# La pestaña nueva se acomoda en un par de cuadros: recién ahí se sabe dónde quedó lo que se señala.
	for i in 3:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var target: Callable = step.get("target", Callable())
	_rect = target.call() if target.is_valid() else Rect2()
	if _rect.has_area():
		_rect = _rect.grow(PAD)
	_text.text = step.get("text", "")
	_hint.text = tr("ui_journal_guide_done" if is_last() else "ui_journal_guide_next")
	_box.visible = true
	_box.reset_size()
	_place_box()
	_time = 0.0
	queue_redraw()
	_busy = false


func finish() -> void:
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	if _rect.has_area():
		queue_redraw()


## El cartel va abajo de lo señalado si entra; si no, arriba, al costado o, sin nada que señalar, en el medio.
func _place_box() -> void:
	var view: Vector2 = get_viewport_rect().size
	var box: Vector2 = _box.get_combined_minimum_size()
	_box.size = box
	if not _rect.has_area():
		_side = Side.NONE
		_box.position = ((view - box) / 2.0).round()
		return
	var x: float = clampf(_rect.get_center().x - box.x / 2.0, MARGIN, view.x - MARGIN - box.x)
	if _rect.end.y + GAP + box.y <= view.y - MARGIN:
		_side = Side.BELOW
		_box.position = Vector2(x, _rect.end.y + GAP)
	elif _rect.position.y - GAP - box.y >= MARGIN:
		_side = Side.ABOVE
		_box.position = Vector2(x, _rect.position.y - GAP - box.y)
	else:
		var y: float = clampf(_rect.get_center().y - box.y / 2.0, MARGIN, view.y - MARGIN - box.y)
		if _rect.end.x + GAP + box.x <= view.x - MARGIN:
			_side = Side.RIGHT
			_box.position = Vector2(_rect.end.x + GAP, y)
		else:
			_side = Side.LEFT
			_box.position = Vector2(maxf(MARGIN, _rect.position.x - GAP - box.x), y)
	_box.position = _box.position.round()


func _draw() -> void:
	var view: Vector2 = get_viewport_rect().size
	if not _rect.has_area():
		draw_rect(Rect2(Vector2.ZERO, view), Color(SHADE, 0.4))   # sin nada que señalar: el diario se sigue viendo
		return
	# Todo oscuro menos lo que se explica.
	var r: Rect2 = _rect
	draw_rect(Rect2(0, 0, view.x, r.position.y), SHADE)
	draw_rect(Rect2(0, r.end.y, view.x, view.y - r.end.y), SHADE)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), SHADE)
	draw_rect(Rect2(r.end.x, r.position.y, view.x - r.end.x, r.size.y), SHADE)
	var pulse: float = 0.6 + 0.4 * sin(_time * 5.0)
	draw_rect(r, Color(UiStyle.ACCENT, pulse), false, 2.0)
	if not _box.visible:
		return
	# La flecha, del cartel a lo señalado, con un vaivén.
	var bob: float = round(2.0 * sin(_time * 6.0))
	var b: Rect2 = Rect2(_box.position, _box.size)
	var tip: Vector2
	var base: Vector2
	var across: Vector2
	match _side:
		Side.BELOW:
			var ax: float = clampf(r.get_center().x, b.position.x + 12.0, b.end.x - 12.0)
			tip = Vector2(ax, r.end.y + 2.0 + bob)
			base = Vector2(ax, b.position.y)
			across = Vector2(ARROW_HALF, 0)
		Side.ABOVE:
			var ax: float = clampf(r.get_center().x, b.position.x + 12.0, b.end.x - 12.0)
			tip = Vector2(ax, r.position.y - 2.0 - bob)
			base = Vector2(ax, b.end.y)
			across = Vector2(ARROW_HALF, 0)
		Side.RIGHT:
			var ay: float = clampf(r.get_center().y, b.position.y + 10.0, b.end.y - 10.0)
			tip = Vector2(r.end.x + 2.0 + bob, ay)
			base = Vector2(b.position.x, ay)
			across = Vector2(0, ARROW_HALF)
		Side.LEFT:
			var ay: float = clampf(r.get_center().y, b.position.y + 10.0, b.end.y - 10.0)
			tip = Vector2(r.position.x - 2.0 - bob, ay)
			base = Vector2(b.end.x, ay)
			across = Vector2(0, ARROW_HALF)
		_:
			return
	var points := PackedVector2Array([base - across, tip, base + across])
	draw_colored_polygon(points, UiStyle.ACCENT)
	draw_polyline(PackedVector2Array([base - across, tip, base + across]), UiStyle.INK, 1.0)
