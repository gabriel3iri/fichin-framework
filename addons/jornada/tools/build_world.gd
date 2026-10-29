extends Node
## Constructor de mundo: arma el TileSet, una escena por zona y la escena de la partida, todo desde datos.
## Uso: godot --headless --path . res://addons/jornada/tools/build_world.tscn
## (se corre como escena, no con --script, para que existan los autoloads)
## Requiere haber corrido `godot --headless --import` si cambiaron los PNG de tiles.
##
## Lee:
##   data/world.json   tiles del atlas, piezas de edificios, estilos, objetos, bordes entre suelos, rutas y personajes
##   data/zones.json   zonas, sus escenas y conexiones (puertas y bordes)
##   el layout de cada zona ("layout" en zones.json), de uno de estos tipos ("kind"):
##     grid       el mapa entero: "rows" de caracteres y "legend" (carácter -> tile); "outdoor" suma los detalles sueltos
##     interior   un cuarto: pared norte de 4 filas con "windows" y "doors" a cuartos hijos, "floor", "counters" y la
##                salida en la pared sur ("exit_x", hacia "parent"). Una puerta con "part" usa otra pieza de 2x3 de
##                world.json "parts" (una escalera); "exit_part", otra pieza para la salida (una escalera que baja).
##                Una puerta con "side": "south" va en la pared sur, como la salida (otra escalera que baja).
##                "exit_x": null, sin salida propia: el cuarto se conecta solo por sus puertas (un sótano).
##     outdoor    (sin "kind") suelo "ground" + rectángulos "fills" + "buildings" + el seto del borde
##   Todos aceptan "props" (decorado), "spots" (puestos de trabajo) y "nodes" ({name, script, position}: nodos del juego).
##   Las rutas de "paths" (edificios dibujados, objetos examinables, overlays) son opcionales: si no existen, se saltean.

const WORLD_PATH: String = "res://data/world.json"
const ZONES_PATH: String = "res://data/zones.json"

## Pseudoazar de bordes y decals: fijo, no se configura (cambiarlo cambia todo el mundo).
const EDGE_ROWS: int = 3
const PAVED_DEPTH: float = 5.0
## Pasto, tierra y bosque: el borde se mete EDGE_BASE px en promedio (ola de 2 a 11 px), con una franja de mezcla
## de DITHER px, y las esquinas se redondean con estos radios. El empedrado, igual pero menos hondo.
const EDGE_BASE: float = 6.0
const DITHER: float = 4.0
const FILLET: float = 7.0
const CORNER_RADIUS: float = 8.0
const PAVED_FILLET: float = 8.0
const VARIANT_ROWS: int = 4

var TILE: int = 16
var _cfg: Dictionary
var _paths: Dictionary
var _tiles: Array = []
var _tile_ids: Dictionary = {}
var _prefix: String = ""
var _variant_rows: Dictionary = {}
var _edge_terrains: Array = []
var _decal_names: Array = []
var _buildings: Dictionary = {}
var _inspectables: Dictionary = {}
var _zones: Dictionary = {}


func _ready() -> void:
	_cfg = _read_json(WORLD_PATH)
	_paths = _cfg["paths"]
	TILE = int(_cfg.get("tile_size", 16))
	_tiles = _cfg["tiles"]["list"]
	_prefix = _cfg["tiles"].get("prefix", "")
	for i in _tiles.size():
		_tile_ids[_tiles[i]["name"]] = i
	_edge_terrains = _cfg["ground"].get("edge_terrains", [])
	_decal_names = _cfg["ground"].get("decals", [])
	if _paths.has("buildings") and FileAccess.file_exists(_paths["buildings"]):
		_buildings = _read_json(_paths["buildings"])["buildings"]
	if _paths.has("inspectables") and FileAccess.file_exists(_paths["inspectables"]):
		_inspectables = _read_json(_paths["inspectables"])
	_zones = _read_json(ZONES_PATH)["zones"]
	_build_atlas()
	var tileset: TileSet = _build_tileset()
	for zone_id: String in _zones:
		if not _zones[zone_id].has("layout"):
			push_error("build_world: la zona %s no tiene layout" % zone_id)
			continue
		_build_zone(zone_id, _zones[zone_id], tileset)
	_build_main()
	get_tree().quit()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("build_world: no se pudo leer %s" % path)
		return {}
	return parsed


## Columna del atlas de un tile: por nombre completo o, si no está, con el prefijo de world.json (grass -> town_grass).
func _tile(tile_name: String) -> int:
	if _tile_ids.has(tile_name):
		return _tile_ids[tile_name]
	if _tile_ids.has(_prefix + tile_name):
		return _tile_ids[_prefix + tile_name]
	push_error("build_world: tile desconocido: %s" % tile_name)
	return 0


func _tile_name(i: int) -> String:
	return _tiles[i]["name"]


func _part(part: String) -> int:
	return _tile(_cfg["parts"][part])


## Puerta de 2x3 tiles de world.json "parts": [fila][columna] -> columna del atlas.
func _door_part(part: String) -> Array:
	var out: Array = []
	for row: Array in _cfg["parts"][part]:
		out.append(row.map(func(n: String) -> int: return _tile(n)))
	return out


func _globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path)


