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
# Al final de cada charla con una persona: preguntarle el nombre o preguntarle por otra gente (los nombres se aprenden,
# JournalManager.names). "" | "menu" | "pick" | "reply".
var _person: String = ""
var _people_step: String = ""
var _people_done: bool = false
## Quiénes son de afuera, chicos o conocidos por el apellido: data/game.json ("people"), vía GameConfig.
const REFUSALS: int = 4
## Variantes de la negativa antes de from_loop (data/relations.json). Las demás respuestas por alguien se arman con
## _about_line / _voiced_line, que buscan sus variantes en el CSV.
const EARLY_REFUSALS: int = 3
## Cada persona habla de un solo vecino por loop, más uno por nivel de confianza (<persona>_trust_<n>).
var _asked: Dictionary = {}            # persona -> cuántas veces contestó por alguien en este loop
var _refused: bool = false             # ya se negó en esta charla: no se le vuelve a preguntar
var _people_queue: Array[String] = []  # líneas que siguen de una respuesta (tras la frase de un lazo)
var _people_then: String = ""          # tras una negativa con "entry", la charla sigue por esa entrada

## Preguntas repetidas: una opción "ask" ya contestada en este loop no se vuelve a contestar: «eso ya se lo contesté»
## (dlg_repeat_answered). Con confianza (Trust, data/trust.json) cada repetición más allá de su paciencia baja un nivel, y
## en el mínimo corta la charla (dlg_repeat_busy) y por el resto del loop no le habla: al acercarse, un globo
## (bark_repeat_snub). Sin confianza, corta al repetir data/game.json "dialogue.repeats_to_snub" veces.
## Las tres frases admiten la propia del NPC (<clave>_<npc>), la de su voz (<clave>_<voz>) y variantes _1, _2...
## Una opción con "repeatable": true (o con costo o efectos: pedir otra cerveza) se puede elegir siempre.
## Confianza: una línea u opción con "trust": n la sube o la baja (Trust). Una opción con "once_per_loop": true se elige
## una sola vez por loop (los halagos: si no, se podría subir la confianza sin fin). "needs_names": true, solo cuando ya
## se pueden aprender nombres (la respuesta dice uno). Las opciones no desaparecen al usarlas: la caja las atenúa.
var _answered: Dictionary = {}         # "npc/clave de la opción" -> true, en este loop
var _repeats: Dictionary = {}          # npc -> cuántas veces repitió una pregunta en este loop
var _snubbed: Dictionary = {}          # npc -> true: no le habla más en este loop
var _aside: String = ""                # tras una frase suelta: "back" vuelve a las opciones, "end" cierra, "entry:<id>" sigue ahí
var _name_refused: Dictionary = {}    # persona -> true: ya se negó a decir su nombre en este loop
var _inline_people: bool = false       # esta charla ya ofreció «¿cómo se llama?» entre sus opciones: no hay menú al final
## «¿Usted es Erna?» (Identification): con un nombre puesto en la ficha de quien tiene enfrente, se le puede preguntar
## una vez por loop. Si acierta, el dato queda confirmado y sube la confianza; si no, queda tachado en su ficha y la
## reacción depende del lazo con la verdadera dueña del nombre (data/relations.json, `wrong_name` de cada tipo):
##   "snub"    se ofende: la confianza va al mínimo y no le habla más hasta el día siguiente (rivales, rencores)
##   "friend"  «esa es mi amiga»: si hay frase propia (dlg_people_guess_friend_<quien>_<la otra>), le cuenta quién es
##   (nada)    un «no» seco y un nivel menos de confianza
## Frases: dlg_people_guess_<right|wrong|friend|snub>[_<quien contesta>[_<la otra>]|_<voz>], con variantes _1, _2...
var _guessed: Dictionary = {}          # persona -> true: ya se le preguntó si es tal en este loop


func _ready() -> void:
	LoopManager.loop_started.connect(func(_n: int) -> void: _reset_loop())
	LoopManager.game_reset.connect(_reset_loop)


func _reset_loop() -> void:
	_seen_this_loop.clear()
	_asked.clear()
	_answered.clear()
	_repeats.clear()
	_snubbed.clear()
	_name_refused.clear()
	_guessed.clear()


## ¿La línea en pantalla descubre algo nuevo para el diario? La caja toca el sonido de descubrimiento cuando termina
## de escribirla (lo que da la opción elegida cuenta para la línea que sigue).
var line_discovers: bool = false
var _discovering: bool = false


