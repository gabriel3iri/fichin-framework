extends Node2D
## Escena de juego: carga la zona inicial, arranca (o continúa) la partida y crea el menú de pausa.


@onready var _zone_holder: Node2D = $ZoneHolder
@onready var _player: PlayerController = $Actors/Player


func _ready() -> void:
	if OS.is_debug_build():
		DataValidator.validate_all()   # flags, keys del CSV, zonas y que nadie nazca sobre una pared
	ZoneManager.bind(_zone_holder, _player)
	ZoneManager.load_zone(GameConfig.start_zone(), ZoneManager.tile_px(GameConfig.start_tile()))   # data/game.json
	add_child(PauseMenu.new())
	add_child(Journal.new())
	add_child(DeductionScreen.new())
	var day_light := DayLight.new()
	day_light.setup($Actors)
	add_child(day_light)
	var weather := Weather.new()
	weather.setup(day_light)
	add_child(weather)
	GameManager.start_game()
	# Partida nueva: antes de despertar, quién es y qué vino a hacer (el pensamiento al despertar espera la pausa).
	if not GameConfig.value("intro", {}).is_empty() and LoopManager.loop_number == 1 \
			and TimeManager.now_minutes() <= GameConfig.day_start() + 2 and SaveManager.pending_quick_state.is_empty():
		add_child(IntroCard.new())
	DeductionSystem.check(false)   # deducciones cuyas piezas ya estaban al cargar: se conceden en silencio
	SaveManager.apply_pending_quick_state(_player)