# ── Atlas y TileSet ────────────────────────────────────────────────────────
func _build_atlas() -> void:
	var atlas := Image.create(TILE * _tiles.size(), TILE * VARIANT_ROWS, false, Image.FORMAT_RGBA8)
	for i in _tiles.size():
		var rows: Array[int] = []
		for row in VARIANT_ROWS:
			var path: String = _paths["tiles_dir"] + _tile_name(i) + ("" if row == 0 else "_v%d" % row) + ".png"
			if row > 0 and not FileAccess.file_exists(path):
				continue
			var img: Image = Image.load_from_file(_globalize(path))
			img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, row * TILE))
			rows.append(row)
		_variant_rows[i] = rows
	atlas.save_png(_globalize(_paths["atlas"]))
	_build_edges_atlas().save_png(_globalize(_paths["edges_atlas"]))
	var decals := Image.create(TILE * maxi(_decal_names.size(), 1), TILE, false, Image.FORMAT_RGBA8)
	for i in _decal_names.size():
		var img: Image = Image.load_from_file(_globalize(_paths["decals_dir"] + _decal_names[i] + ".png"))
		img.convert(Image.FORMAT_RGBA8)
		decals.blit_rect(img, Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
	decals.save_png(_globalize(_paths["decals_atlas"]))
	print("atlas guardado")


## Vecinos de un suelo: bit 1 N, 2 E, 4 S, 8 O, 16 NE, 32 SE, 64 SO, 128 NO. De las 256 combinaciones solo 47 se
## dibujan distinto (una esquina en diagonal no cuenta si ya hay borde en uno de los dos lados que la tocan): el
## atlas guarda solo esas, en EDGE_ROWS filas de 16 por suelo y versión. Así carga rápido.
static func edge_canon(mask: int) -> int:
	var n: bool = mask & 1 != 0
	var e: bool = mask & 2 != 0
	var s: bool = mask & 4 != 0
	var w: bool = mask & 8 != 0
	var out: int = mask & 15
	if mask & 16 and not n and not e:
		out |= 16
	if mask & 32 and not s and not e:
		out |= 32
	if mask & 64 and not s and not w:
		out |= 64
	if mask & 128 and not n and not w:
		out |= 128
	return out


static var _canon_cache: Array[int] = []


static func edge_canon_list() -> Array[int]:
	if not _canon_cache.is_empty():
		return _canon_cache
	var seen: Array[int] = []
	for mask in 256:
		var c: int = edge_canon(mask)
		if c not in seen:
			seen.append(c)
	seen.sort()
	_canon_cache = seen
	return seen


## Celda del atlas de bordes para la combinación `mask` del suelo k en la versión v.
func _edge_cell(mask: int, k: int, v: int) -> Vector2i:
	var i: int = edge_canon_list().find(edge_canon(mask))
	return Vector2i(i % 16, (v * _edge_terrains.size() + k) * EDGE_ROWS + i / 16)


func _edge_variants() -> int:
	return int(_cfg["ground"].get("edge_variants", 1))


func _build_edges_atlas() -> Image:
	var canon: Array[int] = edge_canon_list()
	assert(canon.size() <= 16 * EDGE_ROWS)
	var rows: int = maxi(EDGE_ROWS * _edge_terrains.size() * _edge_variants(), 1)
	var atlas := Image.create(TILE * 16, TILE * rows, false, Image.FORMAT_RGBA8)
	var styles: Dictionary = _cfg["ground"].get("edge_styles", {})
	for k in _edge_terrains.size():
		var src: Image = Image.load_from_file(_globalize(_paths["tiles_dir"] + _edge_terrains[k] + ".png"))
		src.convert(Image.FORMAT_RGBA8)
		var style: String = styles.get(_edge_terrains[k], "organic")
		for v in _edge_variants():
			for i in canon.size():
				var origin := Vector2i((i % 16) * TILE, ((v * _edge_terrains.size() + k) * EDGE_ROWS + i / 16) * TILE)
				_draw_edge(atlas, origin, src, style, canon[i], v)
	return atlas


func _draw_edge(atlas: Image, origin: Vector2i, src: Image, style: String, mask: int, v: int) -> void:
	var paved: bool = style == "paved"
	var excess: Array = []   # por píxel: < 0 tapado del todo; 0..DITHER-1 franja de mezcla; mayor, nada
	for y in TILE:
		var row: Array = []
		for x in TILE:
			row.append(_edge_excess(mask, x, y, style, v))
		excess.append(row)
	var solid := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < TILE and y < TILE and excess[y][x] < 0.0
	for y in TILE:
		for x in TILE:
			var at := Vector2i(origin.x + x, origin.y + y)
			var h: int = (x * 73 + y * 151 + v * 37 + mask * 11) % 97
			var e: float = excess[y][x]
			if e < 0.0:
				var c: Color = src.get_pixel(x, y)
				if paved and e > -1.0:
					c = c.darkened(0.35)                                  # junta: donde terminan las piedras
				elif paved and e > -2.0:
					c = c.lightened(0.08)                                 # canto de la última hilera, con luz
				atlas.set_pixel(at.x, at.y, c)
			elif paved:
				if e < 1.0 and solid.call(x, y - 1):
					atlas.set_pixel(at.x, at.y, Color(0.05, 0.04, 0.08, 0.3))   # sombrita, sin piedras sueltas
			elif e < DITHER:
				# franja de mezcla: cada vez menos píxeles del suelo de arriba (pixel art, sin transparencias)
				var keep: float = 1.0 - (e + 0.5) / DITHER
				if h < keep * 70.0:
					var c2: Color = src.get_pixel(x, y)
					atlas.set_pixel(at.x, at.y, c2.darkened(0.12) if style == "grass" and h % 3 == 0 else c2)
				elif style == "grass" and e < 1.0 and h % 5 == 0:
					atlas.set_pixel(at.x, at.y, src.get_pixel(x, y).darkened(0.3))   # matas que asoman
			elif solid.call(x, y - 1):
				atlas.set_pixel(at.x, at.y, Color(0.05, 0.04, 0.08, 0.35 if paved else 0.25))


## Ola del borde a lo largo de un lado: vale `base` en las puntas (t = 0 y 16), así dos celdas vecinas con distinta
## versión empalman sin escalón, y en el medio sube y baja según la versión.
func _edge_wave(t: int, side: int, v: int, base: float, amp: float) -> float:
	var shapes: Array = [[2, 2.5, 3, 1.5], [1, 3.0, 4, -1.5], [3, -2.0, 2, 1.5], [1, -2.5, 5, 1.0]]
	var sh: Array = shapes[(v * 2 + side) % shapes.size()]
	var u: float = PI * t / TILE
	return base + amp * (sh[1] * sin(u * sh[0]) + sh[3] * sin(u * sh[2]))


## Cuánto le falta al píxel (x, y) para quedar tapado por el suelo de arriba (negativo = tapado).
func _edge_excess(mask: int, x: int, y: int, style: String, v: int) -> float:
	var sides: Array[bool] = [mask & 1 != 0, mask & 2 != 0, mask & 4 != 0, mask & 8 != 0]   # N, E, S, O
	var dist: Array[float] = [y + 0.5, TILE - 0.5 - x, TILE - 0.5 - y, x + 0.5]
	var along: Array[int] = [x, y, x, y]
	var paved: bool = style == "paved"
	var depth: Array[float] = []
	for s in 4:
		var d: float = clampf(_edge_wave(along[s], s, v, PAVED_DEPTH, 0.45), 3.0, 8.0) if paved \
				else clampf(_edge_wave(along[s], s, v, EDGE_BASE, 1.0), 2.0, 11.0)
		if style == "rock" and (along[s] + v) % 5 == 0:
			d += 1.5
		depth.append(d)
	var best: float = 99.0
	for s in 4:
		if sides[s]:
			best = minf(best, dist[s] - depth[s])
	# Dos lados que se tocan: la esquina de adentro se rellena con una curva (o un bisel en el empedrado).
	var radius: float = PAVED_FILLET if paved else FILLET
	for s in 4:
		var t: int = (s + 1) % 4
		if not (sides[s] and sides[t]):
			continue
		var da: float = depth[s] + radius
		var db: float = depth[t] + radius
		if dist[s] < da and dist[t] < db:
			best = minf(best, radius - Vector2(dist[s] - da, dist[t] - db).length())
	# Solo el vecino en diagonal: una esquina redondeada (o a 45° en el empedrado).
	var corners: Array = [[16, 0, 1], [32, 2, 1], [64, 2, 3], [128, 0, 3]]   # bit, lado vertical, lado horizontal
	for c: Array in corners:
		if mask & c[0] == 0 or sides[c[1]] or sides[c[2]]:
			continue
		var a: float = dist[c[1]]
		var b: float = dist[c[2]]
		best = minf(best, Vector2(a, b).length() - (PAVED_DEPTH + 3.0 if paved else CORNER_RADIUS))
	return best


## TileSet: fuente 0 el suelo (colisión según "solid"), 1 los bordes y 2 los decals (solo dibujo).
## Datos por tile que leen otros sistemas: "window" (bool) y "window_sun" (ancho y desplazamiento del rayo de sol).
func _build_tileset() -> TileSet:
	var img: Image = Image.load_from_file(_globalize(_paths["atlas"]))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "window")
	ts.set_custom_data_layer_type(0, TYPE_BOOL)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(1, "window_sun")
	ts.set_custom_data_layer_type(1, TYPE_VECTOR2)
	var src := TileSetAtlasSource.new()
	src.texture = load(_paths["atlas"]) if ResourceLoader.exists(_paths["atlas"]) else ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var h: float = TILE / 2.0
	var poly := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	for i in _tiles.size():
		var def: Dictionary = _tiles[i]
		for row: int in _variant_rows[i]:
			var coords := Vector2i(i, row)
			src.create_tile(coords)
			var data: TileData = src.get_tile_data(coords, 0)
			if def.get("solid", false):
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, poly)
			if def.get("window", false):
				data.set_custom_data("window", true)
			if def.has("sun"):
				data.set_custom_data("window_sun", Vector2(def["sun"][0], def["sun"][1]))
	var edge_grid := Vector2i(16, maxi(EDGE_ROWS * _edge_terrains.size() * _edge_variants(), 1))
	for extra: Array in [[_paths["edges_atlas"], 1, edge_grid], [_paths["decals_atlas"], 2, Vector2i(maxi(_decal_names.size(), 1), 1)]]:
		var overlay := TileSetAtlasSource.new()
		overlay.texture = load(extra[0]) if ResourceLoader.exists(extra[0]) else \
				ImageTexture.create_from_image(Image.load_from_file(_globalize(extra[0])))
		overlay.texture_region_size = Vector2i(TILE, TILE)
		ts.add_source(overlay, extra[1])
		var grid: Vector2i = extra[2]
		for y in grid.y:
			for x in grid.x:
				overlay.create_tile(Vector2i(x, y))
	var err: int = ResourceSaver.save(ts, _paths["tileset"])
	print("tileset guardado err=", err)
	return load(_paths["tileset"])


