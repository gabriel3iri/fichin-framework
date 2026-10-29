extends Node
## Identificar a la gente (data/identify.json), al estilo de Return of the Obra Dinn: una ficha por persona y varios
## datos que el jugador completa (nombre, apellido, ocupación...). Las opciones de cada dato se van habilitando con lo
## que el jugador averigua: flags (documentos, registros) o nombres que oyó (JournalManager). El juego nunca dice qué
## está mal: cada vez que hay `batch` fichas enteras bien sin confirmar (3), las confirma juntas. Así no se puede
## adivinar de a uno.
## Además, una marca libre por ficha («creo que está vivo / muerto»): no es parte de la respuesta, sirve para
## descartar y filtrar la lista.
## Lo que el jugador anota sobrevive a los loops (es su libreta) y entra en el guardado. Las flags de cierre no pueden
## ser deducciones (esas las da solo DeductionSystem).
##
## identify.json:
##   tab_key, empty_key        pestaña del diario y el texto mientras no hay nada
##   batch                     fichas enteras bien que se confirman juntas (3)
##   toast_key                 aviso al confirmar (%d = cuántas)
##   seen_toast_key            aviso cuando aparecen fichas nuevas en el diario
##   complete_flag             se gana con todo confirmado
##   fields                    {id: {title_key, unique?, name_part?, journal_bit?: "first"|"last", options: [{id, key,
##                             unlock_any?: [flags], people?: [ids del diario]}]}}: cada dato y sus opciones. Una
##                             opción está a mano si no pide nada, si se tiene alguno de unlock_any o si el jugador
##                             ya oyó esa parte del nombre (journal_bit) de alguna de `people`. `unique`: una opción va
##                             en una sola ficha (los nombres de los muertos). `name_part`: es parte del nombre (en el
##                             resumen de la ficha va junto con los otros, sin separador).
##   groups                    [{id, title_key, fields: [ids], show_any: [flags], complete_flag?}]: un grupo aparece
##                             cuando se tiene alguno de show_any (vacío = desde el principio); complete_flag se gana
##                             con todas sus fichas confirmadas. La pestaña aparece con la primera ficha visible.
##   cards                     [{id, group, portrait, look_key, answer: {dato: opción}, person?, clues: [{key,
##                             requires_any}], flag?}]: con `person`, la ficha aparece cuando el jugador vio a esa
##                             persona; `flag` se gana al confirmar esa ficha.

signal changed
signal confirmed(card_ids: Array)

const PATH: String = "res://data/identify.json"
const MARKS: Array[String] = ["", "alive", "dead"]
const FILTERS: Array[String] = ["all", "alive", "dead", "unmarked"]

## Ficha -> {dato: opción} que eligió el jugador.
var guesses: Dictionary = {}
var confirmed_ids: Array[String] = []
## Ficha -> "alive" | "dead": la marca libre del jugador.
var marks: Dictionary = {}

var _cfg: Dictionary = {}
var _cards: Dictionary = {}   # id -> ficha
var _groups: Dictionary = {}  # id -> grupo


func _ready() -> void:
	_cfg = GameConfig.read_data(PATH)
	if _cfg.is_empty():
		return
	for card: Dictionary in _cfg.get("cards", []):
		_cards[card["id"]] = card
	for group: Dictionary in _cfg.get("groups", []):
		_groups[group["id"]] = group
	SaveManager.register_section("identification", to_dict, from_dict)
	LoopManager.game_reset.connect(reset)
	LoopManager.knowledge_gained.connect(_on_knowledge_gained)


func enabled() -> bool:
	return not _cfg.is_empty()


func config() -> Dictionary:
	return _cfg


## ¿Ya se puede usar? (hace falta el diario y alguna ficha a la vista)
func is_available() -> bool:
	return enabled() and JournalManager.has_journal() and not visible_cards().is_empty()


func groups() -> Array:
	return _cfg.get("groups", [])


## Grupos con alguna ficha a la vista.
func visible_groups() -> Array:
	return groups().filter(func(g: Dictionary) -> bool: return not visible_cards(g["id"]).is_empty())


func cards(group_id: String = "") -> Array:
	return _cfg.get("cards", []).filter(func(c: Dictionary) -> bool: return group_id == "" or c["group"] == group_id)


## Fichas que el jugador ya puede ver: su grupo está a la vista y, si es de una persona, ya la vio.
func visible_cards(group_id: String = "") -> Array:
	return cards(group_id).filter(_card_seen)


func card(card_id: String) -> Dictionary:
	return _cards.get(card_id, {})


