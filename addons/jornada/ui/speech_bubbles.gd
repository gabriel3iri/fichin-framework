class_name SpeechBubbles
extends Node2D
## Globos de lo que se dice y se piensa sobre las cabezas (barullo, charlas, «estoy ocupado», llamados, discursos y los
## pensamientos del jugador): un recuadro claro, apenas transparente, con borde y una colita que apunta a quien habla.
## Se dibujan en pantalla (una CanvasLayer de ChatterSystem), no en el mundo: así caen siempre en píxeles enteros, con
## cualquier acercamiento de la cámara, y no los tiñe la luz del día.
## Estilos (`style` de `say`):
##   speech    lo común: papel claro, colita de flecha
##   accent    alguien le habla al jugador: papel más cálido; se acomoda antes que el barullo
##   address   alguien recita para un público (un sermón, un discurso): más ancho, doble borde, colita corta
##   thought   lo que piensa el jugador: nube de esquinas redondas, papel azulado y colita de burbujitas
## Cada cuadro se acomodan: primero los de más prioridad, y cada globo prueba su lugar de antes, encima de la cabeza,
## más arriba, corrido de costado (con la colita torcida). Si no entra sin pisar a otro ni salirse de la pantalla, ese
## cuadro no se dibuja (su tiempo sigue corriendo). Quien quiera hablar puede preguntar antes si hay lugar (`has_room`).

const FONT_PATH: String = "res://addons/jornada/ui/skin/font_pixel.tres"
const FONT_SIZE: int = 10
const STYLES: Array[StringName] = [&"speech", &"accent", &"address", &"thought"]
## Prioridad de cada estilo si quien llama no da otra: lo que piensa el jugador primero, después discursos y lo que le
## dicen a él, al final el barullo.
const STYLE_PRIORITY: Dictionary = {&"speech": 0, &"accent": 1, &"address": 2, &"thought": 3}
## Alto mínimo de la colita (entre el borde de abajo y la cabeza).
const TAIL: int = 4
## Distancia mínima a los bordes de la pantalla y entre globos.
const SCREEN_MARGIN: int = 2
const GAP: int = 1
## Cuánto sube un globo por escalón para esquivar a otro, y cuántos escalones prueba.
const LIFT_STEP: int = 6
const LIFT_STEPS: int = 6
## Desvanecido al final (s).
const FADE: float = 0.2

## Ancho máximo del texto (px) de speech/accent; cambia con `barks.json` → settings.bubble_width.
var max_text_width: int = 112
## Los otros estilos, un poco más anchos (un discurso, un pensamiento largo).
var address_text_width: int = 168
var thought_text_width: int = 150
## Opacidad según dónde está quien habla (lejos del jugador, más transparente). La pone ChatterSystem.
var alpha_for: Callable = func(_pos: Vector2) -> float: return 1.0


class Bubble:
	var speaker: Node2D
	var head: Vector2          # punta de la colita, relativa al origen de quien habla
	var text: String
	var style: StringName
	var lines: PackedStringArray
	var size: Vector2i
	var priority: int
	var age: float = 0.0
	var seconds: float
	var serial: int
	var rect: Rect2i
	var tip: Vector2i
	var offset: Vector2i       # lugar elegido el cuadro anterior (relativo a la punta): se prueba primero
	var placed_before: bool = false
	var shown: bool = false
	var alpha: float = 1.0


var _bubbles: Array[Bubble] = []
var _font: Font
var _line_height: int = 10
var _ascent: int = 8
var _serial: int = 0


func _ready() -> void:
	_font = load(FONT_PATH)
	_line_height = mini(int(ceilf(_font.get_height(FONT_SIZE))), FONT_SIZE)   # renglones juntos: la fuente es de 10 px
	_ascent = int(ceilf(_font.get_ascent(FONT_SIZE)))


## Muestra `text` sobre `speaker` durante `seconds` (más el desvanecido). Reemplaza el globo que tuviera.
## `head`: dónde apunta la colita, relativo al origen de quien habla. `priority` < 0 = la del estilo (STYLE_PRIORITY);
## más alta = se acomoda primero.
func say(speaker: Node2D, head: Vector2, text: String, seconds: float, style: StringName = &"speech",
		priority: int = -1) -> void:
	if not style in STYLES:
		push_warning("SpeechBubbles: estilo desconocido '%s'" % style)
		style = &"speech"
	remove(speaker)
	var b := Bubble.new()
	b.speaker = speaker
	b.head = head
	b.text = text
	b.style = style
	b.lines = _wrap(text, _text_width_for(style))
	b.size = _box_size(b.lines, style)
	b.priority = priority if priority >= 0 else int(STYLE_PRIORITY[style])
	b.seconds = maxf(seconds, 0.1)
	_serial += 1
	b.serial = _serial
	_bubbles.append(b)
	_layout()


