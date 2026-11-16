extends Node
## Cuenta las jornadas (loop_number: 1, 2, 3...) y guarda el conocimiento. Al terminar una jornada se olvidan los
## flags de los tipos de data/game.json "day.reset_kinds" (p. ej. confianza, estado del mundo y
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
## mande el juego ("arrest" u otros). El juego lo registra (su sistema de finales, por ejemplo);
## sin registrar, se pasa directo a la jornada siguiente.
var end_of_day_handler: Callable = func(_reason: String) -> void: next_loop()

## Jornada especial (data/game.json "special_days"): un día distinto del de siempre, con su reparto, sus horarios y
## diálogos (`data_dir`), su fecha, su horario de comienzo y fin y un tinte (un sueño, un viaje en el tiempo, una fiesta). La que
## está en curso (`special_day`) y la que toca después de esta (`next_special_day`, la pide el juego antes de cerrar
## la jornada). "" = un día como los demás.
var special_day: String = ""
var next_special_day: String = ""


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
	special_day = ""
	next_special_day = ""
	TimeManager.reset()
	TimeManager.start()
	loop_started.emit(loop_number)


## Partida nueva: se olvida todo.
func reset_all() -> void:
	loop_number = 1
	special_day = ""
	next_special_day = ""
	knowledge.clear()
	JournalManager.reset()
	game_reset.emit()


## Cierra la jornada actual (fin del reloj o arresto) y arranca la siguiente.
## `announce`: suena el aviso de reinicio (los cierres con pantalla propia lo manejan desde el juego).
## `start_clock`: falso cuando una pantalla de transición mantiene el mundo congelado hasta terminar.
func next_loop(announce: bool = true, start_clock: bool = true) -> void:
	if announce:
		AudioManager.play_sfx("loop_reset", -2.0)
	loop_number += 1
	knowledge = knowledge.filter(func(f: String) -> bool: return not resets_at_day_end(f))
	special_day = next_special_day
	next_special_day = ""
	TimeManager.reset()
	var day: Dictionary = special()
	if not day.is_empty():
		# Sin "start" o "end" propios, los de la jornada de siempre (data/game.json "day").
		var start_at: int = TimeManager.parse_clock(str(day["start"])) if day.has("start") else GameConfig.day_start()
		var end_at: int = TimeManager.parse_clock(str(day["end"])) if day.has("end") else GameConfig.day_end()
		TimeManager.set_window(start_at, end_at)
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
	var date: String = str(special().get("date", ""))
	if date != "":
		var parts: PackedStringArray = date.split("-")
		var unix: int = Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])})
		var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
		return {"year": d["year"], "month": d["month"], "day": d["day"], "weekday": (int(d["weekday"]) + 6) % 7}
	return GameConfig.date_for_day(loop_number)


## ¿Es un día de los de siempre? En una jornada especial que deja afuera lo de siempre (`hide_regular`) se callan los
## sistemas del día normal: el plazo del trabajo, las búsquedas, los eventos con hora, el tren.
func is_regular_day() -> bool:
	return not special().get("hide_regular", false)


## La configuración de la jornada especial en curso ({} si es un día como los demás).
func special() -> Dictionary:
	return GameConfig.value("special_days", {}).get(special_day, {}) if special_day != "" else {}


## Dónde está hoy el archivo `relative` de `kind` ("schedules", "dialogue") de `id`: el de la jornada especial si lo
## tiene; si la jornada especial deja afuera a la gente de siempre (`hide_regular`), "" (hoy no está); si no, el de siempre.
func data_file(kind: String, id: String, regular: String) -> String:
	var day: Dictionary = special()
	if day.is_empty():
		return regular
	var own: String = "%s/%s/%s.json" % [str(day.get("data_dir", "")), kind, id]
	if FileAccess.file_exists(own):
		return own
	if kind == "schedules" and day.get("hide_regular", false):
		return ""
	return regular


## `from_deduction_system`: solo DeductionSystem puede conceder flags de tipo DEDUCTION.
func gain_knowledge(flag: String, from_deduction_system: bool = false) -> void:
	if not KnowledgeRegistry.is_valid(flag):
		push_error("Flag desconocido: '%s'. Agregarlo al registro de flags del juego." % flag)
		return
	if KnowledgeRegistry.kind_of(flag) == KnowledgeRegistry.Kind.DEDUCTION and not from_deduction_system:
		push_error("'%s' es una deducción: no se concede directamente." % flag)
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


## Baja un nivel de confianza con `who` (id de la persona): con confianza numérica (Trust, data/trust.json) baja el nivel;
## si no, quita el flag más alto que tenga.
func lose_trust(who: String) -> void:
	var trust: Node = get_node_or_null("/root/Trust")
	if trust != null and trust.enabled:
		trust.change(who, -1)
		return
	for level in [3, 2, 1]:
		var flag: String = "%s_trust_%d" % [who, level]
		if has_knowledge(flag):
			knowledge.erase(flag)
			return
