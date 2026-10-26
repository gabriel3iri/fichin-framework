extends Node
## Guardado (canon 09 §13): un solo slot, autoguardado al inicio de cada loop, y F5 / F9 para el
## guardado rápido a media jornada. El autoguardado conserva lo que persiste entre loops
## (conocimiento, contador de loops, tareas dominadas); el guardado rápido añade el estado del momento.

signal saved
## La carga rápida terminó de aplicarse (hora, lugar, tareas). Los sistemas que guardan estado a media jornada lo
## retoman acá, porque antes el mundo todavía no existe o se reinicia.
signal quick_state_applied

const AUTOSAVE_PATH: String = "user://savegame.json"
const QUICKSAVE_PATH: String = "user://quicksave.json"
const VERSION: int = 1

## Estado a mitad de loop que main.gd aplica al cargar la escena.
var pending_quick_state: Dictionary = {}
## Secciones que guarda cada sistema del juego: clave -> [guardar: func() -> Variant, cargar: func(valor)].
var _sections: Dictionary = {}


## Un sistema del juego guarda lo suyo con el autoguardado (lo que persiste entre jornadas): `save` devuelve algo que
## se pueda pasar a JSON y `load` lo recibe al cargar. En Rabenholz, EndingSystem guarda los finales vistos.
func register_section(key: String, save: Callable, load: Callable) -> void:
	_sections[key] = [save, load]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LoopManager.loop_started.connect(func(_n: int) -> void: autosave())


func has_save() -> bool:
	return FileAccess.file_exists(AUTOSAVE_PATH)


func has_quicksave() -> bool:
	return FileAccess.file_exists(QUICKSAVE_PATH)


func read(path: String = AUTOSAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(_migrate(FileAccess.get_file_as_string(path)))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != VERSION:
		return {}
	return parsed


## Ids renombrados (data/game.json "renamed_ids": {"viejo": "nuevo"}): un guardado anterior al cambio sigue sirviendo.
## Cambia el id suelto y como prefijo de flags ("viejo_trust_1" -> "nuevo_trust_1"), siempre entre comillas.
func _migrate(text: String) -> String:
	var renames: Dictionary = GameConfig.value("renamed_ids", {})
	for old: String in renames:
		if old.begins_with("_"):
			continue   # "_doc"
		var pattern := RegEx.create_from_string("\"%s(?=[\"_])" % old)
		text = pattern.sub(text, "\"" + str(renames[old]), true)
	return text


func autosave() -> void:
	_write(AUTOSAVE_PATH, _snapshot(false))


func quick_save() -> void:
	_write(QUICKSAVE_PATH, _snapshot(true))
	Toasts.show_key("toast_quicksaved")


## Aplica un guardado y arranca la partida. `quick` = carga rápida (restaura también la hora y el lugar).
func load_and_start(quick: bool) -> bool:
	var data: Dictionary = read(QUICKSAVE_PATH if quick else AUTOSAVE_PATH)
	if data.is_empty():
		return false
	LoopManager.knowledge.assign(data.get("knowledge", []))
	JournalManager.from_dict(data.get("journal", {}))
	for key: String in _sections:
		if data.has(key):
			(_sections[key][1] as Callable).call(data[key])
	WorkManager.restore_mastered(data.get("mastered", []))
	GameManager.pending_loop = int(data.get("loop", 1))
	pending_quick_state = data if quick else {}
	GameManager.start_scene()
	return true


## Se llama desde main.gd cuando la escena ya está lista (zona inicial cargada y partida iniciada).
func apply_pending_quick_state(player: PlayerController) -> void:
	if pending_quick_state.is_empty():
		return
	var s: Dictionary = pending_quick_state
	pending_quick_state = {}
	TimeManager.minutes = float(s.get("minutes", TimeManager.day_start))
	LoopManager.knowledge.assign(s.get("knowledge", []))
	WorkManager.restore_done(s.get("done", []))
	GameManager.suspicion = int(s.get("suspicion", 0))
	GameManager.suspicion_changed.emit(GameManager.suspicion)
	var zone: String = str(s.get("zone", ""))
	if ZoneManager.has_zone(zone):
		var pos: Array = s.get("pos", [0, 0])
		ZoneManager.load_zone(zone, Vector2(pos[0], pos[1]))
	WorkManager.progress_changed.emit()
	quick_state_applied.emit()


func delete_all() -> void:
	for path in [AUTOSAVE_PATH, QUICKSAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _snapshot(full: bool) -> Dictionary:
	var data: Dictionary = {
		"version": VERSION, "loop": LoopManager.loop_number, "knowledge": LoopManager.knowledge,
		"mastered": WorkManager.mastered_ids(), "journal": JournalManager.to_dict(), "saved_at": Time.get_unix_time_from_system(),
	}
	for key: String in _sections:
		data[key] = (_sections[key][0] as Callable).call()
	if full:
		data["minutes"] = TimeManager.minutes
		data["zone"] = ZoneManager.current_zone
		var p: PlayerController = ZoneManager.player
		data["pos"] = [p.global_position.x, p.global_position.y] if p != null else [0, 0]
		data["done"] = WorkManager.done_ids()
		data["suspicion"] = GameManager.suspicion
	return data


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: no se pudo escribir %s" % path)
		return
	file.store_string(JSON.stringify(data))
	saved.emit()