## Valores que reemplazan {nombre} en los textos de la charla en curso (quien arma la charla los pone antes de `start`; se
## vacía al terminar). Sirve para líneas que dependen de lo que pasó: «{quien} me avisó que lo vio por {lugar}».
var context: Dictionary = {}


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
	_people_queue.clear()
	_people_then = ""
	_aside = ""
	_inline_people = false
	_refused = false
	_people_done = not npc_id in JournalManager.speakers()   # objetos y puertas no tienen esta parte
	_speaker = Identification.shown_name(_person) if _person != "" else tr(data["name_key"])
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
	GameManager.sync_day_clock()   # la charla no gasta minutos del día
	dialogue_started.emit(npc_id)
	_show(first)
	return true


## Quién habla ahora (como lo nombra el técnico, o el objeto que se mira); "" si no hay charla.
func speaker() -> String:
	return _speaker if is_active else ""


## Ids de todas las entradas del diálogo de un NPC (vacío si no tiene).
func entry_ids(npc_id: String) -> Array:
	var data: Dictionary = _load_npc(npc_id) if has_dialogue(npc_id) else {}
	return data.get("by_id", {}).keys()


## El jugador no eligió: el NPC se despide y se cierra la caja.
## Los objetos examinables (obj_*) cierran en silencio: no hablan.
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
	if not is_active:
		return
	_people_done = true   # sin menú de nombres ni "anotar": se corta ya
	_people_step = ""
	_noting = true
	Toasts.commit_notes()
	_end()


## Avanza cuando la línea no ofrece opciones.
func advance() -> void:
	if not is_active or has_options:
		return
	if text_revealing:
		skip_typing_requested.emit()
		return
	if _aside != "":
		var then: String = _aside
		_aside = ""
		if then == "end":
			_people_done = true   # cortó la charla: sin «¿cómo se llama?» ni preguntas por nadie
			_end()
		elif then.begins_with("entry:"):
			_people_step = ""
			_show(_entries[then.trim_prefix("entry:")])
		else:
			_emit(_current)
		return
	if _people_step == "reply":
		if _people_then != "":
			var then: String = _people_then
			_people_then = ""
			_people_step = ""
			_show(_entries[then])
			return
		if not _people_queue.is_empty():
			_people_reply(_people_queue.pop_front())
			return
		_back_to_talk()
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
	if _noting:
		Toasts.commit_notes()
		_end()
		return
	if _people_step != "" or _visible_options[index].get("people", false):
		_choose_people(_visible_options[index])
		return
	var option: Dictionary = _visible_options[index]
	if _is_repeat(option):
		_repeat(option.get("method", "") == "empathy")
		return
	if _counts_as_question(option) or option.get("once_per_loop", false):
		_answered["%s/%s" % [_npc_id, option["text_key"]]] = true
	if option.has("cost"):
		Wallet.debit(float(option["cost"]))
	_discovering = _discovers(option.get("reveals", []))
	_apply(option.get("reveals", []), option.get("suspicion_delta", 0), option.get("effects", []))
	Trust.change(_person, int(option.get("trust", 0)))
	var next_id: String = option.get("next", "")
	if next_id == "":
		_end()
	else:
		_show(_entries[next_id])


func _show(entry: Dictionary) -> void:
	_current = entry
	_seen_this_loop["%s/%s" % [_npc_id, entry["id"]]] = true
	line_discovers = _discovering or _discovers(entry.get("reveals", []))
	_discovering = false
	_apply(entry.get("reveals", []), entry.get("suspicion_delta", 0), entry.get("effects", []))
	Trust.change(_person, int(entry.get("trust", 0)))
	# "learns_name": la persona se presenta en esta línea (first | last | full); desde acá el diálogo y el diario la nombran.
	var learns: String = entry.get("learns_name", "")
	if learns != "" and _person != "":
		var bits: Dictionary = {"first": JournalManager.FIRST, "last": JournalManager.LAST, "full": JournalManager.FULL}
		JournalManager.learn_name(_person, int(bits.get(learns, 0)))
		_speaker = Identification.shown_name(_person)
	# "names": {npc: first|last|full}: en esta línea nombra a otro (Ilse habla de su patrón); el técnico lo aprende.
	var named: Dictionary = entry.get("names", {})
	for npc_id: String in named:
		var pid: String = JournalManager.person_for_dialogue(npc_id)
		if pid != "":
			var parts: Dictionary = {"first": JournalManager.FIRST, "last": JournalManager.LAST, "full": JournalManager.FULL}
			JournalManager.learn_name(pid, int(parts.get(named[npc_id], 0)))
	_emit(entry)


