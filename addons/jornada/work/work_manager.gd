extends Node
## Trabajo del jugador: las tareas de la orden del día (data/work.json), cada una con un minijuego 2D.
##
## - La orden de trabajo es el flag del rol "work_received" (data/game.json "flags"); sin ella no se puede empezar.
## - Una tarea cuesta su duración en minutos de juego, y un minijuego mal hecho cuesta más.
## - Completar una cambia la sospecha (`suspicion_on_complete`, −8). Tener 0 tareas a la hora de entrega (`deadline`)
##   la sube (`suspicion_on_fail`, 15) y da el flag del rol "work_failed".
## - Mientras nunca terminó todas, cada tarea se estira hasta la entrega (duration_for, work.json "pace"); después
##   cuesta su duración por la destreza. Desde la jornada `veteran_from` (6; 0 = nunca), una tarea ya hecha a la
##   perfección en una jornada anterior se repite sin minijuego por `veteran_fraction` (0,6) de su duración (modo
##   veterano): la habilidad se convierte en tiempo.

signal task_completed(task_id: String)
signal progress_changed

const WORK_PATH: String = "res://data/work.json"
## Valores por defecto de work.json (cada juego los cambia ahí).
const SUSPICION_ON_COMPLETE: int = -8
const SUSPICION_ON_FAIL: int = 15
const VETERAN_LOOP: int = 6
const VETERAN_FRACTION: float = 0.6
## Qué parte de su duración cuesta una tarea según la destreza (veces resuelta bien en loops anteriores): la primera
## vez entera, después 80 % y 60 %. Son los mismos tres niveles en que los minijuegos se acortan: trabajar mejor
## deja más día libre para explorar y anotar.
const DURATION_BY_SKILL: Array[float] = [1.0, 0.8, 0.6]

var tasks: Array = []
## Hora de entrega (minutos del día). Sin "deadline" en work.json no hay plazo: `has_deadline` es falso y no se muestra ni se exige.
var deadline: int = 1 << 30
var has_deadline: bool = false
## Ritmo de aprendizaje (work.json "pace"; ver duration_for). Vacío: cada tarea cuesta su duración por la destreza.
var pace: Dictionary = {}
## Sospecha al completar una tarea y al llegar a la entrega sin ninguna; desde qué jornada vale el modo veterano (0 =
## nunca) y qué parte de la duración cuesta (work.json; si no, las constantes de arriba).
var suspicion_on_complete: int = SUSPICION_ON_COMPLETE
var suspicion_on_fail: int = SUSPICION_ON_FAIL
var veteran_from: int = VETERAN_LOOP
var veteran_fraction: float = VETERAN_FRACTION
var active_task: String = ""

var _done: Dictionary = {}       # task_id -> true (este loop)
var _mastered: Dictionary = {}   # task_id -> true (persiste entre loops)
var _times: Dictionary = {}      # task_id -> cuántas veces se terminó, en todas las jornadas (persiste y se guarda)
var _deadline_checked: bool = false
var _host: CanvasLayer


func _ready() -> void:
	var parsed: Dictionary = GameConfig.read_data(WORK_PATH)
	if not parsed.is_empty():
		tasks = parsed.get("tasks", [])
		pace = parsed.get("pace", {})
		suspicion_on_complete = int(parsed.get("suspicion_on_complete", SUSPICION_ON_COMPLETE))
		suspicion_on_fail = int(parsed.get("suspicion_on_fail", SUSPICION_ON_FAIL))
		veteran_from = int(parsed.get("veteran_from", VETERAN_LOOP))
		veteran_fraction = float(parsed.get("veteran_fraction", VETERAN_FRACTION))
		if parsed.has("deadline"):
			deadline = TimeManager.parse_clock(parsed["deadline"])
			has_deadline = true
	LoopManager.loop_started.connect(_on_loop_started)
	TimeManager.minute_changed.connect(_on_minute_changed)
	SaveManager.register_section("work_times", func() -> Variant: return _times.duplicate(),
		func(saved: Variant) -> void:
			_times.clear()
			for id: Variant in (saved if saved is Dictionary else {}):
				_times[str(id)] = int(saved[id]))


func mastered_ids() -> Array:
	return _mastered.keys()


## Veces que esta tarea se resolvió perfecta en loops anteriores (0 = nunca). Alimenta la rampa de
## tiempo de los minijuegos: a más destreza, minijuego más corto.
func skill_level(task_id: String) -> int:
	return int(_mastered.get(task_id, 0))


## Minutos de juego que cuesta hoy la tarea: su duración por la fracción que corresponde a la destreza. Con work.json
## "pace" "share_until_all_done", mientras nunca terminó todas las tareas (rol "all_tasks_done" de game.json), cada una se
## lleva su parte de lo que queda hasta la entrega (lo que falta repartido entre las pendientes, nunca menos que su
## duración): el que todavía no conoce el trabajo lo estira hasta la hora.
func duration_for(task: Dictionary) -> int:
	if bool(pace.get("share_until_all_done", false)) and has_deadline and not is_done(task["id"]) \
			and not LoopManager.has_knowledge(GameConfig.flag("all_tasks_done")):
		var pending: int = maxi(1, tasks.size() - completed_count())
		return int(roundf(maxf(float(task["duration"]), float(deadline - TimeManager.now_minutes()) / pending)))
	var level: int = clampi(skill_level(task["id"]), 0, DURATION_BY_SKILL.size() - 1)
	return int(roundf(float(task["duration"]) * DURATION_BY_SKILL[level]))


