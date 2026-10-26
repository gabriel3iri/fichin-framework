class_name WorkOrderPanel
extends CanvasLayer
## Orden de trabajo (tecla T): tareas obligatorias y opcionales, avance y salario.
## No pausa el juego: mirarla también cuesta tiempo.

## Lo consulta el menú de pausa para no abrirse encima de la orden de trabajo.
static var is_open: bool = false

var _panel: PanelContainer
var _body: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(300, 0)
	_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_panel.visible = false
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 2)
	_panel.add_child(_body)
	center.add_child(_panel)
	WorkManager.progress_changed.connect(_refresh)
	LoopManager.knowledge_gained.connect(func(_flag: String) -> void: _refresh())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("work_order"):
		if _panel.visible and event.is_action_pressed("ui_cancel"):
			_panel.visible = false
			is_open = false
			get_viewport().set_input_as_handled()
		return
	if DialogueManager.is_active or WorkManager.active_task != "" or Journal.is_open:
		return
	_panel.visible = not _panel.visible
	is_open = _panel.visible
	if _panel.visible:
		AudioManager.play_sfx("journal_open", -4.0)
		_refresh()
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not _panel.visible:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_body.add_child(UiStyle.label(tr("work_panel_title"), UiStyle.ACCENT))
	if not WorkManager.has_order():
		_body.add_child(UiStyle.label(tr("work_not_arrived"), UiStyle.DIM))
		return
	for mandatory in [true, false]:
		_body.add_child(UiStyle.label(tr("work_mandatory" if mandatory else "work_optional"), UiStyle.DIM))
		for task: Dictionary in WorkManager.tasks:
			if task["mandatory"] == mandatory:
				_body.add_child(_task_row(task))
	var total: int = WorkManager.tasks.size()
	_body.add_child(UiStyle.label(tr("work_progress") % [WorkManager.completed_count(), total], UiStyle.TEXT))
	_body.add_child(UiStyle.label(tr("work_pay") % WorkManager.pay_earned(), UiStyle.TEXT))
	if WorkManager.has_deadline:
		_body.add_child(UiStyle.label(tr("work_deadline") % TimeManager.format_clock(WorkManager.deadline), UiStyle.DIM))


func _task_row(task: Dictionary) -> HBoxContainer:
	var done: bool = WorkManager.is_done(task["id"])
	var row := HBoxContainer.new()
	var mark := UiStyle.label("[x]" if done else "[ ]", UiStyle.OK if done else UiStyle.TEXT)
	mark.custom_minimum_size = Vector2(16, 0)
	var name_label := UiStyle.label(tr(task["name_key"]), UiStyle.DIM if done else UiStyle.TEXT)
	name_label.custom_minimum_size = Vector2(150, 0)
	var minutes := UiStyle.label("%d min" % task["duration"], UiStyle.DIM)
	row.add_child(mark)
	row.add_child(name_label)
	row.add_child(minutes)
	return row