## Datos que pide la ficha (los de su grupo).
func fields_of(card_id: String) -> Array:
	return _groups.get(card(card_id).get("group", ""), {}).get("fields", ["name"])


func field(field_id: String) -> Dictionary:
	return _cfg.get("fields", {}).get(field_id, {})


func _group_seen(group: Dictionary) -> bool:
	var show: Array = group.get("show_any", [])
	return show.is_empty() or show.any(func(f: String) -> bool: return LoopManager.has_knowledge(f))


func _card_seen(c: Dictionary) -> bool:
	if not _group_seen(_groups.get(c["group"], {})):
		return false
	var person: String = c.get("person", "")
	return person == "" or JournalManager.is_met(person) or JournalManager.sightings.has(person)


## Avisa cuando aparecen fichas nuevas: un flag que muestra un grupo, o el diario recién conseguido con fichas a la vista.
func _on_knowledge_gained(flag: String) -> void:
	if _cfg.has("seen_toast_key") and JournalManager.has_journal():
		var news: bool = flag == GameConfig.flag("has_journal") and not visible_cards().is_empty()
		for group: Dictionary in groups():
			var show: Array = group.get("show_any", [])
			if flag in show and show.filter(func(f: String) -> bool: return LoopManager.has_knowledge(f)).size() == 1:
				news = true
		if news:
			Toasts.show_key(_cfg["seen_toast_key"])
	changed.emit()


