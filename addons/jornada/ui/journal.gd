class_name Journal
extends CanvasLayer
## Diario de evidencias (tecla J, canon 09 §6). Pestañas: Evidencias, Personas, Deducciones, Mapa y, si el juego las
## define, una lista de gente que se desbloquea con un flag (data/journal.json "roster"; en Rabenholz, El tren) y las
## fichas para identificar a la gente (data/identify.json, sistema Identification).
## Mientras está abierto el reloj se detiene: consultar las notas no es una acción del técnico en el pueblo.

enum Tab { EVIDENCE, PEOPLE, DEDUCTIONS, MAP, ROSTER, IDENTIFY }

const BASE_TAB_KEYS: Array[String] = ["ui_journal_tab_evidence", "ui_journal_tab_people", "ui_journal_tab_deductions", "ui_journal_tab_map"]
const NUMBER_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
const SHEETS_DIR: String = "res://assets/generated_assets/sprites/npcs/%s_sheet.png"
const PROTAGONIST_SHEET: String = "res://assets/generated_assets/sprites/protagonist_sheet.png"
const PORTRAITS_DIR: String = "res://assets/generated_assets/portraits/%s.png"

const TYPE_KEYS: Dictionary = {
	KnowledgeRegistry.Kind.WITNESS: "ui_journal_type_witness",
	KnowledgeRegistry.Kind.TESTIMONY: "ui_journal_type_testimony",
	KnowledgeRegistry.Kind.DOCUMENT: "ui_journal_type_document",
	KnowledgeRegistry.Kind.PHYSICAL: "ui_journal_type_physical",
	KnowledgeRegistry.Kind.HEARD: "ui_journal_type_heard",
	KnowledgeRegistry.Kind.DEDUCTION: "ui_journal_type_deduction",
}
const TYPE_COLORS: Dictionary = {
	KnowledgeRegistry.Kind.WITNESS: Color(0.45, 0.65, 0.85),
	KnowledgeRegistry.Kind.TESTIMONY: Color(0.82, 0.72, 0.5),
	KnowledgeRegistry.Kind.DOCUMENT: Color(0.9, 0.3, 0.32),
	KnowledgeRegistry.Kind.PHYSICAL: Color(0.5, 0.75, 0.5),
	KnowledgeRegistry.Kind.HEARD: Color(0.72, 0.55, 0.82),
	KnowledgeRegistry.Kind.DEDUCTION: Color(1.0, 0.804, 0.612),
}

## Lo consultan el menú de pausa y el panel de trabajo para no abrirse encima.
static var is_open: bool = false

