class_name OptionsMenu
extends CanvasLayer
## Opciones (docs/technical/ui_menu_spec.md §3): audio, video, idioma y juego. Se abre como una capa
## encima del menú principal o de la pausa. Todo cambia en tiempo real y se guarda solo.

signal closed

const SPEED_KEYS: Array[String] = ["ui_settings_speed_0", "ui_settings_speed_1", "ui_settings_speed_2", "ui_settings_speed_3"]
const TIME_KEYS: Array[String] = ["ui_settings_time_0", "ui_settings_time_1", "ui_settings_time_2"]
const LANGUAGE_NAMES: Dictionary = {"es": "Español", "en": "English", "de": "Deutsch"}   # nombres propios: no se traducen

var _rows: VBoxContainer
var _dim: ColorRect


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	center.add_child(panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	panel.add_child(_rows)
	_build()


func _build() -> void:
	_rows.add_child(UiStyle.label(tr("ui_settings_title"), UiStyle.ACCENT))
	_section("ui_settings_audio")
	for key in ["master", "music", "sfx", "ambient"]:
		_slider_row("ui_settings_" + key, key)
	_section("ui_settings_video")
	_toggle_row("ui_settings_fullscreen", "fullscreen")
	_toggle_row("ui_settings_vsync", "vsync")
	_section("ui_settings_game")
	_cycle_row("ui_settings_language", "language", SettingsManager.LANGUAGES.size(),
			func(i: int) -> String: return LANGUAGE_NAMES[SettingsManager.LANGUAGES[i]], true)
	_cycle_row("ui_settings_text_speed", "text_speed", SPEED_KEYS.size(), func(i: int) -> String: return tr(SPEED_KEYS[i]))
	_cycle_row("ui_settings_time_scale", "time_scale", TIME_KEYS.size(), func(i: int) -> String: return tr(TIME_KEYS[i]))
	_toggle_row("ui_settings_tutorials", "tutorials")
	var back := UiStyle.button(tr("ui_settings_back"), false, true)
	back.pressed.connect(close)
	_rows.add_child(back)
	back.grab_focus()


func _section(key: String) -> void:
	_rows.add_child(UiStyle.label(tr(key), UiStyle.DIM))


func _row(label_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := UiStyle.label(tr(label_key))
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	_rows.add_child(row)
	return row


func _slider_row(label_key: String, setting: String) -> void:
	var row := _row(label_key)
	var slider: HSlider = UiStyle.slider(0.0, 1.0, 0.05, float(SettingsManager.get_value(setting)))
	slider.custom_minimum_size = Vector2(130, 10)
	var value := UiStyle.label("%d%%" % roundi(slider.value * 100.0), UiStyle.ACCENT)
	value.custom_minimum_size = Vector2(34, 0)
	slider.value_changed.connect(func(v: float) -> void:
		SettingsManager.set_value(setting, v)
		value.text = "%d%%" % roundi(v * 100.0))
	row.add_child(slider)
	row.add_child(value)


func _toggle_row(label_key: String, setting: String) -> void:
	var row := _row(label_key)
	var button := UiStyle.button("", true, true)
	button.custom_minimum_size = Vector2(60, 0)
	var refresh := func() -> void:
		button.text = tr("ui_settings_on") if SettingsManager.get_value(setting) else tr("ui_settings_off")
	refresh.call()
	button.pressed.connect(func() -> void:
		SettingsManager.set_value(setting, not SettingsManager.get_value(setting))
		refresh.call())
	row.add_child(button)


## Botón que recorre las opciones una por una. `by_code` = el valor guardado es el código (idioma), no el índice.
func _cycle_row(label_key: String, setting: String, count: int, name_of: Callable, by_code: bool = false) -> void:
	var row := _row(label_key)
	var button := UiStyle.button("", true, true)
	button.custom_minimum_size = Vector2(110, 0)
	var current := func() -> int:
		return SettingsManager.LANGUAGES.find(SettingsManager.get_value(setting)) if by_code else int(SettingsManager.get_value(setting))
	button.text = name_of.call(current.call())
	button.pressed.connect(func() -> void:
		var next: int = (current.call() + 1) % count
		SettingsManager.set_value(setting, SettingsManager.LANGUAGES[next] if by_code else next)
		button.text = name_of.call(next)
		if by_code:
			_rebuild())
	row.add_child(button)


## Al cambiar de idioma se vuelve a dibujar el menú con los textos nuevos.
func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	await get_tree().process_frame
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()