## Opciones de un dato que el jugador ya puede usar, en el orden de identify.json.
func options_available(field_id: String) -> Array:
	var def: Dictionary = field(field_id)
	var bit: int = {"first": JournalManager.FIRST, "last": JournalManager.LAST}.get(def.get("journal_bit", ""), 0)
	return def.get("options", []).filter(func(o: Dictionary) -> bool:
		var unlock: Array = o.get("unlock_any", [])
		var people: Array = o.get("people", [])
		if unlock.is_empty() and people.is_empty():
			return true
		if unlock.any(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
			return true
		return bit != 0 and people.any(func(p: String) -> bool: return JournalManager.name_bits(p) & bit != 0))


## ¿Ya no hace falta? Una opción desaparece de la lista cuando todas las fichas que la llevan están confirmadas (un
## apellido de familia, cuando están las dos; las opciones que no son de nadie no desaparecen nunca).
func is_used_up(field_id: String, option_id: String) -> bool:
	var holders: Array = _cfg.get("cards", []).filter(func(c: Dictionary) -> bool:
		return field_id in fields_of(c["id"]) and (c.get("answer", {}) as Dictionary).get(field_id, "") == option_id)
	return not holders.is_empty() and holders.all(func(c: Dictionary) -> bool: return is_confirmed(c["id"]))


func option_text(field_id: String, option_id: String) -> String:
	for o: Dictionary in field(field_id).get("options", []):
		if o["id"] == option_id:
			return tr(o["key"])
	return ""


## Lo que el jugador puso en un dato de la ficha ("" = nada).
func guess_of(card_id: String, field_id: String = "name") -> String:
	return (guesses.get(card_id, {}) as Dictionary).get(field_id, "")


## La ficha como la anotó el jugador, en una línea («Klara Zimmermann · Jefa de estación»); "" si no anotó nada.
func summary(card_id: String) -> String:
	var parts: Array[String] = []
	var names: Array[String] = []
	for f: String in fields_of(card_id):
		var text: String = option_text(f, guess_of(card_id, f))
		if text == "":
			continue
		if field(f).get("name_part", false):
			names.append(text)
		else:
			parts.append(text)
	if not names.is_empty():
		parts.push_front(" ".join(names))
	return " · ".join(parts)


func is_confirmed(card_id: String) -> bool:
	return card_id in confirmed_ids


func is_complete(card_id: String) -> bool:
	return fields_of(card_id).all(func(f: String) -> bool: return guess_of(card_id, f) != "")


## Pistas de una ficha que ya se tienen.
func clues(card_id: String) -> Array[String]:
	var out: Array[String] = []
	for clue: Dictionary in card(card_id).get("clues", []):
		var needed: Array = clue.get("requires_any", [])
		if needed.is_empty() or needed.any(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
			out.append(clue["key"])
	return out


## Pone `option_id` en el dato `field_id` de la ficha. Si el dato es `unique` y esa opción estaba en otra ficha (sin
## confirmar), se mueve. Las confirmadas no se tocan.
func guess(card_id: String, option_id: String, field_id: String = "name") -> void:
	if not _cards.has(card_id) or is_confirmed(card_id) or not field_id in fields_of(card_id):
		return
	if field(field_id).get("unique", false):
		for other: String in guesses.keys():
			if guess_of(other, field_id) == option_id and not is_confirmed(other):
				(guesses[other] as Dictionary).erase(field_id)
	var entry: Dictionary = guesses.get(card_id, {})
	entry[field_id] = option_id
	guesses[card_id] = entry
	_check()
	changed.emit()


## Borra un dato de la ficha (o todos, sin `field_id`).
func clear(card_id: String, field_id: String = "") -> void:
	if is_confirmed(card_id) or not guesses.has(card_id):
		return
	if field_id == "":
		guesses.erase(card_id)
	else:
		(guesses[card_id] as Dictionary).erase(field_id)
	changed.emit()


## La marca libre del jugador: "", "alive" o "dead".
func mark_of(card_id: String) -> String:
	return marks.get(card_id, "")


func set_mark(card_id: String, mark: String) -> void:
	if not mark in MARKS:
		return
	if mark == "":
		marks.erase(card_id)
	else:
		marks[card_id] = mark
	changed.emit()


## Pasa a la marca siguiente: sin marca -> vivo -> muerto -> sin marca.
func cycle_mark(card_id: String) -> void:
	set_mark(card_id, MARKS[(MARKS.find(mark_of(card_id)) + 1) % MARKS.size()])


## ¿La ficha entra en el filtro? ("all", "alive", "dead", "unmarked")
func passes_filter(card_id: String, filter: String) -> bool:
	match filter:
		"alive", "dead":
			return mark_of(card_id) == filter
		"unmarked":
			return mark_of(card_id) == ""
	return true


## [confirmadas, total]
func progress() -> Array[int]:
	return [confirmed_ids.size(), _cards.size()]


func _is_right(c: Dictionary) -> bool:
	var answer: Dictionary = c.get("answer", {})
	return fields_of(c["id"]).all(func(f: String) -> bool: return answer.has(f) and guess_of(c["id"], f) == answer[f])


## Cada vez que hay `batch` fichas enteras bien sin confirmar, se confirman juntas (en el orden de las fichas). Al
## final, si lo que queda bien completa todo, se confirma aunque sean menos.
func _check() -> void:
	var batch: int = maxi(int(_cfg.get("batch", 3)), 1)
	var right: Array[String] = []
	for c: Dictionary in _cfg.get("cards", []):
		if not is_confirmed(c["id"]) and _is_right(c):
			right.append(c["id"])
	var newly: Array[String] = []
	while right.size() >= batch or (not right.is_empty() and confirmed_ids.size() + right.size() == _cards.size()):
		var take: int = mini(batch, right.size())
		newly.append_array(right.slice(0, take))
		right = right.slice(take)
	if newly.is_empty():
		return
	confirmed_ids.append_array(newly)
	for card_id: String in newly:
		var flag: String = card(card_id).get("flag", "")
		if flag != "":
			LoopManager.gain_knowledge(flag)
	if _cfg.has("toast_key"):
		Toasts.show_key(_cfg["toast_key"], [newly.size()])
	confirmed.emit(newly)
	for group: Dictionary in groups():
		var flag: String = group.get("complete_flag", "")
		if flag != "" and cards(group["id"]).all(func(c: Dictionary) -> bool: return is_confirmed(c["id"])):
			LoopManager.gain_knowledge(flag)
	for done: Dictionary in _cfg.get("complete_flags", []):
		var all_done: bool = true
		for group_id: String in done.get("groups", []):
			all_done = all_done and cards(group_id).all(func(c: Dictionary) -> bool: return is_confirmed(c["id"]))
		if all_done:
			LoopManager.gain_knowledge(done["flag"])
	if confirmed_ids.size() == _cards.size() and _cfg.get("complete_flag", "") != "":
		LoopManager.gain_knowledge(_cfg["complete_flag"])


func reset() -> void:
	guesses.clear()
	confirmed_ids.clear()
	marks.clear()
	changed.emit()


func to_dict() -> Dictionary:
	return {"guesses": guesses.duplicate(true), "confirmed": confirmed_ids.duplicate(), "marks": marks.duplicate()}


## Un guardado de antes de los datos múltiples tiene un nombre suelto por ficha: pasa a {"name": ...}.
func from_dict(value: Variant) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		return
	guesses.clear()
	for card_id: String in (value.get("guesses", {}) as Dictionary):
		var entry: Variant = value["guesses"][card_id]
		guesses[card_id] = {"name": entry} if typeof(entry) == TYPE_STRING else (entry as Dictionary).duplicate()
	confirmed_ids.assign(value.get("confirmed", []))
	marks = (value.get("marks", {}) as Dictionary).duplicate()
	changed.emit()
