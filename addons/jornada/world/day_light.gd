class_name DayLight
extends Node
## Luz del día según la hora (data/lighting.json): tiñe el mundo, enciende ventanas, faroles y fuegos
## (nodos del grupo "glow", que no se tiñen), mueve con el sol la sombra de cada edificio y hace que
## las fuentes de luz cercanas iluminen a personajes y objetos. Lo crea main.gd.
## Las zonas con algún pasaje por el borde son exteriores; el resto, interiores.
##
## El tinte va por self_modulate de cada sprite/tilemap y no por CanvasModulate: así los avisos [E],
## los globos de diálogo y los vidrios encendidos conservan su color de noche. Cada personaje u objeto
## recibe un único color (el de su base): se ilumina entero, sin degradés, como en pixel art.

const DATA_PATH: String = "res://data/lighting.json"
const SHADOW_COLOR: Color = Color(0.06, 0.05, 0.14)
## Fuerza máxima de la sombra de un edificio (alfa) y su largo con el sol alto / bajo (px).
const SHADOW_ALPHA: float = 0.3
const SHADOW_SHORT: float = 10.0
const SHADOW_LONG: float = 40.0
## El suelo en 3/4 se ve acortado en vertical.
const GROUND_SQUASH: float = 0.7
## Luz cálida de faroles y ventanas; cuánto puede acercar un color a ella (1 = del todo).
const WARM_LIGHT: Color = Color(1.0, 0.84, 0.6)
const MAX_LIT: float = 0.82
## Ventanas encendidas de las fachadas: alcance (px desde el pie de la fachada) y fuerza.
const WINDOW_REACH: float = 30.0
const WINDOW_POWER: float = 0.45
const SKY_GLASS: Color = Color(0.82, 0.9, 1.05)
const PATCH_ALPHA: float = 0.22
const PATCH_LENGTH: float = 40.0
const PATCH_REACH: float = 34.0
const PATCH_POWER: float = 0.55

var _glass_textures: Dictionary = {}   # por tile; vive lo que la partida (main.gd crea un DayLight)

var _actors: Node2D
var _keys: Dictionary = {}
var _sunrise: float
var _sunset: float
var _azimuth_rise: float
var _azimuth_set: float
var _max_altitude: float
var _exterior: bool = true
var _shadows: Array[Polygon2D] = []
var _rects: Array[Rect2] = []
## Fuentes de luz de la zona: {pos, reach, power, kind ("glow" | "window" | "day"), min_glow}.
var _sources: Array[Dictionary] = []
var _glass: Array[Sprite2D] = []
var _patches: Array[Polygon2D] = []
var _base: Color = Color.WHITE
var _glow: float = 0.0
var _outside: Dictionary = {}


func setup(actors: Node2D) -> void:
	_actors = actors


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_sunrise = TimeManager.parse_clock(data["sunrise"])
	_sunset = TimeManager.parse_clock(data["sunset"])
	_azimuth_rise = float(data["sunrise_azimuth"])
	_azimuth_set = float(data["sunset_azimuth"])
	_max_altitude = float(data["max_sun_altitude"])
	for kind in ["exterior", "interior"]:
		var keys: Array = []
		for k: Dictionary in data[kind]:
			keys.append({"t": float(TimeManager.parse_clock(k["time"])), "color": Color(k["color"]),
					"glow": float(k["glow"]), "sun": float(k["sun"])})
		_keys[kind] = keys
	TimeManager.minute_changed.connect(_on_minute.unbind(2))
	ZoneManager.zone_changed.connect(_on_zone_changed)
	if ZoneManager.current_zone != "":
		_on_zone_changed(ZoneManager.current_zone)


func _process(_delta: float) -> void:
	# Los personajes se mueven: su luz se recalcula cada cuadro (el resto, una vez por minuto).
	if _actors == null:
		return
	for actor in _actors.get_children():
		var body := actor as Node2D
		if body == null or not body.visible:
			continue
		var sprite := body.get_node_or_null("AnimatedSprite2D") as CanvasItem
		if sprite != null:
			sprite.self_modulate = _lit(_base, body.global_position)


func _on_zone_changed(zone_id: String) -> void:
	_exterior = ZoneManager.is_exterior(zone_id)
	_shadows.clear()
	_rects.clear()
	_glass.clear()
	_patches.clear()
	var root: Node = ZoneManager.zone_root
	var holder: Node = root.get_node_or_null("SunShadows")
	if holder != null:
		for building in root.get_children():
			if building.is_in_group("building"):
				var poly := Polygon2D.new()
				poly.color = SHADOW_COLOR
				holder.add_child(poly)
				_shadows.append(poly)
				_rects.append(building.get_meta("rect_px"))
	if not _exterior:
		_build_windows(root)
	_collect_sources(root)
	refresh()


