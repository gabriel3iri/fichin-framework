extends Node
## Estado del diario (canon 09 §6). Lo que el jugador ha anotado fuera de los flags:
## a quién conoció, qué lugares pisó, en qué sitios y a qué horas vio a cada persona, y qué entradas ya leyó.
## Persiste entre loops (es memoria del jugador, no del mundo) y se guarda con la partida.
##
## Recordar no es anotar: el técnico recuerda todo lo que averigua (flags, a quién conoció, nombres), pero en el
## diario solo figura lo que pasó teniéndolo en la mano (GameConfig.flag("has_journal"); en Rabenholz, desde el loop 2). Lo de antes entra
## cuando vuelve a enterarse con el diario, o (lo que sabe de una persona) cuando vuelve a hablar con ella.

signal changed
## Se escribió en el diario algo que el técnico ya sabía o acaba de averiguar (Toasts avisa).
signal flag_noted(flag: String)

const JOURNAL_PATH: String = "res://data/journal.json"
## A esta distancia (en píxeles, cubre la pantalla de 640x360) se considera que el jugador "ve" a un NPC.
const SIGHT_RANGE: Vector2 = Vector2(300.0, 170.0)
## Dos avistamientos separados por más de esto son rangos distintos (p. ej. por la mañana y por la tarde).
const SIGHT_GAP_MIN: int = 8
const MAX_RANGES: int = 6

var met: Array[String] = []
var visited: Array[String] = []
## persona -> { zona -> [[desde, hasta], ...] } en minutos desde medianoche.
var sightings: Dictionary = {}
var seen_flags: Array[String] = []
## Qué sabe del nombre de cada persona, en bits: FIRST (el nombre de pila: se lo preguntó o alguien se lo dijo) y
## LAST (el apellido: se lo dijo otro). Sin ninguno se la describe ("El del abrigo gris"). Persiste: es memoria.
const FIRST: int = 1
const LAST: int = 2
const FULL: int = 3
var names: Dictionary = {}
## A quién le oyó decir qué hace (la ocupación): lo primero que cuenta un vecino de otro. Persiste, como los nombres.
var roles_heard: Array[String] = []
## Lo escrito en el diario: flags y, por persona, {"names": bits anotados, "met": si habló con ella}.
var noted_flags: Array[String] = []
var noted_people: Dictionary = {}
## Quién no tiene apellido (con el nombre ya se sabe todo, "Padre Simeon") y qué nombres se saben desde el principio
## (Franz, el dueño del Gasthof): data/game.json, "people".
## Ya se sorprendió de que el diario conserva lo anotado (loop 3).
var journal_surprise_done: bool = false

var _people: Array = []
var _by_id: Dictionary = {}
var _by_dialogue: Dictionary = {}
var _data: Dictionary = {}


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOURNAL_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JournalManager: no se pudo leer %s" % JOURNAL_PATH)
		return
	_data = parsed
	_people = _data.get("people", [])
	for person: Dictionary in _people:
		_by_id[person["id"]] = person
		for dialogue_id: String in person["dialogue"]:
			_by_dialogue[dialogue_id] = person["id"]
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	LoopManager.knowledge_gained.connect(_note_flag)
	LoopManager.knowledge_repeated.connect(_note_flag)
	TimeManager.minute_changed.connect(_on_minute_changed)
	ZoneManager.zone_changed.connect(_note_zone)


func data() -> Dictionary:
	return _data


func people() -> Array:
	return _people


func person(person_id: String) -> Dictionary:
	return _by_id.get(person_id, {})


func person_for_dialogue(dialogue_id: String) -> String:
	return _by_dialogue.get(dialogue_id, "")


## Diálogos que son de una persona (no de un objeto ni de una puerta).
func speakers() -> Array:
	return _by_dialogue.keys()


func is_met(person_id: String) -> bool:
	return person_id in met


func is_heard_of(person_id: String) -> bool:
	var heard: String = _by_id.get(person_id, {}).get("heard", "")
	return heard != "" and LoopManager.has_knowledge(heard)