## Muestra la línea de una entrada con sus opciones (sin volver a dar lo que da: para regresar a ella).
func _emit(entry: Dictionary) -> void:
	_visible_options = _options_of(entry).filter(_option_available)
	# «¿Cómo se llama?» y «le quería preguntar por alguien» van entre las opciones, antes de las de callarse.
	if not _visible_options.is_empty() and not _people_done:
		var extra: Array = _people_questions().map(func(q: Dictionary) -> Dictionary:
			var o: Dictionary = q.duplicate()
			o["people"] = true
			return o)
		if not extra.is_empty():
			_inline_people = true
			var at: int = _visible_options.size()
			for i in _visible_options.size():
				if _visible_options[i].get("method", "") == "silence":
					at = i
					break
			for o: Dictionary in extra:
				_visible_options.insert(at, o)
				at += 1
	has_options = not _visible_options.is_empty()
	var labels: Array = _visible_options.map(func(o: Dictionary) -> String: return o["label"] if o.has("label") else tr(o["text_key"]))
	var sd: String = tr(entry["sd_key"]) if entry.has("sd_key") else ""
	var text: String = tr(entry["text_key"])
	if not context.is_empty():
		text = text.format(context)
	Identification.hear_text(text)   # lo que le dicen de frente se anota solo (la caja lo resalta)
	line_shown.emit(_speaker, text, sd, labels, entry.get("next", "") != "")


## Las opciones de una entrada: las suyas o, con "options_of": "<entrada>", las de esa (el saludo de cada mañana ofrece
## lo mismo que el mostrador, sin copiarlo).
func _options_of(entry: Dictionary) -> Array:
	if entry.has("options_of") and _entries.has(entry["options_of"]):
		return _entries[entry["options_of"]].get("options", [])
	return entry.get("options", [])


## ¿La opción n de las que se ven ya está usada? (la eligió en este loop, o ya sabe todo lo que da). Sigue disponible;
## la caja la muestra más tenue.
func option_used(index: int) -> bool:
	if index < 0 or index >= _visible_options.size() or _people_step != "":
		return false
	var option: Dictionary = _visible_options[index]
	if not option.has("text_key") or option.get("method", "") == "silence":
		return false
	if _answered.has("%s/%s" % [_npc_id, option["text_key"]]):
		return true
	var gives: Array = (option.get("reveals", []) as Array).duplicate()
	var target: Dictionary = _entries.get(option.get("next", ""), {})
	gives.append_array(target.get("reveals", []))
	return not gives.is_empty() and gives.all(func(f: String) -> bool: return LoopManager.has_knowledge(f))


## Una pregunta («ask», sin costo ni efectos) que ya contestó en este loop.
## Preguntar lo mismo o decir dos veces lo mismo («Parece cansado»): la segunda vez es una repetición (gasta paciencia).
func _counts_as_question(option: Dictionary) -> bool:
	return option.get("method", "") in ["ask", "empathy"] and not option.get("repeatable", false) \
			and not option.has("cost") and (option.get("effects", []) as Array).is_empty()


func _is_repeat(option: Dictionary) -> bool:
	return _counts_as_question(option) and _answered.has("%s/%s" % [_npc_id, option["text_key"]])


func _repeat(said: bool = false) -> void:
	_repeats[_npc_id] = int(_repeats.get(_npc_id, 0)) + 1
	var stage: String = "said" if said else "answered"   # "said": le repite un cumplido o una pregunta de cortesía
	_aside = "back"
	if Trust.enabled and _person != "":
		if int(_repeats[_npc_id]) > Trust.patience(_person):
			Trust.change(_person, -1)
		if Trust.snubbed(_person):
			stage = "busy"
			_aside = "end"
	elif int(_repeats[_npc_id]) >= int(GameConfig.value("dialogue.repeats_to_snub", 2)):
		stage = "busy"
		_aside = "end"
		_snubbed[_npc_id] = true
	var text: String = _repeat_line(stage, _npc_id)
	_visible_options = []
	has_options = false
	line_shown.emit(_speaker, text, "", [], true)


