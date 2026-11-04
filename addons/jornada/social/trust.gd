extends Node
## Confianza de cada persona con el jugador (data/trust.json): un nivel de `min` a `max` (−2 a 3 en Rabenholz) que arranca
## en 0 cada jornada. Sin ese archivo el juego no tiene confianza numérica y todo sigue con los flags sueltos.
##
##   - Los flags `<persona>_trust_<n>` (y `<persona>_trust`, el nivel 1) siguen siendo lo que piden diálogos y sistemas:
##     este nivel los mantiene al día (con nivel 2 tiene _1 y _2). Ganar uno de esos flags por otro lado (una tarea, una
##     respuesta) sube el nivel hasta ahí.
##   - Lo cambian las líneas y opciones de diálogo con `"trust": n` (llamarlo por su nombre, un halago), repetir
##     preguntas (más allá de su `patience`) y LoopManager.lose_trust.
##   - En `min` no habla más en la jornada (DialogueManager.snubs).
##   - Se ve en la caja de diálogo: una barra bajo el retrato, de roja a verde (DialogueBox).
## La persona es la del diario (JournalManager), no el id del diálogo: Hanns es «furrer».

signal changed(person: String, level: int, delta: int)

const PATH: String = "res://data/trust.json"

var enabled: bool = false
var min_level: int = -2
var max_level: int = 3

var _cfg: Dictionary = {}
var _levels: Dictionary = {}       # persona -> nivel (las que no están, en 0)
var _syncing: bool = false
var _loaded: Variant = null


func _ready() -> void:
	_cfg = GameConfig.read_data(PATH)
	if _cfg.is_empty():
		return
	enabled = true
	min_level = int(_cfg.get("min", -2))
	max_level = int(_cfg.get("max", 3))
	LoopManager.loop_started.connect(func(_n: int) -> void: reset())
	LoopManager.game_reset.connect(reset)
	LoopManager.knowledge_gained.connect(_on_knowledge_gained)
	SaveManager.register_section("trust", func() -> Variant: return {"levels": _levels.duplicate()},
		func(saved: Variant) -> void: _loaded = saved)
	SaveManager.quick_state_applied.connect(_on_quick_state_applied)


func reset() -> void:
	_levels.clear()


func level(person: String) -> int:
	return int(_levels.get(person, 0))


## Sube o baja el nivel (acotado) y deja los flags al día.
func change(person: String, delta: int) -> void:
	if not enabled or person == "" or delta == 0:
		return
	var before: int = level(person)
	var after: int = clampi(before + delta, min_level, max_level)
	if after == before:
		return
	_levels[person] = after
	_sync_flags(person)
	changed.emit(person, after, after - before)


## Ya no le habla en esta jornada.
func snubbed(person: String) -> bool:
	return enabled and person != "" and level(person) <= min_level


## Cuántas preguntas repetidas le aguanta sin perder confianza (`patience`, 0 si no dice).
func patience(person: String) -> int:
	return int(_person_cfg(person).get("patience", _cfg.get("default", {}).get("patience", 0)))


func _person_cfg(person: String) -> Dictionary:
	return _cfg.get("people", {}).get(person, {})


## Con nivel n tiene <persona>_trust_1.._n (y <persona>_trust, el viejo nivel 1); los de arriba se pierden.
func _sync_flags(person: String) -> void:
	_syncing = true
	var lvl: int = level(person)
	for n in range(1, max_level + 1):
		var flag: String = "%s_trust_%d" % [person, n]
		if not KnowledgeRegistry.is_valid(flag):
			continue
		if lvl >= n:
			LoopManager.gain_knowledge(flag)
		elif LoopManager.has_knowledge(flag):
			LoopManager.lose_knowledge(flag)
	var single: String = "%s_trust" % person
	if KnowledgeRegistry.is_valid(single):
		if lvl >= 1:
			LoopManager.gain_knowledge(single)
		elif LoopManager.has_knowledge(single):
			LoopManager.lose_knowledge(single)
	_syncing = false


## Un flag de confianza ganado por otro lado (una respuesta, las tareas de trabajo) sube el nivel hasta ahí.
func _on_knowledge_gained(flag: String) -> void:
	if _syncing:
		return
	var m: RegExMatch = RegEx.create_from_string("^(.+)_trust(?:_(\\d))?$").search(flag)
	if m == null:
		return
	var person: String = m.get_string(1)
	var target: int = int(m.get_string(2)) if m.get_string(2) != "" else 1
	if target > level(person):
		change(person, target - level(person))


func _on_quick_state_applied() -> void:
	if _loaded is Dictionary:
		_levels.clear()
		var saved: Dictionary = _loaded["levels"]
		for person: String in saved:
			_levels[person] = int(saved[person])   # el JSON del guardado devuelve los números como float
	_loaded = null