func remove(speaker: Node2D) -> void:
	for b: Bubble in _bubbles.duplicate():
		if b.speaker == speaker:
			_bubbles.erase(b)
	queue_redraw()


func clear() -> void:
	_bubbles.clear()
	queue_redraw()


## ¿Tiene un globo vivo (aunque este cuadro no haya entrado en pantalla)?
func has_bubble(speaker: Node2D) -> bool:
	return _find(speaker) != null


func text_of(speaker: Node2D) -> String:
	var b: Bubble = _find(speaker)
	return b.text if b != null else ""


func style_of(speaker: Node2D) -> StringName:
	var b: Bubble = _find(speaker)
	return b.style if b != null else &""


## ¿Se ve ahora el globo de `speaker`?
func is_shown(speaker: Node2D) -> bool:
	var b: Bubble = _find(speaker)
	return b != null and b.shown


## Rectángulos (en pantalla) de los globos que se ven: para pruebas.
func shown_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for b: Bubble in _bubbles:
		if b.shown:
			out.append(b.rect)
	return out


func tail_tips() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b: Bubble in _bubbles:
		if b.shown:
			out.append(b.tip)
	return out


## ¿Entraría ahora un globo con `text` sobre `speaker` sin pisar a los que se ven?
func has_room(speaker: Node2D, head: Vector2, text: String, style: StringName = &"speech") -> bool:
	if not speaker.is_visible_in_tree():
		return false
	var probe := Bubble.new()
	probe.speaker = speaker
	probe.head = head
	probe.style = style
	probe.size = _box_size(_wrap(text, _text_width_for(style)), style)
	var taken: Array[Rect2i] = []
	for b: Bubble in _bubbles:
		if b.shown and b.speaker != speaker:
			taken.append_array(_occupied(b))
	return _place(probe, _anchor(probe), taken)


func _process(delta: float) -> void:
	if _bubbles.is_empty():
		return
	for b: Bubble in _bubbles.duplicate():
		b.age += delta
		if b.age >= b.seconds + FADE or not is_instance_valid(b.speaker) or not b.speaker.is_inside_tree():
			_bubbles.erase(b)
	_layout()


func _find(speaker: Node2D) -> Bubble:
	for b: Bubble in _bubbles:
		if b.speaker == speaker:
			return b
	return null


func _anchor(b: Bubble) -> Vector2i:
	var screen: Vector2 = get_viewport().get_canvas_transform() * (b.speaker.global_position + b.head)
	return Vector2i(screen.round())


func _screen() -> Rect2i:
	return Rect2i(Vector2i.ZERO, Vector2i(get_viewport_rect().size))


func _layout() -> void:
	var order: Array[Bubble] = _bubbles.duplicate()
	order.sort_custom(func(a: Bubble, b: Bubble) -> bool:
		return a.priority > b.priority if a.priority != b.priority else a.serial < b.serial)
	var taken: Array[Rect2i] = []
	for b: Bubble in order:
		b.shown = false
		if not b.speaker.is_visible_in_tree():
			continue
		var anchor: Vector2i = _anchor(b)
		if not _screen().has_point(anchor):
			continue
		if _place(b, anchor, taken):
			b.shown = true
			b.offset = b.rect.position - anchor
			b.placed_before = true
			taken.append_array(_occupied(b))
			var fade: float = clampf((b.seconds + FADE - b.age) / FADE, 0.0, 1.0)
			b.alpha = fade if b.style == &"thought" else clampf(float(alpha_for.call(b.speaker.global_position)), 0.0, 1.0) * fade
	queue_redraw()


## Busca dónde va el globo (deja `rect` y `tip`); falso si no entra sin pisar nada de `taken`.
func _place(b: Bubble, anchor: Vector2i, taken: Array[Rect2i]) -> bool:
	var w: int = b.size.x
	var h: int = b.size.y
	var screen: Rect2i = _screen()
	var tail: int = TAIL + (4 if b.style == &"thought" else 0)   # las burbujitas necesitan un poco más de alto
	var base := Vector2i(anchor.x - w / 2, anchor.y - tail - h)
	var candidates: Array[Vector2i] = []
	if b.placed_before:
		candidates.append(anchor + b.offset)
	var shifts: Array[int] = [0, -(w / 2 - 4), w / 2 - 4, -(w / 2 + 10), w / 2 + 10]
	for lift: int in LIFT_STEPS + 1:
		for shift: int in shifts:
			candidates.append(base + Vector2i(shift, -lift * LIFT_STEP))
	for pos: Vector2i in candidates:
		var x: int = clampi(pos.x, screen.position.x + SCREEN_MARGIN, screen.end.x - SCREEN_MARGIN - w)
		var y: int = maxi(pos.y, screen.position.y + SCREEN_MARGIN)
		if y + h + tail > anchor.y + 1:
			continue   # se comería la cabeza (quien habla está pegado al borde de arriba)
		var rect := Rect2i(x, y, w, h)
		if absi(clampi(anchor.x, rect.position.x + 3, rect.end.x - 4) - anchor.x) > 24:
			continue   # la colita quedaría demasiado torcida
		b.rect = rect
		b.tip = anchor
		var fits: bool = true
		for own: Rect2i in _occupied(b):
			for other: Rect2i in taken:
				if own.grow(GAP).intersects(other):
					fits = false
					break
			if not fits:
				break
		if fits:
			return true
	return false