## ¿Ya no le habla en este loop (lo hartó: la confianza en el mínimo o, sin confianza, preguntándole lo mismo)?
func snubs(npc_id: String) -> bool:
	return _snubbed.has(npc_id) or Trust.snubbed(JournalManager.person_for_dialogue(npc_id))


## Lo que dice quien ya no le habla, en vez de abrir la charla.
func snub_line(npc_id: String) -> String:
	return _repeat_line("snub", npc_id)


func _repeat_line(stage: String, npc_id: String) -> String:
	var base: String = ("bark_repeat_" if stage == "snub" else "dlg_repeat_") + stage
	var bases: Array[String] = ["%s_%s" % [base, npc_id]]
	var person: String = JournalManager.person_for_dialogue(npc_id)
	var voice: String = Relations.voice(person) if person != "" else ""
	if voice != "":
		bases.append("%s_%s" % [base, voice])
	bases.append(base)
	return _pick_line(bases)


## Después de contestar por alguien: vuelve a las opciones de la charla (o, si la charla no tenía, al menú del final).
func _back_to_talk() -> void:
	_people_step = ""
	if _inline_people and not _current.is_empty() and not _options_of(_current).is_empty():
		_emit(_current)
	else:
		_show_people_menu()


func _end() -> void:
	if not _noting and not _people_done and not _inline_people and not _people_questions().is_empty():
		_show_people_menu()
		return
	# Si en la charla apareció algo para el diario, el último paso es anotarlo (no se tapa con avisos mientras se lee).
	if not _noting and not Toasts.pending_notes().is_empty():
		_noting = true
		var lines: PackedStringArray = [tr("ui_note_intro")]
		for flag: String in Toasts.pending_notes():
			lines.append("· " + tr("flag_" + flag))
		_visible_options = [{"text_key": "ui_note_take"}]
		has_options = true
		line_shown.emit(tr("ui_note_speaker"), "\n".join(lines), "", [tr("ui_note_take")], false)
		return
	_noting = false
	_people_step = ""
	_person = ""
	context = {}
	is_active = false
	has_options = false
	var finished: String = _npc_id
	_npc_id = ""
	_current = {}
	GameManager.sync_day_clock()
	dialogue_ended.emit(finished)


# --- Nombres: preguntar cómo se llama o por otra gente ----------------------------------------------

func _people_questions() -> Array:
	var out: Array = []
	if _person == "":
		return out
	if JournalManager.names_allowed() and not JournalManager.name_bits(_person) & JournalManager.FIRST \
			and not _name_refused.has(_person):
		out.append({"id": "name", "label": tr("ui_people_ask_name")})
	var guess: Array = Identification.askable_guess(_person)
	if not guess.is_empty() and JournalManager.names_allowed() and not _guessed.has(_person):
		var label_key: String = "ui_people_ask_guess_" + String(Identification.field(guess[0]).get("journal_bit", ""))
		out.append({"id": "guess", "label": tr(label_key) % Identification.option_text(guess[0], guess[1])})
	# Antes de from_loop (data/relations.json) nadie habla de nadie: ni se ofrece la pregunta.
	if not GameConfig.in_group("outsiders", _npc_id) and not _refused and not _people_candidates().is_empty() \
			and not (Relations.enabled() and LoopManager.loop_number < Relations.from_loop()):
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