## Bits del nombre que recuerda (FIRST, LAST).
func name_bits(person_id: String) -> int:
	var bits: int = int(names.get(person_id, 0)) | int(GameConfig.known_from_start().get(person_id, 0))
	if is_heard_of(person_id):
		bits |= FIRST
	return _complete(person_id, bits)


func learn_name(person_id: String, bits: int) -> void:
	var before: int = int(names.get(person_id, 0))
	if before | bits != before:
		names[person_id] = before | bits
		changed.emit()
	if has_journal():
		_note_person(person_id)


func learn_role(person_id: String) -> void:
	if not person_id in roles_heard:
		roles_heard.append(person_id)
		changed.emit()


## Cómo se lo nombra según lo que recuerda: la descripción, el nombre, el apellido ("el alcalde Brandt") o los dos.
func display_name(person_id: String) -> String:
	return _name_for(person_id, name_bits(person_id))


## Cómo figura en el diario: solo con lo que se anotó.
func journal_name(person_id: String) -> String:
	return _name_for(person_id, noted_name_bits(person_id))


func _name_for(person_id: String, bits: int) -> String:
	match bits:
		0: return tr("who_" + person_id)
		FIRST: return tr("first_" + person_id)
		LAST: return _capitalized(tr("last_" + person_id))   # "El alcalde Brandt"
		_: return tr(_by_id.get(person_id, {}).get("name_key", person_id))


