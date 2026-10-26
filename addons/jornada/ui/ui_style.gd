class_name UiStyle
extends RefCounted
## Estilos de UI pixel art compartidos (paneles, botones, sliders). Sin antialiasing ni redondeos.

const INK: Color = Color(0.122, 0.122, 0.122)
const BG: Color = Color(0.137, 0.137, 0.137, 0.96)
const BORDER: Color = Color(0.455, 0.302, 0.18)
const ACCENT: Color = Color(1.0, 0.804, 0.612)
const TEXT: Color = Color(0.894, 0.886, 0.831)
const DIM: Color = Color(0.647, 0.643, 0.549)
const OK: Color = Color(0.31, 0.451, 0.345)
const BAD: Color = Color(0.902, 0.224, 0.275)
## Nombres sobre la cabeza: letra blanca en un recuadro negro con borde marrón (distinto de los diálogos).
const NAME_TEXT: Color = Color(0.96, 0.95, 0.92)
const NAME_BG: Color = Color(0.03, 0.03, 0.03, 0.9)

static var _grabber: ImageTexture


static func name_tag() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = NAME_BG
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 0
	box.content_margin_bottom = 1
	return box


static func panel(compact: bool = false) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load("res://addons/jornada/ui/skin/ui_panel.png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, 4.0)
		box.set_content_margin(side, 4.0 if compact else 7.0)
	return box


static func flat(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(1)
	box.border_color = border
	box.set_content_margin_all(3.0)
	box.anti_aliasing = false
	return box


## `compact` baja el alto del botón (listas largas dentro de un panel).
static func button(text: String, compact: bool = false, focusable: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL if focusable else Control.FOCUS_NONE
	var styles: Dictionary = {
		"normal": flat(Color(0.17, 0.17, 0.15), BORDER),
		"hover": flat(Color(0.23, 0.23, 0.2), ACCENT),
		"pressed": flat(INK, ACCENT),
		"disabled": flat(Color(0.13, 0.13, 0.12), Color(0.25, 0.25, 0.22)),
		"focus": flat(Color(0.23, 0.23, 0.2), ACCENT),
	}
	for style_name: String in styles:
		var box: StyleBoxFlat = styles[style_name]
		if compact:
			box.content_margin_top = 0.0
			box.content_margin_bottom = 0.0
		b.add_theme_stylebox_override(style_name, box)
	b.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click", -6.0))
	b.mouse_entered.connect(func() -> void: AudioManager.play_sfx("ui_hover", -14.0))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", DIM)
	return b


static func slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(110, 10)
	s.focus_mode = Control.FOCUS_NONE
	var track := flat(Color(0.1, 0.1, 0.09), Color(0.3, 0.3, 0.26))
	track.content_margin_top = 1.0
	track.content_margin_bottom = 1.0
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", flat(BORDER, BORDER))
	s.add_theme_stylebox_override("grabber_area_highlight", flat(ACCENT, ACCENT))
	if _grabber == null:
		var img := Image.create(5, 9, false, Image.FORMAT_RGBA8)
		img.fill(ACCENT)
		for x in 5:
			img.set_pixel(x, 0, INK)
			img.set_pixel(x, 8, INK)
		for y in 9:
			img.set_pixel(0, y, INK)
			img.set_pixel(4, y, INK)
		_grabber = ImageTexture.create_from_image(img)
	s.add_theme_icon_override("grabber", _grabber)
	s.add_theme_icon_override("grabber_highlight", _grabber)
	s.add_theme_icon_override("grabber_disabled", _grabber)
	return s


static func label(text: String, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l
