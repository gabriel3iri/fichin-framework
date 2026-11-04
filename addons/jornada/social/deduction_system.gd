extends Node
## Deducciones (canon 05 §8 y 09 §7). Nunca se obtienen directamente. Dos modos (data/game.json "deductions.manual"):
##   - automático: cuando el jugador reúne las piezas, el sistema concede el flag y avisa;
##   - manual: el jugador las arma en el diario (Cases, pestaña «Casos»): agrupa las pistas justas en un hilo y lo
##     resuelve (`resolve`). Juntar las piezas no alcanza: hay que darse cuenta de qué va con qué. Las que tienen
##     "auto": true (conteos, como «los veintiuno nombrados») se resuelven solas igual.
## Las definiciones salen de data/journal.json (generado por tools/gen_journal.py).

signal deduction_made(deduction_id: String)

const JOURNAL_PATH: String = "res://data/journal.json"

var _defs: Array = []


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOURNAL_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_defs = parsed.get("deductions", [])
	else:
		push_error("DeductionSystem: no se pudo leer %s" % JOURNAL_PATH)
	LoopManager.knowledge_gained.connect(func(_flag: String) -> void: check(true))


func definitions() -> Array:
	return _defs


func is_resolved(deduction_id: String) -> bool:
	return LoopManager.has_knowledge(deduction_id)


## Piezas obtenidas de una deducción: las obligatorias y, si las tiene, cuál de las alternativas se cumple.
func pieces(def: Dictionary) -> Dictionary:
	var met: Array[String] = []
	var missing: Array[String] = []
	for flag: String in def["all_of"]:
		if LoopManager.has_knowledge(flag):
			met.append(flag)
		else:
			missing.append(flag)
	var any_met: Array[String] = []
	for flag: String in def["any_of"]:
		if LoopManager.has_knowledge(flag):
			any_met.append(flag)
	return {"met": met, "missing": missing, "any_met": any_met, "needs_any": not (def["any_of"] as Array).is_empty()}


func is_satisfied(def: Dictionary) -> bool:
	var p: Dictionary = pieces(def)
	return (p["missing"] as Array).is_empty() and (not p["needs_any"] or not (p["any_met"] as Array).is_empty())


## `announce` = false al cargar una partida: se concede en silencio.
func check(announce: bool) -> void:
	for def: Dictionary in _defs:
		var id: String = def["id"]
		if manual() and not def.get("auto", false):
			continue   # en modo manual, solo las marcadas "auto" (conteos, no razonamientos) se resuelven solas
		if not LoopManager.has_knowledge(id) and is_satisfied(def):
			LoopManager.gain_knowledge(id, true)
			if announce:
				deduction_made.emit(id)


func manual() -> bool:
	return bool(GameConfig.value("deductions.manual", false))


func definition(deduction_id: String) -> Dictionary:
	for def: Dictionary in _defs:
		if def["id"] == deduction_id:
			return def
	return {}


## La deducción que forman exactamente estas pistas (todas las obligatorias, alguna de las alternativas si las hay, y
## ninguna que sobre), o "" si no forman ninguna. No mira si el jugador ya la resolvió.
func matching(clues: Array) -> String:
	if clues.is_empty():
		return ""
	for def: Dictionary in _defs:
		var all_of: Array = def["all_of"]
		var any_of: Array = def["any_of"]
		if not all_of.all(func(f: String) -> bool: return f in clues):
			continue
		if not any_of.is_empty() and not any_of.any(func(f: String) -> bool: return f in clues):
			continue
		if clues.all(func(f: String) -> bool: return f in all_of or f in any_of):
			return def["id"]
	return ""


## El jugador la armó: se concede y se anuncia como cualquier deducción.
func resolve(deduction_id: String) -> void:
	if deduction_id == "" or LoopManager.has_knowledge(deduction_id):
		return
	LoopManager.gain_knowledge(deduction_id, true)
	deduction_made.emit(deduction_id)
