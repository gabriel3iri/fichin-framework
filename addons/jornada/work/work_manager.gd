extends Node
## Trabajo del técnico (canon 09 §5). Cinco tareas (data/work.json), cada una con un minijuego 2D.
##
## - La orden de trabajo llega a las 06:20 (TimedEvents); sin ella no se puede empezar.
## - Una tarea cuesta su duración en minutos de juego, y un minijuego mal hecho cuesta más.
## - Completar baja la sospecha (-8). Tener 0 tareas al llegar a las 17:00 sube la sospecha (+15)
##   y deja `work_order_failed` (único castigo que persiste entre loops).
## - Desde el loop 6, una tarea ya hecha a la perfección en un loop anterior se repite sin
##   minijuego por el 60% del tiempo (modo veterano): la habilidad se convierte en tiempo.

signal task_completed(task_id: String)
signal progress_changed

const WORK_PATH: String = "res://data/work.json"
const SUSPICION_ON_COMPLETE: int = -8
const SUSPICION_ON_FAIL: int = 15
const VETERAN_LOOP: int = 6
const VETERAN_FRACTION: float = 0.6

var tasks: Array = []
## Hora de entrega (minutos del día). Sin "deadline" en work.json no hay plazo: `has_deadline` es falso y no se muestra ni se exige.
var deadline: int = 1 << 30
var has_deadline: bool = false
var active_task: String = ""

var _done: Dictionary = {}       # task_id -> true (este loop)
var _mastered: Dictionary = {}   # task_id -> true (persiste entre loops)
var _deadline_checked: bool = false
var _host: CanvasLayer


func _ready() -> void:
	var parsed: Dictionary = GameConfig.read_data(WORK_PATH)
	if not parsed.is_empty():
		tasks = parsed.get("tasks", [])
		if parsed.has("deadline"):
			deadline = TimeManager.parse_clock(parsed["deadline"])
			has_deadline = true
	LoopManager.loop_started.connect(_on_loop_started)
	TimeManager.minute_changed.connect(_on_minute_changed)


func mastered_ids() -> Array:
	return _mastered.keys()


func done_ids() -> Array:
	return _done.keys()


func restore_mastered(ids: Array) -> void:
	_mastered.clear()
	for id in ids:
		_mastered[str(id)] = true


func restore_done(ids: Array) -> void:
	_done.clear()
	for id in ids:
		_done[str(id)] = true


func reset_all() -> void:
	_mastered.clear()
	_done.clear()
	_deadline_checked = false
	active_task = ""


func task_by_id(task_id: String) -> Dictionary:
	for task: Dictionary in tasks:
		if task["id"] == task_id:
			return task
	return {}


## ¿Ya llegó la orden de trabajo de hoy? (el flag lo define data/game.json)
func has_order() -> bool:
	return LoopManager.has_knowledge(GameConfig.flag("work_received"))


func is_done(task_id: String) -> bool:
	return _done.has(task_id)


func completed_count() -> int:
	return _done.size()


## Salario del día: lo que pagan las tareas ya terminadas (pago por tarea, data/economy.json). 0 sin economía.
func pay_earned() -> int:
	return int(Wallet.pay_per_task() * completed_count())


## Lo llama el punto de trabajo cuando el jugador presiona E.
func try_start(task_id: String) -> void:
	if active_task != "":
		return
	var task: Dictionary = task_by_id(task_id)
	if task.is_empty():
		return
	if not has_order():
		Toasts.show_key("toast_work_no_order")
		return
	if is_done(task_id):
		Toasts.show_key("toast_work_done")
		return
	if TimeManager.now_minutes() >= deadline:
		Toasts.show_key("toast_work_late")
		return
	if LoopManager.loop_number >= VETERAN_LOOP and _mastered.has(task_id):
		Toasts.show_key("toast_work_veteran")
		_finish(task, true, {"veteran": true})
		return
	_open_minigame(task)