var _root: Control
var _tab_buttons: Array[Button] = []
var _summary: Label
var _list_scroll: ScrollContainer
## Ancho de las líneas del panel de detalle (el panel mide 300).
const DETAIL_WIDTH: float = 296.0
var _list: VBoxContainer
var _detail_panel: VBoxContainer
## El detalle va con scroll: una ficha con muchas cosas anotadas no estira el diario fuera de la pantalla.
var _detail_scroll: ScrollContainer
var _tab: int = Tab.EVIDENCE
## Las cuatro de siempre y las que defina el juego (lista, identificar), en orden; `_tab_ids` dice cuál es cuál.
var _tab_keys: Array[String] = []
var _tab_ids: Array[int] = []
## Pestaña de identificar: eligiendo un nombre para la ficha (teclado: E para empezar, arriba/abajo, E para poner).
var _picking: bool = false
var _pick_index: int = 0
var _pick_buttons: Array[Button] = []
var _items: Array[Dictionary] = []
var _rows: Array[Button] = []
var _selected: int = 0
var _icons: Dictionary = {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tab_keys.assign(BASE_TAB_KEYS)
	_tab_ids.assign([Tab.EVIDENCE, Tab.PEOPLE, Tab.DEDUCTIONS, Tab.MAP])
	var roster: Dictionary = JournalManager.data().get("roster", {})
	if roster.has("tab_key"):
		_tab_keys.append(roster["tab_key"])
		_tab_ids.append(Tab.ROSTER)
	if Identification.enabled():
		_tab_keys.append(Identification.config().get("tab_key", ""))
		_tab_ids.append(Tab.IDENTIFY)
	Identification.changed.connect(func() -> void:
		if _root.visible and _current_tab() == Tab.IDENTIFY:
			_rebuild())
	_build()
	_root.visible = false


func _exit_tree() -> void:
	is_open = false


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible or not event.is_action_pressed("journal"):
		return
	if GameManager.state != GameManager.State.PLAYING or DialogueManager.is_active \
			or WorkManager.active_task != "" or WorkOrderPanel.is_open or DeductionScreen.is_playing:
		return
	if not JournalManager.has_journal():
		return   # todavía no tiene diario (aparece en la habitación desde el segundo día)
	open()
	get_viewport().set_input_as_handled()


## Mientras está abierto lo captura todo, para que Esc cierre el diario y no abra la pausa.
func _input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if _picking and _pick_input(event):
		get_viewport().set_input_as_handled()
		return
	if _current_tab() == Tab.IDENTIFY and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		_start_picking()
	elif event.is_action_pressed("journal") or event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		close()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in NUMBER_KEYS:
		if _tab_shown(NUMBER_KEYS.find(event.keycode)):
			_set_tab(NUMBER_KEYS.find(event.keycode))
	elif event.is_action_pressed("move_left"):
		_step_tab(-1)
	elif event.is_action_pressed("move_right"):
		_step_tab(1)
	elif event.is_action_pressed("move_up", true):
		_select(_selected - 1)
	elif event.is_action_pressed("move_down", true):
		_select(_selected + 1)
	else:
		return
	get_viewport().set_input_as_handled()


func open() -> void:
	GameManager.pause_game()
	is_open = true
	_root.visible = true
	AudioManager.play_sfx("journal_open", -4.0)
	for i in _tab_buttons.size():
		_tab_buttons[i].visible = _tab_shown(i)
	_set_tab(_tab if _tab_shown(_tab) else 0)


func close() -> void:
	if not _root.visible:
		return
	_mark_current_seen()
	_root.visible = false
	is_open = false
	GameManager.resume_game()


# --- Construcción -------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(10, 8)
	panel.custom_minimum_size = Vector2(620, 344)
	panel.size = Vector2(620, 344)
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 3)
	column.add_child(header)
	for i in _tab_keys.size():
		var button := UiStyle.button("%d  %s" % [i + 1, tr(_tab_keys[i])], true)
		button.toggle_mode = true
		button.pressed.connect(_set_tab.bind(i))
		header.add_child(button)
		_tab_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_summary = UiStyle.label("", UiStyle.DIM)
	header.add_child(_summary)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	column.add_child(body)

	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size = Vector2(286, 0)
	_list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list_scroll.add_child(_list)

	var line := VSeparator.new()
	body.add_child(line)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.custom_minimum_size = Vector2(DETAIL_WIDTH + 4.0, 0)
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_detail_scroll)
	_detail_panel = VBoxContainer.new()
	_detail_panel.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_detail_panel.add_theme_constant_override("separation", 3)
	_detail_scroll.add_child(_detail_panel)

	var footer := HBoxContainer.new()
	column.add_child(footer)
	footer.add_child(UiStyle.label(tr("ui_journal_nav"), UiStyle.DIM))
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	footer.add_child(UiStyle.label(tr("ui_journal_close"), UiStyle.DIM))


# --- Pestañas -----------------------------------------------------------------------------------

func _current_tab() -> int:
	return _tab_ids[_tab] if _tab < _tab_ids.size() else Tab.EVIDENCE


## La pestaña de identificar aparece recién cuando hay caras para identificar.
func _tab_shown(index: int) -> bool:
	if index < 0 or index >= _tab_ids.size():
		return false
	return _tab_ids[index] != Tab.IDENTIFY or Identification.is_available()


func _step_tab(step: int) -> void:
	var index: int = _tab
	for i in _tab_keys.size():
		index = (index + step + _tab_keys.size()) % _tab_keys.size()
		if _tab_shown(index):
			break
	_set_tab(index)