func _capitalized(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


## Con el nombre de pila de quien no tiene apellido ya se sabe todo.
func _complete(person_id: String, bits: int) -> int:
	return FULL if GameConfig.in_group("no_surname", person_id) and bits & FIRST else bits


# --- Lo anotado en el diario --------------------------------------------------------------------------------

func has_journal() -> bool:
	return LoopManager.has_knowledge(GameConfig.flag("has_journal"))


func is_noted(flag: String) -> bool:
	return flag in noted_flags


## ¿Figura en el diario? (habló con ella o anotó algo de su nombre teniéndolo).
func is_noted_person(person_id: String) -> bool:
	return noted_people.has(person_id) or noted_name_bits(person_id) != 0


func is_noted_met(person_id: String) -> bool:
	return bool(noted_people.get(person_id, {}).get("met", false))


func noted_name_bits(person_id: String) -> int:
	var bits: int = int(noted_people.get(person_id, {}).get("names", 0))
	var heard: String = _by_id.get(person_id, {}).get("heard", "")
	if heard != "" and is_noted(heard):
		bits |= FIRST
	return _complete(person_id, bits)


## Escribe lo que sabe del nombre de la persona (y si habló con ella) en el diario.
func _note_person(person_id: String, talked: bool = false) -> void:
	var entry: Dictionary = noted_people.get(person_id, {"names": 0, "met": false})
	entry["names"] = int(entry["names"]) | name_bits(person_id)
	entry["met"] = bool(entry["met"]) or talked
	noted_people[person_id] = entry
	changed.emit()


func _note_flag(flag: String) -> void:
	if flag == GameConfig.flag("has_journal") or is_noted(flag) or not has_journal():
		return
	noted_flags.append(flag)
	changed.emit()
	flag_noted.emit(flag)


func reset() -> void:
	met.clear()
	names.clear()
	roles_heard.clear()
	noted_flags.clear()
	noted_people.clear()
	journal_surprise_done = false
	visited.clear()
	sightings.clear()
	seen_flags.clear()
	changed.emit()


## Exterior al que pertenece una zona (ella misma si ya es un exterior).
func parent_exterior(zone_id: String) -> String:
	if (_data.get("map_cells", {}) as Dictionary).has(zone_id):
		return zone_id
	return (_data.get("zone_parent", {}) as Dictionary).get(zone_id, zone_id)


func is_unseen(flag: String) -> bool:
	return not flag in seen_flags


func mark_seen(flag: String) -> void:
	if not flag in seen_flags:
		seen_flags.append(flag)


func unseen_count() -> int:
	var count: int = 0
	for flag in noted_flags:
		if LoopManager.has_knowledge(flag) and _is_listed(flag) and is_unseen(flag):
			count += 1
	return count


func _is_listed(flag: String) -> bool:
	var kind: int = KnowledgeRegistry.kind_of(flag)
	return kind in [KnowledgeRegistry.Kind.WITNESS, KnowledgeRegistry.Kind.TESTIMONY, KnowledgeRegistry.Kind.DOCUMENT, KnowledgeRegistry.Kind.PHYSICAL, KnowledgeRegistry.Kind.HEARD]


func to_dict() -> Dictionary:
	var d: Dictionary = {"met": met, "visited": visited, "sightings": sightings, "seen_flags": seen_flags, "names": names,
			"roles_heard": roles_heard,
			"noted_flags": noted_flags, "noted_people": noted_people, "journal_surprise_done": journal_surprise_done}
	return d.duplicate(true)   # copias: si después se resetea el diario, lo guardado no cambia


func from_dict(d: Dictionary) -> void:
	met.assign(d.get("met", []))
	names = {}
	for pid: String in d.get("names", {}):
		var level: int = int(d["names"][pid])
		names[pid] = FULL if level >= 2 else level   # partidas viejas: 1 = nombre, 2 = nombre y apellido
	roles_heard.assign(d.get("roles_heard", []))
	noted_flags.assign(d.get("noted_flags", []))
	noted_people = (d.get("noted_people", {}) as Dictionary).duplicate(true)
	journal_surprise_done = bool(d.get("journal_surprise_done", false))
	visited.assign(d.get("visited", []))
	seen_flags.assign(d.get("seen_flags", []))
	sightings = {}
	for npc: String in d.get("sightings", {}):
		sightings[npc] = {}
		for zone: String in d["sightings"][npc]:
			# El JSON trae los minutos como float: se pasan a int (comparar int con float da falso).
			sightings[npc][zone] = (d["sightings"][npc][zone] as Array).map(func(r: Array) -> Array: return [int(r[0]), int(r[1])])
	changed.emit()


func _on_dialogue_started(dialogue_id: String) -> void:
	var person_id: String = person_for_dialogue(dialogue_id)
	if person_id != "" and not person_id in met:
		met.append(person_id)
		changed.emit()
	if person_id != "" and has_journal():
		_note_person(person_id, true)


## Lugares y avistamientos son pura anotación: sin diario no quedan registrados.
func _note_zone(zone_id: String) -> void:
	if not has_journal():
		return
	if zone_id != "" and not zone_id in visited:
		visited.append(zone_id)
		changed.emit()


func _on_minute_changed(_hour: int, _minute: int) -> void:
	_note_zone(ZoneManager.current_zone)
	var player: PlayerController = ZoneManager.player
	if player == null or not has_journal():
		return
	var now: int = TimeManager.now_minutes()
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor == null or not actor.visible or actor.zone != ZoneManager.current_zone:
			continue
		var offset: Vector2 = (actor.global_position - player.global_position).abs()
		if offset.x > SIGHT_RANGE.x or offset.y > SIGHT_RANGE.y:
			continue
		var person_id: String = person_for_dialogue(actor.npc_id)
		if person_id != "":
			_record_sighting(person_id, actor.zone, now)


func _record_sighting(person_id: String, zone_id: String, now: int) -> void:
	var zones: Dictionary = sightings.get(person_id, {})
	var ranges: Array = zones.get(zone_id, [])
	if not ranges.is_empty() and now - int(ranges[-1][1]) <= SIGHT_GAP_MIN and now >= int(ranges[-1][0]):
		ranges[-1][1] = maxi(int(ranges[-1][1]), now)
	else:
		ranges.append([now, now])
		if ranges.size() > MAX_RANGES:
			ranges.pop_front()
	zones[zone_id] = ranges
	sightings[person_id] = zones
	changed.emit()
