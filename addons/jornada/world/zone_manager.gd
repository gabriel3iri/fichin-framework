extends CanvasLayer
## Zonas separadas (canon 09 §3 y docs/technical/world_navigation_design.md).
##
## Cada zona es una escena que se monta en el ZoneHolder de la escena principal; el mapa de
## conexiones vive en data/zones.json. Dos tipos de conexión:
##   - puerta (interiores): fundido de 0,3 s, 0 minutos de juego, tecla E;
##   - borde ("kind": "edge", entre exteriores vecinos): el jugador camina hasta el límite de
##     la zona y la pantalla se desliza a la siguiente, sin fundido negro.
## También guarda las grillas de navegación (A*) de cada zona para que los NPCs rodeen paredes,
## mostradores y objetos, y resuelve rutas de varias zonas.

signal zone_changed(zone_id: String)

const ZONES_PATH: String = "res://data/zones.json"
const TILE: int = 16
const FADE: float = 0.3
const SLIDE_TIME: float = 0.4
## Zona ficticia: el personaje ya no está en ninguna (p. ej. el 409 salió).
const GONE: String = "gone"
const OPPOSITE: Dictionary = {"north": "south", "south": "north", "east": "west", "west": "east"}

var current_zone: String = ""
var _layout_kinds: Dictionary = {}
var zone_root: Node2D
var player: PlayerController

var _zones: Dictionary = {}
var _grids: Dictionary = {}
var _holder: Node2D
var _fade: ColorRect
var _busy: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ZONES_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_zones = parsed["zones"]
	else:
		push_error("ZoneManager: %s inválido" % ZONES_PATH)


func bind(holder: Node2D, p: PlayerController) -> void:
	_holder = holder
	player = p
	current_zone = ""
	zone_root = null


static func tile_px(tile: Vector2i) -> Vector2:
	## Centro-abajo del tile: donde apoyan los pies de un personaje.
	return Vector2(tile.x * TILE + TILE / 2.0, tile.y * TILE + TILE)


static func cell_of(feet: Vector2) -> Vector2i:
	## Celda que ocupa un personaje cuyos pies están en `feet` (el borde inferior cuenta como la celda de arriba).
	return Vector2i(floori(feet.x / TILE), floori((feet.y - 1.0) / TILE))


func has_zone(zone_id: String) -> bool:
	return _zones.has(zone_id)


func zone_ids() -> Array:
	return _zones.keys()


func zone_size(zone_id: String) -> Vector2i:
	var raw: Array = _zones.get(zone_id, {}).get("size", [0, 0])
	return Vector2i(raw[0], raw[1])


## Exterior = tiene algún pasaje por el borde hacia otra zona (los interiores solo tienen puertas).
## Exterior (luz del sol, clima) o interior: "exterior" en zones.json si está; si no, lo que diga su layout (un layout
## "interior" es interior); sin layout, es exterior la zona que tiene algún paso por el borde.
func is_exterior(zone_id: String) -> bool:
	var cfg: Dictionary = _zones.get(zone_id, {})
	if cfg.has("exterior"):
		return bool(cfg["exterior"])
	if cfg.has("layout"):
		if not _layout_kinds.has(zone_id):
			_layout_kinds[zone_id] = GameConfig.read_data(cfg["layout"]).get("kind", "outdoor")
		return _layout_kinds[zone_id] != "interior"
	for conn: Dictionary in cfg.get("connections", {}).values():
		if conn.get("kind", "door") == "edge":
			return true
	return false


## Zonas a las que se sale desde `zone_id` (bordes y puertas).
func neighbors(zone_id: String) -> Array:
	return _zones.get(zone_id, {}).get("connections", {}).keys()


## Px que la cámara no muestra en cada borde de la zona [izquierda, arriba, derecha, abajo] (paredes de borde).
func camera_inset(zone_id: String) -> Array:
	return _zones.get(zone_id, {}).get("camera_inset", [0, 0, 0, 0])


func connection(zone_id: String, to_zone: String) -> Dictionary:
	return _zones.get(zone_id, {}).get("connections", {}).get(to_zone, {})