func _set_tab(index: int) -> void:
	_mark_current_seen()
	_picking = false
	_tab = clampi(index, 0, _tab_keys.size() - 1)
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == _tab
	_selected = 0
	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_items.clear()
	_rows.clear()
	_summary.text = ""
	_list_scroll.custom_minimum_size.x = 286.0
	_detail_scroll.get_parent().get_child(1).visible = true   # separador
	_detail_scroll.visible = true
	match _current_tab():
		Tab.EVIDENCE: _build_evidence()
		Tab.PEOPLE: _build_people()
		Tab.DEDUCTIONS: _build_deductions()
		Tab.MAP: _build_map()
		Tab.ROSTER: _build_roster()
		Tab.IDENTIFY: _build_identify()
	_selected = clampi(_selected, 0, maxi(_items.size() - 1, 0))
	_refresh_selection()


func _select(index: int) -> void:
	if _items.is_empty():
		return
	_picking = false
	_selected = clampi(index, 0, _items.size() - 1)
	_refresh_selection()


func _refresh_selection() -> void:
	for i in _rows.size():
		_rows[i].button_pressed = i == _selected
	_detail_scroll.scroll_vertical = 0
	for child in _detail_panel.get_children():
		_detail_panel.remove_child(child)
		child.queue_free()
	if _items.is_empty():
		return
	var item: Dictionary = _items[_selected]
	_mark_seen(item)
	_fill_detail(item)
	if item.has("card"):
		_fill_identify_detail(item["card"])
	await get_tree().process_frame
	if _selected < _rows.size() and is_instance_valid(_rows[_selected]):
		_list_scroll.ensure_control_visible(_rows[_selected])


func _mark_seen(item: Dictionary) -> void:
	var flag: String = item.get("flag", "")
	if flag != "":
		JournalManager.mark_seen(flag)
		if _selected < _rows.size():
			_rows[_selected].add_theme_color_override("font_color", item.get("color", UiStyle.TEXT))


func _mark_current_seen() -> void:
	if _current_tab() == Tab.EVIDENCE and _selected < _items.size():
		JournalManager.mark_seen(_items[_selected].get("flag", ""))


# --- Filas y detalle ----------------------------------------------------------------------------

func _add_header(text: String) -> void:
	var header := UiStyle.label(text, UiStyle.DIM)
	_list.add_child(header)


func _add_row(item: Dictionary) -> void:
	var button := UiStyle.button(item["text"], true)
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.custom_minimum_size = Vector2(0, 14)
	button.expand_icon = false
	if item.has("icon"):
		button.icon = item["icon"]
	var color: Color = item.get("color", UiStyle.TEXT)
	for style_color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(style_color, color)
	if item.get("unseen", false):
		button.add_theme_color_override("font_color", UiStyle.ACCENT)
		button.add_theme_color_override("font_hover_color", UiStyle.ACCENT)
	if item.has("icon_color"):
		for style_color in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
			button.add_theme_color_override(style_color, item["icon_color"])
	var index: int = _items.size()
	button.pressed.connect(func() -> void: _select(index))
	_list.add_child(button)
	_items.append(item)
	_rows.append(button)


func _fill_detail(item: Dictionary) -> void:
	if item.has("portrait"):
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		var portrait := TextureRect.new()
		portrait.texture = item["portrait"]
		portrait.custom_minimum_size = Vector2(64, 64) if item["portrait"].get_width() == 64 else Vector2(32, 64)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.modulate = item.get("portrait_color", Color.WHITE)
		head.add_child(portrait)
		var title_box := VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# al lado del retrato queda menos ancho: si las líneas pidieran el del panel entero, lo estirarían fuera de pantalla
		var beside: float = DETAIL_WIDTH - portrait.custom_minimum_size.x - 6.0
		title_box.add_child(_wrapped(item["title"], UiStyle.ACCENT, beside))
		for sub: Dictionary in item.get("subtitle", []):
			title_box.add_child(_wrapped(sub["text"], sub.get("color", UiStyle.DIM), beside))
		head.add_child(title_box)
		_detail_panel.add_child(head)
	else:
		_detail_panel.add_child(_wrapped(item["title"], UiStyle.ACCENT))
		for sub: Dictionary in item.get("subtitle", []):
			_detail_panel.add_child(_wrapped(sub["text"], sub.get("color", UiStyle.DIM)))
	for line: Dictionary in item.get("lines", []):
		_detail_panel.add_child(_wrapped(line["text"], line.get("color", UiStyle.TEXT)))


