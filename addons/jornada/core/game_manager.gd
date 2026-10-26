extends Node
## Estado global: arranque, pausa y sospecha (0-100, canon 09 §4). Valida los datos al iniciar.

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
	# El idioma lo aplica SettingsManager (por defecto español: canon 10).
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
	# partida anterior (p. ej. las 17:47) aparecían donde estaban de tarde y caminaban hasta su lugar de las 06:00.
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
	TimeManager.start()
	_set_state(State.PLAYING)


func add_suspicion(delta: int) -> void:
	if delta == 0:
		return
	var before: int = suspicion
	suspicion = clampi(suspicion + delta, 0, suspicion_arrest)
	suspicion_changed.emit(suspicion)
	if delta > 0:
		AudioManager.play_sfx("suspicion_up", -4.0)
	if before < suspicion_warning and suspicion >= suspicion_warning:
		LoopManager.gain_knowledge(GameConfig.flag("suspicion_warning"))
		AudioManager.play_sfx("arrest_warning")
	if suspicion >= suspicion_arrest:
		LoopManager.gain_knowledge(GameConfig.flag("suspicion_arrest"))
		LoopManager.end_day.call_deferred("arrest")


func _on_loop_started(_loop_number: int) -> void:
	suspicion = 0
	suspicion_changed.emit(suspicion)


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)
