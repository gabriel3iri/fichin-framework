extends Node
## Estado global: arranque, pausa y sospecha (0-100). Valida los datos al iniciar.

enum State { NOT_STARTED, PLAYING, PAUSED }

signal state_changed(new_state: State)
signal suspicion_changed(value: int)

## Escenas del juego (data/game.json, "scenes"): la del menú y la de la partida.
var menu_scene: String = GameConfig.value("scenes.menu", "")
var game_scene: String = GameConfig.value("scenes.game", "")
## Umbrales de sospecha (data/game.json, "suspicion"): advertencia y arresto.
var suspicion_arrest: int = int(GameConfig.value("suspicion.arrest", 100))
var suspicion_warning: int = int(GameConfig.value("suspicion.warning", 60))

var state: State = State.NOT_STARTED
var suspicion: int = 0
## Loop con el que arranca la próxima partida (1 = nueva; otro = continuar).
var pending_loop: int = 1


func _ready() -> void:
	# El idioma lo aplica SettingsManager (por defecto, español).
	LoopManager.loop_started.connect(_on_loop_started)


func start_game() -> void:
	if state != State.NOT_STARTED:
		return
	LoopManager.begin(pending_loop)
	pending_loop = 1
	AudioManager.enter_game()
	_set_state(State.PLAYING)


## Partida nueva: se olvida todo y se carga la escena de juego.
func new_game() -> void:
	LoopManager.reset_all()
	WorkManager.reset_all()
	SaveManager.pending_quick_state = {}
	pending_loop = 1
	start_scene()


func start_scene() -> void:
	state = State.NOT_STARTED
	suspicion = 0
	# El reloj vuelve al principio ANTES de cargar la escena: los NPC se colocan según la hora al nacer, y con la hora de la
	# partida anterior (p. ej. al final del día) aparecían donde estaban de tarde y caminaban hasta su lugar de la mañana.
	# Y quieto: hasta que cambie la escena, el mundo viejo sigue un cuadro, y con el reloj andando registraba cosas
	# (el diario anotaba la zona de la que se venía). La escena nueva lo arranca en start_game().
	TimeManager.pause()
	TimeManager.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file(game_scene)


func return_to_menu() -> void:
	TimeManager.pause()
	get_tree().paused = false
	state = State.NOT_STARTED
	suspicion = 0
	get_tree().change_scene_to_file(menu_scene)


func pause_game() -> void:
	if state != State.PLAYING:
		return
	TimeManager.pause()
	get_tree().paused = true
	_set_state(State.PAUSED)


func resume_game() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	_set_state(State.PLAYING)
	sync_day_clock()


## ¿Hay algo que deba detener el reloj del día? (charla, diario, orden, o pausa del juego). Lo pensado en la pestaña
## «Casos» se cobra al cerrar el diario (Cases.spend_thinking).
func day_clock_held() -> bool:
	var talking: bool = DialogueManager.is_active and not clock_runs_in_dialogue()
	return state == State.PAUSED or talking or Journal.is_open or WorkOrderPanel.is_open


## ¿El reloj sigue andando mientras se habla con alguien? (data/game.json "day.clock_runs_in_dialogue"; por defecto
## no). Con el reloj andando, el mundo sigue con él (TimeManager.world): quien habla con el jugador se queda quieto y
## los demás siguen su día.
func clock_runs_in_dialogue() -> bool:
	return bool(GameConfig.value("day.clock_runs_in_dialogue", false))


## El reloj de la jornada se detiene con charla, diario u orden de trabajo. Llamar al abrir/cerrar cualquiera.
func sync_day_clock() -> void:
	if state == State.NOT_STARTED:
		return
	if day_clock_held():
		TimeManager.pause()
	else:
		TimeManager.start()


func add_suspicion(delta: int) -> void:
	if delta == 0:
		return
	var before: int = suspicion
	suspicion = clampi(suspicion + delta, 0, suspicion_arrest)
	suspicion_changed.emit(suspicion)
	if delta > 0:
		AudioManager.play_sfx("suspicion_up", -4.0)
	if before < suspicion_warning and suspicion >= suspicion_warning:
		_gain_role("suspicion_warning")
		AudioManager.play_sfx("arrest_warning")
	if suspicion >= suspicion_arrest:
		_gain_role("suspicion_arrest")
		LoopManager.end_day.call_deferred("arrest")


## Da el flag del rol `role` (data/game.json "flags") si el juego le puso uno: un rol sin flag no se usa.
func _gain_role(role: String) -> void:
	var role_flag: String = GameConfig.flag(role)
	if role_flag != "":
		LoopManager.gain_knowledge(role_flag)


func _on_loop_started(_loop_number: int) -> void:
	suspicion = 0
	suspicion_changed.emit(suspicion)


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)
