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
	if dm.is_active:
		dm.abort()
	# Flags estáticos de UI: si un test los deja en true, TimeManager.start() se niega a correr.
	Journal.is_open = false
	WorkOrderPanel.is_open = false
	var gm: Node = autoload("GameManager")
	if gm.state == gm.State.PAUSED:
		gm.resume_game()
	else:
		gm.sync_day_clock()


## Partida nueva hasta que la escena de juego está en pie; con `skip_intro` saca la tarjeta del principio.
func start_game(skip_intro: bool = true, skip_wake: bool = true) -> bool:
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
	if skip_wake and is_instance_valid(zm.player):
		zm.player.skip_wake_pause()
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


# --- Muebles con profundidad ------------------------------------------------------------------------------------------

## Muebles bajos de los interiores cuya base es más finita que su dibujo (Prop.furniture_base): detrás de ellos el
## personaje parece parado sobre la mesa o queda tapado hasta el pecho. Lee las escenas armadas (sin cargarlas en el
## mundo), así que es rápido. Vacío si está todo bien; si no, una línea por mueble. Si da algo, falta volver a armar el
## mundo con build_world.
func shallow_furniture() -> Array[String]:
	var cfg: Variant = read_json("res://data/world.json").get("props", {}).get("depth", {})
	var problems: Array[String] = []
	for zone_id: String in zm.zone_ids():
		if zm.is_exterior(zone_id):
			continue
		var root: Node = (load(zm.get("_zones")[zone_id]["scene"]) as PackedScene).instantiate()
		for node: Node in root.find_children("*", "", true, false):
			var prop := node as Prop
			if prop == null or prop.flat or prop.hung or prop.raise != 0.0 or prop.is_gate():
				continue
			if prop.wall_reach.y > 0.0 or _against_north_wall(root, prop):
				continue
			var want: Vector2 = Prop.furniture_base(prop.prop_texture, prop.frames, prop.collider_size, cfg)
			if want.y > prop.collider_size.y + 0.5:
				problems.append("%s: %s tiene la base de %d px de fondo y su dibujo pide %d" % [zone_id, prop.name,
						prop.collider_size.y, want.y])
		root.free()
	return problems


## ¿La celda de arriba del objeto es pared? (ahí nadie pasa por detrás)
func _against_north_wall(root: Node, prop: Prop) -> bool:
	var ground := root.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return false
	var cell: Vector2i = ground.local_to_map(prop.position + Vector2(0, -8)) + Vector2i(0, -1)
	var data: TileData = ground.get_cell_tile_data(cell)
	return data == null or data.get_collision_polygons_count(0) > 0


# --- Lo que se toca con E ---------------------------------------------------------------------------------------------

## Capa del cuerpo del jugador (las áreas que lo detectan tienen este bit en collision_mask).
const PLAYER_LAYER: int = 4
## Cuántas celdas alrededor de un área se prueban.
const REACH_MARGIN: int = 2


## Recorre todas las zonas y devuelve lo que no se puede tocar con E: cada puerta, objeto examinable, asiento y puesto
## de trabajo necesita un lugar libre (la grilla de caminos, que da por sólido lo que no se alcanza desde ninguna salida)
## desde donde el cuerpo del jugador entra en su área; cada puerta tiene que dejar al llegar en una celda libre. Vacío si
## está todo bien. Rápido (unos segundos para un pueblo entero): se puede correr siempre.
func unreachable_interactables() -> Array[String]:
	var body: CollisionShape2D = _player_shape()
	if body == null:
		return ["el jugador no tiene cuerpo"]
	# Un traslado con fundido que quedó a medio hacer (de otra prueba) cambiaría de zona en medio del recorrido.
	await until(func() -> bool: return not bool(zm.get("_busy")), 10.0)
	var problems: Array[String] = []
	for zone_id: String in zm.zone_ids():
		zm.load_zone(zone_id, Vector2.ZERO)
		await frames(1)
		if zm.current_zone != zone_id:   # algo la cambió en ese cuadro: se vuelve a cargar
			zm.load_zone(zone_id, Vector2.ZERO)
		problems.append_array(_unreachable_in(zone_id, body))
	return problems