func _wrapped(text: String, color: Color, width: float = DETAIL_WIDTH) -> Label:
	var label := UiStyle.label(text, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _type_icon(kind: int) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var color: Color = TYPE_COLORS.get(kind, Color.WHITE)
	var dark: Color = color.darkened(0.5)
	if kind == KnowledgeRegistry.Kind.DOCUMENT or kind == KnowledgeRegistry.Kind.DEDUCTION:
		# Sello de lacre: disco con corona y marca central.
		for y in 8:
			for x in 8:
				var d: float = Vector2(x - 3.5, y - 3.5).length()
				if d <= 3.6:
					image.set_pixel(x, y, color if d > 1.6 else dark)
		image.set_pixel(3, 3, color.lightened(0.4))
		image.set_pixel(4, 4, color.lightened(0.4))
	else:
		for y in range(1, 7):
			for x in range(1, 7):
				image.set_pixel(x, y, color if (x + y) % 5 != 0 else dark)
	var texture := ImageTexture.create_from_image(image)
	_icons[kind] = texture
	return texture


# --- 1 · Evidencias -----------------------------------------------------------------------------

func _build_evidence() -> void:
	var data: Dictionary = JournalManager.data()
	var groups: Array = data.get("groups", [])
	var category_group: Dictionary = data.get("category_group", {})
	var by_group: Dictionary = {}
	var counts: Dictionary = {
		KnowledgeRegistry.Kind.DOCUMENT: 0, KnowledgeRegistry.Kind.TESTIMONY: 0,
		KnowledgeRegistry.Kind.WITNESS: 0, KnowledgeRegistry.Kind.PHYSICAL: 0,
	}
	for flag in JournalManager.noted_flags:   # solo lo anotado teniendo el diario (lo de antes se recuerda, no figura)
		var kind: int = KnowledgeRegistry.kind_of(flag)
		if not counts.has(kind) or not LoopManager.has_knowledge(flag):
			continue
		counts[kind] += 1
		var group_id: String = category_group.get(KnowledgeRegistry.FLAGS[flag]["category"], "witnesses")
		if not by_group.has(group_id):
			by_group[group_id] = []
		(by_group[group_id] as Array).append(flag)
	_summary.text = tr("ui_journal_summary") % [counts[KnowledgeRegistry.Kind.DOCUMENT], counts[KnowledgeRegistry.Kind.TESTIMONY], counts[KnowledgeRegistry.Kind.WITNESS], counts[KnowledgeRegistry.Kind.PHYSICAL]]
	if by_group.is_empty():
		_list.add_child(_wrapped(tr("ui_journal_empty_evidence"), UiStyle.DIM))
		return
	for group: Dictionary in groups:
		if not by_group.has(group["id"]):
			continue
		_add_header(tr(group["title_key"]))
		for flag: String in by_group[group["id"]]:
			_add_row(_evidence_item(flag))


func _evidence_item(flag: String) -> Dictionary:
	var kind: int = KnowledgeRegistry.kind_of(flag)
	var is_doc: bool = kind == KnowledgeRegistry.Kind.DOCUMENT
	var lines: Array[Dictionary] = [{"text": tr("desc_" + flag)}]
	if is_doc:
		lines.append({"text": tr("ui_journal_seal_hint"), "color": UiStyle.DIM})
	return {
		"flag": flag, "text": tr("flag_" + flag), "icon": _type_icon(kind), "color": UiStyle.TEXT,
		"unseen": JournalManager.is_unseen(flag), "title": tr("flag_" + flag),
		"subtitle": [{"text": tr(TYPE_KEYS[kind]), "color": TYPE_COLORS[kind]}], "lines": lines,
	}


# --- 2 · Personas -------------------------------------------------------------------------------

## Solo la gente que conoce o de la que oyó hablar: el resto aparece cuando alguien la nombra.
func _build_people() -> void:
	var any: bool = false
	for person: Dictionary in JournalManager.people():
		if JournalManager.is_noted_person(person["id"]):
			_add_row(_person_item(person))
			any = true
	if not any:
		_list.add_child(_wrapped(tr("ui_journal_empty_people"), UiStyle.DIM))


func _person_item(person: Dictionary) -> Dictionary:
	# Solo con lo anotado: el nombre, el apellido o los dos, según lo que se averiguó teniendo el diario.
	var met: bool = JournalManager.is_noted_met(person["id"])
	var heard: bool = JournalManager.noted_name_bits(person["id"]) != 0
	var name_text: String = JournalManager.journal_name(person["id"])
	var item: Dictionary = {
		"text": name_text, "title": name_text, "color": UiStyle.TEXT if met else UiStyle.DIM,
		"icon": _portrait_icon(person), "icon_color": Color.WHITE if met else Color(0.25, 0.25, 0.25),
		"portrait": _portrait_full(person), "portrait_color": Color.WHITE if met else Color(0.22, 0.22, 0.22),
	}
	var lines: Array[Dictionary] = []
	var subtitle: Array[Dictionary] = []
	if met:
		subtitle.append({"text": tr(person["role_key"]), "color": UiStyle.ACCENT})
		subtitle.append({"text": tr("ui_journal_age") % int(person["age"]), "color": UiStyle.DIM})
		lines.append({"text": tr(person["bio_key"])})
		lines.append({"text": tr("ui_journal_known_facts"), "color": UiStyle.DIM})
		var any: bool = false
		for flag: String in person["flags"]:
			if LoopManager.has_knowledge(flag) and JournalManager.is_noted(flag):
				lines.append({"text": "· " + tr("flag_" + flag)})
				any = true
		if not any:
			lines.append({"text": tr("ui_journal_no_facts"), "color": UiStyle.DIM})
	elif heard:
		subtitle.append({"text": tr("ui_journal_heard_of"), "color": UiStyle.DIM})
		for flag: String in person["flags"]:
			if LoopManager.has_knowledge(flag) and JournalManager.is_noted(flag):
				lines.append({"text": "· " + tr("flag_" + flag)})
	else:
		subtitle.append({"text": tr("ui_journal_unknown_role"), "color": UiStyle.DIM})
	item["subtitle"] = subtitle
	item["lines"] = lines
	return item


func _sheet_for(person: Dictionary) -> Texture2D:
	var sheet_id: String = person.get("sheet", "")
	var path: String = SHEETS_DIR % sheet_id if sheet_id != "" else PROTAGONIST_SHEET
	if not ResourceLoader.exists(path):
		path = PROTAGONIST_SHEET
	return load(path)


## Retrato de 64x64 si el personaje tiene uno; si no, el sprite de frente.
func _portrait_full(person: Dictionary) -> Texture2D:
	var portrait_path: String = PORTRAITS_DIR % person.get("sheet", "")
	if person.get("sheet", "") != "" and ResourceLoader.exists(portrait_path):
		return load(portrait_path)
	var cell := AtlasTexture.new()
	cell.atlas = _sheet_for(person)
	cell.region = Rect2(0, 0, 16, 32)
	return cell


func _portrait_icon(person: Dictionary) -> Texture2D:
	var cell := AtlasTexture.new()
	cell.atlas = _sheet_for(person)
	cell.region = Rect2(0, 2, 16, 14)   # cabeza y hombros
	return cell


# --- 3 · Deducciones ----------------------------------------------------------------------------

## Una deducción aparece cuando ya tiene al menos una pieza (los títulos solos adelantarían la historia).
func _build_deductions() -> void:
	var any: bool = false
	for def: Dictionary in DeductionSystem.definitions():
		var parts: Dictionary = DeductionSystem.pieces(def)
		if DeductionSystem.is_resolved(def["id"]) or not (parts["met"] as Array).is_empty() or not (parts["any_met"] as Array).is_empty():
			_add_row(_deduction_item(def))
			any = true
	if not any:
		_list.add_child(_wrapped(tr("ui_journal_empty_deductions"), UiStyle.DIM))


func _deduction_item(def: Dictionary) -> Dictionary:
	var resolved: bool = DeductionSystem.is_resolved(def["id"])
	var parts: Dictionary = DeductionSystem.pieces(def)
	var lines: Array[Dictionary] = []
	for flag: String in def["all_of"]:
		var has: bool = flag in parts["met"]
		lines.append({"text": ("[x] " + tr("flag_" + flag)) if has else "[ ] ?", "color": UiStyle.OK if has else UiStyle.DIM})
	if parts["needs_any"]:
		var found: Array = parts["any_met"]
		if found.is_empty():
			lines.append({"text": "[ ] ?  (%s)" % tr("ui_journal_ded_one_of"), "color": UiStyle.DIM})
		else:
			lines.append({"text": "[x] " + tr("flag_" + found[0]), "color": UiStyle.OK})
	var title: String = tr("flag_" + def["id"]) if resolved else tr(def["title_key"])
	var subtitle: Array[Dictionary] = [{"text": tr("ui_journal_ded_done") if resolved else tr("ui_journal_ded_open"), "color": UiStyle.OK if resolved else UiStyle.DIM}]
	if resolved:
		lines.append({"text": tr("desc_" + def["id"]), "color": UiStyle.ACCENT})
	var summary: String = ""
	if not resolved:
		var slots: int = (def["all_of"] as Array).size() + (1 if parts["needs_any"] else 0)
		var have: int = (parts["met"] as Array).size() + (1 if not (parts["any_met"] as Array).is_empty() else 0)
		summary = "  %d/%d" % [have, slots]
	return {
		"text": tr(def["title_key"]) + summary, "title": title, "subtitle": subtitle, "lines": lines,
		"icon": _type_icon(KnowledgeRegistry.Kind.DEDUCTION if resolved else KnowledgeRegistry.Kind.TESTIMONY),
		"icon_color": Color.WHITE if resolved else Color(0.35, 0.35, 0.35),
		"color": UiStyle.ACCENT if resolved else UiStyle.DIM,
	}


# --- 4 · Mapa -----------------------------------------------------------------------------------

const MAP_ORDER: Array[String] = ["mill", "viaduct", "station_exterior", "north_road", "foundry", "centro", "quarry", "cemetery", "stream"]
const MAP_CELL: Vector2 = Vector2(92, 40)

func _build_map() -> void:
	var cells: Dictionary = JournalManager.data().get("map_cells", {})
	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(286, 4 * (MAP_CELL.y + 8))
	_list.add_child(canvas)
	var parents: Dictionary = JournalManager.data().get("zone_parent", {})
	for zone_id in MAP_ORDER:
		var cell: Array = cells[zone_id]
		# Un exterior cuenta como descubierto si se pisó él o cualquiera de sus interiores.
		var visited: bool = zone_id in JournalManager.visited
		for child_id: String in parents:
			if parents[child_id] == zone_id and child_id in JournalManager.visited:
				visited = true
		var button := UiStyle.button(tr("zone_" + zone_id) if visited else tr("ui_journal_map_unknown"), true)
		button.toggle_mode = true
		button.clip_text = true
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.position = Vector2(cell[0] * (MAP_CELL.x + 4), cell[1] * (MAP_CELL.y + 6))
		button.size = MAP_CELL
		button.custom_minimum_size = MAP_CELL
		if not visited:
			button.add_theme_color_override("font_color", UiStyle.DIM)
		var index: int = _items.size()
		button.pressed.connect(func() -> void: _select(index))
		canvas.add_child(button)
		_items.append(_map_item(zone_id, visited))
		_rows.append(button)
	# Se abre sobre el lugar donde está el jugador.
	var here: int = MAP_ORDER.find(JournalManager.parent_exterior(ZoneManager.current_zone))
	_selected = maxi(here, 0)


func _map_item(zone_id: String, visited: bool) -> Dictionary:
	if not visited:
		return {"title": tr("ui_journal_map_unknown"), "subtitle": [], "lines": []}
	var lines: Array[Dictionary] = []
	var family: Array[String] = [zone_id]
	var parents: Dictionary = JournalManager.data().get("zone_parent", {})
	for child_id: String in parents:
		if parents[child_id] == zone_id and child_id in JournalManager.visited:
			family.append(child_id)
	if family.size() > 1:
		lines.append({"text": tr("ui_journal_map_places"), "color": UiStyle.DIM})
		for place in family.slice(1):
			lines.append({"text": "· " + tr("zone_" + place)})
	lines.append({"text": tr("ui_journal_map_schedules"), "color": UiStyle.DIM})
	var seen_any: bool = false
	for person: Dictionary in JournalManager.people():
		var by_zone: Dictionary = JournalManager.sightings.get(person["id"], {})
		for place in family:
			if not by_zone.has(place):
				continue
			var who: String = JournalManager.journal_name(person["id"])
			var spans: PackedStringArray = []
			for span: Array in by_zone[place]:
				var a: String = TimeManager.format_clock(int(span[0]))
				var b: String = TimeManager.format_clock(int(span[1]))
				spans.append(a if a == b else "%s–%s" % [a, b])
			var where: String = "" if place == zone_id else " (%s)" % tr("zone_" + place)
			lines.append({"text": "%s  %s%s" % [who, ", ".join(spans), where]})
			seen_any = true
	if not seen_any:
		lines.append({"text": tr("ui_journal_map_none"), "color": UiStyle.DIM})
	return {"title": tr("zone_" + zone_id), "subtitle": [], "lines": lines}


# --- 5 · El tren --------------------------------------------------------------------------------

## Lista de gente que se desbloquea con un flag (data/journal.json, "roster"): nombre, edad y qué hace.
func _build_roster() -> void:
	var roster: Dictionary = JournalManager.data().get("roster", {})
	_detail_scroll.visible = false
	_detail_scroll.get_parent().get_child(1).visible = false
	_list_scroll.custom_minimum_size.x = 596.0
	if not LoopManager.has_knowledge(roster.get("unlock_flag", "")):
		_list.add_child(_wrapped(tr(roster.get("empty_key", "")), UiStyle.DIM))
		return
	_list.add_child(_wrapped(tr(roster.get("title_key", "")), UiStyle.ACCENT))
	if roster.has("subtitle_key"):
		_list.add_child(_wrapped(tr(roster["subtitle_key"]), UiStyle.DIM))
	_list.add_child(Control.new())
	for passenger: Dictionary in roster.get("entries", []):
		var row := HBoxContainer.new()
		var name_label := UiStyle.label(tr(passenger["name_key"]), UiStyle.TEXT)
		name_label.custom_minimum_size = Vector2(120, 0)
		var age_label := UiStyle.label(tr("ui_journal_age") % int(passenger["age"]), UiStyle.ACCENT)
		age_label.custom_minimum_size = Vector2(60, 0)
		row.add_child(name_label)
		row.add_child(age_label)
		row.add_child(UiStyle.label(tr(passenger["role_key"]), UiStyle.DIM))
		_list.add_child(row)


# --- 6 · Identificar ----------------------------------------------------------------------------

## Fichas de data/identify.json por grupo: la cara, el nombre que puso el jugador (o «?») y si ya está confirmado.
func _build_identify() -> void:
	var cfg: Dictionary = Identification.config()
	var done: Array[int] = Identification.progress()
	_summary.text = tr("ui_journal_ident_progress") % [done[0], done[1]]
	if not Identification.is_available():
		_list.add_child(_wrapped(tr(cfg.get("empty_key", "ui_journal_ident_empty")), UiStyle.DIM))
		return
	for group: Dictionary in Identification.visible_groups():
		var group_cards: Array = Identification.cards(group["id"])
		var group_done: int = group_cards.filter(func(c: Dictionary) -> bool: return Identification.is_confirmed(c["id"])).size()
		_add_header("%s  %d/%d" % [tr(group["title_key"]), group_done, group_cards.size()])
		for c: Dictionary in group_cards:
			_add_row(_identify_item(c, group))


func _identify_item(c: Dictionary, group: Dictionary) -> Dictionary:
	var guess: String = Identification.guess_of(c["id"])
	var is_done: bool = Identification.is_confirmed(c["id"])
	var shown: String = Identification.name_text(guess) if guess != "" else "?"
	var lines: Array[Dictionary] = [{"text": tr(c.get("look_key", ""))}]
	for clue_key: String in Identification.clues(c["id"]):
		lines.append({"text": "· " + tr(clue_key)})
	return {
		"card": c["id"], "text": ("[x] " if is_done else "") + shown,
		"color": UiStyle.OK if is_done else (UiStyle.TEXT if guess != "" else UiStyle.DIM),
		"icon": _face_icon(c.get("portrait", "")), "portrait": _card_portrait(c.get("portrait", "")),
		"title": shown if guess != "" else tr("ui_journal_ident_unknown"),
		"subtitle": [{"text": tr(group["title_key"]), "color": UiStyle.ACCENT},
				{"text": tr("ui_journal_ident_confirmed") if is_done else tr("ui_journal_ident_pending"),
				"color": UiStyle.OK if is_done else UiStyle.DIM}],
		"lines": lines,
	}


## Debajo de la ficha: la lista de nombres para elegir (con el mouse o con E y las flechas).
func _fill_identify_detail(card_id: String) -> void:
	_pick_buttons.clear()
	if Identification.is_confirmed(card_id):
		return
	_detail_panel.add_child(_wrapped(tr("ui_journal_ident_hint"), UiStyle.DIM))
	var names: Array = Identification.names_available().filter(func(n: Dictionary) -> bool:
		for other: String in Identification.guesses:
			if Identification.guesses[other] == n["id"] and Identification.is_confirmed(other):
				return false   # ya está confirmado en otra ficha
		return true)
	if names.is_empty():
		_detail_panel.add_child(_wrapped(tr("ui_journal_ident_no_names"), UiStyle.DIM))
		return
	var current: String = Identification.guess_of(card_id)
	for n: Dictionary in names:
		var label: String = tr(n["name_key"])
		var elsewhere: bool = Identification.guesses.values().has(n["id"]) and current != n["id"]
		if elsewhere:
			label += "  " + tr("ui_journal_ident_elsewhere")
		var button := UiStyle.button(label, true)
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.button_pressed = n["id"] == current
		if elsewhere:
			button.add_theme_color_override("font_color", UiStyle.DIM)
		var name_id: String = n["id"]
		button.pressed.connect(func() -> void: Identification.guess(card_id, name_id))
		_detail_panel.add_child(button)
		_pick_buttons.append(button)
	if current != "":
		var clear := UiStyle.button(tr("ui_journal_ident_clear"), true)
		clear.alignment = HORIZONTAL_ALIGNMENT_LEFT
		clear.pressed.connect(func() -> void: Identification.clear(card_id))
		_detail_panel.add_child(clear)


func _start_picking() -> void:
	if _pick_buttons.is_empty():
		return
	_picking = true
	_pick_index = maxi(_pick_buttons.map(func(b: Button) -> bool: return b.button_pressed).find(true), 0)
	_show_pick()


## Con el teclado, eligiendo un nombre: arriba/abajo, E (o Enter) lo pone, Esc vuelve a la lista. true = lo usó.
func _pick_input(event: InputEvent) -> bool:
	if event.is_action_pressed("move_up", true):
		_pick_index = (_pick_index + _pick_buttons.size() - 1) % _pick_buttons.size()
	elif event.is_action_pressed("move_down", true):
		_pick_index = (_pick_index + 1) % _pick_buttons.size()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_picking = false
		_pick_buttons[_pick_index].pressed.emit()
		return true
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("journal") or event.is_action_pressed("pause_menu"):
		_picking = false
		_refresh_selection()
		return true
	else:
		return false
	_show_pick()
	return true


func _show_pick() -> void:
	for i in _pick_buttons.size():
		_pick_buttons[i].button_pressed = i == _pick_index
	_detail_scroll.ensure_control_visible(_pick_buttons[_pick_index])


func _card_portrait(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else _type_icon(KnowledgeRegistry.Kind.WITNESS)


## La cara del retrato en chico (para la lista).
func _face_icon(path: String) -> Texture2D:
	if _icons.has(path):
		return _icons[path]
	var texture: Texture2D = _card_portrait(path)
	var image: Image = texture.get_image()
	if image == null:
		return texture
	image.convert(Image.FORMAT_RGBA8)
	var w: int = image.get_width()
	var face: Image = image.get_region(Rect2i(w / 4, w / 8, w / 2, w / 2))
	face.resize(14, 14, Image.INTERPOLATE_NEAREST)
	var icon := ImageTexture.create_from_image(face)
	_icons[path] = icon
	return icon