# ── Zonas ──────────────────────────────────────────────────────────────────
func _build_zone(zone_id: String, zone_cfg: Dictionary, tileset: TileSet) -> void:
	var layout: Dictionary = _read_json(zone_cfg["layout"])
	var kind: String = layout.get("kind", "outdoor")
	var conns: Dictionary = zone_cfg.get("connections", {})
	var cells: Dictionary
	# Puertas: las de los edificios (outdoor) y los cuartos (interior) salen del layout; en una grilla, de zones.json.
	var doors: Array[Dictionary] = []
	var outdoor: bool = true
	var trees: Array[Vector2i] = []
	match kind:
		"grid":
			cells = _grid_cells(layout)
			outdoor = layout.get("outdoor", false)
			for target: String in conns:
				if conns[target].get("kind", "door") != "edge":
					doors.append({"to": target, "conn": conns[target]})
		"interior":
			cells = _interior_cells(layout, doors)
			outdoor = false
		_:
			cells = _outdoor_cells(layout, conns, doors)
	if outdoor:
		var leafy: Array = _cfg["ground"].get("leafy_props", [])
		for p: Dictionary in layout.get("props", []):
			if p["prop"] in leafy:
				trees.append(Vector2i(p["tile"][0], p["tile"][1]))

	var root := Node2D.new()
	root.name = zone_id.to_pascal_case()
	root.y_sort_enabled = true
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tileset
	root.add_child(ground)
	ground.owner = root
	_fill_ground(root, ground, cells, outdoor, trees)
	_add_overlays(root, zone_id)
	if kind != "interior":
		_add_buildings(root, zone_id)
	for d: Dictionary in doors:
		_add_door(root, d["to"], d["conn"], str(d.get("sign", "")))
	var size := Vector2i(layout["size"][0], layout["size"][1])
	for target: String in conns:
		if conns[target].get("kind", "door") == "edge":
			_add_edge(root, target, conns[target], size)
	for spot: Dictionary in layout.get("spots", []):
		_add_spot(root, spot)
	_add_props(root, layout.get("props", []), outdoor)
	_add_inspectables(root, zone_id)
	for n: Dictionary in layout.get("nodes", []):
		_add_node(root, n)

	var scene := PackedScene.new()
	scene.pack(root)
	print("zona ", zone_id, " guardada err=", ResourceSaver.save(scene, zone_cfg["scene"]))


