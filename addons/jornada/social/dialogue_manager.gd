extends Node
## Reproduce los diálogos de data/dialogue/<npc_id>.json (canon 08).
##
## Una entrada = una línea (<=3 frases). Se encadenan con "next". Los puntos de entrada
## ("entry": true) se eligen por prioridad entre los que cumplen su condición.
## Todo el texto sale de game.csv vía tr(); acá no hay literales de usuario.

signal dialogue_started(npc_id: String)
## options: Array[String] ya traducidas (vacío si no hay elección).
signal line_shown(speaker: String, text: String, stage_direction: String, options: Array, has_next: bool)
signal dialogue_ended(npc_id: String)
## La caja pide completar el texto que se está escribiendo (en vez de avanzar).
signal skip_typing_requested

const DIALOGUE_DIR: String = "res://data/dialogue/"

var is_active: bool = false
var has_options: bool = false
## Lo pone la caja de diálogo mientras escribe el texto letra por letra.
var text_revealing: bool = false

var _npc_id: String = ""
var _speaker: String = ""
var _entries: Dictionary = {}          # id -> entrada del NPC actual
var _entry_points: Array = []
var _current: Dictionary = {}
var _visible_options: Array = []       # opciones disponibles de la línea actual
var _seen_this_loop: Dictionary = {}   # "npc/entrada" -> true
var _cache: Dictionary = {}            # npc_id -> datos parseados
var _noting: bool = false              # último paso: "Anotar en el diario"
## Segundos sin elegir opción → el NPC se despide y se cierra la caja (data/game.json dialogue.idle_seconds).
var _idle_seconds: float = 15.0
var _idle_left: float = -1.0
var _idle_closing: bool = false
var _idle_hold: float = -1.0           # tras la frase de despedida, espera breve y cierra
# Al final de cada charla con una persona: preguntarle el nombre o preguntarle por otra gente (los nombres se aprenden,
# JournalManager.names). "" | "menu" | "pick" | "reply".
var _person: String = ""
var _people_step: String = ""
var _people_done: bool = false
## Quiénes son de afuera, chicos o conocidos por el apellido: data/game.json ("people"), vía GameConfig.
const REFUSALS: int = 4
## Cada persona habla de un solo vecino por loop, más uno por nivel de confianza (<persona>_trust_<n>).
var _asked: Dictionary = {}            # persona -> cuántas veces contestó por alguien en este loop
var _refused: bool = false             # ya se negó en esta charla: no se le vuelve a preguntar


func _ready() -> void:
	_idle_seconds = float(GameConfig.value("dialogue.idle_seconds", 15))
	set_process(true)
	LoopManager.loop_started.connect(func(_n: int) -> void:
		_seen_this_loop.clear()
		_asked.clear())


## Valores que reemplazan {nombre} en los textos de la charla en curso (quien arma la charla los pone antes de `start`; se
## vacía al terminar). Sirve para líneas que dependen de lo que pasó: «{quien} me avisó que lo vio por {lugar}».
var context: Dictionary = {}


func _process(delta: float) -> void:
	if not is_active:
		return
	if _idle_closing:
		if text_revealing:
			return
		if _idle_hold < 0.0:
			_idle_hold = 1.2
		_idle_hold -= delta
		if _idle_hold <= 0.0:
			_idle_closing = false
			_idle_hold = -1.0
			_noting = true
			Toasts.commit_notes()
			_end()
		return
	# Solo en opciones de diálogo (no menú de nombres ni "anotar en el diario").
	if not has_options or text_revealing or _idle_seconds <= 0.0 \
			or _noting or _people_step != "":
		return
	if _idle_left < 0.0:
		_idle_left = _idle_seconds
	_idle_left -= delta
	if _idle_left <= 0.0:
		_begin_idle_dismiss()


## Abre la charla de `npc_id`. Con `entry_id` arranca exactamente en esa entrada (sin mirar condiciones ni prioridad).
func start(npc_id: String, entry_id: String = "") -> bool:
	if is_active:
		return false
	var data: Dictionary = _load_npc(npc_id)
	if data.is_empty():
		return false
	_npc_id = npc_id
	_person = JournalManager.person_for_dialogue(npc_id)
	_people_step = ""
	_refused = false
	_people_done = not npc_id in JournalManager.speakers()   # objetos y puertas no tienen esta parte
	_speaker = JournalManager.display_name(_person) if _person != "" else tr(data["name_key"])
	_entries = data["by_id"]
	_entry_points = data["entry_points"]
	var first: Dictionary = _entries[entry_id] if entry_id != "" and _entries.has(entry_id) else _pick_entry_point()
	if first.is_empty():
		return false
	# Una charla que arranca un sistema (búsqueda, detención) o una entrada con "no_small_talk" no es para preguntar
	# nombres ni por los vecinos: nadie pregunta «¿cómo se llama?» mientras se lo llevan preso.
	if entry_id != "" or first.get("no_small_talk", false):
		_people_done = true
	is_active = true
	_idle_closing = false
	_idle_left = -1.0
	_idle_hold = -1.0
	dialogue_started.emit(npc_id)
	_show(first)
	return true