## Por cuántos vecinos le contesta en este loop, según la confianza: data/relations.json "allowance" (uno por nivel,
## desde 0; en Rabenholz 1, 1, 2, 2). Sin esa lista, uno más uno por nivel.
func _people_allowance() -> int:
	var level: int = 0
	for n in [3, 2, 1]:
		if LoopManager.has_knowledge("%s_trust_%d" % [_person, n]):
			level = n
			break
	var table: Array = Relations.data().get("allowance", [])
	if table.is_empty():
		return 1 + level
	return int(table[mini(level, table.size() - 1)])


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
			# data/game.json "people.keeps_name": no lo da (el de la cuatro); se lo pregunta igual, pero no aprende nada.
			if GameConfig.in_group("keeps_name", _person):
				_name_refused[_person] = true
				_people_reply(_pick_line(["dlg_people_myname_refuse_" + _person, "dlg_people_myname_refuse"]))
				return
			JournalManager.learn_name(_person, JournalManager.FIRST)
			_speaker = Identification.shown_name(_person)
			_people_reply(tr("dlg_people_myname") % tr("first_" + _person))
		"guess":
			_guess_name()
		"ask":
			var gate: Dictionary = _gate()
			if not gate.is_empty():
				# Todavía no habla de los vecinos (primer día, sin la segunda cerveza, sin haberlo escuchado...). Con
				# "entry", la charla sigue por ahí (Hanns le ofrece otra); si no, por hoy no se le vuelve a preguntar.
				var then: String = String(gate.get("entry", ""))
				if then != "" and _entries.has(then):
					_people_then = then
				else:
					_refused = true
				_people_reply(tr(String(gate.get("refuse", ""))))
				return
			if int(_asked.get(_person, 0)) >= _people_allowance():
				# Ya contó lo que estaba dispuesto a contar: sin más confianza no habla de los vecinos.
				_refused = true
				var key: String = "dlg_people_refuse_kid" if GameConfig.in_group("kids", _person) else "dlg_people_refuse_%d" % randi_range(1, REFUSALS)
				var refusals: Array[String] = ["dlg_people_refuse_" + _person, key]   # la propia, si tiene
				_people_reply(_pick_line(refusals))
				return
			_people_step = "pick"
			var picks: Array = []
			for pid: String in _people_candidates().slice(0, 6):
				picks.append({"id": "who:" + pid, "label": JournalManager.display_name(pid)})
			_visible_options = picks + [{"id": "back", "label": tr("ui_people_back")}]
			has_options = true
			line_shown.emit(_speaker, tr("ui_people_who"), "", _visible_options.map(func(o: Dictionary) -> String: return o["label"]), false)
		"back":
			_back_to_talk()
		_:
			var pid: String = String(option["id"]).trim_prefix("who:")
			if Relations.enabled():
				_answer_about(pid)
			else:
				_asked[_person] = int(_asked.get(_person, 0)) + 1
				_tell_about(pid)


## «¿Usted es Erna?»: contesta según sea o no, y según el lazo con quien sí lo es.
func _guess_name() -> void:
	var guess: Array = Identification.askable_guess(_person)
	if guess.is_empty():
		_back_to_talk()
		return
	_guessed[_person] = true
	var field_id: String = guess[0]
	var option_id: String = guess[1]
	var bit: int = {"first": JournalManager.FIRST, "last": JournalManager.LAST}.get(
			Identification.field(field_id).get("journal_bit", ""), 0)
	if Identification.is_answer(_person, field_id, option_id):
		Identification.confirm_field(_person, field_id, option_id)
		JournalManager.learn_name(_person, bit)
		_speaker = Identification.shown_name(_person)
		Trust.change(_person, 1)
		_people_reply(_guess_line("right"))
		return
	Identification.rule_out(_person, field_id, option_id)
	_speaker = Identification.shown_name(_person)
	# La reacción más fuerte entre quien contesta y cada dueña de ese nombre (un apellido puede ser de varios).
	var reaction: String = ""
	var other: String = ""
	for holder: String in Identification.holders(field_id, option_id):
		var kind: String = String(Relations.rules(String(Relations.tie(_person, holder).get("type", ""))).get("wrong_name", ""))
		if kind == "snub" or (kind == "friend" and reaction == ""):
			reaction = kind
			other = holder
	match reaction:
		"snub":
			Trust.change(_person, -99)
			if not Trust.enabled:
				_snubbed[_npc_id] = true
			_visible_options = []
			has_options = false
			_aside = "end"
			line_shown.emit(_speaker, _guess_line("snub", other), "", [], true)
		"friend":
			var own: String = "dlg_people_guess_friend_%s_%s" % [_person, other]
			if tr(own) != own:
				JournalManager.learn_name(other, bit)   # le cuenta quién es: ahora se sabe de quién es ese nombre
				_people_reply(tr(own))
			else:
				_people_reply(_guess_line("friend"))
		_:
			Trust.change(_person, -1)
			_people_reply(_guess_line("wrong"))


func _guess_line(what: String, other: String = "") -> String:
	var base: String = "dlg_people_guess_" + what
	var bases: Array[String] = []
	if other != "":
		bases.append("%s_%s_%s" % [base, _person, other])
	bases.append("%s_%s" % [base, _person])
	var voice: String = Relations.voice(_person)
	if voice != "":
		bases.append("%s_%s" % [base, voice])
	bases.append(base)
	return _pick_line(bases)


## Por qué no habla de los vecinos ahora ({"refuse": clave del CSV, "entry"?}), o vacío si habla.
func _gate() -> Dictionary:
	if not Relations.enabled():
		return {}
	if LoopManager.loop_number < Relations.from_loop():
		return {"refuse": "dlg_people_refuse_kid" if GameConfig.in_group("kids", _person) else "dlg_people_early_%d" % randi_range(1, EARLY_REFUSALS)}
	return Relations.gate(_person, ZoneManager.current_zone)


