extends Node2D
## Escena de juego: carga la zona inicial, arranca (o continúa) la partida y crea el menú de pausa.


@onready var _zone_holder: Node2D = $ZoneHolder
@onready var _player: PlayerController = $Actors/Player


func _ready() -> void:
	if OS.is_debug_build():
		DataValidator.validate_all()   # flags, keys del CSV, zonas y que nadie nazca sobre una pared
	_special_day()
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


## Jornada especial (LoopManager.special_day): suma su reparto (`cast`: id -> hoja de sprite; horarios y diálogos en su
## `data_dir`) y tiñe el mundo (`tint`). La gente de siempre sin horario propio ese día no aparece (NpcActor).
func _special_day() -> void:
	var day: Dictionary = LoopManager.special()
	if day.is_empty():
		return
	var actors: Node = get_node("Actors")
	var cast: Dictionary = day.get("cast", {})
	for id: String in cast:
		var npc: Node = load("res://addons/jornada/scenes/npc_actor.tscn").instantiate()
		npc.name = "Special_" + id
		npc.set("npc_id", id)
		npc.set("sheet", load(str(cast[id])))
		actors.add_child(npc)
	var tint: Array = day.get("tint", [])
	if tint.size() >= 3:
		var color := Color(float(tint[0]), float(tint[1]), float(tint[2]))
		_zone_holder.modulate = color
		actors.modulate = color