# ── Rutas entre zonas ──────────────────────────────────────────────────────
## Zonas a atravesar de `from` a `to` (incluye ambas). Vacío si no hay camino.
func zone_path(from_zone: String, to_zone: String) -> Array[String]:
	var result: Array[String] = []
	if from_zone == to_zone:
		result.append(from_zone)
		return result
	var previous: Dictionary = {from_zone: ""}
	var queue: Array[String] = [from_zone]
	while not queue.is_empty():
		var here: String = queue.pop_front()
		for next: String in _zones.get(here, {}).get("connections", {}):
			if previous.has(next) or not _zones.has(next):
				continue
			previous[next] = here
			if next == to_zone:
				var step: String = next
				while step != "":
					result.push_front(step)
					step = previous[step]
				return result
			queue.append(next)
	return result


## Celda (dentro de `zone_id`) por donde se sale hacia `to_zone`. Vector2i(-1, -1) si no hay.
func exit_cell(zone_id: String, to_zone: String) -> Vector2i:
	var conn: Dictionary = connection(zone_id, to_zone)
	if conn.is_empty():
		return Vector2i(-1, -1)
	if conn.get("kind", "door") == "edge":
		var size: Vector2i = zone_size(zone_id)
		var mid: int = (int(conn["range"][0]) + int(conn["range"][1])) / 2
		match conn["side"]:
			"east": return Vector2i(size.x - 2, mid)
			"west": return Vector2i(1, mid)
			"south": return Vector2i(mid, size.y - 2)
			_: return Vector2i(mid, 1)
	var spawn: Array = conn["spawn_tile"]
	return Vector2i(spawn[0], spawn[1])


## Dónde aparece alguien en `zone_id` al llegar desde `from_zone` (null si no hay conexión).
## `along_px` (opcional) conserva la posición del jugador a lo largo del borde.
func spawn_px(zone_id: String, from_zone: String, along_px: float = -1.0) -> Variant:
	var back: Dictionary = connection(zone_id, from_zone)
	var forward: Dictionary = connection(from_zone, zone_id)
	if back.is_empty() and forward.is_empty():
		return null
	if forward.get("kind", "door") == "edge" or back.get("kind", "door") == "edge":
		return _edge_arrival(zone_id, from_zone, along_px)
	var spawn: Array = back["spawn_tile"]
	# Las puertas miden 2 tiles: "spawn_dx" centra al que llega en el vano.
	return tile_px(Vector2i(spawn[0], spawn[1])) + Vector2(float(back.get("spawn_dx", 0.0)), 0.0)


func _edge_arrival(zone_id: String, from_zone: String, along_px: float) -> Variant:
	var forward: Dictionary = connection(from_zone, zone_id)
	if forward.is_empty():
		return null
	var size: Vector2i = zone_size(zone_id)
	var first: int = int(forward["range"][0])
	var last: int = int(forward["range"][1])
	var start: int = int(forward["to_start"])
	var along: float = along_px
	if along < 0.0:
		along = (first + last + 1) * TILE / 2.0
	var mapped: float = start * TILE + (along - first * TILE)
	mapped = clampf(mapped, start * TILE + 6.0, (start + last - first + 1) * TILE - 6.0)
	match forward["side"]:   # lado por el que se SALIÓ de from_zone
		"east": return Vector2(TILE * 1.5, mapped)
		"west": return Vector2(size.x * TILE - TILE * 1.5, mapped)
		"south": return Vector2(mapped, TILE * 2.0)
		_: return Vector2(mapped, size.y * TILE - TILE * 1.5)