## Qué sabe ya el técnico de alguien, en capas: 0 nada, 1 qué hace, 2 un nombre, 3 nombre completo.
func _layer(pid: String) -> int:
	var bits: int = JournalManager.name_bits(pid)
	if bits == JournalManager.FULL:
		return 3
	if bits != 0:
		return 2
	return 1 if pid in JournalManager.roles_heard else 0


## Contesta por alguien según data/relations.json: lo que sabe de él (depth), el lazo que los une y lo que el técnico ya
## sabe. Cada respuesta da la capa siguiente (qué hace, después un nombre, después el nombre completo); un lazo puede
## dar más de una de golpe, menos, o hacerlo esquivar, y anteponer lo que piensa del otro. Las frases salen de
## _about_line: cada una en la voz de quien contesta y, si el juego las tiene, propias de la persona por la que se pregunta.
func _answer_about(pid: String) -> void:
	var known: int = Relations.depth(_person, pid)
	if known == 0:
		_people_reply(_voiced_line("unknown", pid))
		return
	var link: Dictionary = Relations.tie(_person, pid)
	var tie_type: String = String(link.get("type", ""))
	var rules: Dictionary = Relations.rules(tie_type)
	var cap: int = known
	if rules.has("cap"):
		cap = mini(cap, Relations.DEPTHS.find(String(rules["cap"])))
	var dodge: bool = bool(rules.get("dodge", false))
	if dodge:
		cap = mini(cap, 1)   # quien guarda un secreto dice a lo sumo qué hace
	var says: String = String(link.get("says", ""))
	var before: int = _layer(pid)
	var after: int = mini(before + int(rules.get("steps", 1)), cap)
	if after <= before:
		_asked[_person] = int(_asked.get(_person, 0)) + 1   # preguntar igual gasta: no se le saca todo de a uno
		if says != "":
			_people_reply(tr(says))
		elif dodge:
			_people_reply(_voiced_line("dodge", pid, tie_type))
		else:
			_people_reply(_voiced_line("nomore", pid, tie_type))
		return
	if not bool(rules.get("free", false)):
		_asked[_person] = int(_asked.get(_person, 0)) + 1
	var lines: Array[String] = []
	if says != "":
		lines.append(tr(says))
	if after == 1:
		JournalManager.learn_role(pid)
		lines.append(_about_line("role", pid, tie_type))
	elif after == 2:
		lines.append(_learn_a_name(pid, tie_type))
	else:
		if before == 0:
			lines.append(_about_line("role", pid, tie_type))   # de golpe hasta el final: también qué hace
		JournalManager.learn_role(pid)
		JournalManager.learn_name(pid, JournalManager.FULL)
		lines.append(_about_line("full", pid, tie_type))
	_people_queue.assign(lines.slice(1))
	_people_reply(lines[0])


## Contesta por una persona con un solo dato: lo primero que dice el pueblo de ella (el apellido o el nombre) o, si
## ya sabe uno, el nombre completo.
func _tell_about(pid: String) -> void:
	if JournalManager.name_bits(pid) == 0:
		_people_reply(_learn_a_name(pid))
		return
	JournalManager.learn_name(pid, JournalManager.FULL)
	_people_reply(_about_line("full", pid))


## Aprende el nombre por el que se conoce a alguien (el apellido para los de game.json "known_by_surname") y devuelve
## la frase que lo dice.
func _learn_a_name(pid: String, tie_type: String = "") -> String:
	if GameConfig.in_group("known_by_surname", pid):
		JournalManager.learn_name(pid, JournalManager.LAST)
		return _about_line("surname", pid, tie_type)
	JournalManager.learn_name(pid, JournalManager.FIRST)
	return _about_line("first", pid, tie_type)


