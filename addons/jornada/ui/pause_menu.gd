class_name PauseMenu
extends CanvasLayer
## Menú de pausa (Esc): continuar, opciones, guardado y carga rápida, volver al menú. Congela el reloj.
## No se abre durante un diálogo, un minijuego o con la orden de trabajo en pantalla.

var _root: Control
var _first: Button


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	box.add_child(UiStyle.label(tr("ui_pause_title"), UiStyle.ACCENT))
	_first = _entry(box, "ui_pause_resume", close)
	_entry(box, "ui_pause_options", _open_options)
	_entry(box, "ui_pause_save", func() -> void:
		SaveManager.quick_save()
		close())
	var load_button := _entry(box, "ui_pause_load", func() -> void:
		close()
		SaveManager.load_and_start(true))
	load_button.disabled = not SaveManager.has_quicksave()
	_entry(box, "ui_pause_menu", func() -> void:
		close()
		GameManager.return_to_menu())


func _entry(box: VBoxContainer, key: String, handler: Callable) -> Button:
	var button := UiStyle.button(tr(key), false, true)
	button.custom_minimum_size = Vector2(190, 0)
	button.pressed.connect(handler)
	box.add_child(button)
	return button


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save") and GameManager.state == GameManager.State.PLAYING:
		SaveManager.quick_save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load") and SaveManager.has_quicksave():
		SaveManager.load_and_start(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_menu"):
		if _root.visible:
			close()
		elif _can_open():
			open()
		else:
			return
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	return GameManager.state == GameManager.State.PLAYING and not DialogueManager.is_active \
			and WorkManager.active_task == "" and not WorkOrderPanel.is_open


func open() -> void:
	GameManager.pause_game()
	_root.visible = true
	_first.grab_focus()


func close() -> void:
	_root.visible = false
	GameManager.resume_game()


func _open_options() -> void:
	var options := OptionsMenu.new()
	options.closed.connect(func() -> void: _first.grab_focus())
	add_child(options)