func _open_minigame(task: Dictionary) -> void:
	var minigame: Minigame = (load(task["minigame"]) as GDScript).new()
	minigame.task = task
	active_task = task["id"]
	GameManager.pause_game()  # congela reloj, NPCs y jugador mientras se trabaja
	_host = CanvasLayer.new()
	_host.layer = 60
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_host.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 26.0   # deja libre el borde superior para los avisos
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(center)
	center.add_child(minigame)
	minigame.finished.connect(_on_minigame_finished.bind(task))
	get_tree().root.add_child(_host)


func _on_minigame_finished(success: bool, data: Dictionary, task: Dictionary) -> void:
	_host.queue_free()
	_host = null
	active_task = ""
	GameManager.resume_game()
	if data.get("cancelled", false):
		return
	_finish(task, success, data)


func _finish(task: Dictionary, success: bool, data: Dictionary) -> void:
	# Un trabajo fallido (descarga, mecanismo roto) solo cuesta su penalización, no la jornada de la tarea.
	var minutes: int = int(data.get("extra_minutes", 0))
	if success:
		minutes += int(task["duration"] * (VETERAN_FRACTION if data.get("veteran", false) else 1.0))
	if data.get("toast_key", "") != "":
		Toasts.show_key(data["toast_key"])   # el minijuego avisa qué pasó (una descarga, una pieza rota...)
	if success:
		_done[task["id"]] = true
		if not data.get("forced", false) and data.get("extra_minutes", 0) == 0:
			_mastered[task["id"]] = true
		Wallet.credit(Wallet.pay_per_task())   # pago por tarea terminada (antes solo se mencionaba en la orden)
		GameManager.add_suspicion(SUSPICION_ON_COMPLETE)
		_grant_trust()
		Toasts.show_key("toast_task_done", [tr(task["name_key"])])
	else:
		if task.get("fail_loses_trust", false):
			LoopManager.lose_trust(GameConfig.value("work.boss", ""))   # quien da la orden
		Toasts.show_key("toast_task_failed")
	# El tiempo pasa DESPUÉS de resolver, para que lo revelado dependa de la hora a la que se termina.
	TimeManager.advance_minutes(minutes)
	if success:
		_grant_reveals(task)
		task_completed.emit(task["id"])
	progress_changed.emit()


func _grant_reveals(task: Dictionary) -> void:
	var now: int = TimeManager.now_minutes()
	for reveal: Dictionary in task.get("reveals", []):
		if reveal.has("after") and now < TimeManager.parse_clock(reveal["after"]):
			continue
		var ok: bool = true
		for needed: String in reveal.get("requires", []):
			ok = ok and LoopManager.has_knowledge(needed)
		if ok:
			LoopManager.gain_knowledge(reveal["flag"])


## Completar tareas da confianza con quien dio la orden (data/game.json, "work": boss y trust_at_tasks).
func _grant_trust() -> void:
	var boss: String = GameConfig.value("work.boss", "")
	var levels: Dictionary = GameConfig.value("work.trust_at_tasks", {})
	for needed: String in levels:
		if boss != "" and completed_count() >= int(needed):
			LoopManager.gain_knowledge("%s_trust_%d" % [boss, int(levels[needed])])


func _on_loop_started(_loop_number: int) -> void:
	_done.clear()
	_deadline_checked = false
	active_task = ""
	# La orden es de cada día: vuelve a llegar cuando la entrega Klara (dialogue/klara.json, klara_order_*).
	LoopManager.lose_knowledge(GameConfig.flag("work_received"))
	progress_changed.emit()


func _on_minute_changed(_hour: int, _minute: int) -> void:
	if _deadline_checked or TimeManager.now_minutes() < deadline:
		return
	_deadline_checked = true
	if completed_count() == 0:
		LoopManager.gain_knowledge(GameConfig.flag("work_failed"))
		GameManager.add_suspicion(SUSPICION_ON_FAIL)
		Toasts.show_key("toast_work_failed")