## Lo que dice quien contesta (_person) de `pid` en una capa (`kind`: role, first, surname o full). Busca en el CSV,
## de lo más propio a lo más general, la primera clave que exista (con variantes _1, _2...):
##   rel_<kind>_<pid>_<quien contesta>   lo que dice esa persona de esa otra (su hija, su peón...)
##   rel_<kind>_<pid>_<voz>              lo que dice alguien de esa voz (chicos, el cura...) de esa persona
##   rel_<kind>_<pid>                    lo que dice cualquiera de esa persona
##   dlg_people_<kind>_<tipo de lazo>    la frase de quien le tiene rencor, es su rival..., con el dato en %s
##   dlg_people_<kind>_<voz>             la frase de esa voz, con el dato en %s
##   dlg_people_<kind>                   la frase genérica, con el dato en %s
## La voz de cada uno la da data/relations.json ("voices"). El dato es qué hace (en minúscula), el nombre, el
## apellido ("el alcalde Brandt") o el nombre completo; una frase propia puede decirlo con sus palabras, sin %s.
func _about_line(kind: String, pid: String, tie_type: String = "") -> String:
	var voice: String = Relations.voice(_person)
	var bases: Array[String] = ["rel_%s_%s_%s" % [kind, pid, _person]]
	if voice != "":
		bases.append("rel_%s_%s_%s" % [kind, pid, voice])
	bases.append("rel_%s_%s" % [kind, pid])
	if tie_type != "":
		bases.append("dlg_people_%s_%s" % [kind, tie_type])
	if voice != "":
		bases.append("dlg_people_%s_%s" % [kind, voice])
	bases.append("dlg_people_" + kind)
	var text: String = _pick_line(bases)
	if not "%s" in text:
		return text
	var person: Dictionary = JournalManager.person(pid)
	match kind:
		"role":
			var role: String = tr(person.get("role_key", ""))
			return text % (role.left(1).to_lower() + role.substr(1))
		"first":
			return text % tr("first_" + pid)
		"surname":
			return text % tr("last_" + pid)
		_:
			return text % tr(person.get("name_key", pid))


## Una respuesta sin dato (no lo conoce, no sabe más, esquiva): la que tiene quien contesta para `pid`
## (rel_<lo que es>_<pid>_<quien contesta>, con lo que es = unknown, nomore o dodge), la propia de quien contesta
## (dlg_people_<lo que es>_<quien contesta>), la de su lazo, la de su voz o la genérica
## (dlg_people_<lo que es>[_<tipo de lazo>|_<voz>]).
func _voiced_line(what: String, pid: String = "", tie_type: String = "") -> String:
	var base: String = "dlg_people_" + what
	var bases: Array[String] = []
	if pid != "":
		bases.append("rel_%s_%s_%s" % [what, pid, _person])
	bases.append("%s_%s" % [base, _person])   # la de quien contesta («¿El de la bufanda? Yo atiendo el mostrador»)
	if tie_type != "":
		bases.append("%s_%s" % [base, tie_type])
	var voice: String = Relations.voice(_person)
	if voice != "":
		bases.append("%s_%s" % [base, voice])
	bases.append(base)
	return _pick_line(bases)


## Una frase al azar de la primera base que tenga texto en el CSV: sus variantes <base>_1, <base>_2... o, si no tiene,
## la base sola.
func _pick_line(bases: Array[String]) -> String:
	for base: String in bases:
		var found: Array[String] = []
		var i: int = 1
		while true:
			var key: String = "%s_%d" % [base, i]
			var text: String = tr(key)
			if text == key:
				break
			found.append(text)
			i += 1
		if found.is_empty() and tr(base) != base:
			found.append(tr(base))
		if not found.is_empty():
			return found[randi() % found.size()]
	return ""


func _people_reply(text: String) -> void:
	line_discovers = false
	_people_step = "reply"
	_visible_options = []
	has_options = false
	line_shown.emit(_speaker, text, "", [], true)


## ¿Alguno de estos flags es nuevo y va al diario?
## Sin diario no se anota nada: no suena (salvo la línea que da el diario).
func _discovers(reveals: Array) -> bool:
	if GameConfig.flag("has_journal") in reveals:
		return true
	if not JournalManager.has_journal():
		return false
	return reveals.any(func(f: String) -> bool:
		return not LoopManager.has_knowledge(f) and (KnowledgeRegistry.kind_of(f) in Toasts.NOTE_KINDS
				or KnowledgeRegistry.kind_of(f) == KnowledgeRegistry.Kind.PHYSICAL))


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
	# "absent": solo si esas personas no están en la zona del jugador (la valija del de la cuatro, cuando él no está).
	for npc_id: String in cond.get("absent", []):
		if _present_here(npc_id):
			return false
	# Tareas de trabajo hechas hoy (p. ej. quien dio la orden comenta cuando se las entregan).
	var tasks: int = WorkManager.completed_count()
	if tasks < cond.get("tasks_min", 0) or tasks > cond.get("tasks_max", 9999):
		return false
	return _energy_ok(cond) and _time_ok(cond) and _names_ok(cond) and _seen_ok(cond) and _watch_ok(cond) and _knowledge_ok(cond.get("knowledge", []), cond.get("knowledge_any", []), cond.get("not_knowledge", []))


