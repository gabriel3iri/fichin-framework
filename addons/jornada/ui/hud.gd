class_name Hud
extends CanvasLayer
## HUD de pantalla completa (base 640x360). Usa los bordes: reloj y loop arriba a la izquierda,
## sospecha arriba a la derecha, avance del trabajo abajo a la izquierda, teclas abajo a la derecha.
## Nada de números de sospecha ni de "Loop 1": el jugador no sabe aún que hay un bucle.

var _time: Label
var _loop: Label
var _work_chip: PanelContainer
var _work_label: Label
var _hints: Label
var _fast: Label

## F mantenida: el tiempo (y todo lo que se mueve) corre a esta velocidad, para revisar rutinas.
const FAST_FORWARD: float = 8.0


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top_left(root)
	_build_top_right(root)
	_build_bottom_left(root)
	_build_bottom_right(root)
	_fast = UiStyle.label(tr("hud_fast_forward") % int(FAST_FORWARD), UiStyle.ACCENT)
	_fast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fast.offset_top = 10.0
	_fast.visible = false
	root.add_child(_fast)

	TimeManager.minute_changed.connect(_on_minute_changed)
	LoopManager.loop_started.connect(_on_loop_started)
	LoopManager.knowledge_gained.connect(func(_f: String) -> void:
		_refresh_work()
		_hints.text = _hints_text())
	WorkManager.progress_changed.connect(_refresh_work)
	DialogueManager.dialogue_started.connect(_on_dialogue_started.unbind(1))
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended.unbind(1))
	SettingsManager.changed.connect(func(key: String) -> void:
		if key == "tutorials":
			_hints.visible = SettingsManager.get_value("tutorials"))
	_hints.visible = SettingsManager.get_value("tutorials")
	_on_minute_changed(TimeManager.hour, TimeManager.minute)
	_on_loop_started(LoopManager.loop_number)
	_refresh_work()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	TimeManager.minute_changed.disconnect(_on_minute_changed)
	LoopManager.loop_started.disconnect(_on_loop_started)
	WorkManager.progress_changed.disconnect(_refresh_work)


func _process(_delta: float) -> void:
	var fast: bool = Input.is_physical_key_pressed(KEY_F) and not get_tree().paused and not DialogueManager.is_active
	var scale: float = FAST_FORWARD if fast else 1.0
	if Engine.time_scale != scale:
		Engine.time_scale = scale
	_fast.visible = fast


## Z (a prueba): cambia el acercamiento de la cámara (1x, 1,5x, 2x; PlayerCamera.ZOOMS).
## N (ayuda de depuración): muestra u oculta los nombres de todos. Sin eso, el nombre sale al pasar el mouse.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_N:
		SettingsManager.set_value("debug_name_tags", not bool(SettingsManager.get_value("debug_name_tags")))
		get_tree().call_group("npc_actors", "refresh_name_tag")
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.physical_keycode == KEY_Z:
		var next: int = (int(SettingsManager.get_value("camera_zoom")) + 1) % PlayerCamera.ZOOMS.size()
		SettingsManager.set_value("camera_zoom", next)
		Toasts.show_key("hud_zoom", [String.num(PlayerCamera.ZOOMS[next], 1)])
		get_viewport().set_input_as_handled()


func _build_top_left(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.add_theme_stylebox_override("panel", UiStyle.panel(true))
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	row.add_child(PocketWatch.new())
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	_time = Label.new()
	_time.add_theme_font_size_override("font_size", 20)
	_time.add_theme_color_override("font_color", UiStyle.ACCENT)
	column.add_child(_time)
	_loop = UiStyle.label("", UiStyle.DIM)
	column.add_child(_loop)


func _build_top_right(root: Control) -> void:
	var indicator: Control = (load("res://addons/jornada/scenes/suspicion_indicator.tscn") as PackedScene).instantiate()
	root.add_child(indicator)


func _build_bottom_left(root: Control) -> void:
	_work_chip = PanelContainer.new()
	_work_chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_work_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_work_chip.offset_left = 8.0
	_work_chip.offset_bottom = -8.0
	_work_chip.add_theme_stylebox_override("panel", UiStyle.panel(true))
	_work_label = UiStyle.label("", UiStyle.TEXT)
	_work_chip.add_child(_work_label)
	root.add_child(_work_chip)


## Teclas que sirven ahora: la orden de trabajo solo si el juego tiene trabajo; el diario, cuando se lo tiene.
func _hints_text() -> String:
	var keys: Array[String] = ["hud_hint_interact"]
	if not WorkManager.tasks.is_empty():
		keys.append("hud_hint_work")
	if JournalManager.has_journal():
		keys.append("hud_hint_journal")
	keys.append("hud_hint_run")
	return "     ".join(keys.map(func(k: String) -> String: return tr(k)))


func _build_bottom_right(root: Control) -> void:
	_hints = UiStyle.label(_hints_text(), UiStyle.DIM)
	_hints.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hints.offset_right = -10.0
	_hints.offset_bottom = -6.0
	root.add_child(_hints)


func _on_minute_changed(_hour: int, _minute: int) -> void:
	_time.text = TimeManager.get_time_string()
	_refresh_work()   # la entrega cambia de color en la última hora


## Bajo el reloj va la fecha de la jornada (data/game.json "day"): en modo loop, siempre la misma; en next_day avanza.
## El número de vuelta no se muestra: lo cuenta el diario.
func _on_loop_started(_loop_number: int) -> void:
	var date: Dictionary = LoopManager.today()
	_loop.visible = not date.is_empty()
	if not date.is_empty():
		_loop.text = tr("hud_date_format") % [tr("weekday_%d" % int(date["weekday"])), int(date["day"]),
				tr("month_short_%d" % int(date["month"])), int(date["year"])]


## Durante un diálogo se ocultan las ayudas y el contador de trabajo (ahí va el retrato).
func _on_dialogue_started() -> void:
	_hints.visible = false
	_work_chip.visible = false


func _on_dialogue_ended() -> void:
	_hints.visible = SettingsManager.get_value("tutorials")
	_refresh_work()


func _refresh_work() -> void:
	var has_order: bool = WorkManager.has_order()
	_work_chip.visible = has_order
	if has_order:
		# Con la entrega a la vista (Klara la dice al darle la orden) el plazo se siente: en la última hora, en rojo.
		if not WorkManager.has_deadline:   # un juego sin plazo muestra solo el avance
			_work_label.text = tr("hud_work") % [WorkManager.completed_count(), WorkManager.tasks.size()]
			_work_label.add_theme_color_override("font_color", UiStyle.TEXT)
		else:
			var left: int = WorkManager.deadline - TimeManager.now_minutes()
			_work_label.text = tr("hud_work_deadline") % [WorkManager.completed_count(), WorkManager.tasks.size(),
					TimeManager.format_clock(WorkManager.deadline)]
			_work_label.add_theme_color_override("font_color", UiStyle.BAD if left <= 60 else UiStyle.TEXT)