func done_ids() -> Array:
	return _done.keys()


func restore_mastered(ids: Array) -> void:
	_mastered.clear()
	for id in ids:
		_mastered[str(id)] = 1


func restore_done(ids: Array) -> void:
	_done.clear()
	for id in ids:
		_done[str(id)] = true


func reset_all() -> void:
	_mastered.clear()
	_times.clear()
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


## Cuántas veces terminó esta tarea, contando todas las jornadas (la primera vez es 1). Lo que piensa al terminarla
## depende de esto, no del número de jornada: una tarea que nunca hizo es nueva aunque sea el tercer día.
func times_done(task_id: String) -> int:
	return int(_times.get(task_id, 0))


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
	if veteran_from > 0 and LoopManager.loop_number >= veteran_from and _mastered.has(task_id):
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
		minutes += int(task["duration"] * veteran_fraction) if data.get("veteran", false) else duration_for(task)
	if data.get("toast_key", "") != "":
		Toasts.show_key(data["toast_key"])   # el minijuego avisa qué pasó (una descarga, una pieza rota...)
	if success:
		_done[task["id"]] = true
		_times[task["id"]] = times_done(task["id"]) + 1
		if not data.get("forced", false) and data.get("extra_minutes", 0) == 0:
			_mastered[task["id"]] = int(_mastered.get(task["id"], 0)) + 1
		Wallet.credit(Wallet.pay_per_task())   # pago por tarea terminada (antes solo se mencionaba en la orden)
		GameManager.add_suspicion(suspicion_on_complete)
		_grant_trust()
		Toasts.show_key("toast_task_done", [tr(task["name_key"])])
		# Todas hechas en una jornada: la primera vez, el flag del rol "all_tasks_done" (data/game.json "flags"; el
		# juego lo pone en persistent_flags para que quede: ya conoce el trabajo); las siguientes, el de
		# "all_tasks_done_again" (de ese día: quien recibe la entrega no felicita igual la primera que las otras).
		var all_done: String = GameConfig.flag("all_tasks_done")
		if all_done != "" and completed_count() >= tasks.size():
			var again: String = GameConfig.flag("all_tasks_done_again")
			if not LoopManager.has_knowledge(all_done):
				LoopManager.gain_knowledge(all_done)
			elif again != "":
				LoopManager.gain_knowledge(again)
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


## Completar tareas da confianza con quien dio la orden (data/game.json, "work": boss y trust_at_tasks), desde la jornada
## `trust_from` (una jornada o un rol/flag, GameConfig.unlocked; o `trust_from_loop`). Antes, terminarlas todas solo la
## deja en 0 si estaba en negativo.
func _grant_trust() -> void:
	var boss: String = GameConfig.value("work.boss", "")
	var levels: Dictionary = GameConfig.value("work.trust_at_tasks", {})
	if not GameConfig.unlocked(GameConfig.value("work.trust_from", GameConfig.value("work.trust_from_loop", 1))):
		var all_tasks: int = levels.keys().map(func(k: String) -> int: return int(k)).max() if not levels.is_empty() else 0
		if boss != "" and completed_count() >= all_tasks and Trust.level(boss) < 0:
			Trust.change(boss, -Trust.level(boss))
		return
	# "trust_after_all_done": mientras nunca terminó todo, el trabajo no le gana confianza (la primera entrega completa
	# llega tarde: sigue enojada); desde la jornada siguiente, sí.
	if GameConfig.value("work.trust_after_all_done", false) and not LoopManager.has_knowledge(GameConfig.flag("all_tasks_done")):
		return
	for needed: String in levels:
		if boss != "" and completed_count() >= int(needed):
			LoopManager.gain_knowledge("%s_trust_%d" % [boss, int(levels[needed])])


func _on_loop_started(_loop_number: int) -> void:
	_done.clear()
	_deadline_checked = false
	active_task = ""
	# La orden es de cada día: vuelve a llegar cuando la da quien la da (un diálogo del juego).
	LoopManager.lose_knowledge(GameConfig.flag("work_received"))
	progress_changed.emit()


func _on_minute_changed(_hour: int, _minute: int) -> void:
	if not LoopManager.is_regular_day():
		return   # jornada especial que deja afuera lo de siempre: no corre
	if _deadline_checked or TimeManager.now_minutes() < deadline:
		return
	_deadline_checked = true
	if completed_count() == 0:
		var failed: String = GameConfig.flag("work_failed")
		if failed != "":
			LoopManager.gain_knowledge(failed)
		GameManager.add_suspicion(suspicion_on_fail)
		Toasts.show_key("toast_work_failed")