## Grilla: cada carácter de "rows" es un tile según "legend".
func _grid_cells(layout: Dictionary) -> Dictionary:
	var legend: Dictionary = {}
	for ch: String in layout["legend"]:
		legend[ch] = _tile(layout["legend"][ch])
	var cells: Dictionary = {}
	var rows: Array = layout["rows"]
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if not legend.has(row[x]):
				push_error("build_world: carácter '%s' sin tile en la leyenda (%d, %d)" % [row[x], x, y])
				continue
			cells[Vector2i(x, y)] = legend[row[x]]
	return cells


## Celdas del borde (de `depth` de grosor) por donde se pasa a una zona vecina.
func _opening_cells(size: Vector2i, conns: Dictionary, depth: int) -> Dictionary:
	var open: Dictionary = {}
	for target: String in conns:
		var conn: Dictionary = conns[target]
		if conn.get("kind", "door") != "edge":
			continue
		for along in range(int(conn["range"][0]), int(conn["range"][1]) + 1):
			for d in depth:
				match conn["side"]:
					"east": open[Vector2i(size.x - 1 - d, along)] = true
					"west": open[Vector2i(d, along)] = true
					"south": open[Vector2i(along, size.y - 1 - d)] = true
					_: open[Vector2i(along, d)] = true
	return open


## Exterior: suelo base, rectángulos encima (en orden), edificios y el seto del borde, abierto en los pasos.
func _outdoor_cells(layout: Dictionary, conns: Dictionary, doors: Array[Dictionary]) -> Dictionary:
	var size := Vector2i(layout["size"][0], layout["size"][1])
	var border: Dictionary = _cfg.get("outdoor_border", {})
	var depth: int = int(border.get("depth", 0))
	var open: Dictionary = _opening_cells(size, conns, depth)
	var cells: Dictionary = {}
	var ground_idx: int = _tile(str(layout["ground"]))
	for y in size.y:
		for x in size.x:
			cells[Vector2i(x, y)] = ground_idx
	for f: Dictionary in layout.get("fills", []):
		var r: Array = f["rect"]
		var idx: int = _tile(str(f["tile"]))
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				if cells.has(Vector2i(x, y)):
					cells[Vector2i(x, y)] = idx
	for b: Dictionary in layout.get("buildings", []):
		_place_building(cells, b, doors)
	if depth == 0:
		return cells
	var hedge: int = _tile(border["tile"])
	var road: int = _tile(border["opening"])
	var through: Array = border.get("through", []).map(func(n: String) -> int: return _tile(n))
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if open.has(cell):
				# el pasaje continúa el camino; si estaba cubierto por el suelo base queda como camino
				if cells[cell] == ground_idx:
					cells[cell] = road
			elif (x < depth or y < depth or x >= size.x - depth or y >= size.y - depth) and cells[cell] not in through:
				cells[cell] = hedge
	return cells