## Ids de todas las entradas del diálogo de un NPC (vacío si no tiene).
func entry_ids(npc_id: String) -> Array:
	var data: Dictionary = _load_npc(npc_id) if has_dialogue(npc_id) else {}
	return data.get("by_id", {}).keys()


## El jugador no eligió: el NPC se despide y se cierra la caja.
## Los objetos examinables (obj_*) cierran en silencio: no hablan.
func _begin_idle_dismiss() -> void:
	_idle_left = -1.0
	_idle_closing = true
	_idle_hold = -1.0
	_people_step = ""
	_visible_options = []
	has_options = false
	if _npc_id.begins_with("obj_"):
		_idle_closing = false
		_noting = true
		Toasts.commit_notes()
		_end()
		return
	line_shown.emit(_speaker, tr("dlg_idle_dismiss"), "", [], false)


## ¿Tiene archivo de diálogo? Los extras y los pasajeros no: contestan con ChatterSystem.brush_off.
func has_dialogue(npc_id: String) -> bool:
	return _cache.has(npc_id) or FileAccess.file_exists(DIALOGUE_DIR + npc_id + ".json")


## ¿Habría algo que decir ahora? Lo usan los objetos examinables para mostrar (o no) el aviso [E].
func can_start(npc_id: String) -> bool:
	var data: Dictionary = _load_npc(npc_id)
	if data.is_empty():
		return false
	return not _pick_entry_point(npc_id, data["entry_points"]).is_empty()


## Corta el diálogo en curso sin efectos (fin del loop, arresto). El NPC retoma su horario. Lo aprendido se anota igual.
func abort() -> void:
	if is_active:
		_idle_closing = false
		_idle_left = -1.0
		_idle_hold = -1.0
		_noting = true
		Toasts.commit_notes()
		_end()


## Avanza cuando la línea no ofrece opciones.
func advance() -> void:
	if not is_active or has_options:
		return
	if _idle_closing:
		# Cierra al toque si el jugador confirma durante la despedida.
		if text_revealing:
			skip_typing_requested.emit()
			return
		_idle_closing = false
		_idle_hold = -1.0
		_noting = true
		Toasts.commit_notes()
		_end()
		return
	if text_revealing:
		skip_typing_requested.emit()
		return
	if _people_step == "reply":
		_show_people_menu()
		return
	var next_id: String = _current.get("next", "")
	if next_id == "":
		_end()
	else:
		_show(_entries[next_id])


## Elige la opción n (0-based) de la línea actual.
func choose(index: int) -> void:
	if not is_active or not has_options or text_revealing or index < 0 or index >= _visible_options.size():
		return
	_idle_left = -1.0
	if _noting:
		Toasts.commit_notes()
		_end()
		return
	if _people_step != "":
		_choose_people(_visible_options[index])
		return
	var option: Dictionary = _visible_options[index]
	_apply(option.get("reveals", []), option.get("suspicion_delta", 0), option.get("effects", []))
	var next_id: String = option.get("next", "")
	if next_id == "":
		_end()
	else:
		_show(_entries[next_id])


func _show(entry: Dictionary) -> void:
	_current = entry
	_idle_left = -1.0
	_seen_this_loop["%s/%s" % [_npc_id, entry["id"]]] = true
	_apply(entry.get("reveals", []), entry.get("suspicion_delta", 0), entry.get("effects", []))
	# "learns_name": la persona se presenta en esta línea (first | last | full); desde acá el diálogo y el diario la nombran.
	var learns: String = entry.get("learns_name", "")
	if learns != "" and _person != "":
		var bits: Dictionary = {"first": JournalManager.FIRST, "last": JournalManager.LAST, "full": JournalManager.FULL}
		JournalManager.learn_name(_person, int(bits.get(learns, 0)))
		_speaker = JournalManager.display_name(_person)
	_visible_options = (entry.get("options", []) as Array).filter(_option_available)
	has_options = not _visible_options.is_empty()
	var labels: Array = _visible_options.map(func(o: Dictionary) -> String: return tr(o["text_key"]))
	var sd: String = tr(entry["sd_key"]) if entry.has("sd_key") else ""
	var text: String = tr(entry["text_key"])
	if not context.is_empty():
		text = text.format(context)
	line_shown.emit(_speaker, text, sd, labels, entry.get("next", "") != "")