func _on_minute() -> void:
	refresh()


## Aplica la luz de la hora actual a la zona y a los personajes.
func refresh() -> void:
	var light: Dictionary = sample(TimeManager.minutes, _exterior)
	_outside = sample(TimeManager.minutes, true)
	_base = light["color"]
	_glow = light["glow"]
	_tint(ZoneManager.zone_root, _base)
	_tint(_actors, _base)
	_update_shadows(light["sun"])
	_update_windows()


## Interpola las claves de data/lighting.json para el minuto `minutes`.
func sample(minutes: float, exterior: bool) -> Dictionary:
	var keys: Array = _keys["exterior" if exterior else "interior"]
	if minutes <= keys[0]["t"]:
		return keys[0]
	for i in range(1, keys.size()):
		var b: Dictionary = keys[i]
		if minutes <= b["t"]:
			var a: Dictionary = keys[i - 1]
			var f: float = (minutes - a["t"]) / (b["t"] - a["t"])
			return {"color": a["color"].lerp(b["color"], f), "glow": lerpf(a["glow"], b["glow"], f),
					"sun": lerpf(a["sun"], b["sun"], f)}
	return keys[-1]


func _tint(node: Node, color: Color) -> void:
	if node == null:
		return
	if node.is_in_group("glow"):
		var item := node as CanvasItem
		item.modulate.a = maxf(_glow, float(item.get_meta("min_glow", 0.0)))
		return
	if node.is_in_group("window_glass") or node is InteractPrompt or node is Control:
		return
	if node is Sprite2D or node is AnimatedSprite2D or node is TileMapLayer or node is CPUParticles2D:
		var parent := node.get_parent() as Node2D
		# Objetos chicos (muebles, faroles, árboles, puestos, examinables): reciben la luz de su base.
		if parent != null and (parent is Prop or parent is WorkSpot or parent is Inspectable):
			(node as CanvasItem).self_modulate = _lit(color, parent.global_position)
		else:
			(node as CanvasItem).self_modulate = color
	for child in node.get_children():
		_tint(child, color)


# ── Fuentes de luz ─────────────────────────────────────────────────────────
func _collect_sources(root: Node) -> void:
	_sources.clear()
	for node in root.find_children("*", "Sprite2D", true, false):
		if node.is_in_group("glow") and float(node.get_meta("reach", 0.0)) > 0.0:
			_sources.append({"pos": (node.get_parent() as Node2D).global_position, "reach": node.get_meta("reach"),
					"power": node.get_meta("power"), "kind": "glow", "min_glow": node.get_meta("min_glow")})
	for building in root.get_children():
		if building.is_in_group("building"):
			for p: Vector2 in building.get_meta("lights", PackedVector2Array()):
				_sources.append({"pos": (building as Node2D).global_position + p, "reach": WINDOW_REACH,
						"power": WINDOW_POWER, "kind": "window", "min_glow": 0.0})
	for patch in _patches:
		var center: Vector2 = patch.get_meta("center")
		_sources.append({"pos": center, "reach": PATCH_REACH, "power": PATCH_POWER, "kind": "day", "min_glow": 0.0})


## Color de `base` iluminado por las fuentes cercanas a `feet` (la base del personaje u objeto).
func _lit(base: Color, feet: Vector2) -> Color:
	var amount: float = 0.0
	var tint := Color(0, 0, 0)
	var daylight: float = 1.0 - float(_outside.get("glow", 0.0))
	for s: Dictionary in _sources:
		var d: float = feet.distance_to(s["pos"])
		if d >= s["reach"]:
			continue
		var level: float
		var color: Color = WARM_LIGHT
		match s["kind"]:
			"day":
				level = daylight
				color = (_outside.get("color", Color.WHITE) as Color) * SKY_GLASS
			_:
				level = maxf(_glow, s["min_glow"])
		var f: float = 1.0 - d / s["reach"]
		level *= s["power"] * f * f * (3.0 - 2.0 * f)
		if level <= 0.0:
			continue
		amount += level
		tint += color * level
	if amount <= 0.0:
		return base
	var light := Color(tint.r / amount, tint.g / amount, tint.b / amount)
	var lit: Color = base.lerp(light, minf(amount, 1.0) * MAX_LIT)
	# La luz no oscurece: si la base ya es más clara (de día), queda la base.
	return Color(maxf(lit.r, base.r), maxf(lit.g, base.g), maxf(lit.b, base.b), base.a)