## Lo que ocupa un globo ya ubicado: el recuadro y la caja de su colita.
func _occupied(b: Bubble) -> Array[Rect2i]:
	var base_x: int = _tail_base_x(b)
	var left: int = mini(base_x, b.tip.x) - 2
	var right: int = maxi(base_x, b.tip.x) + 2
	return [b.rect, Rect2i(left, b.rect.end.y, right - left + 1, maxi(b.tip.y - b.rect.end.y, 1))]


func _tail_base_x(b: Bubble) -> int:
	var inset: int = 5 if b.style == &"thought" else 3
	return clampi(b.tip.x, b.rect.position.x + inset, b.rect.end.x - inset - 1)


func _text_width_for(style: StringName) -> int:
	match style:
		&"address": return address_text_width
		&"thought": return thought_text_width
	return max_text_width


## Margen interior (x, y), sin contar el borde.
func _pad(style: StringName) -> Vector2i:
	match style:
		&"address": return Vector2i(5, 2)   # dentro del doble borde
		&"thought": return Vector2i(5, 1)   # las esquinas redondas comen lugar
	return Vector2i(3, 1)


func _wrap(text: String, width: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var current: String = ""
	for word: String in text.split(" ", false):
		var attempt: String = word if current == "" else current + " " + word
		if current != "" and _text_width(attempt) > width:
			lines.append(current)
			current = word
		else:
			current = attempt
	if current != "" or lines.is_empty():
		lines.append(current)
	return lines


func _text_width(text: String) -> int:
	return int(ceilf(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x))


func _box_size(lines: PackedStringArray, style: StringName) -> Vector2i:
	var widest: int = 0
	for line: String in lines:
		widest = maxi(widest, _text_width(line))
	var pad: Vector2i = _pad(style)
	return Vector2i(widest + 2 * pad.x + 2, lines.size() * _line_height + 2 * pad.y + 2)


func _draw() -> void:
	for b: Bubble in _bubbles:
		if b.shown and b.alpha > 0.01:
			_draw_bubble(b)


func _draw_bubble(b: Bubble) -> void:
	var bg: Color = UiStyle.BUBBLE_BG
	var text_color: Color = UiStyle.BUBBLE_TEXT
	match b.style:
		&"accent": bg = UiStyle.BUBBLE_ACCENT_BG
		&"address": bg = UiStyle.BUBBLE_ADDRESS_BG
		&"thought":
			bg = UiStyle.BUBBLE_THOUGHT_BG
			text_color = UiStyle.BUBBLE_THOUGHT_TEXT
	var ink: Color = UiStyle.BUBBLE_INK
	var shade: Color = UiStyle.BUBBLE_SHADE
	bg.a *= b.alpha
	ink.a *= b.alpha
	shade.a *= b.alpha
	text_color.a *= b.alpha
	if b.style == &"thought":
		_draw_cloud(b, bg, ink, shade)
	else:
		_draw_box(b, bg, ink, shade)
	var pad: Vector2i = _pad(b.style)
	var r: Rect2i = b.rect
	for i in b.lines.size():
		var line: String = b.lines[i]
		var x: int = r.position.x + 1 + pad.x + (r.size.x - 2 - 2 * pad.x - _text_width(line)) / 2
		var y: int = r.position.y + 1 + pad.y + i * _line_height + _ascent
		draw_string(_font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, text_color)


## Recuadro con las esquinas recortadas (un píxel), sombra de un píxel abajo y colita de flecha; `address` suma un
## segundo borde adentro. Ningún píxel translúcido se pinta dos veces (el fondo deja ver un poco lo de atrás).
func _draw_box(b: Bubble, bg: Color, ink: Color, shade: Color) -> void:
	var r: Rect2i = b.rect
	var gap_x: int = _tail_base_x(b) - 1   # por donde sale la colita (3 px)
	_px_rect(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2, bg)
	_px_rect(r.position.x + 1, r.position.y, r.size.x - 2, 1, ink)
	_px_rect(r.position.x + 1, r.end.y - 1, gap_x - r.position.x - 1, 1, ink)
	_px_rect(gap_x, r.end.y - 1, 3, 1, bg)
	_px_rect(gap_x + 3, r.end.y - 1, r.end.x - 1 - gap_x - 3, 1, ink)
	_px_rect(r.position.x, r.position.y + 1, 1, r.size.y - 2, ink)
	_px_rect(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2, ink)
	if b.style == &"address":
		var frame: Color = UiStyle.BORDER
		frame.a *= b.alpha
		_px_rect(r.position.x + 2, r.position.y + 2, r.size.x - 4, 1, frame)
		_px_rect(r.position.x + 2, r.end.y - 3, r.size.x - 4, 1, frame)
		_px_rect(r.position.x + 2, r.position.y + 3, 1, r.size.y - 6, frame)
		_px_rect(r.end.x - 3, r.position.y + 3, 1, r.size.y - 6, frame)
	# La sombra se corta donde baja la colita (que la dibuja _draw_tail con su propio borde).
	_px_rect(r.position.x + 2, r.end.y, gap_x - r.position.x - 3, 1, shade)
	_px_rect(gap_x + 4, r.end.y, r.end.x - 1 - gap_x - 4, 1, shade)
	_draw_tail(b, bg, ink)


## La colita, renglón por renglón desde el borde de abajo hasta la punta: tres píxeles de ancho que se angostan, con
## borde; si la punta está corrida, se tuerce sin dejar huecos.
func _draw_tail(b: Bubble, bg: Color, ink: Color) -> void:
	var top: int = b.rect.end.y - 1
	var rows: int = b.tip.y - top
	if rows <= 0:
		return
	var base_x: int = _tail_base_x(b)
	var prev_x: int = base_x
	for i in rows + 1:
		var t: float = float(i) / float(rows)
		var cx: int = roundi(lerpf(base_x, b.tip.x, t))
		var half: int = 1 if t < 0.55 else 0
		var left: int = mini(cx, prev_x) - half
		var right: int = maxi(cx, prev_x) + half
		if i == rows:
			_px_rect(left, top + i, right - left + 1, 1, ink)
		elif i > 0:
			_px_rect(left - 1, top + i, 1, 1, ink)
			_px_rect(right + 1, top + i, 1, 1, ink)
			_px_rect(left, top + i, right - left + 1, 1, bg)
		prev_x = cx


## Nube de pensamiento: esquinas redondeadas de dos píxeles, sin colita de flecha sino burbujitas que bajan hacia la
## cabeza (una de 4 px, otra de 2 px).
func _draw_cloud(b: Bubble, bg: Color, ink: Color, shade: Color) -> void:
	var r: Rect2i = b.rect
	var x0: int = r.position.x
	var y0: int = r.position.y
	var x1: int = r.end.x - 1
	var y1: int = r.end.y - 1
	# Fondo en tres franjas que no se pisan.
	_px_rect(x0 + 2, y0 + 1, r.size.x - 4, 1, bg)
	_px_rect(x0 + 1, y0 + 2, r.size.x - 2, r.size.y - 4, bg)
	_px_rect(x0 + 2, y1 - 1, r.size.x - 4, 1, bg)
	# Borde con las esquinas de dos píxeles (un escalón en diagonal).
	_px_rect(x0 + 2, y0, r.size.x - 4, 1, ink)
	_px_rect(x0 + 2, y1, r.size.x - 4, 1, ink)
	_px_rect(x0, y0 + 2, 1, r.size.y - 4, ink)
	_px_rect(x1, y0 + 2, 1, r.size.y - 4, ink)
	for corner: Vector2i in [Vector2i(x0 + 1, y0 + 1), Vector2i(x1 - 1, y0 + 1), Vector2i(x0 + 1, y1 - 1), Vector2i(x1 - 1, y1 - 1)]:
		_px_rect(corner.x, corner.y, 1, 1, ink)
	_px_rect(x0 + 2, r.end.y, r.size.x - 3, 1, shade)
	# Burbujitas entre el globo y la cabeza.
	var from := Vector2(_tail_base_x(b), r.end.y + 1)
	var to := Vector2(b.tip)
	var big := Vector2i(from.lerp(to, 0.25).round())
	var small := Vector2i(from.lerp(to, 0.8).round())
	_px_rect(big.x - 1, big.y - 1, 2, 1, ink)
	_px_rect(big.x - 2, big.y, 1, 2, ink)
	_px_rect(big.x - 1, big.y, 2, 2, bg)
	_px_rect(big.x + 1, big.y, 1, 2, ink)
	_px_rect(big.x - 1, big.y + 2, 2, 1, ink)
	_px_rect(small.x, small.y, 2, 2, ink)


func _px_rect(x: int, y: int, w: int, h: int, color: Color) -> void:
	if w > 0 and h > 0:
		draw_rect(Rect2(x, y, w, h), color)
