extends Node
## Tablero de casos (pestaña «Casos» del diario): el jugador junta pistas en hilos para darles sentido. Cuando un hilo
## tiene exactamente las pistas de una deducción (DeductionSystem.matching), se puede resolver: se gana la deducción,
## que a su vez es una pista más y puede abrir diálogos (encarar a alguien con lo que se dedujo).
##
##   - Las pistas son lo anotado en el diario (JournalManager.noted_flags) de los tipos que se listan, más las
##     deducciones ya resueltas.
##   - Los hilos son del jugador: sobreviven a los loops y entran en el guardado. Una pista va en un solo hilo.
##   - Con deducciones en modo manual (data/game.json "deductions.manual") es la única forma de resolverlas.
##   - Pensar lleva tiempo, pero no mientras se mira el diario (el mundo no sigue sin que el técnico lo vea): cada pista
##     puesta en un hilo y cada caso resuelto suman minutos (data/game.json "deductions.think_minutes": place, solve)
##     que el reloj cobra de una vez al cerrar el diario (`spend_thinking`).

signal changed

const MAX_THREADS: int = 8
const MAX_CLUES: int = 8
const CLUE_KINDS: Array[String] = ["witness", "testimony", "document", "physical", "heard", "deduction"]

## Cada hilo: {"clues": [flags], "solved": id de la deducción resuelta con él, o ""}.
var threads: Array[Dictionary] = []
## Minutos pensados desde que se abrió el diario: se cobran al cerrarlo.
var thinking: int = 0


func _ready() -> void:
	LoopManager.game_reset.connect(reset)
	SaveManager.register_section("cases", func() -> Variant: return threads.duplicate(true),
		func(saved: Variant) -> void:
			threads.clear()
			for t: Variant in (saved if saved is Array else []):
				threads.append({"clues": (t.get("clues", []) as Array).duplicate(), "solved": str(t.get("solved", ""))})
			changed.emit())


func reset() -> void:
	threads.clear()
	thinking = 0
	changed.emit()


## Las pistas que el jugador tiene para trabajar, en el orden en que las anotó.
func clues() -> Array[String]:
	var out: Array[String] = []
	for flag: String in JournalManager.noted_flags:
		if LoopManager.has_knowledge(flag) and is_clue(flag):
			out.append(flag)
	return out


func is_clue(flag: String) -> bool:
	if not KnowledgeRegistry.is_valid(flag):
		return false
	var kind: String = str(KnowledgeRegistry.Kind.find_key(KnowledgeRegistry.kind_of(flag))).to_lower()
	return kind in CLUE_KINDS


## El hilo donde está la pista (-1 si no está en ninguno).
func thread_of(flag: String) -> int:
	for i in threads.size():
		if flag in threads[i]["clues"]:
			return i
	return -1


func is_used(flag: String) -> bool:
	return thread_of(flag) >= 0


func new_thread() -> int:
	if threads.size() >= MAX_THREADS:
		return -1
	threads.append({"clues": [], "solved": ""})
	changed.emit()
	return threads.size() - 1


func remove_thread(index: int) -> void:
	if index < 0 or index >= threads.size() or threads[index]["solved"] != "":
		return
	threads.remove_at(index)
	changed.emit()


## Pone la pista en el hilo (si estaba en otro, la saca de ahí). Los hilos resueltos no se tocan.
func place(flag: String, index: int) -> bool:
	if index < 0 or index >= threads.size() or threads[index]["solved"] != "" or not flag in clues():
		return false
	var clue_list: Array = threads[index]["clues"]
	if flag in clue_list or clue_list.size() >= MAX_CLUES:
		return false
	var from: int = thread_of(flag)
	if from >= 0 and threads[from]["solved"] != "":
		return false
	if from >= 0:
		(threads[from]["clues"] as Array).erase(flag)
	clue_list.append(flag)
	_think("place", 2)
	changed.emit()
	return true


## La saca del tablero (vuelve a la lista).
func take_back(flag: String) -> void:
	var from: int = thread_of(flag)
	if from < 0 or threads[from]["solved"] != "":
		return
	(threads[from]["clues"] as Array).erase(flag)
	changed.emit()


## La deducción que forma el hilo y todavía no se resolvió ("" si ninguna).
func pending(index: int) -> String:
	if index < 0 or index >= threads.size() or threads[index]["solved"] != "":
		return ""
	var id: String = DeductionSystem.matching(threads[index]["clues"])
	return "" if id == "" or LoopManager.has_knowledge(id) else id


func solve(index: int) -> String:
	var id: String = pending(index)
	if id == "":
		return ""
	threads[index]["solved"] = id
	_think("solve", 5)
	DeductionSystem.resolve(id)
	changed.emit()
	return id


func _think(what: String, default: int) -> void:
	thinking += int(GameConfig.value("deductions.think_minutes." + what, default))


## Lo pensado desde que se abrió el diario (y lo deja en cero): el diario lo cobra al cerrarse.
func spend_thinking() -> int:
	var minutes: int = thinking
	thinking = 0
	return minutes