func _present_here(npc_id: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group("npc_actors"):
		if node.get("npc_id") == npc_id and node.get("zone") == ZoneManager.current_zone and (node as Node2D).visible:
			return true
	return false


func _option_available(option: Dictionary) -> bool:
	if option.get("needs_names", false) and not JournalManager.names_allowed():
		return false   # la respuesta dice un nombre: no antes de que se puedan aprender
	if option.get("once_per_loop", false) and _answered.has("%s/%s" % [_npc_id, option["text_key"]]):
		return false
	if LoopManager.loop_number < option.get("loop_min", 1) or LoopManager.loop_number > option.get("loop_max", 9999):
		return false
	return _energy_ok(option) and _time_ok(option) and _cost_ok(option) and _names_ok(option) and _seen_ok(option) and _watch_ok(option) and _after_ok(option) and _knowledge_ok(option.get("requires", []), option.get("requires_any", []), option.get("not_requires", []))


## "after_today": [clave de opción...] solo si hoy ya le eligió a esta persona alguna de esas opciones (prometer callar
## lo que contó recién después de que lo contó).
func _after_ok(rules: Dictionary) -> bool:
	var keys: Array = rules.get("after_today", [])
	# Una opción ya elegida (su text_key) o una entrada ya dicha (su id): así cuenta lo que contestó, no lo que esquivó.
	return keys.is_empty() or keys.any(func(k: String) -> bool:
		return _answered.has("%s/%s" % [_npc_id, k]) or _seen_this_loop.has("%s/%s" % [_npc_id, k]))


## "seen_today": [npc...] solo si hoy ya se lo cruzó (lo tuvo a la vista): preguntar por el de la cuatro recién después
## de verlo.
func _seen_ok(rules: Dictionary) -> bool:
	return (rules.get("seen_today", []) as Array).all(func(npc_id: String) -> bool:
		return JournalManager.was_seen_today(JournalManager.person_for_dialogue(npc_id)))


## "unwatched_by": [npc...] solo si ninguno de ellos está en la zona del jugador (Ilse cuenta lo de la puerta de servicio
## en voz baja, sin el patrón a la vista); "watched_by": [npc...], si alguno está (entonces esquiva).
func _watch_ok(rules: Dictionary) -> bool:
	var here := func(npc_id: String) -> bool:
		return get_tree().get_nodes_in_group("npc_actors").any(func(n: Node) -> bool:
			return n is NpcActor and n.npc_id == npc_id and n.zone == ZoneManager.current_zone)
	if (rules.get("unwatched_by", []) as Array).any(here):
		return false
	var watchers: Array = rules.get("watched_by", [])
	return watchers.is_empty() or watchers.any(here)


## "knows_name": [npc...] solo si el técnico sabe cómo se llama cada uno (alguna parte del nombre): llamar a alguien por
## su nombre («Franz, qué lindo lugar») recién cuando se lo sabe. "not_knows_name": mientras no se lo sepa.
func _names_ok(rules: Dictionary) -> bool:
	var known := func(npc_id: String) -> bool:
		var pid: String = JournalManager.person_for_dialogue(npc_id)
		return pid != "" and JournalManager.name_bits(pid) != 0
	return (rules.get("knows_name", []) as Array).all(known) and not (rules.get("not_knows_name", []) as Array).any(known)


## "energy_below": N solo aparece si la energía es menor que N (la comida no se ofrece a quien no la necesita).
func _energy_ok(rules: Dictionary) -> bool:
	return not rules.has("energy_below") or Stamina.value < float(rules["energy_below"])


## "cost": N solo aparece si alcanza la plata (la opción de compra se apaga sin dinero). Cobra al elegirla (choose).
## "cost": solo si alcanza la plata. "cant_afford": solo si NO alcanza (la respuesta de quien no fía).
func _cost_ok(rules: Dictionary) -> bool:
	if rules.has("cant_afford") and Wallet.can_afford(float(rules["cant_afford"])):
		return false
	return not rules.has("cost") or Wallet.can_afford(float(rules["cost"]))


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