## Edificio de afuera: dos filas de techo, pared, zócalo, ventanas en la penúltima fila y la puerta de 2x3 al pie.
func _place_building(cells: Dictionary, b: Dictionary, doors: Array[Dictionary]) -> void:
	var r: Array = b["rect"]
	var x0: int = r[0]
	var y0: int = r[1]
	var w: int = r[2]
	var h: int = r[3]
	var wall_style: Dictionary = _cfg["wall_styles"][b["style"]]
	var roof: Array = _cfg["roof_styles"][b["roof"]]
	var plinth: int = _part("plinth")
	for dx in w:
		cells[Vector2i(x0 + dx, y0)] = _tile(roof[0])
		cells[Vector2i(x0 + dx, y0 + 1)] = _tile(roof[1])
		for dy in range(2, h - 1):
			cells[Vector2i(x0 + dx, y0 + dy)] = _tile(wall_style["wall"])
		cells[Vector2i(x0 + dx, y0 + h - 1)] = plinth
	var door: Dictionary = b["door"]
	var door_w: int = 2
	var door_x: int = x0 + int(door["dx"])
	for col in b["windows"]:
		var wx: int = x0 + int(col)
		if wx < door_x or wx >= door_x + door_w:
			cells[Vector2i(wx, y0 + h - 2)] = _tile(wall_style["window"])
	var door_tiles: Array = _door_part("door_outside")
	for row in 3:
		for col in door_w:
			cells[Vector2i(door_x + col, y0 + h - 3 + row)] = door_tiles[row][col]
	doors.append({"to": door["to"], "conn": {
		"door_tile": [door_x, y0 + h - 1], "door_size": [door_w, 3], "approach": "south",
	}})


## Interior: pared norte de 4 filas (techo, pared con ventanas de 2x2, zócalo), piso, mostradores, puertas a cuartos
## hijos en la pared norte y la alfombra de salida en la pared sur. Puertas y ventanas: `x` = columna izquierda.
## (El JSON trae los números como float: se convierten a int.)
func _interior_cells(layout: Dictionary, doors: Array[Dictionary]) -> Dictionary:
	var size := Vector2i(layout["size"][0], layout["size"][1])
	var style: Dictionary = _cfg["wall_styles"][layout["style"]]
	var wall: int = _tile(style["wall"])
	var floor_idx: int = _tile(str(layout["floor"]))
	var cells: Dictionary = {}
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if x == 0 or x == size.x - 1 or y == size.y - 1 or y <= 2:
				cells[cell] = wall
			elif y == 3:
				cells[cell] = _tile(style["plinth"]) if style.has("plinth") else _part("plinth")
			else:
				cells[cell] = floor_idx
	var glass: Array = style["window_2x2"].map(func(n: String) -> int: return _tile(n))
	# "window_top" ([izq, der]): la ventana sube a la fila 0 (alta, de 2x3; el arco va arriba).
	var glass_top: Array = style.get("window_top", []).map(func(n: String) -> int: return _tile(n))
	for left in layout.get("windows", []):
		var x: int = int(left)
		if glass_top.size() == 2:
			cells[Vector2i(x, 0)] = glass_top[0]
			cells[Vector2i(x + 1, 0)] = glass_top[1]
		cells[Vector2i(x, 1)] = glass[0]
		cells[Vector2i(x + 1, 1)] = glass[1]
		cells[Vector2i(x, 2)] = glass[2]
		cells[Vector2i(x + 1, 2)] = glass[3]
	for d: Dictionary in layout.get("doors", []):
		if d.get("side", "north") == "south":   # en la pared sur, como la salida: una pieza de 2x1 (una escalera que baja)
			var low: Variant = _cfg["parts"][str(d.get("part", "exit_mat"))]
			for col in 2:
				cells[Vector2i(int(d["x"]) + col, size.y - 1)] = _tile(low[col] if low is Array else str(low))
			continue
		# "part": otra pieza de 2x3 (una escalera); si no, la puerta del estilo de pared o la de siempre.
		var inner: Array = _door_part(str(d.get("part", style.get("door", "door_inside"))))
		for row in 3:
			for col in 2:
				cells[Vector2i(int(d["x"]) + col, 1 + row)] = inner[row][col]
	var has_exit: bool = layout.get("exit_x") != null      # sin salida propia (un sótano): se entra por sus puertas
	var exit_x: int = int(layout["exit_x"]) if has_exit else -1
	var exit_part: Variant = _cfg["parts"][str(layout.get("exit_part", "exit_mat"))]   # una pieza o [izq, der]
	for col in (2 if has_exit else 0):
		cells[Vector2i(exit_x + col, size.y - 1)] = _tile(exit_part[col] if exit_part is Array else str(exit_part))
	for c: Array in layout.get("counters", []):
		for x in range(int(c[0]), int(c[1]) + 1):
			cells[Vector2i(x, int(c[2]))] = _part("counter")
	if has_exit:
		doors.append({"to": layout["parent"], "conn": {"door_tile": [exit_x, size.y - 1], "door_size": [2, 1], "approach": "north"}})
	for d: Dictionary in layout.get("doors", []):
		if d.get("side", "north") == "south":
			doors.append({"to": d["to"], "conn": {"door_tile": [int(d["x"]), size.y - 1], "door_size": [2, 1], "approach": "north"}})
			continue
		doors.append({"to": d["to"], "conn": {"door_tile": [int(d["x"]), 3], "door_size": [2, 3], "approach": "south"},
				"sign": d.get("sign", "")})
	return cells