# ── Navegación (A*) ────────────────────────────────────────────────────────
## Grilla de la zona: las celdas con colisión (tiles sólidos y objetos con huella) son obstáculos.
func nav_grid(zone_id: String) -> AStarGrid2D:
	if _grids.has(zone_id):
		return _grids[zone_id]
	var grid := AStarGrid2D.new()
	var scene: PackedScene = load(_zones[zone_id]["scene"])
	var root: Node2D = scene.instantiate()
	var layer_node := root.get_node("Ground") as TileMapLayer
	var rect: Rect2i = layer_node.get_used_rect()
	grid.region = rect
	grid.cell_size = Vector2(TILE, TILE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var data: TileData = layer_node.get_cell_tile_data(Vector2i(x, y))
			if data != null and data.get_collision_polygons_count(0) > 0:
				grid.set_point_solid(Vector2i(x, y), true)
	for child in root.get_children():
		if child.has_method("footprint"):
			var box: Rect2 = child.footprint()
			var x0: int = floori(box.position.x / TILE)
			var y0: int = floori(box.position.y / TILE)
			var x1: int = floori((box.end.x - 0.01) / TILE)
			var y1: int = floori((box.end.y - 0.01) / TILE)
			for cy in range(y0, y1 + 1):
				for cx in range(x0, x1 + 1):
					if grid.is_in_boundsv(Vector2i(cx, cy)):
						grid.set_point_solid(Vector2i(cx, cy), true)
	root.free()
	_grids[zone_id] = grid
	_seal_pockets(zone_id, grid)
	return grid


## Las celdas libres a las que no se llega desde ninguna salida de la zona (un hueco entre una mesa y sus sillas)
## cuentan como obstáculo: si no, quien esquiva o busca «la celda libre más cercana» puede quedar encerrado ahí y
## salir en línea recta a través de los muebles.
func _seal_pockets(zone_id: String, grid: AStarGrid2D) -> void:
	var pending: Array[Vector2i] = []
	for other: String in neighbors(zone_id):
		var seed: Vector2i = _nearest_free(grid, exit_cell(zone_id, other))
		if seed.x >= 0:
			pending.append(seed)
	if pending.is_empty():
		return
	var reached: Dictionary = {}
	for cell: Vector2i in pending:
		reached[cell] = true
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if not reached.has(next) and grid.is_in_boundsv(next) and not grid.is_point_solid(next):
				reached[next] = true
				pending.append(next)
	var rect: Rect2i = grid.region
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if not grid.is_point_solid(cell) and not reached.has(cell):
				grid.set_point_solid(cell, true)


func is_cell_solid(zone_id: String, cell: Vector2i) -> bool:
	var grid: AStarGrid2D = nav_grid(zone_id)
	return not grid.is_in_boundsv(cell) or grid.is_point_solid(cell)


## Puntos de paso (pies, en px) para ir de `from_px` a `to_px` rodeando obstáculos.
## El último punto es exactamente `to_px`. Si no hay camino, va directo y avisa.
func find_path(zone_id: String, from_px: Vector2, to_px: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not _zones.has(zone_id) or not _zones[zone_id].has("scene"):
		result.append(to_px)
		return result
	var grid: AStarGrid2D = nav_grid(zone_id)
	var start: Vector2i = _nearest_free(grid, cell_of(from_px))
	var goal: Vector2i = _nearest_free(grid, cell_of(to_px))
	if start.x < 0 or goal.x < 0:
		push_warning("ZoneManager: sin celda libre cerca de %s -> %s en %s" % [from_px, to_px, zone_id])
		result.append(to_px)
		return result
	var cells: Array[Vector2i] = grid.get_id_path(start, goal)
	if cells.is_empty():
		push_warning("ZoneManager: sin camino %s -> %s en %s" % [start, goal, zone_id])
		result.append(to_px)
		return result
	for i in range(1, cells.size()):   # la primera celda es donde ya está
		result.append(tile_px(cells[i]))
	result.append(to_px)
	return result


## Tipo de suelo bajo los pies (para los pasos): "wood", "grass", "dirt" o "stone".
func surface_at(feet: Vector2) -> String:
	if zone_root == null:
		return "stone"
	var layer := zone_root.get_node_or_null("Ground") as TileMapLayer
	if layer == null:
		return "stone"
	return AudioManager.surface_for_tile(layer.get_cell_atlas_coords(cell_of(feet)).x)


## Largo (px) del camino de `from_px` a `to_px` pasando por las zonas intermedias.
## Sirve para calcular a qué hora tiene que salir un NPC para llegar a la hora del horario.
func route_length_px(from_zone: String, from_px: Vector2, to_zone: String, to_px: Vector2) -> float:
	var hops: Array[String] = zone_path(from_zone, to_zone)
	if hops.is_empty():
		return 0.0
	var total: float = 0.0
	var here_zone: String = from_zone
	var here_px: Vector2 = from_px
	for i in range(1, hops.size()):
		var next_zone: String = hops[i]
		var exit_at: Vector2i = exit_cell(here_zone, next_zone)
		var arrive: Variant = spawn_px(next_zone, here_zone)
		if exit_at.x < 0 or arrive == null:
			return total
		total += _walk_length(here_zone, here_px, tile_px(exit_at))
		here_zone = next_zone
		here_px = arrive
	return total + _walk_length(here_zone, here_px, to_px)


func _walk_length(zone_id: String, a: Vector2, b: Vector2) -> float:
	var length: float = 0.0
	var last: Vector2 = a
	for waypoint in find_path(zone_id, a, b):
		length += last.distance_to(waypoint)
		last = waypoint
	return length


func _nearest_free(grid: AStarGrid2D, cell: Vector2i) -> Vector2i:
	if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
		return cell
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := Vector2i(cell.x + dx, cell.y + dy)
				if grid.is_in_boundsv(c) and not grid.is_point_solid(c):
					return c
	return Vector2i(-1, -1)


# ── Cambio de zona ─────────────────────────────────────────────────────────
## Carga una zona sin transición (arranque del loop).
func load_zone(zone_id: String, player_px: Vector2) -> void:
	_swap(zone_id)
	player.global_position = player_px
	_snap_camera()


## Puerta a un interior: fundido, 0 minutos de juego.
func change_zone(target: String) -> void:
	if _busy:
		return
	if not has_zone(target):
		Toasts.show_key("toast_closed")
		return
	_busy = true
	var from_zone: String = current_zone
	player.can_move = false
	await _fade_to(1.0)
	_swap(target)
	var spawn: Variant = spawn_px(target, from_zone)
	if spawn != null:
		player.global_position = spawn
		_snap_camera()
		get_tree().call_group("npc_actors", "step_aside_for_player")
	AudioManager.play_sfx("door_close", -4.0)
	await _fade_to(0.0)
	player.can_move = true
	_busy = false


## Borde entre exteriores vecinos: la pantalla se desliza a la zona siguiente (sin fundido negro).
func walk_through(target: String) -> void:
	if _busy or not has_zone(target):
		return
	var conn: Dictionary = connection(current_zone, target)
	if conn.get("kind", "door") != "edge":
		return
	_busy = true
	player.can_move = false
	var from_zone: String = current_zone
	var side: String = conn["side"]
	var along: float = player.global_position.y if side in ["east", "west"] else player.global_position.x
	var old_view: ImageTexture = await _capture_world()
	_swap(target)
	var arrival: Variant = spawn_px(target, from_zone, along)
	if arrival != null:
		player.global_position = arrival
		_snap_camera()
	await get_tree().process_frame
	await get_tree().process_frame
	var new_view: ImageTexture = await _capture_world()
	await _slide(old_view, new_view, side)
	player.can_move = true
	_busy = false


## La cámara tiene suavizado: después de mover al jugador hay que llevarla de golpe a su lugar. Si no, arranca
## desde la posición de la zona anterior y se desliza de costado durante y después de la transición.
func _snap_camera() -> void:
	player.snap_camera()   # cambió de zona de golpe: sin deslizarse desde la posición anterior


func _swap(zone_id: String) -> void:
	player.reset_interactable()
	if zone_root != null:
		_holder.remove_child(zone_root)
		zone_root.free()
	var scene: PackedScene = load(_zones[zone_id]["scene"])
	zone_root = scene.instantiate()
	_holder.add_child(zone_root)
	current_zone = zone_id
	zone_changed.emit(zone_id)


func _fade_to(alpha: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE)
	await tween.finished


## Foto del mundo sin la interfaz (HUD, avisos...), para la transición deslizante.
func _capture_world() -> ImageTexture:
	var hidden: Array[CanvasLayer] = []
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer_node := node as CanvasLayer
		if layer_node != self and layer_node.visible and layer_node.layer >= 10:
			layer_node.visible = false
			hidden.append(layer_node)
	# El cambio de visibilidad tarda unos cuadros en llegar a la textura del viewport.
	for _i in 4:
		await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	for layer_node in hidden:
		layer_node.visible = true
	return ImageTexture.create_from_image(image)


func _slide(old_view: Texture2D, new_view: Texture2D, side: String) -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 95
	add_child(overlay)
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var direction: Vector2 = {
		"east": Vector2(-1, 0), "west": Vector2(1, 0), "south": Vector2(0, -1), "north": Vector2(0, 1),
	}[side]
	var old_rect: Sprite2D = _view_rect(old_view, screen)
	var new_rect: Sprite2D = _view_rect(new_view, screen)
	overlay.add_child(old_rect)
	overlay.add_child(new_rect)
	new_rect.position = -direction * screen
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(old_rect, "position", direction * screen, SLIDE_TIME)
	tween.tween_property(new_rect, "position", Vector2.ZERO, SLIDE_TIME)
	await tween.finished
	overlay.queue_free()


## La foto se dibuja con un Sprite2D escalado explícitamente a la pantalla virtual.
func _view_rect(texture: Texture2D, screen: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = texture
	sprite.scale = screen / texture.get_size()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite
