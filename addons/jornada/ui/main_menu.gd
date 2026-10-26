extends Control
## Menú principal (docs/technical/ui_menu_spec.md §2): fondo atmosférico, título y cuatro botones.
## Continuar solo está activo si hay partida guardada. Sin ambiente ni efectos del juego; suena menu.ogg.

const VERSION_TEXT_KEY: String = "ui_menu_version"

var _continue: Button
var _new_game: Button
var _buttons: VBoxContainer
var _confirm: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Fondo y título los pone el juego (data/game.json: "title", "ui.menu_background").
	var background_script: String = GameConfig.value("ui.menu_background", "")
	if background_script != "":
		var background := Node2D.new()
		background.set_script(load(background_script))
		add_child(background)

	var title := Label.new()
	title.text = GameConfig.value("title", "")
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.62))
	title.add_theme_color_override("font_outline_color", Color(0.06, 0.07, 0.12))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 22.0
	add_child(title)
	var subtitle := UiStyle.label(tr("ui_menu_subtitle"), Color(0.82, 0.78, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	subtitle.offset_top = 70.0
	add_child(subtitle)

	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.offset_top = 128.0
	add_child(holder)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 4)
	holder.add_child(_buttons)
	_new_game = _menu_button("ui_menu_new_game", _on_new_game)
	_continue = _menu_button("ui_menu_continue", _on_continue)
	_menu_button("ui_menu_options", _on_options)
	_menu_button("ui_menu_quit", func() -> void: get_tree().quit())
	_refresh_continue()

	var footer_left := UiStyle.label(tr("ui_menu_place"), Color(0.7, 0.68, 0.62))
	footer_left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer_left.offset_left = 10.0
	footer_left.offset_bottom = -6.0
	add_child(footer_left)
	var footer_right := UiStyle.label(tr(VERSION_TEXT_KEY), Color(0.7, 0.68, 0.62))
	footer_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer_right.offset_right = -10.0
	footer_right.offset_bottom = -6.0
	add_child(footer_right)

	AudioManager.enter_menu()
	(_continue if not _continue.disabled else _new_game).grab_focus()


func _menu_button(key: String, handler: Callable) -> Button:
	var button := UiStyle.button(tr(key), false, true)
	button.custom_minimum_size = Vector2(150, 0)
	button.pressed.connect(handler)
	_buttons.add_child(button)
	return button


func _refresh_continue() -> void:
	var data: Dictionary = SaveManager.read()
	_continue.disabled = data.is_empty()
	_continue.modulate = Color(1, 1, 1, 0.45) if _continue.disabled else Color.WHITE
	if not data.is_empty():
		var when: String = Time.get_datetime_string_from_unix_time(int(data.get("saved_at", 0)), true)
		_continue.tooltip_text = tr("ui_menu_continue_tip") % [int(data.get("loop", 1)), when]


func _on_new_game() -> void:
	if SaveManager.has_save():
		_ask_overwrite()
	else:
		GameManager.new_game()


func _on_continue() -> void:
	if not SaveManager.load_and_start(false):
		_refresh_continue()


func _on_options() -> void:
	var options := OptionsMenu.new()
	options.closed.connect(func() -> void: _new_game.grab_focus())
	add_child(options)


func _ask_overwrite() -> void:
	_confirm = Control.new()
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var message := UiStyle.label(tr("ui_menu_confirm_overwrite"))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(240, 0)
	box.add_child(message)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var yes := UiStyle.button(tr("ui_settings_yes"), false, true)
	yes.pressed.connect(func() -> void:
		SaveManager.delete_all()
		GameManager.new_game())
	var no := UiStyle.button(tr("ui_settings_no"), false, true)
	no.pressed.connect(func() -> void:
		_confirm.queue_free()
		_new_game.grab_focus())
	row.add_child(yes)
	row.add_child(no)
	no.grab_focus()