## Pinta el Ground (con variantes por celda) y, encima, los bordes entre suelos y los decals (`outdoor`).
## Todo en y = 0, antes de los edificios: en el orden por Y queda debajo de todo lo demás.
func _fill_ground(root: Node2D, ground: TileMapLayer, cells: Dictionary, outdoor: bool, trees: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		ground.set_cell(cell, 0, Vector2i(cells[cell], _variant_row(cells[cell], cell)))
	var priority: Dictionary = {}
	for k in _edge_terrains.size():
		priority[_tile(_edge_terrains[k])] = k
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
			Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var edge_cells: Dictionary = {}   # índice del suelo de arriba -> {celda: máscara}
	for cell: Vector2i in cells:
		var own: int = cells[cell]
		if not priority.has(own):
			continue
		for i in dirs.size():
			var other: int = cells.get(cell + dirs[i], -1)
			if priority.has(other) and priority[other] > priority[own]:
				if not edge_cells.has(other):
					edge_cells[other] = {}
				edge_cells[other][cell] = edge_cells[other].get(cell, 0) | (1 << i)
	var order: Array = edge_cells.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return priority[a] < priority[b])
	for terrain: int in order:
		var layer := TileMapLayer.new()
		layer.name = "Edges_" + _tile_name(terrain)
		layer.tile_set = ground.tile_set
		root.add_child(layer)
		layer.owner = root
		var k: int = priority[terrain]
		for cell: Vector2i in edge_cells[terrain]:
			var mask: int = edge_cells[terrain][cell]
			var v: int = absi(cell.x * 92821 + cell.y * 68917) % _edge_variants()
			layer.set_cell(cell, 1, _edge_cell(mask, k, v))
	if not outdoor:
		return
	var decals := TileMapLayer.new()
	decals.name = "Decals"
	decals.tile_set = ground.tile_set
	root.add_child(decals)
	decals.owner = root
	var rules: Dictionary = _cfg["ground"].get("decal_rules", {})
	for cell: Vector2i in cells:
		var rule: Array = rules.get(_tile_name(cells[cell]), [])
		if rule.is_empty():
			continue
		var chance: float = rule[0]
		var near_tree: bool = trees.any(func(t: Vector2i) -> bool: return absi(t.x - cell.x) <= 2 and absi(t.y - cell.y) <= 2)
		if near_tree:
			chance += 0.25
		if _hash(cell, 3) >= chance:
			continue
		var options: Array = rule[1]
		var pick: String = "leaves" if near_tree and _hash(cell, 4) < 0.6 else options[int(_hash(cell, 5) * options.size())]
		decals.set_cell(cell, 2, Vector2i(_decal_names.find(pick), 0))


## Fila del atlas para esta celda: base o variante, según "variant_weights".
func _variant_row(tile: int, cell: Vector2i) -> int:
	var rows: Array = _variant_rows.get(tile, [0])
	if rows.size() == 1:
		return 0
	var h: float = _hash(cell, 13)
	var weights: Array = _cfg["ground"].get("variant_weights", [1.0])
	for row in weights.size():
		h -= float(weights[row])
		if h < 0.0:
			return row if rows.has(row) else 0
	return 0


## Pseudoazar determinista por celda en [0, 1).
## (Mezcla de enteros de MurmurHash3 en 32 bits: los bits bajos de una multiplicación sola se repiten en grilla.)
func _hash(cell: Vector2i, salt: int) -> float:
	var h: int = ((cell.x * 0x27d4eb2d) ^ (cell.y * 0x165667b1) ^ (salt * 0x9e3779b9)) & 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x85ebca6b) & 0xFFFFFFFF
	h ^= h >> 13
	h = (h * 0xc2b2ae35) & 0xFFFFFFFF
	h ^= h >> 16
	return float(h & 0xFFFFFF) / 16777216.0


## Imágenes del tamaño de la zona sobre el suelo y debajo de todo lo demás (vías, paisaje pintado), si existen.
func _add_overlays(root: Node2D, zone_id: String) -> void:
	for overlay: Dictionary in _paths.get("overlays", []):
		var path: String = str(overlay["path"]).replace("{zone}", zone_id)
		if not ResourceLoader.exists(path):
			continue
		var sprite := Sprite2D.new()
		sprite.name = overlay["name"]
		sprite.texture = load(path)
		sprite.centered = false
		root.add_child(sprite)
		sprite.owner = root


## Edificios en 3/4 (buildings.json): el nodo está en la base de la fachada para que el orden
## por Y tape a quien camina detrás. Las celdas del Ground siguen siendo las que colisionan.
## "SunShadows" (en y = 0, debajo de todo) lo llena DayLight con la sombra del sol de cada edificio.
func _add_buildings(root: Node2D, zone_id: String) -> void:
	var shadows := Node2D.new()
	shadows.name = "SunShadows"
	root.add_child(shadows)
	shadows.owner = root
	for b: Dictionary in _buildings.get(zone_id, []):
		var r: Array = b["rect"]
		var node := Node2D.new()
		node.name = "Bld_" + str(b["id"]).get_slice("__", 1).to_pascal_case()
		node.position = Vector2(int(r[0]) * TILE, (int(r[1]) + int(r[3])) * TILE)
		node.set_meta("rect_px", Rect2(int(r[0]) * TILE, int(r[1]) * TILE, int(r[2]) * TILE, int(r[3]) * TILE))
		var smoke := PackedVector2Array()
		for s: Dictionary in b.get("smoke", []):
			smoke.append(Vector2(s["x"], s["y"] - int(r[3]) * TILE))
		node.set_meta("smoke", smoke)
		var lights := PackedVector2Array()
		for l: Array in b.get("lights", []):
			lights.append(Vector2(l[0], l[1] - int(r[3]) * TILE))
		node.set_meta("lights", lights)
		node.add_to_group("building", true)
		root.add_child(node)
		node.owner = root
		var offset := Vector2(b["offset"][0], b["offset"][1])
		for layer in ["", "_lit"]:
			var path: String = "%s%s%s.png" % [_paths["buildings_dir"], b["id"], layer]
			if layer and not ResourceLoader.exists(path):
				continue
			var sprite := Sprite2D.new()
			sprite.name = "Lit" if layer else "Sprite"
			sprite.centered = false
			sprite.position = offset
			sprite.texture = load(path)
			if layer:
				sprite.modulate.a = 0.0
				sprite.add_to_group("glow", true)
			node.add_child(sprite)
			sprite.owner = root
		for i in smoke.size():
			node.add_child(_smoke(smoke[i], bool(b["smoke"][i].get("heavy", false)), "Smoke%d" % i))
			node.get_child(-1).owner = root
		if b.has("clock"):
			var clock := Node2D.new()
			clock.name = "TowerClock"
			clock.set_script(load("res://addons/jornada/world/tower_clock.gd"))
			clock.position = Vector2(b["clock"][0], b["clock"][1] - int(r[3]) * TILE)
			node.add_child(clock)
			clock.owner = root