func _end() -> void:
	# Despedida por inactividad: no abre el menú de nombres ni la tarjeta de anotar.
	if not _idle_closing and not _noting and not _people_done and not _people_questions().is_empty():
		_show_people_menu()
		return
	# Si en la charla apareció algo para el diario, el último paso es anotarlo (no se tapa con avisos mientras se lee).
	if not _idle_closing and not _noting and not Toasts.pending_notes().is_empty():
		_noting = true
		var lines: PackedStringArray = [tr("ui_note_intro")]
		for flag: String in Toasts.pending_notes():
			lines.append("· " + tr("flag_" + flag))
		_visible_options = [{"text_key": "ui_note_take"}]
		has_options = true
		_idle_left = -1.0
		line_shown.emit(tr("ui_note_speaker"), "\n".join(lines), "", [tr("ui_note_take")], false)
		return
	_noting = false
	_idle_closing = false
	_idle_left = -1.0
	_idle_hold = -1.0
	_people_step = ""
	_person = ""
	context = {}
	is_active = false
	has_options = false
	var finished: String = _npc_id
	_npc_id = ""
	_current = {}
	dialogue_ended.emit(finished)


# --- Nombres: preguntar cómo se llama o por otra gente ----------------------------------------------

func _people_questions() -> Array:
	var out: Array = []
	if _person == "":
		return out
	if not JournalManager.name_bits(_person) & JournalManager.FIRST:
		out.append({"id": "name", "label": tr("ui_people_ask_name")})
	if not GameConfig.in_group("outsiders", _npc_id) and not _refused and not _people_candidates().is_empty():
		out.append({"id": "ask", "label": tr("ui_people_ask_about")})
	return out


## Gente que vio o conoce y de la que todavía no sabe el nombre completo (menos el que tiene enfrente).
func _people_candidates() -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in JournalManager.people():
		var pid: String = p["id"]
		var bits: int = JournalManager.name_bits(pid)
		if pid == _person or bits == JournalManager.FULL:
			continue
		if JournalManager.sightings.has(pid) or JournalManager.is_met(pid) or bits != 0:
			out.append(pid)
	return out


## Por cuántos vecinos le contesta en este loop: uno, más uno por nivel de confianza.
func _people_allowance() -> int:
	for level in [3, 2, 1]:
		if LoopManager.has_knowledge("%s_trust_%d" % [_person, level]):
			return 1 + level
	return 1


func _show_people_menu() -> void:
	var questions: Array = _people_questions()
	if questions.is_empty():
		_people_done = true
		_people_step = ""
		_end()
		return
	_people_step = "menu"
	_visible_options = questions + [{"id": "done", "label": tr("ui_people_done")}]
	has_options = true
	line_shown.emit(_speaker, tr("ui_people_more"), "", _visible_options.map(func(o: Dictionary) -> String: return o["label"]), false)


func _choose_people(option: Dictionary) -> void:
	match option["id"]:
		"done":
			_people_done = true
			_people_step = ""
			_end()
		"name":
			JournalManager.learn_name(_person, JournalManager.FIRST)
			_speaker = JournalManager.display_name(_person)
			_people_reply(tr("dlg_people_myname") % tr("first_" + _person))
		"ask":
			if int(_asked.get(_person, 0)) >= _people_allowance():
				# Ya contó lo que estaba dispuesto a contar: sin más confianza no habla de los vecinos.
				_refused = true
				var key: String = "dlg_people_refuse_kid" if GameConfig.in_group("kids", _person) else "dlg_people_refuse_%d" % randi_range(1, REFUSALS)
				_people_reply(tr(key))
				return
			_people_step = "pick"
			var picks: Array = []
			for pid: String in _people_candidates().slice(0, 6):
				picks.append({"id": "who:" + pid, "label": JournalManager.display_name(pid)})
			_visible_options = picks + [{"id": "back", "label": tr("ui_people_back")}]
			has_options = true
			line_shown.emit(_speaker, tr("ui_people_who"), "", _visible_options.map(func(o: Dictionary) -> String: return o["label"]), false)
		"back":
			_show_people_menu()
		_:
			_asked[_person] = int(_asked.get(_person, 0)) + 1
			_tell_about(String(option["id"]).trim_prefix("who:"))


