extends HBoxContainer
## Pestaña «Casos» del diario (Cases): a la izquierda las pistas anotadas, con de dónde salió cada una; a la derecha los
## hilos del jugador. Una pista se lleva a un hilo arrastrándola (o eligiéndola y tocando el hilo); vuelve a la lista
## arrastrándola de nuevo o con clic derecho. En la lista, las que ya están en un hilo se ven tenues. Cuando un hilo
## junta exactamente lo que hace falta, muestra la deducción y se puede resolver.
## Pensar lleva tiempo: cada pista puesta y cada caso resuelto suman minutos que se cobran al cerrar el diario
## (Cases.thinking); mientras tanto el reloj está frenado, como en el resto del diario.

const LIST_WIDTH: float = 214.0
const THREAD_WIDTH: float = 176.0
const USED_ALPHA: float = 0.4
const PAPER: Color = Color(0.93, 0.89, 0.79)
const PAPER_SOLVED: Color = Color(0.82, 0.9, 0.78)
const PAPER_INK: Color = Color(0.17, 0.14, 0.12)
const PIN: Color = Color(0.75, 0.2, 0.2)

var type_colors: Dictionary = {}

var _list: VBoxContainer
var _grid: GridContainer
var _selected: String = ""
var _shown: String = ""   # lo que se dibujó (pistas, hilos, elegida): sin cambios no se rearma, así el tooltip no se va


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	add_child(left)
	left.add_child(UiStyle.label(tr("ui_cases_clues"), UiStyle.ACCENT))
	var list_scroll := ClueList.new()
	list_scroll.board = self
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	list_scroll.add_child(_list)

	add_child(VSeparator.new())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var header := HBoxContainer.new()
	right.add_child(header)
	header.add_child(UiStyle.label(tr("ui_cases_threads"), UiStyle.ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var add := UiStyle.button(tr("ui_cases_new_thread"), true)
	add.pressed.connect(func() -> void: Cases.new_thread())
	header.add_child(add)
	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(grid_scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	grid_scroll.add_child(_grid)

	Cases.changed.connect(refresh)
	# El diario avisa cada minuto (avistamientos) y en esta pestaña el reloj corre: solo se rearma si cambiaron las pistas.
	JournalManager.changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh(false))


func _exit_tree() -> void:
	Cases.changed.disconnect(refresh)


func refresh(force: bool = true) -> void:
	var state: String = str([Cases.clues(), Cases.threads, _selected, TranslationServer.get_locale()])
	if not force and state == _shown:
		return
	_shown = state
	for child in _list.get_children() + _grid.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	var clues: Array[String] = Cases.clues()
	if not _selected in clues or Cases.is_used(_selected):
		_selected = ""
	if clues.is_empty():
		_list.add_child(_wrapped(tr("ui_cases_empty"), UiStyle.DIM, LIST_WIDTH))
	for flag: String in clues:
		_list.add_child(_clue_row(flag))
	for i in Cases.threads.size():
		_grid.add_child(_thread_box(i))
	if Cases.threads.is_empty():
		_grid.add_child(_wrapped(tr("ui_cases_no_threads"), UiStyle.DIM, THREAD_WIDTH * 2.0))


## Lo que dice el encabezado del diario en esta pestaña.
func summary() -> String:
	var used: int = Cases.clues().filter(func(f: String) -> bool: return Cases.is_used(f)).size()
	var text: String = tr("ui_cases_summary") % [Cases.clues().size(), used]
	if Cases.thinking > 0:
		text += "  ·  " + tr("ui_cases_thinking") % Cases.thinking
	return text


## Elegir una pista (para tocar después el hilo) solo la resalta: rearmar la lista acá cortaría el arrastre.
func select(flag: String) -> void:
	_selected = "" if _selected == flag else flag
	for row in _list.get_children():
		if row is ClueRow:
			row.add_theme_stylebox_override("panel", _row_style(row.flag == _selected))
	_shown = str([Cases.clues(), Cases.threads, _selected, TranslationServer.get_locale()])


func _row_style(selected: bool) -> StyleBoxFlat:
	return UiStyle.flat(Color(1, 1, 1, 0.1) if selected else Color(0, 0, 0, 0), UiStyle.ACCENT if selected else Color(0, 0, 0, 0))


func drop_on_thread(flag: String, index: int) -> void:
	if Cases.place(flag, index):
		AudioManager.play_sfx("journal_open", -12.0)
	_selected = ""


func clicked_thread(index: int) -> void:
	if _selected != "":
		drop_on_thread(_selected, index)
		refresh()


# --- Piezas ---------------------------------------------------------------------------------------

func _clue_row(flag: String) -> Control:
	var row := ClueRow.new()
	row.board = self
	row.flag = flag
	var kind: int = KnowledgeRegistry.kind_of(flag)
	var used: bool = Cases.is_used(flag)
	row.add_theme_stylebox_override("panel", _row_style(flag == _selected))
	row.tooltip_text = tr("desc_" + flag)
	row.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)
	var mark := ColorRect.new()
	mark.color = type_colors.get(kind, UiStyle.DIM)
	mark.custom_minimum_size = Vector2(3, 0)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(mark)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)
	text.add_child(_wrapped(("✓ " if used else "") + tr("flag_" + flag), UiStyle.TEXT, LIST_WIDTH - 14.0))
	var source: String = JournalManager.source_text(flag)
	if source != "":
		text.add_child(_wrapped(source, UiStyle.DIM, LIST_WIDTH - 14.0))
	if used:
		row.modulate.a = USED_ALPHA
	return row