## Humo de chimenea: cuadraditos de 2-3 px que suben y se corren con el viento ("heavy": más y más oscuro).
func _smoke(at: Vector2, heavy: bool, node_name: String) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = node_name
	p.position = at
	p.amount = 14 if heavy else 7
	p.lifetime = 4.5 if heavy else 3.5
	p.preprocess = p.lifetime
	p.direction = Vector2(0.25, -1)
	p.spread = 12.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector2(3.0, -1.0)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0 if heavy else 3.0
	var ramp := Gradient.new()
	var tone: float = 0.42 if heavy else 0.72
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	ramp.colors = PackedColorArray([Color(tone, tone, tone + 0.02, 0.0), Color(tone, tone, tone + 0.02, 0.6),
			Color(tone + 0.1, tone + 0.1, tone + 0.12, 0.0)])
	p.color_ramp = ramp
	return p


## Franja de salida en el borde: al pisarla, la pantalla se desliza a la zona vecina.
func _add_edge(root: Node2D, target: String, conn: Dictionary, size: Vector2i) -> void:
	var first: int = int(conn["range"][0])
	var last: int = int(conn["range"][1])
	var length: float = (last - first + 1) * TILE
	var mid: float = (first + last + 1) * TILE / 2.0
	var area := Area2D.new()
	area.name = "EdgeTo" + target.to_pascal_case()
	area.set_script(load("res://addons/jornada/world/edge_exit.gd"))
	area.set("target_zone", target)
	area.collision_layer = 0
	area.collision_mask = 4
	var shape_size := Vector2(8, length)
	match conn["side"]:
		"east": area.position = Vector2(size.x * TILE - 4, mid)
		"west": area.position = Vector2(4, mid)
		"south":
			area.position = Vector2(mid, size.y * TILE - 4)
			shape_size = Vector2(length, 8)
		_:
			area.position = Vector2(mid, 4)
			shape_size = Vector2(length, 8)
	root.add_child(area)
	area.owner = root
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = shape_size
	shape.shape = rect
	area.add_child(shape)
	shape.owner = root


## Puesto de trabajo: la tarea está en data/work.json; tile = pies del objeto.
func _add_spot(root: Node2D, spot: Dictionary) -> void:
	var node: Node2D = load("res://addons/jornada/scenes/work_spot.tscn").instantiate()
	node.name = spot["name"]
	node.set("task_id", spot["task"])
	node.set("prop_texture", load(_paths["props_dir"] + str(spot["prop"]) + ".png"))
	node.set("prompt_y", float(spot.get("prompt_y", -36)))
	node.position = _foot(spot["tile"])
	root.add_child(node)
	node.owner = root


## Pies de un objeto en la casilla `tile`: centro de abajo.
func _foot(tile: Array) -> Vector2:
	return Vector2(int(tile[0]) * TILE + TILE / 2.0, int(tile[1]) * TILE + TILE)


## Decorado del layout. Afuera, algunos objetos cambian de dibujo según la celda (world.json "variants").
func _add_props(root: Node2D, props: Array, outdoor: bool) -> void:
	var table: Dictionary = _cfg["props"].get("list", {})
	var skip: Array = _cfg["props"].get("skip", [])
	for p: Dictionary in props:
		var kind: String = p["prop"]
		if kind in skip:
			continue
		var tile := Vector2i(p["tile"][0], p["tile"][1])
		if outdoor:
			var roll: float = _hash(tile, 7)
			var variants: Dictionary = table.get(kind, {}).get("variants", {})
			for other: String in variants:
				roll -= float(variants[other])
				if roll < 0.0:
					kind = other
					break
		_add_decor(root, kind, tile)


func _collider(kind: String) -> Vector2:
	var c: Array = _cfg["props"].get("list", {}).get(kind, {}).get("collider", _cfg["props"].get("default_collider", [12, 6]))
	return Vector2(c[0], c[1])


