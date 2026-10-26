extends Node
## Deducciones automáticas (canon 05 §8 y 09 §7). Nunca se obtienen directamente: cuando el jugador
## reúne las piezas, el sistema concede el flag y avisa para que salte la pantalla de deducción.
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
		if not LoopManager.has_knowledge(id) and is_satisfied(def):
			LoopManager.gain_knowledge(id, true)
			if announce:
				deduction_made.emit(id)