# ── Ventanas de los interiores ─────────────────────────────────────────────
## Sobre cada tile de ventana: el vidrio toma el color de afuera (cielo de día, azul de noche) y,
## mientras hay luz, un rectángulo de sol entra al piso, inclinado según la hora.
func _build_windows(root: Node) -> void:
	var ground := root.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return
	var layer := Node2D.new()
	layer.name = "WindowLight"
	root.add_child(layer)
	# Los tiles de ventana traen datos propios en el TileSet (build_world): "window" y el rayo de sol "window_sun".
	if ground.tile_set == null or ground.tile_set.get_custom_data_layer_by_name("window") < 0:
		return
	for cell in ground.get_used_cells():
		var data: TileData = ground.get_cell_tile_data(cell)
		if data == null or not data.get_custom_data("window"):
			continue
		var coords: Vector2i = ground.get_cell_atlas_coords(cell)
		var source := ground.tile_set.get_source(ground.get_cell_source_id(cell)) as TileSetAtlasSource
		var glass := Sprite2D.new()
		glass.texture = _glass_texture(source, coords)
		glass.centered = false
		glass.position = Vector2(cell * ZoneManager.TILE)
		glass.add_to_group("window_glass")
		layer.add_child(glass)
		_glass.append(glass)
		var sun: Vector2 = data.get_custom_data("window_sun")
		if sun == Vector2.ZERO:
			continue   # solo el tile de abajo de cada ventana deja entrar el rectángulo de sol al piso
		var patch := Polygon2D.new()
		patch.material = PixelLight.add_material()
		var x: float = cell.x * ZoneManager.TILE
		var floor_y: float = (cell.y + 2) * ZoneManager.TILE   # la ventana está en la fila 2; el piso arranca en la 4
		patch.set_meta("window", Rect2(x + sun.y, floor_y, sun.x, PATCH_LENGTH))
		patch.set_meta("center", Vector2(x + sun.y + sun.x / 2.0, floor_y + PATCH_LENGTH * 0.6))
		layer.add_child(patch)
		_patches.append(patch)


func _update_windows() -> void:
	if _glass.is_empty():
		return
	var outside: Color = _outside["color"]
	var daylight: float = 1.0 - float(_outside["glow"])
	var t: float = TimeManager.minutes
	var f: float = clampf((t - _sunrise) / (_sunset - _sunrise), 0.0, 1.0)
	var skew: float = roundf(lerpf(14.0, -14.0, f))
	for glass in _glass:
		glass.modulate = outside * SKY_GLASS
	for patch in _patches:
		var r: Rect2 = patch.get_meta("window")
		patch.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
				Vector2(r.end.x + skew + 3, r.end.y), Vector2(r.position.x + skew - 3, r.end.y)])
		patch.color = Color(outside.r, outside.g, outside.b, PATCH_ALPHA * daylight)
		patch.visible = daylight > 0.02


## Máscara del vidrio de un tile de ventana: solo los píxeles amarillos del vidrio, en gris
## (conservan el sombreado), para que el color lo ponga la hora.
func _glass_texture(source: TileSetAtlasSource, coords: Vector2i) -> ImageTexture:
	var cache_key := "%s:%s" % [source.texture.resource_path, coords]
	if _glass_textures.has(cache_key):
		return _glass_textures[cache_key]
	var src: Image = source.texture.get_image().get_region(source.get_tile_texture_region(coords))
	src.convert(Image.FORMAT_RGBA8)
	var levels: Dictionary = {Color("#FFE6C7"): 1.0, Color("#FFCD9C"): 0.9, Color("#D9A073"): 0.76}
	var img := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in src.get_height():
		for x in src.get_width():
			var c: Color = src.get_pixel(x, y)
			for key: Color in levels:
				if c.is_equal_approx(key):
					var v: float = levels[key]
					img.set_pixel(x, y, Color(v, v, v, 1.0))
					break
	var tex := ImageTexture.create_from_image(img)
	_glass_textures[cache_key] = tex
	return tex


## Sombra de cada edificio: su rectángulo barrido en la dirección contraria al sol.
func _update_shadows(strength: float) -> void:
	var t: float = TimeManager.minutes
	var up: bool = t > _sunrise and t < _sunset and strength > 0.0
	for i in _shadows.size():
		_shadows[i].visible = up
	if not up:
		return
	var f: float = (t - _sunrise) / (_sunset - _sunrise)
	var altitude: float = _max_altitude * sin(PI * f)
	var away: float = deg_to_rad(lerpf(_azimuth_rise, _azimuth_set, f) + 180.0)
	var length: float = lerpf(SHADOW_LONG, SHADOW_SHORT, clampf(altitude / _max_altitude, 0.0, 1.0))
	var offset := Vector2(sin(away), -cos(away) * GROUND_SQUASH) * length
	offset = offset.round()
	for i in _shadows.size():
		var r: Rect2 = _rects[i]
		var corners := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var points := PackedVector2Array(corners)
		for c in corners:
			points.append(c + offset)
		_shadows[i].polygon = Geometry2D.convex_hull(points)
		_shadows[i].color.a = SHADOW_ALPHA * strength