func _add_decor(root: Node2D, kind: String, tile: Vector2i) -> void:
	var node: Node2D = load("res://addons/jornada/scenes/prop.tscn").instantiate()
	node.name = "%s_%d_%d" % [kind.capitalize(), tile.x, tile.y]
	node.set("prop_texture", load(_paths["props_dir"] + kind + ".png"))
	node.set("collider_size", _collider(kind))
	var def: Dictionary = _cfg["props"].get("list", {}).get(kind, {})
	node.set("flat", bool(def.get("flat", false)))
	node.set("frames", int(def.get("frames", 1)))   # animado: tira de cuadros
	node.set("fps", float(def.get("fps", 6.0)))
	node.set("raise", float(def.get("raise", 0.0)))   # se apoya más arriba (sobre un mostrador)
	node.set("shadow", bool(def.get("shadow", true)))   # false: cuelga de la pared, sin sombra en el piso
	node.position = _foot([tile.x, tile.y])
	root.add_child(node)
	node.owner = root


## Objetos examinables de la zona (inspectables.json) y los muebles extra que los alojan. El mueble va ANTES que el
## objeto para que éste se dibuje encima.
func _add_inspectables(root: Node2D, zone_id: String) -> void:
	for decor: Dictionary in _inspectables.get("extra_decor", []):
		if decor["zone"] == zone_id:
			_add_decor(root, decor["prop"], Vector2i(decor["tile"][0], decor["tile"][1]))
	for obj: Dictionary in _inspectables.get("objects", []):
		if obj["zone"] != zone_id:
			continue
		var node: Node2D = load("res://addons/jornada/scenes/inspectable.tscn").instantiate()
		node.name = str(obj["id"]).to_pascal_case()
		node.set("object_id", "obj_" + str(obj["id"]))
		node.set("gives", PackedStringArray(obj["gives"]))
		node.set("sprite_lift", float(obj["lift"]))
		node.set("only_when_available", bool(obj.get("only_when_available", false)))
		if obj["kind"] != "":
			node.set("sprite_texture", load(_paths["props_dir"] + str(obj["kind"]) + ".png"))
		node.position = _foot(obj["tile"])
		root.add_child(node)
		node.owner = root


## Nodo propio del juego ("nodes" del layout): un Node2D con su script, p. ej. un tren o un cartel animado.
func _add_node(root: Node2D, def: Dictionary) -> void:
	var node := Node2D.new()
	node.name = def["name"]
	if def.has("script"):
		node.set_script(load(def["script"]))
	var pos: Array = def.get("position", [0, 0])
	node.position = Vector2(pos[0], pos[1])
	root.add_child(node)
	node.owner = root


## `sign`: número o letra sobre el marco (las habitaciones de una posada), "" = sin cartel.
func _add_door(root: Node2D, target: String, conn: Dictionary, sign: String = "") -> void:
	var tile: Array = conn["door_tile"]
	var size: Array = conn.get("door_size", [1, 1])
	var south: bool = conn["approach"] == "south"
	var door := Area2D.new()
	door.name = "DoorTo" + target.to_pascal_case()
	door.set_script(load("res://addons/jornada/world/door.gd"))
	door.set("target_zone", target)
	if sign != "":
		door.set("sign_text", sign)
		door.set("sign_y", -size[1] * TILE + 6.0)
	door.collision_layer = 0
	door.collision_mask = 4
	var center_y: float = (tile[1] + 1) * TILE if south else tile[1] * TILE
	door.position = Vector2((tile[0] + size[0] / 2.0) * TILE, center_y)
	root.add_child(door)
	door.owner = root
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size[0] * TILE + 4, 24)
	shape.shape = rect
	door.add_child(shape)
	shape.owner = root
	# Aviso [E]: sobre el techo de la puerta (portón) o sobre la cabeza del jugador (felpudo).
	var prompt: Node2D = load("res://addons/jornada/scenes/interact_prompt.tscn").instantiate()
	prompt.name = "Prompt"
	prompt.position = Vector2(0, -size[1] * TILE - 2) if south else Vector2(0, -36)
	door.add_child(prompt)
	prompt.owner = root


# ── Escena de la partida ───────────────────────────────────────────────────
func _build_main() -> void:
	var root := Node2D.new()
	root.name = "Main"
	root.set_script(load("res://addons/jornada/world/main.gd"))

	root.y_sort_enabled = true   # zona y personajes se ordenan juntos por Y (ZoneHolder > zona > objetos)
	var holder := Node2D.new()
	holder.name = "ZoneHolder"
	holder.y_sort_enabled = true
	root.add_child(holder)
	holder.owner = root

	var actors := Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true  # personajes se ordenan por Y
	root.add_child(actors)
	actors.owner = root

	var player: Node2D = load(_paths["player"]).instantiate()
	player.name = "Player"
	actors.add_child(player)
	player.owner = root

	for id: String in _cfg.get("npcs", {}).get("list", []):
		var npc: Node2D = load("res://addons/jornada/scenes/npc_actor.tscn").instantiate()
		npc.name = id.capitalize()
		npc.set("npc_id", id)
		npc.set("sheet", load(str(_paths["npc_sheet"]).replace("{id}", id)))
		actors.add_child(npc)
		npc.owner = root

	var dialogue: Node = load("res://addons/jornada/scenes/dialogue_box.tscn").instantiate()
	dialogue.name = "DialogueBox"
	root.add_child(dialogue)
	dialogue.owner = root

	var work_panel := CanvasLayer.new()
	work_panel.name = "WorkOrderPanel"
	work_panel.set_script(load("res://addons/jornada/work/work_order_panel.gd"))
	root.add_child(work_panel)
	work_panel.owner = root

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://addons/jornada/ui/hud.gd"))
	root.add_child(hud)
	hud.owner = root

	var scene := PackedScene.new()
	scene.pack(root)
	var path: String = GameConfig.data["scenes"]["game"]
	print("main guardado err=", ResourceSaver.save(scene, path))
