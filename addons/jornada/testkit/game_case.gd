extends "res://addons/jornada/testkit/test_case.gd"
## Base para probar un juego hecho con el framework: partida nueva, reloj, zonas y memoria. Cada prueba arranca con la
## memoria del jugador en cero; las que necesitan el mundo llaman a start_game(). Un juego la extiende con lo suyo.

var lm: Node
var jm: Node
var dm: Node
var zm: Node
var tm: Node


func before_each() -> void:
	lm = autoload("LoopManager")
	jm = autoload("JournalManager")
	dm = autoload("DialogueManager")
	zm = autoload("ZoneManager")
	tm = autoload("TimeManager")
	Engine.time_scale = 1.0
	tree.paused = false
	if tree.root.has_node("Notices"):   # un cartel pausa el juego a mitad de la prueba: la que lo quiere lo prende
		tree.root.get_node("Notices").set("enabled", false)
	lm.reset_all()
	jm.reset()


func after_each() -> void:
	speed_up(1.0)
	tree.paused = false
	dm.set("is_active", false)


## Partida nueva hasta que la escena de juego está en pie; con `skip_intro` saca la tarjeta del principio.
func start_game(skip_intro: bool = true) -> bool:
	autoload("GameManager").new_game()
	var ok: bool = await until(func() -> bool:
		return tree.current_scene != null and tree.current_scene.name == "Main" and is_instance_valid(zm.player), 15.0)
	await frames(2)
	if skip_intro:
		for card: Node in tree.root.find_children("*", "CanvasLayer", true, false):
			if card.get_script() != null and card.get_script().resource_path.ends_with("intro_card.gd"):
				card.queue_free()
		tree.paused = false
		await frames(1)
	return assert_true(ok, "no arrancó la escena de juego")


## Acelera el juego. El HUD fija Engine.time_scale en cada cuadro según la tecla F: se lo apaga mientras tanto.
func speed_up(scale: float) -> void:
	var hud: Node = tree.current_scene.get_node_or_null("HUD") if tree.current_scene != null else null
	if hud != null:
		hud.set_process(is_equal_approx(scale, 1.0))
	Engine.time_scale = scale


func set_clock(hour: int, minute: int = 0) -> void:
	tm.minutes = hour * 60 + minute
	tm.advance_minutes(0)


## Lleva al jugador a una celda de una zona, sin transición.
func go(zone_id: String, tile: Vector2i) -> void:
	zm.load_zone(zone_id, zm.tile_px(tile))
	await frames(3)


func read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## ¿Hay camino a pie entre dos celdas de una zona? (la misma grilla que usan los NPCs)
func reachable(zone_id: String, from: Vector2i, to: Vector2i) -> bool:
	var grid: AStarGrid2D = zm.nav_grid(zone_id)
	if not grid.is_in_boundsv(from) or not grid.is_in_boundsv(to) or grid.is_point_solid(from) or grid.is_point_solid(to):
		return false
	return not grid.get_id_path(from, to).is_empty()