## Contesta por una persona con un solo dato: lo primero que dice el pueblo de ella (el apellido o el nombre) o, si
## ya sabe uno, el que falta (y entonces, quién es).
func _tell_about(pid: String) -> void:
	var bits: int = JournalManager.name_bits(pid)
	if bits == 0:
		if GameConfig.in_group("known_by_surname", pid):
			JournalManager.learn_name(pid, JournalManager.LAST)
			_people_reply(tr("dlg_people_surname") % tr("last_" + pid))
		else:
			JournalManager.learn_name(pid, JournalManager.FIRST)
			_people_reply(tr("dlg_people_thats") % tr("first_" + pid))
		return
	var asked_as: String = JournalManager.display_name(pid)
	JournalManager.learn_name(pid, JournalManager.FULL)
	var person: Dictionary = JournalManager.person(pid)
	_people_reply(tr("dlg_people_fullname") % [asked_as, tr(person["name_key"]), tr(person["role_key"])])


func _people_reply(text: String) -> void:
	_people_step = "reply"
	_visible_options = []
	has_options = false
	line_shown.emit(_speaker, text, "", [], true)


func _apply(reveals: Array, suspicion_delta: int, effects: Array = []) -> void:
	for flag: String in reveals:
		LoopManager.gain_knowledge(flag)
	GameManager.add_suspicion(suspicion_delta)
	for effect: String in effects:
		WorldEffects.apply(effect)


func _pick_entry_point(npc_id: String = _npc_id, entry_points: Array = _entry_points) -> Dictionary:
	var best: Dictionary = {}
	var best_priority: int = -1
	for entry: Dictionary in entry_points:
		if entry.get("once_per_loop", false) and _seen_this_loop.has("%s/%s" % [npc_id, entry["id"]]):
			continue
		if not _conditions_met(entry.get("condition", {})):
			continue
		var priority: int = entry.get("priority", 0)
		if priority > best_priority:
			best = entry
			best_priority = priority
	return best


func _conditions_met(cond: Dictionary) -> bool:
	if LoopManager.loop_number < cond.get("loop_min", 1):
		return false
	if LoopManager.loop_number > cond.get("loop_max", 9999):
		return false
	if GameManager.suspicion < cond.get("suspicion_min", 0):
		return false
	if GameManager.suspicion > cond.get("suspicion_max", 100):
		return false
	# "zones": solo en esos lugares (p. ej. la charla larga de la jefa de estación, en la estación y no en la posada).
	var zones: Array = cond.get("zones", [])
	if not zones.is_empty() and not ZoneManager.current_zone in zones:
		return false
	# Tareas de trabajo hechas hoy (p. ej. quien dio la orden comenta cuando se las entregan).
	var tasks: int = WorkManager.completed_count()
	if tasks < cond.get("tasks_min", 0) or tasks > cond.get("tasks_max", 9999):
		return false
	return _time_ok(cond) and _knowledge_ok(cond.get("knowledge", []), cond.get("knowledge_any", []), cond.get("not_knowledge", []))


func _option_available(option: Dictionary) -> bool:
	if LoopManager.loop_number < option.get("loop_min", 1) or LoopManager.loop_number > option.get("loop_max", 9999):
		return false
	return _time_ok(option) and _knowledge_ok(option.get("requires", []), option.get("requires_any", []), option.get("not_requires", []))


func _time_ok(rules: Dictionary) -> bool:
	var now: int = TimeManager.now_minutes()
	if rules.has("time_min") and now < TimeManager.parse_clock(rules["time_min"]):
		return false
	if rules.has("time_max") and now > TimeManager.parse_clock(rules["time_max"]):
		return false
	return true


func _knowledge_ok(all_of: Array, any_of: Array, none_of: Array) -> bool:
	for flag: String in all_of:
		if not LoopManager.has_knowledge(flag):
			return false
	for flag: String in none_of:
		if LoopManager.has_knowledge(flag):
			return false
	if any_of.is_empty():
		return true
	for flag: String in any_of:
		if LoopManager.has_knowledge(flag):
			return true
	return false


func _load_npc(npc_id: String) -> Dictionary:
	if _cache.has(npc_id):
		return _cache[npc_id]
	var path: String = DIALOGUE_DIR + npc_id + ".json"
	if not FileAccess.file_exists(path):
		push_warning("DialogueManager: no existe %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DialogueManager: JSON inválido en %s" % path)
		return {}
	var by_id: Dictionary = {}
	var entry_points: Array = []
	for entry: Dictionary in parsed.get("entries", []):
		by_id[entry["id"]] = entry
		if entry.get("entry", false):
			entry_points.append(entry)
	var data: Dictionary = {"name_key": parsed["name_key"], "by_id": by_id, "entry_points": entry_points}
	_cache[npc_id] = data
	return data