func _thread_box(index: int) -> Control:
	var thread: Dictionary = Cases.threads[index]
	var solved: String = thread["solved"]
	var pending: String = Cases.pending(index)
	var box := ThreadBox.new()
	box.board = self
	box.index = index
	box.solved = solved != ""
	box.custom_minimum_size = Vector2(THREAD_WIDTH, 64)
	box.add_theme_stylebox_override("panel", UiStyle.flat(PAPER_SOLVED if box.solved else PAPER, PAPER_INK))
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not box.solved else Control.CURSOR_ARROW
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var title: String = tr("ded_" + solved) if box.solved else (tr("ded_" + pending) if pending != "" else tr("ui_cases_thread") % (index + 1))
	var title_label := _wrapped(("✔ " if box.solved else "") + title, PAPER_INK, THREAD_WIDTH - 24.0)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_label)
	if not box.solved:
		var close := UiStyle.button("×", true)
		close.tooltip_text = tr("ui_cases_remove_thread")
		close.pressed.connect(func() -> void:
			for flag: String in (thread["clues"] as Array).duplicate():
				Cases.take_back(flag)
			Cases.remove_thread(index))
		top.add_child(close)
	for flag: String in thread["clues"]:
		var chip := ClueChip.new()
		chip.board = self
		chip.flag = flag
		chip.thread = box
		chip.locked = box.solved
		chip.tooltip_text = tr("desc_" + flag)
		chip.add_theme_stylebox_override("panel", UiStyle.flat(Color(1, 1, 1, 0.55), type_colors.get(KnowledgeRegistry.kind_of(flag), PAPER_INK)))
		var chip_label := _wrapped("• " + tr("flag_" + flag), PAPER_INK, THREAD_WIDTH - 12.0)
		chip.add_child(chip_label)
		column.add_child(chip)
	if (thread["clues"] as Array).is_empty():
		column.add_child(_wrapped(tr("ui_cases_drop_here"), Color(PAPER_INK, 0.55), THREAD_WIDTH - 8.0))
	if pending != "":
		var solve := UiStyle.button(tr("ui_cases_solve"), true)
		solve.pressed.connect(func() -> void: Cases.solve(index))
		column.add_child(solve)
	return box


func _wrapped(text: String, color: Color, width: float) -> Label:
	var label := UiStyle.label(text, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func preview(text: String) -> Control:
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UiStyle.flat(Color(0.93, 0.89, 0.79, 0.95), PIN))
	var label := UiStyle.label(text, Color(0.17, 0.14, 0.12))
	tag.add_child(label)
	return tag


# --- Arrastrar y soltar -----------------------------------------------------------------------------

## Una pista de la lista: se arrastra a un hilo, o se elige con clic (al soltar, sin arrastrar) y se toca el hilo.
class ClueRow extends PanelContainer:
	var board: Node
	var flag: String = ""
	var _alpha: float = 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_drag_data(_at: Vector2) -> Variant:
		set_drag_preview(board.preview(tr("flag_" + flag)))
		_alpha = modulate.a
		modulate.a = 0.25   # la que se está llevando
		return {"clue": flag}

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			modulate.a = _alpha

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null:
			return
		if not click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not get_viewport().gui_is_dragging():
			board.select(flag)
		elif click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
			Cases.take_back(flag)


## Una pista ya puesta en un hilo: se arrastra a otro hilo o a la lista; clic derecho la devuelve. Lo que se suelta o
## se toca encima de ella va a su hilo.
class ClueChip extends PanelContainer:
	var board: Node
	var thread: ThreadBox
	var flag: String = ""
	var locked: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_drag_data(_at: Vector2) -> Variant:
		if locked:
			return null
		set_drag_preview(board.preview(tr("flag_" + flag)))
		return {"clue": flag}

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		return thread._can_drop_data(at, data)

	func _drop_data(at: Vector2, data: Variant) -> void:
		thread._drop_data(at, data)

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or not click.pressed:
			return
		if click.button_index == MOUSE_BUTTON_RIGHT and not locked:
			Cases.take_back(flag)
		elif click.button_index == MOUSE_BUTTON_LEFT:
			thread._gui_input(event)


## Un hilo: recibe pistas; se ilumina cuando se le pasa una por encima.
class ThreadBox extends PanelContainer:
	var board: Node
	var index: int = 0
	var solved: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = not solved and data is Dictionary and data.has("clue")
		self_modulate = Color(1.15, 1.12, 0.9) if ok else Color.WHITE
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		self_modulate = Color.WHITE
		board.drop_on_thread(data["clue"], index)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			self_modulate = Color.WHITE

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not solved:
			board.clicked_thread(index)


## La lista de pistas: soltar ahí una pista de un hilo la devuelve.
class ClueList extends ScrollContainer:
	var board: Node

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("clue") and Cases.is_used(data["clue"])

	func _drop_data(_at: Vector2, data: Variant) -> void:
		Cases.take_back(data["clue"])