func _player_shape() -> CollisionShape2D:
	for child: Node in zm.player.get_children():
		if child is CollisionShape2D and not (child as CollisionShape2D).disabled:
			return child
	return null


func _unreachable_in(zone_id: String, body: CollisionShape2D) -> Array[String]:
	var problems: Array[String] = []
	var grid: AStarGrid2D = zm.nav_grid(zone_id)
	var targets: Array[Node] = []
	for kind: String in ["Door", "Inspectable", "Seat", "WorkSpot"]:
		targets.append_array(zm.zone_root.find_children("*", kind, true, false))
	for target: Node in targets:
		var areas: Array[Area2D] = _areas_of(target)
		if areas.is_empty():
			continue
		if not _area_reachable(areas, grid, body):
			problems.append("%s: %s (%s) en %s, no se llega" % [zone_id, target.name, target.get_class() if target.get_script() == null else target.get_script().get_global_name(), zm.cell_of((target as Node2D).global_position)])
		if target is Door:
			var to: String = str(target.get("target_zone"))
			var arrive: Variant = zm.spawn_px(to, zone_id) if zm.has_zone(to) else null
			if arrive is Vector2 and zm.is_cell_solid(to, zm.cell_of(arrive)):
				problems.append("%s: la puerta a %s deja al llegar en una celda tapada %s" % [zone_id, to, zm.cell_of(arrive)])
	return problems


## Las áreas del objeto (él mismo o sus hijas) que detectan al jugador.
func _areas_of(target: Node) -> Array[Area2D]:
	var found: Array[Area2D] = []
	var nodes: Array[Node] = [target]
	nodes.append_array(target.find_children("*", "Area2D", true, false))
	for node: Node in nodes:
		if node is Area2D and ((node as Area2D).collision_mask & PLAYER_LAYER) != 0:
			found.append(node)
	return found


## ¿Hay un lugar donde puede pararse el jugador (una celda libre, con su cuerpo arrimado a cualquier borde) desde
## donde su cuerpo toca alguna de las áreas?
func _area_reachable(areas: Array[Area2D], grid: AStarGrid2D, body: CollisionShape2D) -> bool:
	var shapes: Array = []   # [Shape2D, Transform2D global]
	var bounds := Rect2()
	for area: Area2D in areas:
		for child: Node in area.get_children():
			if child is CollisionShape2D and not (child as CollisionShape2D).disabled and (child as CollisionShape2D).shape != null:
				var cs := child as CollisionShape2D
				shapes.append([cs.shape, cs.global_transform])
				var r: Rect2 = cs.global_transform * cs.shape.get_rect()
				bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)
	if shapes.is_empty():
		return true
	var half: Vector2 = body.shape.get_rect().size / 2.0
	var slack: Vector2 = Vector2(maxf(0.0, 8.0 - half.x), maxf(0.0, 16.0 - half.y * 2.0))
	var from: Vector2i = zm.cell_of(bounds.position) - Vector2i(REACH_MARGIN, REACH_MARGIN)
	var to: Vector2i = zm.cell_of(bounds.end) + Vector2i(REACH_MARGIN, REACH_MARGIN + 1)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var cell := Vector2i(x, y)
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell):
				continue
			for dx: float in [-slack.x, 0.0, slack.x]:
				for dy: float in [-slack.y, 0.0]:
					var feet: Vector2 = zm.tile_px(cell) + Vector2(dx, dy)
					var xf: Transform2D = Transform2D(0.0, feet) * body.transform
					for pair: Array in shapes:
						if body.shape.collide(xf, pair[0], pair[1]):
							return true
	return false
