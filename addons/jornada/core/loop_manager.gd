extends Node
## Cuenta las jornadas (loop_number: 1, 2, 3...) y guarda el conocimiento. Al terminar una jornada se olvidan los
## flags de los tipos de data/game.json "day.reset_kinds" (en Rabenholz, canon 04: confianza, estado del mundo y
## negativos), salvo "persistent_flags". Si la jornada siguiente es el mismo día o el próximo lo dice "day.at_end".

signal loop_started(loop_number: int)
signal knowledge_gained(flag: String)
## Se volvió a averiguar algo que ya sabía (JournalManager lo anota si antes no tenía el diario).
signal knowledge_repeated(flag: String)
## Partida nueva: se olvidó todo. Los sistemas del juego que guardan algo propio se limpian acá.
signal game_reset

var loop_number: int = 1
## El juego puede pedir qué piensa el jugador al despertar la próxima jornada (clave del CSV), p. ej. según cómo terminó
## la anterior. Se usa una vez y gana sobre los pensamientos de data/game.json.
var next_wake_thought: String = ""
var knowledge: Array[String] = []
## Qué pasa cuando termina la jornada: `func(reason: String)`. Motivos: "time" (se acabó el reloj) u otros que
## mande el juego ("arrest", "hands"...). El juego lo registra (en Rabenholz, EndingSystem: el 17:47 y los finales);
## sin registrar, se pasa directo a la jornada siguiente.
var end_of_day_handler: Callable = func(_reason: String) -> void: next_loop()


func _ready() -> void:
	TimeManager.loop_end_reached.connect(func() -> void: end_day("time"))


## Termina la jornada por `reason` (lo decide el manejador registrado).
func end_day(reason: String) -> void:
	end_of_day_handler.call(reason)


func start_first_loop() -> void:
	begin(1)


## Arranca el loop `number` desde las 06:00 (nueva partida o continuar).
func begin(number: int) -> void:
	loop_number = number
	TimeManager.reset()
	TimeManager.start()
	loop_started.emit(loop_number)


## Partida nueva: se olvida todo.
func reset_all() -> void:
	loop_number = 1
	knowledge.clear()
	JournalManager.reset()
	game_reset.emit()


## Cierra el loop actual (17:47 o arresto) y arranca el siguiente.
## `announce`: suena el aviso de reinicio (el 17:47 y los cierres con pantalla propia lo manejan EndingSystem).
## `start_clock`: falso cuando una pantalla de transición mantiene el mundo congelado hasta terminar.
func next_loop(announce: bool = true, start_clock: bool = true) -> void:
	if announce:
		AudioManager.play_sfx("loop_reset", -2.0)
	loop_number += 1
	knowledge = knowledge.filter(func(f: String) -> bool: return not resets_at_day_end(f))
	TimeManager.reset()
	if start_clock:
		TimeManager.start()
	loop_started.emit(loop_number)
	# Recargar la escena = mundo y NPCs vuelven al estado inicial.
	get_tree().reload_current_scene.call_deferred()


## ¿Se olvida este flag al terminar la jornada? (su tipo está en day.reset_kinds y no está en persistent_flags)
func resets_at_day_end(flag: String) -> bool:
	if not KnowledgeRegistry.is_valid(flag) or flag in GameConfig.persistent_flags():
		return false
	var kind: String = str(KnowledgeRegistry.Kind.find_key(KnowledgeRegistry.kind_of(flag))).to_lower()
	return kind in GameConfig.reset_kinds()


## Fecha de la jornada actual ({year, month, day, weekday}; ver GameConfig.date_for_day).
func today() -> Dictionary:
	return GameConfig.date_for_day(loop_number)


## `from_deduction_system`: solo DeductionSystem puede conceder flags de tipo DEDUCTION (canon 04).
func gain_knowledge(flag: String, from_deduction_system: bool = false) -> void:
	if not KnowledgeRegistry.is_valid(flag):
		push_error("Flag desconocido: '%s'. Agregarlo al canon 04 y regenerar el registro." % flag)
		return
	if KnowledgeRegistry.kind_of(flag) == KnowledgeRegistry.Kind.DEDUCTION and not from_deduction_system:
		push_error("'%s' es una deducción: no se concede directamente (canon 04)." % flag)
		return
	if flag in knowledge:
		knowledge_repeated.emit(flag)
		return
	knowledge.append(flag)
	knowledge_gained.emit(flag)


func has_knowledge(flag: String) -> bool:
	return flag in knowledge


func lose_knowledge(flag: String) -> void:
	knowledge.erase(flag)


## Baja un nivel de confianza con `who` (p. ej. "klara"): quita el más alto que tenga.
func lose_trust(who: String) -> void:
	for level in [3, 2, 1]:
		var flag: String = "%s_trust_%d" % [who, level]
		if has_knowledge(flag):
			knowledge.erase(flag)
			return
